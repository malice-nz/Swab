local ExpressionFolding = {}

local function GetLocalId(Node)
	if Node and Node.Tag == "Local" then
		return Node.Id
	end
	return nil
end

local function CollectReferencedLocals(Expr, Out)
	if not Expr then return end
	if Expr.Tag == "Local" then
		Out[Expr.Id] = true
	elseif Expr.Tag == "Binary" then
		CollectReferencedLocals(Expr.Left, Out)
		CollectReferencedLocals(Expr.Right, Out)
	elseif Expr.Tag == "Unary" then
		CollectReferencedLocals(Expr.Value, Out)
	elseif Expr.Tag == "Index" then
		CollectReferencedLocals(Expr.Object, Out)
		CollectReferencedLocals(Expr.Key, Out)
	elseif Expr.Tag == "Call" then
		CollectReferencedLocals(Expr.Function, Out)
		for _, Arg in Expr.Args do
			CollectReferencedLocals(Arg, Out)
		end
	elseif Expr.Tag == "MethodCall" then
		CollectReferencedLocals(Expr.Object, Out)
		for _, Arg in Expr.Args do
			CollectReferencedLocals(Arg, Out)
		end
	elseif Expr.Tag == "Select" then
		CollectReferencedLocals(Expr.Inner, Out)
	elseif Expr.Tag == "Closure" then
		for _, Upval in Expr.Upvalues or {} do
			if Upval.Local and Upval.Local.Tag == "Local" then
				Out[Upval.Local.Id] = true
			end
		end
	end
end

local function HasSideEffects(Expr)
	if not Expr then return false end
	if Expr.Tag == "Call" or Expr.Tag == "MethodCall" then
		return true
	elseif Expr.Tag == "Binary" then
		return HasSideEffects(Expr.Left) or HasSideEffects(Expr.Right)
	elseif Expr.Tag == "Unary" then
		return HasSideEffects(Expr.Value)
	elseif Expr.Tag == "Index" then
		return HasSideEffects(Expr.Object) or HasSideEffects(Expr.Key)
	elseif Expr.Tag == "Select" then
		return HasSideEffects(Expr.Inner)
	end
	return false
end

local function CountUsesInExpr(Expr, Id)
	if not Expr then return 0 end
	if Expr.Tag == "Local" and Expr.Id == Id then
		return 1
	elseif Expr.Tag == "Binary" then
		return CountUsesInExpr(Expr.Left, Id) + CountUsesInExpr(Expr.Right, Id)
	elseif Expr.Tag == "Unary" then
		return CountUsesInExpr(Expr.Value, Id)
	elseif Expr.Tag == "Index" then
		return CountUsesInExpr(Expr.Object, Id) + CountUsesInExpr(Expr.Key, Id)
	elseif Expr.Tag == "Call" then
		local N = CountUsesInExpr(Expr.Function, Id)
		for _, Arg in Expr.Args do
			N += CountUsesInExpr(Arg, Id)
		end
		return N
	elseif Expr.Tag == "MethodCall" then
		local N = CountUsesInExpr(Expr.Object, Id)
		for _, Arg in Expr.Args do
			N += CountUsesInExpr(Arg, Id)
		end
		return N
	elseif Expr.Tag == "Select" then
		return CountUsesInExpr(Expr.Inner, Id)
	elseif Expr.Tag == "Closure" then
		for _, Upval in Expr.Upvalues or {} do
			if Upval.Local and Upval.Local.Tag == "Local" and Upval.Local.Id == Id then
				return 100
			end
		end
		return 0
	end
	return 0
end

