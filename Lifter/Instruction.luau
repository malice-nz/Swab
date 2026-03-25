local OpCode = require("../Opcodes")

local InstructionLifter = {}

local function MakeLocal(Id)
	return { Tag = "Local", Id = Id, Name = nil }
end

local function MakeLiteral(LitType, Value)
	return { Tag = "Literal", LiteralType = LitType, Value = Value }
end

local function MakeNil()
	return { Tag = "Literal", LiteralType = "Nil" }
end

local function MakeBool(V)
	return { Tag = "Literal", LiteralType = "Boolean", Value = V }
end

local function MakeNumber(V)
	return { Tag = "Literal", LiteralType = "Number", Value = V }
end

local function MakeString(V)
	return { Tag = "Literal", LiteralType = "String", Value = V }
end

local function MakeVector(X, Y, Z)
	return { Tag = "Literal", LiteralType = "Vector", Value = {X, Y, Z} }
end

local function MakeGlobal(Name)
	return { Tag = "Global", Name = Name }
end

local function MakeBinary(Left, Right, Op)
	return { Tag = "Binary", Left = Left, Right = Right, Op = Op }
end

local function MakeUnary(Value, Op)
	return { Tag = "Unary", Value = Value, Op = Op }
end

local function MakeIndex(Object, Key)
	return { Tag = "Index", Object = Object, Key = Key }
end

local function MakeCall(Func, Args)
	return { Tag = "Call", Function = Func, Args = Args }
end

local function MakeMethodCall(Object, Method, Args)
	return { Tag = "MethodCall", Object = Object, Method = Method, Args = Args }
end

local function MakeAssign(Left, Right, IsLocal)
	return { Tag = "Assign", Left = Left, Right = Right, IsLocal = IsLocal or false }
end

local function MakeReturn(Values)
	return { Tag = "Return", Values = Values }
end

local function MakeVarArg()
	return { Tag = "VarArg" }
end

local function MakeSelect(Inner)
	return { Tag = "Select", Inner = Inner }
end

local function MakeIf(Condition, ThenBlock, ElseBlock)
	return { Tag = "If", Condition = Condition, ThenBlock = ThenBlock or {}, ElseBlock = ElseBlock or {} }
end

local function MakeTable()
	return { Tag = "Table", Fields = {} }
end

local function MakeClosure(FuncData, Upvalues)
	return { Tag = "Closure", FuncData = FuncData, Upvalues = Upvalues }
end

local function MakeSetList(TableLocal, StartIndex, Values, Tail)
	return { Tag = "SetList", Table = TableLocal, StartIndex = StartIndex, Values = Values, Tail = Tail }
end

local function MakeClose(Locals)
	return { Tag = "Close", Locals = Locals }
end

local function MakeNumForInit(Counter, Limit, Step)
	return { Tag = "NumForInit", Counter = Counter, Limit = Limit, Step = Step }
end

local function MakeNumForNext(Counter, Limit, Step, LoopVar)
	return { Tag = "NumForNext", Counter = Counter, Limit = Limit, Step = Step, LoopVar = LoopVar }
end

local function MakeGenericForInit(Generator, State, Control)
	return { Tag = "GenericForInit", Generator = Generator, State = State, Control = Control }
end

local function MakeGenericForNext(Vars, Generator, State)
	return { Tag = "GenericForNext", Vars = Vars, Generator = Generator, State = State }
end

function InstructionLifter.New(Chunk, FuncIndex)
	local Func = Chunk.Functions[FuncIndex + 1]
	local Lifter = {
		Chunk = Chunk,
		Func = Func,
		FuncIndex = FuncIndex,
		RegisterMap = {},
		ConstantCache = {},
		Upvalues = {},
		ChildClosures = {},
	}

	for I = 1, Func.NumUpvalues do
		Lifter.Upvalues[I] = MakeLocal(-I)
	end

	for I = 1, Func.NumParameters do
		Lifter.RegisterMap[I - 1] = MakeLocal(I - 1)
	end

	return Lifter
end

local function GetRegister(Lifter, Index)
	if not Lifter.RegisterMap[Index] then
		Lifter.RegisterMap[Index] = MakeLocal(Index)
	end
	return Lifter.RegisterMap[Index]
end

