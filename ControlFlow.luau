local ControlFlow = {}

function ControlFlow.Recover(LiftedFunc, Deadline)
	local Blocks = LiftedFunc.Blocks
	local NumBlocks = #Blocks

	if NumBlocks == 0 then
		return {}
	end

	local LoopEnd = {}
	for I = 1, NumBlocks do
		local Block = Blocks[I]
		if Block then
			for _, Edge in Block.Edges do
				if Edge.Target <= I then
					if not LoopEnd[Edge.Target] or I > LoopEnd[Edge.Target] then
						LoopEnd[Edge.Target] = I
					end
				end
			end
		end
	end

	local function GetEdge(Edges, Type)
		for _, E in Edges do
			if E.Type == Type then
				return E.Target
			end
		end
		return nil
	end

	local function ExtractForInit(Stmts, InitLocals)
		local Values = {}
		local Remaining = {}
		local Found = {}

		for I = #Stmts, 1, -1 do
			local Stmt = Stmts[I]
			if Stmt.Tag == "Assign" and #Stmt.Left == 1 and #Stmt.Right == 1 and not Found[Stmt.Left[1]] then
				local Match = false
				for _, L in InitLocals do
					if Stmt.Left[1] == L and not Found[L] then
						Values[L] = Stmt.Right[1]
						Found[L] = true
						Match = true
						break
					end
				end
				if not Match then
					table.insert(Remaining, 1, Stmt)
				end
			else
				table.insert(Remaining, 1, Stmt)
			end
		end

		return Remaining, Values
	end

	local GlobalVisited = {}

	local function Structure(RangeStart, RangeEnd, BreakTarget, ContinueTarget)
		local Result = {}
		local I = RangeStart

		while I >= 1 and I <= RangeEnd do