local function CountUsesInStmt(Stmt, Id)
	if not Stmt then return 0 end
	local Tag = Stmt.Tag
	if Tag == "Assign" then
		local N = 0
		for _, R in Stmt.Right do
			N += CountUsesInExpr(R, Id)
		end
		for _, L in Stmt.Left do
			if L.Tag ~= "Local" then
				N += CountUsesInExpr(L, Id)
			end
		end
		return N
	elseif Tag == "Return" then
		local N = 0
		for _, V in Stmt.Values or {} do
			N += CountUsesInExpr(V, Id)
		end
		return N
	elseif Tag == "Call" or Tag == "MethodCall" then
		return CountUsesInExpr(Stmt, Id)
	elseif Tag == "If" then
		local N = CountUsesInExpr(Stmt.Condition, Id)
		for _, S in Stmt.ThenBlock or {} do N += CountUsesInStmt(S, Id) end
		for _, S in Stmt.ElseBlock or {} do N += CountUsesInStmt(S, Id) end
		return N
	elseif Tag == "While" then
		return CountUsesInExpr(Stmt.Condition, Id) + CountUsesInBlock(Stmt.Body, Id)
	elseif Tag == "Repeat" then
		return CountUsesInBlock(Stmt.Body, Id) + CountUsesInExpr(Stmt.Condition, Id)
	elseif Tag == "NumericFor" then
		return CountUsesInExpr(Stmt.Start, Id) + CountUsesInExpr(Stmt.Limit, Id)
			+ CountUsesInExpr(Stmt.Step, Id) + CountUsesInBlock(Stmt.Body, Id)
	elseif Tag == "GenericFor" then
		local N = 0
		for _, It in Stmt.Iterators or {} do N += CountUsesInExpr(It, Id) end
		N += CountUsesInBlock(Stmt.Body, Id)
		return N
	elseif Tag == "SetList" then
		local N = CountUsesInExpr(Stmt.Table, Id)
		for _, V in Stmt.Values or {} do N += CountUsesInExpr(V, Id) end
		if Stmt.Tail then N += CountUsesInExpr(Stmt.Tail, Id) end
		return N
	end
	return 0
end

function CountUsesInBlock(Stmts, Id)
	local N = 0
	for _, S in Stmts or {} do
		N += CountUsesInStmt(S, Id)
	end
	return N
end

local function SubstituteInExpr(Expr, Id, Replacement)
	if not Expr then return Expr end
	if Expr.Tag == "Local" and Expr.Id == Id then
		return Replacement
	elseif Expr.Tag == "Binary" then
		Expr.Left = SubstituteInExpr(Expr.Left, Id, Replacement)
		Expr.Right = SubstituteInExpr(Expr.Right, Id, Replacement)
	elseif Expr.Tag == "Unary" then
		Expr.Value = SubstituteInExpr(Expr.Value, Id, Replacement)
	elseif Expr.Tag == "Index" then
		Expr.Object = SubstituteInExpr(Expr.Object, Id, Replacement)
		Expr.Key = SubstituteInExpr(Expr.Key, Id, Replacement)
	elseif Expr.Tag == "Call" then
		Expr.Function = SubstituteInExpr(Expr.Function, Id, Replacement)
		for I, Arg in Expr.Args do
			Expr.Args[I] = SubstituteInExpr(Arg, Id, Replacement)
		end
	elseif Expr.Tag == "MethodCall" then
		Expr.Object = SubstituteInExpr(Expr.Object, Id, Replacement)
		for I, Arg in Expr.Args do
			Expr.Args[I] = SubstituteInExpr(Arg, Id, Replacement)
		end
	elseif Expr.Tag == "Select" then
		Expr.Inner = SubstituteInExpr(Expr.Inner, Id, Replacement)
	elseif Expr.Tag == "Closure" then
		-- Don't substitute into closure upvalue captures
	end
	return Expr
end