local function GetConstant(Lifter, Index)
	if Lifter.ConstantCache[Index] then
		return Lifter.ConstantCache[Index]
	end

	local C = Lifter.Func.Constants[Index + 1]
	if not C then
		Lifter.ConstantCache[Index] = MakeNil()
		return MakeNil()
	end
	local Result

	if C.Type == "Nil" then
		Result = MakeNil()
	elseif C.Type == "Boolean" then
		Result = MakeBool(C.Value)
	elseif C.Type == "Number" then
		Result = MakeNumber(C.Value)
	elseif C.Type == "String" then
		local Str = Lifter.Chunk.StringTable[C.Index]
		Result = MakeString(Str or "")
	elseif C.Type == "Vector" then
		Result = MakeVector(C.X, C.Y, C.Z)
	else
		Result = MakeNil()
	end

	Lifter.ConstantCache[Index] = Result
	return Result
end

local function GetConstantString(Lifter, Index): string
	local C = Lifter.Func.Constants[Index + 1]
	if C and C.Type == "String" then
		return Lifter.Chunk.StringTable[C.Index] or ""
	end
	return ""
end

local BinaryOps = {
	[OpCode.ADD] = "Add", [OpCode.SUB] = "Sub", [OpCode.MUL] = "Mul",
	[OpCode.DIV] = "Div", [OpCode.MOD] = "Mod", [OpCode.POW] = "Pow",
	[OpCode.IDIV] = "IDiv",
	[OpCode.ADDK] = "Add", [OpCode.SUBK] = "Sub", [OpCode.MULK] = "Mul",
	[OpCode.DIVK] = "Div", [OpCode.MODK] = "Mod", [OpCode.POWK] = "Pow",
	[OpCode.IDIVK] = "IDiv",
	[OpCode.SUBRK] = "Sub", [OpCode.DIVRK] = "Div",
}

local UnaryOps = {
	[OpCode.NOT] = "Not", [OpCode.MINUS] = "Negate", [OpCode.LENGTH] = "Length",
}