if Deadline and os.clock() > Deadline then error("Timeout") end
			if GlobalVisited[I] then
				break
			end
			GlobalVisited[I] = true
			local Block = Blocks[I]
			if not Block then
				I += 1
				continue
			end

			local Stmts = Block.Statements
			local LastStmt = Stmts[#Stmts]

			if LastStmt and (LastStmt.Tag == "NumForInit" or LastStmt.Tag == "GenericForInit") then
				local PrepEdge = Block.Edges[1]
				if PrepEdge and PrepEdge.Target > I and PrepEdge.Target <= NumBlocks then
					local TestIdx = PrepEdge.Target
					local TestBlock = Blocks[TestIdx]
					local TestStmt = TestBlock and TestBlock.Statements[#TestBlock.Statements]

					if TestStmt and TestStmt.Tag == "NumForNext" then
						local BodyStart = I + 1
						local BodyEnd = TestIdx - 1
						local ExitTarget = TestIdx + 1

						local PreStmts, InitValues = ExtractForInit(
							{table.unpack(Stmts, 1, #Stmts - 1)},
							{LastStmt.Counter, LastStmt.Limit, LastStmt.Step}
						)
						for _, S in PreStmts do
							table.insert(Result, S)
						end

						local LoopVar = TestStmt.LoopVar or TestStmt.Counter
						local StartExpr = InitValues[LastStmt.Counter] or LastStmt.Counter
						local LimitExpr = InitValues[LastStmt.Limit] or LastStmt.Limit
						local StepExpr = InitValues[LastStmt.Step] or LastStmt.Step

						local Body = {}
						if BodyEnd >= BodyStart then
							Body = Structure(BodyStart, BodyEnd, ExitTarget, TestIdx)
						end

						table.insert(Result, {
							Tag = "NumericFor",
							Var = LoopVar,
							Start = StartExpr,
							Limit = LimitExpr,
							Step = StepExpr,
							Body = Body,
						})
						I = ExitTarget
						continue
					elseif TestStmt and TestStmt.Tag == "GenericForNext" then
						local BodyStart = I + 1
						local BodyEnd = TestIdx - 1
						local ExitTarget = TestIdx + 1

						local PreStmts = {}
						for J = 1, #Stmts - 1 do
							table.insert(PreStmts, Stmts[J])
						end
						for _, S in PreStmts do
							table.insert(Result, S)
						end

						local Body = {}
						if BodyEnd >= BodyStart then
							Body = Structure(BodyStart, BodyEnd, ExitTarget, TestIdx)
						end

						table.insert(Result, {
							Tag = "GenericFor",
							Vars = TestStmt.Vars,
							Iterators = {LastStmt.Generator, LastStmt.State, LastStmt.Control},
							Body = Body,
						})
						I = ExitTarget
						continue
					end
				end
			end

			local LoopEndIdx = LoopEnd[I]
			if LoopEndIdx and LoopEndIdx <= RangeEnd and LoopEndIdx > I then
				local LoopEndBlk = Blocks[LoopEndIdx]

				local ExitTarget = LoopEndIdx + 1
				if LoopEndBlk then
					for _, Edge in LoopEndBlk.Edges do
						if Edge.Target > LoopEndIdx or Edge.Target < I then
							ExitTarget = Edge.Target
							break
						end
					end
				end

				if LastStmt and LastStmt.Tag == "If" and #Block.Edges == 2 then
					local ThenTarget = GetEdge(Block.Edges, "Then")
					local ElseTarget = GetEdge(Block.Edges, "Else")

					local BodyTarget, LoopExit
					if ThenTarget and ElseTarget then
						if ThenTarget >= I and ThenTarget <= LoopEndIdx then
							BodyTarget = ThenTarget
							LoopExit = ElseTarget
						else
							BodyTarget = ElseTarget
							LoopExit = ThenTarget
						end
					end

					for J = 1, #Stmts - 1 do
						table.insert(Result, Stmts[J])
					end

					local Cond = LastStmt.Condition
					if BodyTarget and BodyTarget ~= ThenTarget then
						Cond = { Tag = "Unary", Value = Cond, Op = "Not" }
					end

					local Body = Structure(
						BodyTarget or I + 1,
						LoopEndIdx,
						LoopExit or ExitTarget,
						I
					)

					table.insert(Result, {
						Tag = "While",
						Condition = Cond,
						Body = Body,
					})
					I = LoopExit or ExitTarget
				else
					local LoopEndStmts = LoopEndBlk and LoopEndBlk.Statements or {}
					local RepCond = { Tag = "Literal", LiteralType = "Boolean", Value = true }
					local RepCondStmt = LoopEndStmts[#LoopEndStmts]

					if RepCondStmt and RepCondStmt.Tag == "If" then
						RepCond = RepCondStmt.Condition

						local ThenT = GetEdge(LoopEndBlk.Edges, "Then")
						local ElseT = GetEdge(LoopEndBlk.Edges, "Else")
						if ThenT and ThenT >= I and ThenT <= LoopEndIdx then
							RepCond = { Tag = "Unary", Value = RepCond, Op = "Not" }
							if ElseT then
								ExitTarget = ElseT
							end
						else
							if ThenT then
								ExitTarget = ThenT
							end
						end
					end

					local Body = Structure(I, LoopEndIdx - 1, ExitTarget, LoopEndIdx)
					if RepCondStmt and RepCondStmt.Tag == "If" then
						for J = 1, #LoopEndStmts - 1 do
							table.insert(Body, LoopEndStmts[J])
						end
					else
						for _, S in LoopEndStmts do
							table.insert(Body, S)
						end
					end

					table.insert(Result, {
						Tag = "Repeat",
						Condition = RepCond,
						Body = Body,
					})
					I = ExitTarget
				end
				continue
			end

			if #Block.Edges == 2 then
				local ThenTarget = GetEdge(Block.Edges, "Then")
				local ElseTarget = GetEdge(Block.Edges, "Else")

				if ThenTarget and ElseTarget and LastStmt and LastStmt.Tag == "If" then
					for J = 1, #Stmts - 1 do
						table.insert(Result, Stmts[J])
					end

					if ThenTarget == BreakTarget then
						table.insert(Result, {
							Tag = "If",
							Condition = LastStmt.Condition,
							ThenBlock = {{ Tag = "Break" }},
							ElseBlock = {},
						})
						I = ElseTarget
						continue
					end

					if ElseTarget == BreakTarget then
						table.insert(Result, {
							Tag = "If",
							Condition = { Tag = "Unary", Value = LastStmt.Condition, Op = "Not" },
							ThenBlock = {{ Tag = "Break" }},
							ElseBlock = {},
						})
						I = ThenTarget
						continue
					end

					if ThenTarget == ContinueTarget then
						table.insert(Result, {
							Tag = "If",
							Condition = LastStmt.Condition,
							ThenBlock = {{ Tag = "Continue" }},
							ElseBlock = {},
						})
						I = ElseTarget
						continue
					end

					if ElseTarget == ContinueTarget then
						table.insert(Result, {
							Tag = "If",
							Condition = { Tag = "Unary", Value = LastStmt.Condition, Op = "Not" },
							ThenBlock = {{ Tag = "Continue" }},
							ElseBlock = {},
						})
						I = ThenTarget
						continue
					end

					do
						local ThenBlk = ThenTarget <= RangeEnd and Blocks[ThenTarget] or nil
						local ElseBlk = ElseTarget <= RangeEnd and Blocks[ElseTarget] or nil

						if ThenBlk and #ThenBlk.Edges == 0
							and ThenTarget ~= BreakTarget and ThenTarget ~= ContinueTarget then
							local GuardBody = {}
							for _, S in ThenBlk.Statements do
								table.insert(GuardBody, S)
							end
							table.insert(Result, {
								Tag = "If",
								Condition = LastStmt.Condition,
								ThenBlock = GuardBody,
								ElseBlock = {},
							})
							I = ElseTarget
							continue
						end

						if ElseBlk and #ElseBlk.Edges == 0
							and ElseTarget ~= BreakTarget and ElseTarget ~= ContinueTarget then
							local GuardBody = {}
							for _, S in ElseBlk.Statements do
								table.insert(GuardBody, S)
							end
							table.insert(Result, {
								Tag = "If",
								Condition = { Tag = "Unary", Value = LastStmt.Condition, Op = "Not" },
								ThenBlock = GuardBody,
								ElseBlock = {},
							})
							I = ThenTarget
							continue
						end
					end

					if ThenTarget <= ElseTarget then
						local ThenEnd = math.min(ElseTarget - 1, RangeEnd)
						local MergePoint = ElseTarget

						if ThenEnd >= ThenTarget then
							local LastThenBlock = Blocks[ThenEnd]
							if LastThenBlock and #LastThenBlock.Edges == 1 then
								local JumpTarget = LastThenBlock.Edges[1].Target
								if JumpTarget > ElseTarget and JumpTarget <= RangeEnd + 1 then
									MergePoint = JumpTarget
								end
							end
						end

						if MergePoint == ElseTarget then
							local ThenBody = Structure(ThenTarget, ThenEnd, BreakTarget, ContinueTarget)
							table.insert(Result, {
								Tag = "If",
								Condition = LastStmt.Condition,
								ThenBlock = ThenBody,
								ElseBlock = {},
							})
							I = MergePoint
						else
							local ThenBody = Structure(ThenTarget, ThenEnd, BreakTarget, ContinueTarget)
							local ElseEnd = math.min(MergePoint - 1, RangeEnd)
							local ElseBody = Structure(ElseTarget, ElseEnd, BreakTarget, ContinueTarget)
							table.insert(Result, {
								Tag = "If",
								Condition = LastStmt.Condition,
								ThenBlock = ThenBody,
								ElseBlock = ElseBody,
							})
							I = MergePoint
						end
					else
						local ElseEnd = math.min(ThenTarget - 1, RangeEnd)
						local NegCond = { Tag = "Unary", Value = LastStmt.Condition, Op = "Not" }
						local ElseBody = Structure(ElseTarget, ElseEnd, BreakTarget, ContinueTarget)
						table.insert(Result, {
							Tag = "If",
							Condition = NegCond,
							ThenBlock = ElseBody,
							ElseBlock = {},
						})
						I = ThenTarget
					end
					continue
				end
			end

			if #Block.Edges == 1 then
				local Edge = Block.Edges[1]
				for _, Stmt in Stmts do
					table.insert(Result, Stmt)
				end

				if Edge.Target == BreakTarget then
					table.insert(Result, { Tag = "Break" })
					I = RangeEnd + 1
				elseif Edge.Target == ContinueTarget then
					if I < RangeEnd then
						table.insert(Result, { Tag = "Continue" })
					end
					I = RangeEnd + 1
				elseif Edge.Target == I + 1 then
					I += 1
				elseif Edge.Target > RangeEnd then
					I = RangeEnd + 1
				else
					I = Edge.Target
				end
				continue
			end

			if #Block.Edges == 0 then
				for _, Stmt in Stmts do
					table.insert(Result, Stmt)
				end
				I = RangeEnd + 1
				continue
			end

			for _, Stmt in Stmts do
				table.insert(Result, Stmt)
			end
			I += 1
		end

		return Result
	end

	return Structure(1, NumBlocks, nil, nil)
end

return ControlFlow