local function SubstituteInStmt(Stmt, Id, Replacement)
	if not Stmt then return end
	local Tag = Stmt.Tag
	if Tag == "Assign" then
		for I, R in Stmt.Right do
			Stmt.Right[I] = SubstituteInExpr(R, Id, Replacement)
		end
		for I, L in Stmt.Left do
			if L.Tag ~= "Local" then
				Stmt.Left[I] = SubstituteInExpr(L, Id, Replacement)
			end
		end
	elseif Tag == "Return" then
		for I, V in Stmt.Values or {} do
			Stmt.Values[I] = SubstituteInExpr(V, Id, Replacement)
		end
	elseif Tag == "Call" then
		Stmt.Function = SubstituteInExpr(Stmt.Function, Id, Replacement)
		for I, Arg in Stmt.Args do
			Stmt.Args[I] = SubstituteInExpr(Arg, Id, Replacement)
		end
	elseif Tag == "MethodCall" then
		Stmt.Object = SubstituteInExpr(Stmt.Object, Id, Replacement)
		for I, Arg in Stmt.Args do
			Stmt.Args[I] = SubstituteInExpr(Arg, Id, Replacement)
		end
	elseif Tag == "SetList" then
		Stmt.Table = SubstituteInExpr(Stmt.Table, Id, Replacement)
		for I, V in Stmt.Values or {} do
			Stmt.Values[I] = SubstituteInExpr(V, Id, Replacement)
		end
		if Stmt.Tail then
			Stmt.Tail = SubstituteInExpr(Stmt.Tail, Id, Replacement)
		end
	elseif Tag == "If" then
		Stmt.Condition = SubstituteInExpr(Stmt.Condition, Id, Replacement)
		for _, S in Stmt.ThenBlock or {} do SubstituteInStmt(S, Id, Replacement) end
		for _, S in Stmt.ElseBlock or {} do SubstituteInStmt(S, Id, Replacement) end
	elseif Tag == "While" then
		Stmt.Condition = SubstituteInExpr(Stmt.Condition, Id, Replacement)
		for _, S in Stmt.Body or {} do SubstituteInStmt(S, Id, Replacement) end
	elseif Tag == "Repeat" then
		for _, S in Stmt.Body or {} do SubstituteInStmt(S, Id, Replacement) end
		Stmt.Condition = SubstituteInExpr(Stmt.Condition, Id, Replacement)
	elseif Tag == "NumericFor" then
		Stmt.Start = SubstituteInExpr(Stmt.Start, Id, Replacement)
		Stmt.Limit = SubstituteInExpr(Stmt.Limit, Id, Replacement)
		Stmt.Step = SubstituteInExpr(Stmt.Step, Id, Replacement)
		for _, S in Stmt.Body or {} do SubstituteInStmt(S, Id, Replacement) end
	elseif Tag == "GenericFor" then
		for I, It in Stmt.Iterators or {} do
			Stmt.Iterators[I] = SubstituteInExpr(It, Id, Replacement)
		end
		for _, S in Stmt.Body or {} do SubstituteInStmt(S, Id, Replacement) end
	end
end

local function CollectAssignedLocals(Stmt, Out)
	if not Stmt then return end
	local Tag = Stmt.Tag
	if Tag == "Assign" then
		for _, L in Stmt.Left do
			local Id = GetLocalId(L)
			if Id then Out[Id] = true end
		end
	elseif Tag == "If" then
		for _, S in Stmt.ThenBlock or {} do CollectAssignedLocals(S, Out) end
		for _, S in Stmt.ElseBlock or {} do CollectAssignedLocals(S, Out) end
	elseif Tag == "While" or Tag == "Repeat" then
		for _, S in Stmt.Body or {} do CollectAssignedLocals(S, Out) end
	elseif Tag == "NumericFor" then
		local Id = GetLocalId(Stmt.Var)
		if Id then Out[Id] = true end
		for _, S in Stmt.Body or {} do CollectAssignedLocals(S, Out) end
	elseif Tag == "GenericFor" then
		for _, V in Stmt.Vars or {} do
			local Id = GetLocalId(V)
			if Id then Out[Id] = true end
		end
		for _, S in Stmt.Body or {} do CollectAssignedLocals(S, Out) end
	end