function InstructionLifter.LiftBlock(Lifter, BlockStart, BlockEnd, BlockStarts)
	local Statements = {}
	local Edges = {}
	local Top = nil
	local Instructions = Lifter.Func.Instructions
	local Pc = BlockStart

	while Pc <= BlockEnd do
		local Insn = Instructions[Pc]
		if not Insn then break end
		local Op = Insn.Op
		local Index = Pc - BlockStart

		if Insn.Format == "BC" then
			local A, B, C, Aux = Insn.A, Insn.B, Insn.C, Insn.Aux

			if Op == OpCode.NOP or Op == OpCode.PREPVARARGS or Op == OpCode.BREAK then

			elseif Op == OpCode.MOVE then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{GetRegister(Lifter, B)}
				))

			elseif Op == OpCode.GETUPVAL then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{Lifter.Upvalues[B + 1] or MakeLocal(-B - 1)}
				))

			elseif Op == OpCode.SETUPVAL then
				table.insert(Statements, MakeAssign(
					{Lifter.Upvalues[B + 1] or MakeLocal(-B - 1)},
					{GetRegister(Lifter, A)}
				))

			elseif Op == OpCode.LOADNIL then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{MakeNil()}
				))

			elseif Op == OpCode.LOADB then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{MakeBool(B ~= 0)}
				))
				if C ~= 0 then
					table.insert(Edges, {
						Target = Pc + 2,
						Type = "Unconditional",
					})
					break
				end

			elseif Op == OpCode.NEWTABLE then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{MakeTable()}
				))

			elseif Op == OpCode.GETGLOBAL then
				local GlobalName = GetConstantString(Lifter, Aux)
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{MakeGlobal(GlobalName)}
				))

			elseif Op == OpCode.SETGLOBAL then
				local GlobalName = GetConstantString(Lifter, Aux)
				table.insert(Statements, MakeAssign(
					{MakeGlobal(GlobalName)},
					{GetRegister(Lifter, A)}
				))

			elseif Op == OpCode.GETTABLE then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{MakeIndex(GetRegister(Lifter, B), GetRegister(Lifter, C))}
				))

			elseif Op == OpCode.GETTABLEKS then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{MakeIndex(GetRegister(Lifter, B), GetConstant(Lifter, Aux))}
				))

			elseif Op == OpCode.GETTABLEN then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{MakeIndex(GetRegister(Lifter, B), MakeNumber(C + 1))}
				))

			elseif Op == OpCode.SETTABLE then
				table.insert(Statements, MakeAssign(
					{MakeIndex(GetRegister(Lifter, B), GetRegister(Lifter, C))},
					{GetRegister(Lifter, A)}
				))

			elseif Op == OpCode.SETTABLEKS then
				table.insert(Statements, MakeAssign(
					{MakeIndex(GetRegister(Lifter, B), GetConstant(Lifter, Aux))},
					{GetRegister(Lifter, A)}
				))

			elseif Op == OpCode.SETTABLEN then
				table.insert(Statements, MakeAssign(
					{MakeIndex(GetRegister(Lifter, B), MakeNumber(C + 1))},
					{GetRegister(Lifter, A)}
				))

			elseif BinaryOps[Op] then
				local BinOp = BinaryOps[Op]
				if Op == OpCode.SUBRK or Op == OpCode.DIVRK then
					table.insert(Statements, MakeAssign(
						{GetRegister(Lifter, A)},
						{MakeBinary(GetConstant(Lifter, B), GetRegister(Lifter, C), BinOp)}
					))
				elseif Op >= OpCode.ADDK and Op <= OpCode.POWK or Op == OpCode.IDIVK then
					table.insert(Statements, MakeAssign(
						{GetRegister(Lifter, A)},
						{MakeBinary(GetRegister(Lifter, B), GetConstant(Lifter, C), BinOp)}
					))
				else
					table.insert(Statements, MakeAssign(
						{GetRegister(Lifter, A)},
						{MakeBinary(GetRegister(Lifter, B), GetRegister(Lifter, C), BinOp)}
					))
				end

			elseif UnaryOps[Op] then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{MakeUnary(GetRegister(Lifter, B), UnaryOps[Op])}
				))

			elseif Op == OpCode.AND then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{MakeBinary(GetRegister(Lifter, B), GetRegister(Lifter, C), "And")}
				))

			elseif Op == OpCode.OR then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{MakeBinary(GetRegister(Lifter, B), GetRegister(Lifter, C), "Or")}
				))

			elseif Op == OpCode.ANDK then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{MakeBinary(GetRegister(Lifter, B), GetConstant(Lifter, C), "And")}
				))

			elseif Op == OpCode.ORK then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{MakeBinary(GetRegister(Lifter, B), GetConstant(Lifter, C), "Or")}
				))

			elseif Op == OpCode.CONCAT then
				local Operands = {}
				for R = B, C do
					table.insert(Operands, GetRegister(Lifter, R))
				end
				local Result = Operands[#Operands]
				for I = #Operands - 1, 1, -1 do
					Result = MakeBinary(Operands[I], Result, "Concat")
				end
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{Result}
				))

			elseif Op == OpCode.RETURN then
				local Values
				if B ~= 0 then
					Values = {}
					for R = A, A + B - 2 do
						table.insert(Values, GetRegister(Lifter, R))
					end
				else
					local Tail, TailBase = nil, A
					if Top then
						Tail = Top[1]
						TailBase = Top[2]
						Top = nil
					end
					Values = {}
					if Tail then
						for R = A, TailBase - 1 do
							table.insert(Values, GetRegister(Lifter, R))
						end
						table.insert(Values, Tail)
					end
				end
				table.insert(Statements, MakeReturn(Values))
				break

			elseif Op == OpCode.FASTCALL or Op == OpCode.FASTCALL1
				or Op == OpCode.FASTCALL2 or Op == OpCode.FASTCALL2K
				or Op == OpCode.FASTCALL3 then

			elseif Op == OpCode.NAMECALL then
				local NamecallBase = A
				local NamecallObject = GetRegister(Lifter, B)
				local NamecallMethod = GetConstantString(Lifter, Aux)

				Pc += 1
				Pc += 1
				local CallInsn = Instructions[Pc]
				if CallInsn and CallInsn.Op == OpCode.CALL then
					local CallA, CallB, CallC = CallInsn.A, CallInsn.B, CallInsn.C

					local Args
					if CallB ~= 0 then
						Args = {}
						for R = CallA + 2, CallA + CallB - 1 do
							table.insert(Args, GetRegister(Lifter, R))
						end
					else
						Args = {}
						if Top then
							for R = CallA + 2, Top[2] - 1 do
								table.insert(Args, GetRegister(Lifter, R))
							end
							table.insert(Args, Top[1])
							Top = nil
						end
					end

					local MethodCallExpr = MakeMethodCall(NamecallObject, NamecallMethod, Args)

					if CallC ~= 0 then
						if CallC == 1 then
							table.insert(Statements, MethodCallExpr)
						else
							local Left = {}
							for R = CallA, CallA + CallC - 2 do
								table.insert(Left, GetRegister(Lifter, R))
							end
							table.insert(Statements, MakeAssign(Left, {MakeSelect(MethodCallExpr)}))
						end
					else
						Top = {MethodCallExpr, CallA}
					end
				end

			elseif Op == OpCode.CALL then
				local Args
				if B ~= 0 then
					Args = {}
					for R = A + 1, A + B - 1 do
						table.insert(Args, GetRegister(Lifter, R))
					end
				else
					Args = {}
					if Top then
						for R = A + 1, Top[2] - 1 do
							table.insert(Args, GetRegister(Lifter, R))
						end
						table.insert(Args, Top[1])
						Top = nil
					end
				end

				local CallExpr = MakeCall(GetRegister(Lifter, A), Args)

				if C ~= 0 then
					if C == 1 then
						table.insert(Statements, CallExpr)
					else
						local Left = {}
						for R = A, A + C - 2 do
							table.insert(Left, GetRegister(Lifter, R))
						end
						table.insert(Statements, MakeAssign(Left, {MakeSelect(CallExpr)}))
					end
				else
					Top = {CallExpr, A}
				end

			elseif Op == OpCode.CLOSEUPVALS then
				local Locals = {}
				for R = A, Lifter.Func.MaxStackSize - 1 do
					table.insert(Locals, GetRegister(Lifter, R))
				end
				table.insert(Statements, MakeClose(Locals))

			elseif Op == OpCode.SETLIST then
				local Vals = {}
				if C ~= 0 then
					for R = B, B + C - 2 do
						table.insert(Vals, GetRegister(Lifter, R))
					end
					table.insert(Statements, MakeSetList(GetRegister(Lifter, A), Aux, Vals, nil))
				else
					if Top then
						for R = B, Top[2] - 1 do
							table.insert(Vals, GetRegister(Lifter, R))
						end
						table.insert(Statements, MakeSetList(GetRegister(Lifter, A), Aux, Vals, Top[1]))
						Top = nil
					end
				end

			elseif Op == OpCode.GETVARARGS then
				local VarArgExpr = MakeVarArg()
				if B ~= 0 then
					local Left = {}
					for R = A, A + B - 2 do
						table.insert(Left, GetRegister(Lifter, R))
					end
					table.insert(Statements, MakeAssign(Left, {MakeSelect(VarArgExpr)}))
				else
					Top = {VarArgExpr, A}
				end

			elseif Op == OpCode.CAPTURE then

			elseif Op == OpCode.DEP_FORGLOOP_INEXT or Op == OpCode.DEP_FORGLOOP_NEXT then

			else
				table.insert(Statements, { Tag = "Comment", Text = `Unhandled BC op: {OpCode.Name[Op] or Op}` })
			end

		elseif Insn.Format == "AD" then
			local A, D, Aux = Insn.A, Insn.D, Insn.Aux

			if Op == OpCode.LOADK then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{GetConstant(Lifter, D)}
				))

			elseif Op == OpCode.LOADN then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{MakeNumber(D)}
				))

			elseif Op == OpCode.LOADKX then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{GetConstant(Lifter, Aux)}
				))

			elseif Op == OpCode.GETIMPORT then
				local ImportLen = bit32.band(bit32.rshift(Aux, 30), 3)
				local K0 = bit32.band(bit32.rshift(Aux, 20), 1023)
				local K1 = bit32.band(bit32.rshift(Aux, 10), 1023)
				local K2 = bit32.band(Aux, 1023)

				local Expr = MakeGlobal(GetConstantString(Lifter, K0))
				if ImportLen > 1 then
					Expr = MakeIndex(Expr, GetConstant(Lifter, K1))
				end
				if ImportLen > 2 then
					Expr = MakeIndex(Expr, GetConstant(Lifter, K2))
				end
				table.insert(Statements, MakeAssign({GetRegister(Lifter, A)}, {Expr}))

			elseif Op == OpCode.JUMPIFNOT then
				local Cond = GetRegister(Lifter, A)
				table.insert(Statements, MakeIf(Cond, {}, {}))
				table.insert(Edges, { Target = Pc + 1, Type = "Then" })
				table.insert(Edges, { Target = Pc + 1 + D, Type = "Else" })
				break

			elseif Op == OpCode.JUMPIF then
				local Cond = GetRegister(Lifter, A)
				table.insert(Statements, MakeIf(Cond, {}, {}))
				table.insert(Edges, { Target = Pc + 1 + D, Type = "Then" })
				table.insert(Edges, { Target = Pc + 1, Type = "Else" })
				break

			elseif Op == OpCode.JUMPIFEQ then
				local L = GetRegister(Lifter, A)
				local R = GetRegister(Lifter, Aux)
				table.insert(Statements, MakeIf(MakeBinary(L, R, "Equal"), {}, {}))
				table.insert(Edges, { Target = Pc + 1 + D, Type = "Then" })
				table.insert(Edges, { Target = Pc + 2, Type = "Else" })
				break

			elseif Op == OpCode.JUMPIFLE then
				local L = GetRegister(Lifter, A)
				local R = GetRegister(Lifter, Aux)
				table.insert(Statements, MakeIf(MakeBinary(L, R, "LessEqual"), {}, {}))
				table.insert(Edges, { Target = Pc + 1 + D, Type = "Then" })
				table.insert(Edges, { Target = Pc + 2, Type = "Else" })
				break

			elseif Op == OpCode.JUMPIFLT then
				local L = GetRegister(Lifter, A)
				local R = GetRegister(Lifter, Aux)
				table.insert(Statements, MakeIf(MakeBinary(L, R, "LessThan"), {}, {}))
				table.insert(Edges, { Target = Pc + 1 + D, Type = "Then" })
				table.insert(Edges, { Target = Pc + 2, Type = "Else" })
				break

			elseif Op == OpCode.JUMPIFNOTEQ then
				local L = GetRegister(Lifter, A)
				local R = GetRegister(Lifter, Aux)
				table.insert(Statements, MakeIf(MakeBinary(L, R, "Equal"), {}, {}))
				table.insert(Edges, { Target = Pc + 2, Type = "Then" })
				table.insert(Edges, { Target = Pc + 1 + D, Type = "Else" })
				break

			elseif Op == OpCode.JUMPIFNOTLE then
				local L = GetRegister(Lifter, A)
				local R = GetRegister(Lifter, Aux)
				table.insert(Statements, MakeIf(MakeBinary(L, R, "LessEqual"), {}, {}))
				table.insert(Edges, { Target = Pc + 2, Type = "Then" })
				table.insert(Edges, { Target = Pc + 1 + D, Type = "Else" })
				break

			elseif Op == OpCode.JUMPIFNOTLT then
				local L = GetRegister(Lifter, A)
				local R = GetRegister(Lifter, Aux)
				table.insert(Statements, MakeIf(MakeBinary(L, R, "LessThan"), {}, {}))
				table.insert(Edges, { Target = Pc + 2, Type = "Then" })
				table.insert(Edges, { Target = Pc + 1 + D, Type = "Else" })
				break

			elseif Op == OpCode.JUMPXEQKNIL then
				local L = GetRegister(Lifter, A)
				local Inverted = bit32.band(Aux, bit32.lshift(1, 31)) ~= 0
				table.insert(Statements, MakeIf(MakeBinary(L, MakeNil(), "Equal"), {}, {}))
				if Inverted then
					table.insert(Edges, { Target = Pc + 1 + D, Type = "Else" })
					table.insert(Edges, { Target = Pc + 2, Type = "Then" })
				else
					table.insert(Edges, { Target = Pc + 1 + D, Type = "Then" })
					table.insert(Edges, { Target = Pc + 2, Type = "Else" })
				end
				break

			elseif Op == OpCode.JUMPXEQKB then
				local L = GetRegister(Lifter, A)
				local BoolVal = bit32.band(Aux, 1) ~= 0
				local Inverted = bit32.band(Aux, bit32.lshift(1, 31)) ~= 0
				table.insert(Statements, MakeIf(MakeBinary(L, MakeBool(BoolVal), "Equal"), {}, {}))
				if Inverted then
					table.insert(Edges, { Target = Pc + 1 + D, Type = "Else" })
					table.insert(Edges, { Target = Pc + 2, Type = "Then" })
				else
					table.insert(Edges, { Target = Pc + 1 + D, Type = "Then" })
					table.insert(Edges, { Target = Pc + 2, Type = "Else" })
				end
				break

			elseif Op == OpCode.JUMPXEQKN or Op == OpCode.JUMPXEQKS then
				local L = GetRegister(Lifter, A)
				local ConstIdx = bit32.band(Aux, bit32.lshift(1, 24) - 1)
				local Inverted = bit32.band(Aux, bit32.lshift(1, 31)) ~= 0
				local Lit = GetConstant(Lifter, ConstIdx)
				table.insert(Statements, MakeIf(MakeBinary(L, Lit, "Equal"), {}, {}))
				if Inverted then
					table.insert(Edges, { Target = Pc + 1 + D, Type = "Else" })
					table.insert(Edges, { Target = Pc + 2, Type = "Then" })
				else
					table.insert(Edges, { Target = Pc + 1 + D, Type = "Then" })
					table.insert(Edges, { Target = Pc + 2, Type = "Else" })
				end
				break

			elseif Op == OpCode.JUMP or Op == OpCode.JUMPBACK then
				table.insert(Edges, { Target = Pc + 1 + D, Type = "Unconditional" })
				break

			elseif Op == OpCode.JUMPX then
				table.insert(Edges, { Target = Pc + 1 + Insn.E, Type = "Unconditional" })
				break

			elseif Op == OpCode.FORNPREP then
				local Limit = GetRegister(Lifter, A)
				local Step = GetRegister(Lifter, A + 1)
				local Counter = GetRegister(Lifter, A + 2)
				table.insert(Statements, MakeNumForInit(Counter, Limit, Step))
				table.insert(Edges, { Target = Pc + 1 + D, Type = "Unconditional" })
				break

			elseif Op == OpCode.FORNLOOP then
				local Limit = GetRegister(Lifter, A)
				local Step = GetRegister(Lifter, A + 1)
				local Counter = GetRegister(Lifter, A + 2)
				local LoopVar = GetRegister(Lifter, A + 3)
				table.insert(Statements, MakeNumForNext(Counter, Limit, Step, LoopVar))
				table.insert(Edges, { Target = Pc + 1 + D, Type = "Then" })
				table.insert(Edges, { Target = Pc + 1, Type = "Else" })
				break

			elseif Op == OpCode.FORGPREP or Op == OpCode.FORGPREP_INEXT or Op == OpCode.FORGPREP_NEXT then
				local Generator = GetRegister(Lifter, A)
				local State = GetRegister(Lifter, A + 1)
				local Control = GetRegister(Lifter, A + 2)
				table.insert(Statements, MakeGenericForInit(Generator, State, Control))
				table.insert(Edges, { Target = Pc + 1 + D, Type = "Unconditional" })
				break

			elseif Op == OpCode.FORGLOOP then
				local Generator = GetRegister(Lifter, A)
				local State = GetRegister(Lifter, A + 1)
				local VarCount = bit32.band(Aux, 0xFF)
				local Vars = {}
				for I = 0, VarCount - 1 do
					table.insert(Vars, GetRegister(Lifter, A + 3 + I))
				end
				table.insert(Statements, MakeGenericForNext(Vars, Generator, State))
				table.insert(Edges, { Target = Pc + 1 + D, Type = "Then" })
				table.insert(Edges, { Target = Pc + 1, Type = "Else" })
				break

			elseif Op == OpCode.DUPTABLE then
				table.insert(Statements, MakeAssign(
					{GetRegister(Lifter, A)},
					{MakeTable()}
				))

			elseif Op == OpCode.NEWCLOSURE or Op == OpCode.DUPCLOSURE then
				local DestLocal = GetRegister(Lifter, A)
				local ChildFuncIndex
				if Op == OpCode.NEWCLOSURE then
					ChildFuncIndex = Lifter.Func.Children and Lifter.Func.Children[D + 1]
				else
					local ConstEntry = Lifter.Func.Constants[D + 1]
					if ConstEntry and ConstEntry.Type == "Closure" then
						ChildFuncIndex = ConstEntry.FuncId
					else
						ChildFuncIndex = D
					end
				end

				if ChildFuncIndex == nil then
					ChildFuncIndex = D
				end

				local ChildFunc = Lifter.Chunk.Functions[(ChildFuncIndex or 0) + 1]
				local UpvaluesPassed = {}
				if ChildFunc then
					for _ = 1, ChildFunc.NumUpvalues do
						Pc += 1
						local CapInsn = Instructions[Pc]
						if CapInsn and CapInsn.Op == OpCode.CAPTURE then
							local CaptureType = CapInsn.A
							local Source = CapInsn.B
							if CaptureType == 0 then
								table.insert(UpvaluesPassed, { Type = "Value", Local = GetRegister(Lifter, Source) })
							elseif CaptureType == 1 then
								table.insert(UpvaluesPassed, { Type = "Ref", Local = GetRegister(Lifter, Source) })
							elseif CaptureType == 2 then
								table.insert(UpvaluesPassed, { Type = "Upvalue", Local = Lifter.Upvalues[Source + 1] or MakeLocal(-Source - 1) })
							end
						end
					end
				end

				local ClosureNode = MakeClosure(ChildFuncIndex, UpvaluesPassed)

				local ChildFuncName = nil
				if ChildFunc and ChildFunc.FunctionName and ChildFunc.FunctionName > 0 then
					ChildFuncName = Lifter.Chunk.StringTable[ChildFunc.FunctionName]
				end
				if ChildFuncName and #ChildFuncName > 0 then
					ClosureNode.FuncName = ChildFuncName
				end

				table.insert(Lifter.ChildClosures, { FuncIndex = ChildFuncIndex, Node = ClosureNode })
				table.insert(Statements, MakeAssign({DestLocal}, {ClosureNode}))

			else
				table.insert(Statements, { Tag = "Comment", Text = `Unhandled AD op: {OpCode.Name[Op] or Op}` })
			end

		elseif Insn.Format == "E" then
			if Op == OpCode.JUMPX then
				table.insert(Edges, { Target = Pc + 1 + Insn.E, Type = "Unconditional" })
				break
			elseif Op == OpCode.COVERAGE then

			else
				table.insert(Statements, { Tag = "Comment", Text = `Unhandled E op: {OpCode.Name[Op] or Op}` })
			end
		end

		Pc += 1
	end

	if #Edges == 0 then
		local LastInsn = Instructions[math.min(Pc, #Instructions)]
		if LastInsn then
			local LastOp = LastInsn.Op
			local IsTerminator = (LastOp == OpCode.RETURN)
				or (LastOp == OpCode.JUMP) or (LastOp == OpCode.JUMPBACK) or (LastOp == OpCode.JUMPX)
				or (LastOp == OpCode.JUMPIF) or (LastOp == OpCode.JUMPIFNOT)
				or (LastOp == OpCode.JUMPIFEQ) or (LastOp == OpCode.JUMPIFLE) or (LastOp == OpCode.JUMPIFLT)
				or (LastOp == OpCode.JUMPIFNOTEQ) or (LastOp == OpCode.JUMPIFNOTLE) or (LastOp == OpCode.JUMPIFNOTLT)
				or (LastOp == OpCode.JUMPXEQKNIL) or (LastOp == OpCode.JUMPXEQKB)
				or (LastOp == OpCode.JUMPXEQKN) or (LastOp == OpCode.JUMPXEQKS)
				or (LastOp == OpCode.FORNPREP) or (LastOp == OpCode.FORNLOOP)
				or (LastOp == OpCode.FORGPREP) or (LastOp == OpCode.FORGPREP_INEXT)
				or (LastOp == OpCode.FORGPREP_NEXT) or (LastOp == OpCode.FORGLOOP)
				or (LastOp == OpCode.LOADB and LastInsn.C ~= 0)

			if not IsTerminator and BlockEnd + 1 <= #Instructions then
				table.insert(Edges, { Target = BlockEnd + 1, Type = "Unconditional" })
			end
		end
	end

	return Statements, Edges
end

return InstructionLifter
