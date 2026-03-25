local ControlFlow = require("./ControlFlow")
local ExpressionFolding = require("./ExpressionFolding")

local Formatter = {}

local BinaryOpStrings = {
	Add = "+", Sub = "-", Mul = "*", Div = "/", IDiv = "//",
	Mod = "%", Pow = "^", Concat = "..", And = "and", Or = "or",
	Equal = "==", NotEqual = "~=", LessThan = "<", LessEqual = "<=",
	GreaterThan = ">", GreaterEqual = ">=",
}

local UnaryOpStrings = {
	Not = "not ", Negate = "-", Length = "#",
}

local BinaryPrecedence = {
	Or = 1, And = 2,
	Equal = 3, NotEqual = 3, LessThan = 3, LessEqual = 3, GreaterThan = 3, GreaterEqual = 3,
	Concat = 4, Add = 5, Sub = 5,
	Mul = 6, Div = 6, IDiv = 6, Mod = 6,
	Pow = 8,
}

local UNARY_PRECEDENCE = 7
local RightAssociative = { Concat = true, Pow = true }

local Reserved = {
	["and"] = true, ["break"] = true, ["continue"] = true, ["do"] = true,
	["else"] = true, ["elseif"] = true, ["end"] = true, ["false"] = true,
	["for"] = true, ["function"] = true, ["if"] = true, ["in"] = true,
	["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
	["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
	["until"] = true, ["while"] = true,
}

local function IsValidIdentifier(Name)
	if type(Name) ~= "string" or #Name == 0 then return false end
	local First = string.byte(Name, 1)
	if not ((First >= 65 and First <= 90) or (First >= 97 and First <= 122) or First == 95) then
		return false
	end
	for I = 2, #Name do
		local B = string.byte(Name, I)
		if not ((B >= 65 and B <= 90) or (B >= 97 and B <= 122) or (B >= 48 and B <= 57) or B == 95) then
			return false
		end
	end
	return not Reserved[Name]
end

local function EscapeString(Str)
	local Parts = {}
	for I = 1, #Str do
		local B = string.byte(Str, I)
		if B == 92 then table.insert(Parts, "\\\\")
		elseif B == 34 then table.insert(Parts, '\\"')
		elseif B == 10 then table.insert(Parts, "\\n")
		elseif B == 13 then table.insert(Parts, "\\r")
		elseif B == 9 then table.insert(Parts, "\\t")
		elseif B == 0 then table.insert(Parts, "\\0")
		elseif B == 7 then table.insert(Parts, "\\a")
		elseif B == 8 then table.insert(Parts, "\\b")
		elseif B == 12 then table.insert(Parts, "\\f")
		elseif B == 11 then table.insert(Parts, "\\v")
		elseif B < 32 or B == 127 then table.insert(Parts, string.format("\\%d", B))
		else table.insert(Parts, string.char(B))
		end
	end
	return table.concat(Parts)
end

local function FormatNumber(V)
	if V ~= V then return "0/0"
	elseif V == math.huge then return "math.huge"
	elseif V == -math.huge then return "-math.huge"
	elseif V == 0 then return if 1 / V < 0 then "-0" else "0"
	elseif V == math.floor(V) and math.abs(V) < 2^53 then
		return string.format("%g", V)
	else
		for Precision = 1, 17 do
			local S = string.format(`%.{Precision}g`, V)
			if tonumber(S) == V then return S end
		end
		return string.format("%.17g", V)
	end
end

local function EmitLine(State, Text)
	table.insert(State.Output, string.rep("    ", State.Indent) .. Text .. "\n")
end

local function PushIndent(State) State.Indent += 1 end
local function PopIndent(State) State.Indent -= 1 end

local function GetLocalName(State, FuncIndex, Node)
	if not Node then return "_" end
	if Node.Tag ~= "Local" then return nil end
	local Key = `{FuncIndex}_{Node.Id}`
	if State.NamedRegisters[Key] then return State.NamedRegisters[Key] end

	local Func = State.Chunk.Functions[FuncIndex + 1]

	if Node.Id < 0 then
		local UpIdx = -Node.Id
		if Func and Func.UpvalueNames and Func.UpvalueNames[UpIdx] then
			State.NamedRegisters[Key] = Func.UpvalueNames[UpIdx]
			return Func.UpvalueNames[UpIdx]
		end
		if State.ResolvedUpvalueNames and State.ResolvedUpvalueNames[FuncIndex]
			and State.ResolvedUpvalueNames[FuncIndex][UpIdx] then
			local Name = State.ResolvedUpvalueNames[FuncIndex][UpIdx]
			State.NamedRegisters[Key] = Name
			return Name
		end
		local Name = `u{UpIdx - 1}`
		State.NamedRegisters[Key] = Name
		return Name
	end

	if Func and Func.Locals then
		for _, L in Func.Locals do
			if L.Reg == Node.Id and L.Name and #L.Name > 0 then
				State.NamedRegisters[Key] = L.Name
				return L.Name
			end
		end
	end

	local LiftedFunc = State.LiftedFunctions[FuncIndex]
	if LiftedFunc and Node.Id < LiftedFunc.NumParameters then
		local Name = `p{Node.Id}`
		State.NamedRegisters[Key] = Name
		return Name
	end

	local Name = `v{Node.Id}`
	State.NamedRegisters[Key] = Name
	return Name
end

local FormatExpression
local FormatStatement
local FormatBlock
local FormatFunction
local BlockProducesOutput

local function IsDotPath(Node)
	if not Node then return false end
	if Node.Tag == "Local" or Node.Tag == "Global" then return true end
	if Node.Tag == "Index" and Node.Key and Node.Key.Tag == "Literal"
		and Node.Key.LiteralType == "String" and IsValidIdentifier(Node.Key.Value) then
		return IsDotPath(Node.Object)
	end
	return false
end

local function EmitElseChain(State, ElseBlock, FuncIndex)
	if not ElseBlock or #ElseBlock == 0 then
		EmitLine(State, "end")
		return
	end
	if #ElseBlock == 1 and ElseBlock[1].Tag == "If" then
		local EI = ElseBlock[1]
		local ThenHasOutput = BlockProducesOutput(State, EI.ThenBlock, FuncIndex)
		local ElseHasOutput = BlockProducesOutput(State, EI.ElseBlock, FuncIndex)
		if not ThenHasOutput and not ElseHasOutput then
			-- Skip empty elseif entirely
			EmitLine(State, "end")
			return
		elseif not ThenHasOutput and ElseHasOutput then
			-- Flip: elseif cond then end else B → else B end
			EmitLine(State, "else")
			PushIndent(State)
			FormatBlock(State, EI.ElseBlock, FuncIndex)
			PopIndent(State)
			EmitLine(State, "end")
		else
			EmitLine(State, `elseif {FormatExpression(State, EI.Condition, FuncIndex, 0)} then`)
			PushIndent(State)
			if EI.ThenBlock then FormatBlock(State, EI.ThenBlock, FuncIndex) end
			PopIndent(State)
			EmitElseChain(State, EI.ElseBlock, FuncIndex)
		end
	else
		if BlockProducesOutput(State, ElseBlock, FuncIndex) then
			EmitLine(State, "else")
			PushIndent(State)
			FormatBlock(State, ElseBlock, FuncIndex)
			PopIndent(State)
		end
		EmitLine(State, "end")
	end
end

FormatExpression = function(State, Node, FuncIndex, ParentPrecedence)
	local PP = ParentPrecedence or 0
	if not Node then return "nil" end
	local Tag = Node.Tag

	if Tag == "Literal" then
		if Node.LiteralType == "Nil" then return "nil"
		elseif Node.LiteralType == "Boolean" then return if Node.Value then "true" else "false"
		elseif Node.LiteralType == "Number" then return FormatNumber(Node.Value)
		elseif Node.LiteralType == "String" then return `"{EscapeString(Node.Value)}"`
		elseif Node.LiteralType == "Vector" then
			return `Vector3.new({FormatNumber(Node.Value[1])}, {FormatNumber(Node.Value[2])}, {FormatNumber(Node.Value[3])})`
		end
		return "nil"

	elseif Tag == "Local" then
		return GetLocalName(State, FuncIndex, Node)

	elseif Tag == "Global" then
		return Node.Name or "_G"

	elseif Tag == "Binary" then
		local OpStr = BinaryOpStrings[Node.Op] or Node.Op or "?"
		local Prec = BinaryPrecedence[Node.Op] or 0
		local LeftPrec = if RightAssociative[Node.Op] then Prec + 1 else Prec
		local RightPrec = if RightAssociative[Node.Op] then Prec else Prec + 1
		local Left = FormatExpression(State, Node.Left, FuncIndex, LeftPrec)
		local Right = FormatExpression(State, Node.Right, FuncIndex, RightPrec)
		local Result = `{Left} {OpStr} {Right}`
		return if Prec < PP then `({Result})` else Result

	elseif Tag == "Unary" then
		local OpStr = UnaryOpStrings[Node.Op] or Node.Op or "?"
		local Inner = FormatExpression(State, Node.Value, FuncIndex, UNARY_PRECEDENCE)
		local Result = `{OpStr}{Inner}`
		return if UNARY_PRECEDENCE < PP then `({Result})` else Result

	elseif Tag == "Index" then
		local Obj = FormatExpression(State, Node.Object, FuncIndex, 0)
		local Key = Node.Key
		if Key and Key.Tag == "Literal" and Key.LiteralType == "String" and IsValidIdentifier(Key.Value) then
			return `{Obj}.{Key.Value}`
		end
		return `{Obj}[{FormatExpression(State, Key, FuncIndex, 0)}]`

	elseif Tag == "Call" then
		local FuncStr = FormatExpression(State, Node.Function, FuncIndex, 0)
		local Args = {}
		for _, Arg in Node.Args do
			table.insert(Args, FormatExpression(State, Arg, FuncIndex, 0))
		end
		return `{FuncStr}({table.concat(Args, ", ")})`

	elseif Tag == "MethodCall" then
		local Obj = FormatExpression(State, Node.Object, FuncIndex, 0)
		local Args = {}
		for _, Arg in Node.Args do
			table.insert(Args, FormatExpression(State, Arg, FuncIndex, 0))
		end
		return `{Obj}:{Node.Method or "?"}({table.concat(Args, ", ")})`

	elseif Tag == "VarArg" then
		return "..."

	elseif Tag == "Select" then
		return if Node.Inner then FormatExpression(State, Node.Inner, FuncIndex, PP) else "nil"

	elseif Tag == "Table" then
		if not Node.Fields or #Node.Fields == 0 then
			return "{}"
		end
		local Parts = {}
		for _, F in Node.Fields do
			local ValStr = FormatExpression(State, F.Value, FuncIndex, 0)
			if F.Key and F.Key.Tag == "Literal" and F.Key.LiteralType == "String" and IsValidIdentifier(F.Key.Value) then
				table.insert(Parts, `{F.Key.Value} = {ValStr}`)
			elseif F.Key then
				table.insert(Parts, `[{FormatExpression(State, F.Key, FuncIndex, 0)}] = {ValStr}`)
			else
				table.insert(Parts, ValStr)
			end
		end
		return `\{{table.concat(Parts, ", ")}\}`

	elseif Tag == "Closure" then
		return FormatFunction(State, Node.FuncData)
	end

	return "nil"
end

FormatFunction = function(State, FuncIndex, DeclName)
	local Func = State.Chunk.Functions[FuncIndex + 1]
	local LiftedFunc = State.LiftedFunctions[FuncIndex]
	if not Func or not LiftedFunc then return "function() end" end

	local ParamNames = {}
	for I = 0, Func.NumParameters - 1 do
		local ParamName = nil
		if Func.Locals then
			for _, L in Func.Locals do
				if L.Reg == I and L.StartPC == 0 and L.Name and #L.Name > 0 then
					ParamName = L.Name
					break
				end
			end
		end
		if not ParamName then ParamName = `p{I}` end
		table.insert(ParamNames, ParamName)
		State.NamedRegisters[`{FuncIndex}_{I}`] = ParamName
	end

	if Func.IsVararg then
		table.insert(ParamNames, "...")
	end

	local SaveOutput = State.Output
	local SaveIndent = State.Indent
	local SaveAssigned = State.AssignedLocals
	State.Output = {}
	State.AssignedLocals = {}

	local Structured
	if State.StructuredCache and State.StructuredCache[FuncIndex] then
		Structured = State.StructuredCache[FuncIndex]
	else
		local ok, Result = pcall(function()
			return ExpressionFolding.Fold(ControlFlow.Recover(LiftedFunc))
		end)
		Structured = if ok then Result else {}
	end
	if DeclName then
		table.insert(State.Output, `function {DeclName}({table.concat(ParamNames, ", ")})\n`)
	else
		table.insert(State.Output, `function({table.concat(ParamNames, ", ")})\n`)
	end
	PushIndent(State)
	FormatBlock(State, Structured, FuncIndex)
	PopIndent(State)
	table.insert(State.Output, string.rep("    ", State.Indent) .. "end")

	local Result = table.concat(State.Output)
	State.Output = SaveOutput
	State.Indent = SaveIndent
	State.AssignedLocals = SaveAssigned
	return Result
end

FormatBlock = function(State, Stmts, FuncIndex)
	if not Stmts then return end
	for _, Stmt in Stmts do
		FormatStatement(State, Stmt, FuncIndex)
	end
end

BlockProducesOutput = function(State, Block, FuncIndex)
	if not Block or #Block == 0 then return false end
	local SaveOutput = State.Output
	State.Output = {}
	FormatBlock(State, Block, FuncIndex)
	local Produced = #State.Output > 0
	State.Output = SaveOutput
	return Produced
end

FormatStatement = function(State, Node, FuncIndex)
	if not Node then return end
	local Tag = Node.Tag

	if Tag == "Assign" then
		if #Node.Left == 1 and #Node.Right == 1 and Node.Right[1] and Node.Right[1].Tag == "Closure" then
			local L = Node.Left[1]
			local ClosureNode = Node.Right[1]
			if L.Tag == "Local" then
				local Key = `{FuncIndex}_{L.Id}`
				local IsNew = not State.AssignedLocals[Key]
				if ClosureNode.FuncName and #ClosureNode.FuncName > 0 and IsValidIdentifier(ClosureNode.FuncName) then
					State.NamedRegisters[Key] = ClosureNode.FuncName
				end
				local Name = GetLocalName(State, FuncIndex, L)
				State.AssignedLocals[Key] = true
				local FuncStr = FormatFunction(State, ClosureNode.FuncData, Name)
				if IsNew then
					EmitLine(State, `local {FuncStr}`)
				else
					EmitLine(State, FuncStr)
				end
				return
			elseif IsDotPath(L) then
				local LeftStr = FormatExpression(State, L, FuncIndex, 0)
				local FuncStr = FormatFunction(State, ClosureNode.FuncData, LeftStr)
				EmitLine(State, FuncStr)
				return
			end
		end

		local LeftParts = {}
		local RightParts = {}
		local AllLocal = true
		local AnyLocal = false

		for _, L in Node.Left do
			if L.Tag == "Local" then
				local Name = GetLocalName(State, FuncIndex, L)
				table.insert(LeftParts, Name)
				local Key = `{FuncIndex}_{L.Id}`
				if not State.AssignedLocals[Key] then
					AnyLocal = true
					State.AssignedLocals[Key] = true
				else
					AllLocal = false
				end
			else
				AllLocal = false
				table.insert(LeftParts, FormatExpression(State, L, FuncIndex, 0))
			end
		end

		for _, R in Node.Right do
			table.insert(RightParts, FormatExpression(State, R, FuncIndex, 0))
		end

		local LeftStr = table.concat(LeftParts, ", ")
		local RightStr = table.concat(RightParts, ", ")
		if AnyLocal and AllLocal then
			EmitLine(State, `local {LeftStr} = {RightStr}`)
		else
			EmitLine(State, `{LeftStr} = {RightStr}`)
		end

	elseif Tag == "Return" then
		if not Node.Values or #Node.Values == 0 then
			EmitLine(State, "return")
		else
			local Parts = {}
			for _, V in Node.Values do
				table.insert(Parts, FormatExpression(State, V, FuncIndex, 0))
			end
			EmitLine(State, `return {table.concat(Parts, ", ")}`)
		end

	elseif Tag == "Call" or Tag == "MethodCall" then
		EmitLine(State, FormatExpression(State, Node, FuncIndex, 0))

	elseif Tag == "If" then
		local ThenHasOutput = BlockProducesOutput(State, Node.ThenBlock, FuncIndex)
		local ElseHasOutput = BlockProducesOutput(State, Node.ElseBlock, FuncIndex)
		if not ThenHasOutput and not ElseHasOutput then
			-- Skip empty if entirely
		elseif not ThenHasOutput and ElseHasOutput then
			-- Flip: if cond then end else B → if not cond then B end
			local Cond = FormatExpression(State, { Tag = "Unary", Op = "not", Value = Node.Condition }, FuncIndex, 0)
			EmitLine(State, `if {Cond} then`)
			PushIndent(State)
			FormatBlock(State, Node.ElseBlock, FuncIndex)
			PopIndent(State)
			EmitLine(State, "end")
		else
			local Cond = FormatExpression(State, Node.Condition, FuncIndex, 0)
			EmitLine(State, `if {Cond} then`)
			PushIndent(State)
			if Node.ThenBlock then FormatBlock(State, Node.ThenBlock, FuncIndex) end
			PopIndent(State)
			EmitElseChain(State, Node.ElseBlock, FuncIndex)
		end

	elseif Tag == "While" then
		EmitLine(State, `while {FormatExpression(State, Node.Condition, FuncIndex, 0)} do`)
		PushIndent(State)
		FormatBlock(State, Node.Body, FuncIndex)
		PopIndent(State)
		EmitLine(State, "end")

	elseif Tag == "Repeat" then
		EmitLine(State, "repeat")
		PushIndent(State)
		FormatBlock(State, Node.Body, FuncIndex)
		PopIndent(State)
		EmitLine(State, `until {FormatExpression(State, Node.Condition, FuncIndex, 0)}`)

	elseif Tag == "NumericFor" then
		local Var = GetLocalName(State, FuncIndex, Node.Var)
		local Start = FormatExpression(State, Node.Start, FuncIndex, 0)
		local Limit = FormatExpression(State, Node.Limit, FuncIndex, 0)
		local Step = FormatExpression(State, Node.Step, FuncIndex, 0)
		if Node.Var and Node.Var.Tag == "Local" then
			State.AssignedLocals[`{FuncIndex}_{Node.Var.Id}`] = true
		end
		if Step == "1" then
			EmitLine(State, `for {Var} = {Start}, {Limit} do`)
		else
			EmitLine(State, `for {Var} = {Start}, {Limit}, {Step} do`)
		end
		PushIndent(State)
		FormatBlock(State, Node.Body, FuncIndex)
		PopIndent(State)
		EmitLine(State, "end")

	elseif Tag == "GenericFor" then
		local VarNames = {}
		for _, V in Node.Vars do
			table.insert(VarNames, GetLocalName(State, FuncIndex, V))
			if V and V.Tag == "Local" then
				State.AssignedLocals[`{FuncIndex}_{V.Id}`] = true
			end
		end
		local IterParts = {}
		for _, It in Node.Iterators do
			if It then table.insert(IterParts, FormatExpression(State, It, FuncIndex, 0)) end
		end
		EmitLine(State, `for {table.concat(VarNames, ", ")} in {table.concat(IterParts, ", ")} do`)
		PushIndent(State)
		FormatBlock(State, Node.Body, FuncIndex)
		PopIndent(State)
		EmitLine(State, "end")

	elseif Tag == "Break" then
		EmitLine(State, "break")

	elseif Tag == "Continue" then
		EmitLine(State, "continue")

	elseif Tag == "SetList" then
		local Tbl = FormatExpression(State, Node.Table, FuncIndex, 0)
		local StartIdx = Node.StartIndex or 0
		for I, V in Node.Values do
			EmitLine(State, `{Tbl}[{StartIdx + I}] = {FormatExpression(State, V, FuncIndex, 0)}`)
		end

	elseif Tag == "Close" or Tag == "NumForInit" or Tag == "NumForNext"
		or Tag == "GenericForInit" or Tag == "GenericForNext" or Tag == "Comment" then
	end
end

function Formatter.Format(Chunk, LiftedFunctions, MainIndex)
	local State = {
		Chunk = Chunk,
		LiftedFunctions = LiftedFunctions,
		MainIndex = MainIndex,
		Output = {},
		Indent = 0,
		NamedRegisters = {},
		AssignedLocals = {},
		ResolvedUpvalueNames = {},
	}

	local ScanDeadline = os.clock() + 10
	local function PreScanFuncNames(FuncIdx)
		if os.clock() > ScanDeadline then return end
		local Lifted = LiftedFunctions[FuncIdx]
		if not Lifted then return end
		local ok, Structured = pcall(function()
			return ExpressionFolding.Fold(ControlFlow.Recover(Lifted, ScanDeadline))
		end)
		if not ok then return end
		State.StructuredCache = State.StructuredCache or {}
		State.StructuredCache[FuncIdx] = Structured
		for _, Stmt in Structured do
			if Stmt.Tag == "Assign" and #Stmt.Left == 1 and #Stmt.Right == 1 then
				local R = Stmt.Right[1]
				local L = Stmt.Left[1]
				if R and R.Tag == "Closure" then
					if L.Tag == "Local" and R.FuncName and #R.FuncName > 0 and IsValidIdentifier(R.FuncName) then
						local Key = `{FuncIdx}_{L.Id}`
						if not State.NamedRegisters[Key] then
							State.FuncNameOverrides = State.FuncNameOverrides or {}
							State.FuncNameOverrides[Key] = R.FuncName
						end
					end
					PreScanFuncNames(R.FuncData)
				end
			end
		end
	end
	PreScanFuncNames(MainIndex)

	local function ResolveUpvalueNames(ParentIdx)
		local Lifted = LiftedFunctions[ParentIdx]
		if not Lifted then return end
		for _, Child in Lifted.ChildClosures do
			local ChildIdx = Child.FuncIndex
			if not State.ResolvedUpvalueNames[ChildIdx] then
				State.ResolvedUpvalueNames[ChildIdx] = {}
				for I, Capture in Child.Node.Upvalues or {} do
					if Capture.Local then
						local Key = `{ParentIdx}_{Capture.Local.Id}`
						local Name = State.FuncNameOverrides and State.FuncNameOverrides[Key]
						if not Name then
							Name = GetLocalName(State, ParentIdx, Capture.Local)
						end
						State.ResolvedUpvalueNames[ChildIdx][I] = Name
					end
				end
				ResolveUpvalueNames(ChildIdx)
			end
		end
	end
	ResolveUpvalueNames(MainIndex)

	local LiftedMain = LiftedFunctions[MainIndex]
	if not LiftedMain then return "" end

	local Structured
	if State.StructuredCache and State.StructuredCache[MainIndex] then
		Structured = State.StructuredCache[MainIndex]
	else
		local ok, Result = pcall(function()
			return ExpressionFolding.Fold(ControlFlow.Recover(LiftedMain, os.clock() + 15))
		end)
		Structured = if ok then Result else {}
	end
	FormatBlock(State, Structured, MainIndex)
	return table.concat(State.Output)
end

return Formatter