end

local FoldBlock

local function IsSimpleExpr(Expr)
	if not Expr then return true end
	local Tag = Expr.Tag
	return Tag == "Literal" or Tag == "Global" or Tag == "Local"
		or Tag == "VarArg" or Tag == "Table"
end

local function IsSafeToInline(RHS, Id, NextStmt)
	local RHSHasSideEffects = HasSideEffects(RHS)
	if RHSHasSideEffects then
		if not NextStmt then return false end
		local Tag = NextStmt.Tag
		if Tag == "Assign" then
			local UseCount = 0
			for _, R in NextStmt.Right do
				UseCount += CountUsesInExpr(R, Id)
			end
			if UseCount ~= 1 then return false end
			for _, L in NextStmt.Left do
				if L.Tag ~= "Local" then
					UseCount += CountUsesInExpr(L, Id)
				end
			end
			if UseCount ~= 1 then return false end
			return true
		elseif Tag == "Call" or Tag == "MethodCall" or Tag == "Return" then
			return true
		elseif Tag == "If" then
			return CountUsesInExpr(NextStmt.Condition, Id) == 1
		elseif Tag == "While" then
			return CountUsesInExpr(NextStmt.Condition, Id) == 1
		elseif Tag == "GenericFor" then
			local N = 0
			for _, It in NextStmt.Iterators or {} do
				N += CountUsesInExpr(It, Id)
			end
			return N == 1
		end
		return false
	end
	return true
end

local SilentTags = {
	Close = true, NumForInit = true, NumForNext = true,
	GenericForInit = true, GenericForNext = true, Comment = true,
}

local function IsEffectivelyEmpty(Block)
	if not Block or #Block == 0 then return true end
	for _, S in Block do
		if not SilentTags[S.Tag] then return false end
	end
	return true
end

local function StripSilent(Block)
	if not Block then return Block end
	local Out = {}
	for _, S in Block do
		if not SilentTags[S.Tag] then
			table.insert(Out, S)
		end
	end
	return Out
end

FoldBlock = function(Stmts)
	if not Stmts or #Stmts == 0 then return Stmts end

	local Changed = true
	while Changed do
		Changed = false

		for _, Stmt in Stmts do
			if Stmt.Tag == "If" then
				Stmt.ThenBlock = FoldBlock(Stmt.ThenBlock)
				Stmt.ElseBlock = FoldBlock(Stmt.ElseBlock)
			elseif Stmt.Tag == "While" then
				Stmt.Body = FoldBlock(Stmt.Body)
			elseif Stmt.Tag == "Repeat" then
				Stmt.Body = FoldBlock(Stmt.Body)
			elseif Stmt.Tag == "NumericFor" then
				Stmt.Body = FoldBlock(Stmt.Body)
			elseif Stmt.Tag == "GenericFor" then
				Stmt.Body = FoldBlock(Stmt.Body)
			end
		end

		local NewStmts = {}
		local Skip = {}

		for I = 1, #Stmts do
			if Skip[I] then continue end
			local Stmt = Stmts[I]

			if Stmt.Tag == "Assign" and #Stmt.Left == 1 and #Stmt.Right == 1 then
				local Id = GetLocalId(Stmt.Left[1])
				if Id ~= nil then
					local RHS = Stmt.Right[1]

					local TotalUses = 0
					local FirstUseIdx = nil
					for J = I + 1, #Stmts do
						local SJ = Stmts[J]
						local UsesHere = CountUsesInStmt(SJ, Id)
						TotalUses += UsesHere
						if UsesHere > 0 and not FirstUseIdx then
							FirstUseIdx = J
						end
						if SJ.Tag == "Assign" then
							local ReassignsId = false
							for _, L in SJ.Left do
								if GetLocalId(L) == Id then
									ReassignsId = true
									break
								end
							end
							if ReassignsId then
								break
							end
						end
					end

					if TotalUses == 0 and not HasSideEffects(RHS) then
						Changed = true
						continue
					end

					-- Copy propagation: local A = B (where B is a simple Local)
					-- Replace all uses of A with B and remove the assignment
					-- Only safe when neither A nor B is reassigned in remaining scope
					if RHS.Tag == "Local" and TotalUses > 0 then
						local SrcId = RHS.Id
						local TargetReassigned = false
						local SourceReassigned = false
						for J = I + 1, #Stmts do
							local Assigned = {}
							CollectAssignedLocals(Stmts[J], Assigned)
							if Assigned[Id] then TargetReassigned = true end
							if Assigned[SrcId] then SourceReassigned = true end
							if TargetReassigned or SourceReassigned then break end
						end
						if not TargetReassigned and not SourceReassigned then
							for J = I + 1, #Stmts do
								SubstituteInStmt(Stmts[J], Id, RHS)
							end
							Changed = true
							continue
						end
					end

					if TotalUses == 1 then
						if FirstUseIdx then
							local NextIdx = FirstUseIdx
							local NextStmt = Stmts[NextIdx]

							-- Check if this is a table→field setter pattern
							-- Skip inlining so the table constructor fold can handle it
							local IsTableFieldPattern = false
							if RHS.Tag == "Table" and NextStmt then
								if NextStmt.Tag == "Assign" then
									for _, L in NextStmt.Left do
										if L.Tag == "Index" and L.Object and L.Object.Tag == "Local" and L.Object.Id == Id then
											IsTableFieldPattern = true
											break
										end
									end
								elseif NextStmt.Tag == "SetList" then
									if NextStmt.Table and NextStmt.Table.Tag == "Local" and GetLocalId(NextStmt.Table) == Id then
										IsTableFieldPattern = true
									end
								end
							end

							if not IsTableFieldPattern then
								local Safe = true
								local Refs = {}
								CollectReferencedLocals(RHS, Refs)

								for J = I + 1, NextIdx - 1 do
									local Assigned = {}
									CollectAssignedLocals(Stmts[J], Assigned)
									for RefId in Refs do
										if Assigned[RefId] then
											Safe = false
											break
										end
									end
									if not Safe then break end
									if Assigned[Id] then
										Safe = false
										break
									end
								end

								if Safe and NextIdx == I + 1 and IsSafeToInline(RHS, Id, NextStmt) then
									SubstituteInStmt(NextStmt, Id, RHS)
									Changed = true
									continue
								elseif Safe and not HasSideEffects(RHS) then
									SubstituteInStmt(Stmts[NextIdx], Id, RHS)
									Changed = true
									continue
								end
							end
						end
					end
				end
			end

			-- For-in iterator inlining: local v1,v2,v3 = call() → for k,v in call() do
			if Stmt.Tag == "Assign" and #Stmt.Left > 1 and #Stmt.Right == 1 then
				local RHS = Stmt.Right[1]
				local InnerCall = if RHS and RHS.Tag == "Select" then RHS.Inner else RHS
				local NextI = I + 1
				while NextI <= #Stmts and Skip[NextI] do NextI += 1 end
				local NextStmt = Stmts[NextI]

				if NextStmt and NextStmt.Tag == "GenericFor" then
					local Iters = NextStmt.Iterators
					if Iters and #Iters == #Stmt.Left then
						local AllMatch = true
						for K = 1, #Stmt.Left do
							local LId = GetLocalId(Stmt.Left[K])
							local ItId = GetLocalId(Iters[K])
							if LId == nil or ItId == nil or LId ~= ItId then
								AllMatch = false
								break
							end
						end
						if AllMatch then
							-- For-in setup registers are ephemeral VM state (generator, state, control)
							-- They are dead after the loop by Luau semantics, so register reuse is expected
							NextStmt.Iterators = { InnerCall }
							Changed = true
							continue
						end
					end
				end
			end

			-- Table constructor folding: v = {} ; v.k = expr → v = {k = expr}
			if Stmt.Tag == "Assign" and #Stmt.Left == 1 and #Stmt.Right == 1 then
				local Id = GetLocalId(Stmt.Left[1])
				local RHS = Stmt.Right[1]
				if Id ~= nil and RHS and RHS.Tag == "Table" then
					local Fields = if RHS.Fields then table.clone(RHS.Fields) else {}
					local FieldCount = 0
					local SkipCount = 0
					local J = I + 1
					while J <= #Stmts do
						local SJ = Stmts[J]
						if SJ.Tag == "Assign" and #SJ.Left == 1 and #SJ.Right == 1
							and SJ.Left[1].Tag == "Index"
							and SJ.Left[1].Object and SJ.Left[1].Object.Tag == "Local"
							and SJ.Left[1].Object.Id == Id then
							local FieldVal = SJ.Right[1]
							if CountUsesInExpr(FieldVal, Id) > 0 then break end
							FieldCount += 1
							SkipCount += 1
							table.insert(Fields, { Key = SJ.Left[1].Key, Value = FieldVal })
							J += 1
						elseif SJ.Tag == "SetList"
							and SJ.Table and SJ.Table.Tag == "Local"
							and GetLocalId(SJ.Table) == Id then
							local StartIdx = SJ.StartIndex or 0
							local CanFold = true
							for _, V in SJ.Values or {} do
								if CountUsesInExpr(V, Id) > 0 then
									CanFold = false
									break
								end
							end
							if SJ.Tail and CountUsesInExpr(SJ.Tail, Id) > 0 then
								CanFold = false
							end
							if not CanFold then break end
							for VI, V in SJ.Values or {} do
								FieldCount += 1
								if StartIdx == 0 then
									table.insert(Fields, { Key = nil, Value = V })
								else
									table.insert(Fields, {
										Key = { Tag = "Literal", LiteralType = "Number", Value = StartIdx + VI },
										Value = V
									})
								end
							end
							if SJ.Tail then
								FieldCount += 1
								table.insert(Fields, { Key = nil, Value = SJ.Tail })
							end
							SkipCount += 1
							J += 1
						else
							break
						end
					end
					if FieldCount > 0 then
						-- Deduplicate keys (keep last assignment)
						local Seen = {}
						for FI = #Fields, 1, -1 do
							local K = Fields[FI].Key
							if K then
								local KStr = if K.Tag == "Literal" then tostring(K.Value) else tostring(K)
								if Seen[KStr] then
									table.remove(Fields, FI)
								else
									Seen[KStr] = true
								end
							end
						end
						RHS.Fields = Fields
						for K = I + 1, I + SkipCount do
							Skip[K] = true
						end
						Changed = true
					end
				end
			end

			-- Empty If elimination
			if Stmt.Tag == "If" then
				local ThenEmpty = IsEffectivelyEmpty(Stmt.ThenBlock)
				local ElseEmpty = IsEffectivelyEmpty(Stmt.ElseBlock)
				if ThenEmpty and ElseEmpty then
					if HasSideEffects(Stmt.Condition) then
						table.insert(NewStmts, Stmt.Condition)
					end
					Changed = true
					continue
				end
				if ThenEmpty and not ElseEmpty then
					-- Flip: if cond then end else B end → if not cond then B end
					Stmt.Condition = { Tag = "Unary", Op = "not", Value = Stmt.Condition }
					Stmt.ThenBlock = StripSilent(Stmt.ElseBlock)
					Stmt.ElseBlock = nil
					Changed = true
				end
			end

			table.insert(NewStmts, Stmt)
		end

		Stmts = NewStmts
	end

	return Stmts
end

function ExpressionFolding.Fold(Stmts)
	return FoldBlock(Stmts)
end

return ExpressionFolding
