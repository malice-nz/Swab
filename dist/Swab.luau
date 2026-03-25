--!native
--!optimize 2
-- ════════════════════════════════════════════════════════════
-- Swab v1.0.0
-- Bundled by Brix on 2026-03-26 05:37:15
-- Modules: 13 | Lines: 3,276 | Size: 91.0 KB
-- DO NOT EDIT — regenerate with: brix build
-- ════════════════════════════════════════════════════════════

local __MODULES = {}
local __CACHE = {}
local __MODULE_LINES = {}

local function __REQUIRE(Key: string): any
	if __CACHE[Key] ~= nil then return __CACHE[Key] end
	local Factory = __MODULES[Key]
	if not Factory then
		error("[Brix] Unknown module '" .. tostring(Key) .. "'", 2)
	end
	local Ok, Result = xpcall(Factory, function(Err)
		local Info = __MODULE_LINES[Key]
		if Info then
			local BundleLine = tonumber(tostring(Err):match(":(%d+):"))
			if BundleLine then
				local SourceLine = BundleLine - Info.offset
				local Msg = tostring(Err):gsub(":%d+:", ":" .. tostring(SourceLine) .. ":", 1)
				return "[Brix] Error in '" .. Info.source .. "' line " .. tostring(SourceLine) .. ": " .. Msg
			end
		end
		return "[Brix] Error in module '" .. Key .. "': " .. tostring(Err)
	end)
	if not Ok then error(Result, 0) end
	if Result == nil then Result = true end
	__CACHE[Key] = Result
	return Result
end

-- ── Module: ControlFlow ──────────────────────────────────────────────────
-- Source: ControlFlow.luau
__MODULES["ControlFlow"] = function()
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
end
__MODULE_LINES["ControlFlow"] = { offset = 40, source = "ControlFlow.luau" }

-- ── Module: Deserialiser/Constant ──────────────────────────────────────────────────
-- Source: Deserialiser/Constant.luau
__MODULES["Deserialiser/Constant"] = function()
	local Constant	= {};
	export type Constant = typeof(Constant);


	local TagList = {
		--! NIL !--
		[0]	= function(Reader)
			return {
				Type	= 'Nil'
			};
		end,

		--! BOOLEAN !--
		[1]	= function(Reader)
			return {
				Type	= 'Boolean', 
				Value	= Reader:ReadU8()~=0
			};
		end,

		--! NUMBER !--
		[2]	= function(Reader)
			return {
				Type	= 'Number', 
				Value	= Reader:ReadF64()};
		end,

		--! STRING !--
		[3]	= function(Reader)
			return {
				Type	= 'String', 
				Index	= Reader:ReadLEB128()
			};
		end,

		--! IMPORT !--
		[4]	= function(Reader)
			return {
				Type	= 'Import', 
				Id		= Reader:ReadU32()
			};
		end,

		--! TABLE !--
		[5]	= function(Reader)
			local Keys = {};
			for Index = 1, Reader:ReadLEB128() do
				Keys[Index] = Reader:ReadLEB128();
			end
			return {
				Type	= 'Table', 
				Keys	= Keys
			};
		end,

		--! CLOSURE !--
		[6]	= function(Reader)
			return {
				Type	= 'Closure', 
				FuncId	= Reader:ReadLEB128()
			};
		end,

		--! VECTOR !--
		[7]	= function(Reader)
			return {
				Type	= 'Vector', 
				X		= Reader:ReadF32(),
				Y		= Reader:ReadF32(),
				Z		= Reader:ReadF32(),
				W		= Reader:ReadF32()
			};
		end,
	};

	function Constant.Parse<Reader>(Reader:Reader): Constant
		local TagPointer	= Reader:ReadU8();
		return(assert(TagList[TagPointer], `Unknown Constant Tag: {TagPointer}`))(Reader);
	end;

	function Constant.ParseList<Reader>(Reader:Reader): {Constant}
		local Result	= {};
		for Index = 1, Reader:ReadLEB128() do
			Result[Index]	= Constant.Parse(Reader);
		end
		return Result;
	end;

	return Constant;
end
__MODULE_LINES["Deserialiser/Constant"] = { offset = 478, source = "Deserialiser/Constant.luau" }

-- ── Module: Opcodes ──────────────────────────────────────────────────
-- Source: Opcodes.luau
__MODULES["Opcodes"] = function()
	local OpCode = {}

	OpCode.NOP = 0
	OpCode.BREAK = 1
	OpCode.LOADNIL = 2
	OpCode.LOADB = 3
	OpCode.LOADN = 4
	OpCode.LOADK = 5
	OpCode.MOVE = 6
	OpCode.GETGLOBAL = 7
	OpCode.SETGLOBAL = 8
	OpCode.GETUPVAL = 9
	OpCode.SETUPVAL = 10
	OpCode.CLOSEUPVALS = 11
	OpCode.GETIMPORT = 12
	OpCode.GETTABLE = 13
	OpCode.SETTABLE = 14
	OpCode.GETTABLEKS = 15
	OpCode.SETTABLEKS = 16
	OpCode.GETTABLEN = 17
	OpCode.SETTABLEN = 18
	OpCode.NEWCLOSURE = 19
	OpCode.NAMECALL = 20
	OpCode.CALL = 21
	OpCode.RETURN = 22
	OpCode.JUMP = 23
	OpCode.JUMPBACK = 24
	OpCode.JUMPIF = 25
	OpCode.JUMPIFNOT = 26
	OpCode.JUMPIFEQ = 27
	OpCode.JUMPIFLE = 28
	OpCode.JUMPIFLT = 29
	OpCode.JUMPIFNOTEQ = 30
	OpCode.JUMPIFNOTLE = 31
	OpCode.JUMPIFNOTLT = 32
	OpCode.ADD = 33
	OpCode.SUB = 34
	OpCode.MUL = 35
	OpCode.DIV = 36
	OpCode.MOD = 37
	OpCode.POW = 38
	OpCode.ADDK = 39
	OpCode.SUBK = 40
	OpCode.MULK = 41
	OpCode.DIVK = 42
	OpCode.MODK = 43
	OpCode.POWK = 44
	OpCode.AND = 45
	OpCode.OR = 46
	OpCode.ANDK = 47
	OpCode.ORK = 48
	OpCode.CONCAT = 49
	OpCode.NOT = 50
	OpCode.MINUS = 51
	OpCode.LENGTH = 52
	OpCode.NEWTABLE = 53
	OpCode.DUPTABLE = 54
	OpCode.SETLIST = 55
	OpCode.FORNPREP = 56
	OpCode.FORNLOOP = 57
	OpCode.FORGLOOP = 58
	OpCode.FORGPREP_INEXT = 59
	OpCode.FASTCALL3 = 60
	OpCode.DEP_FORGLOOP_INEXT = 60
	OpCode.FORGPREP_NEXT = 61
	OpCode.DEP_FORGLOOP_NEXT = 62
	OpCode.GETVARARGS = 63
	OpCode.DUPCLOSURE = 64
	OpCode.PREPVARARGS = 65
	OpCode.LOADKX = 66
	OpCode.JUMPX = 67
	OpCode.FASTCALL = 68
	OpCode.COVERAGE = 69
	OpCode.CAPTURE = 70
	OpCode.SUBRK = 71
	OpCode.DIVRK = 72
	OpCode.FASTCALL1 = 73
	OpCode.FASTCALL2 = 74
	OpCode.FASTCALL2K = 75
	OpCode.FORGPREP = 76
	OpCode.JUMPXEQKNIL = 77
	OpCode.JUMPXEQKB = 78
	OpCode.JUMPXEQKN = 79
	OpCode.JUMPXEQKS = 80
	OpCode.IDIV = 81
	OpCode.IDIVK = 82

	OpCode.Name = {
		[0] = "NOP", "BREAK", "LOADNIL", "LOADB", "LOADN", "LOADK", "MOVE",
		"GETGLOBAL", "SETGLOBAL", "GETUPVAL", "SETUPVAL", "CLOSEUPVALS",
		"GETIMPORT", "GETTABLE", "SETTABLE", "GETTABLEKS", "SETTABLEKS",
		"GETTABLEN", "SETTABLEN", "NEWCLOSURE", "NAMECALL", "CALL",
		"RETURN", "JUMP", "JUMPBACK", "JUMPIF", "JUMPIFNOT",
		"JUMPIFEQ", "JUMPIFLE", "JUMPIFLT", "JUMPIFNOTEQ", "JUMPIFNOTLE",
		"JUMPIFNOTLT", "ADD", "SUB", "MUL", "DIV", "MOD", "POW",
		"ADDK", "SUBK", "MULK", "DIVK", "MODK", "POWK",
		"AND", "OR", "ANDK", "ORK", "CONCAT", "NOT", "MINUS", "LENGTH",
		"NEWTABLE", "DUPTABLE", "SETLIST", "FORNPREP", "FORNLOOP",
		"FORGLOOP", "FORGPREP_INEXT", "DEP_FORGLOOP_INEXT",
		"FORGPREP_NEXT", "DEP_FORGLOOP_NEXT", "GETVARARGS", "DUPCLOSURE",
		"PREPVARARGS", "LOADKX", "JUMPX", "FASTCALL", "COVERAGE",
		"CAPTURE", "SUBRK", "DIVRK", "FASTCALL1", "FASTCALL2",
		"FASTCALL2K", "FORGPREP", "JUMPXEQKNIL", "JUMPXEQKB",
		"JUMPXEQKN", "JUMPXEQKS", "IDIV", "IDIVK",
	}

	OpCode.Format = {}
	for _, V in {0,1,2,3,6,7,8,9,10,11,13,14,15,16,17,18,20,21,22,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,55,60,63,65,66,68,70,71,72,73,74,75,81,82} do
		OpCode.Format[V] = "BC"
	end
	for _, V in {4,5,12,19,23,24,25,26,27,28,29,30,31,32,54,56,57,58,59,61,62,64,76,77,78,79,80} do
		OpCode.Format[V] = "AD"
	end
	for _, V in {67,69} do
		OpCode.Format[V] = "E"
	end

	OpCode.HasAux = {}
	for _, V in {7,8,12,15,16,20,27,28,29,30,31,32,53,55,58,60,66,74,75,77,78,79,80} do
		OpCode.HasAux[V] = true
	end

	return OpCode
end
__MODULE_LINES["Opcodes"] = { offset = 573, source = "Opcodes.luau" }

-- ── Module: Deserialiser/Instruction ──────────────────────────────────────────────────
-- Source: Deserialiser/Instruction.luau
__MODULES["Deserialiser/Instruction"] = function()
	local OpCode = __REQUIRE("Opcodes")

	local Instruction = {}

	function Instruction.Decode(RawInsn: number, EncodeKey: number)
		local RawOp = bit32.band(RawInsn, 0xFF)
		local Op = bit32.band(RawOp * EncodeKey, 0xFF)

		local Format = OpCode.Format[Op]

		if Format == "BC" then
			local A = bit32.band(bit32.rshift(RawInsn, 8), 0xFF)
			local B = bit32.band(bit32.rshift(RawInsn, 16), 0xFF)
			local C = bit32.band(bit32.rshift(RawInsn, 24), 0xFF)
			return {
				Format = "BC",
				Op = Op,
				A = A,
				B = B,
				C = C,
				Aux = 0,
			}
		elseif Format == "AD" then
			local A = bit32.band(bit32.rshift(RawInsn, 8), 0xFF)
			local DRaw = bit32.band(bit32.rshift(RawInsn, 16), 0xFFFF)
			local D = if DRaw >= 0x8000 then DRaw - 0x10000 else DRaw
			return {
				Format = "AD",
				Op = Op,
				A = A,
				D = D,
				Aux = 0,
			}
		elseif Format == "E" then
			local ERaw = bit32.arshift(RawInsn, 8)
			local E = if ERaw >= 0x800000 then ERaw - 0x1000000 else ERaw
			return {
				Format = "E",
				Op = Op,
				E = E,
			}
		else
			return {
				Format = "BC",
				Op = OpCode.NOP,
				A = 0,
				B = 0,
				C = 0,
				Aux = 0,
			}
		end
	end

	function Instruction.ParseAll(RawWords: {number}, EncodeKey: number): {any}
		local Result = {}
		local Pc = 1

		while Pc <= #RawWords do
			local Insn = Instruction.Decode(RawWords[Pc], EncodeKey)
			local Op = Insn.Op

			if OpCode.HasAux[Op] and Pc + 1 <= #RawWords then
				Insn.Aux = RawWords[Pc + 1]
				Pc += 2
				table.insert(Result, Insn)
				table.insert(Result, {
					Format = "BC",
					Op = OpCode.NOP,
					A = 0,
					B = 0,
					C = 0,
					Aux = 0,
				})
			else
				table.insert(Result, Insn)
				Pc += 1
			end
		end

		return Result
	end

	return Instruction
end
__MODULE_LINES["Deserialiser/Instruction"] = { offset = 702, source = "Deserialiser/Instruction.luau" }

-- ── Module: Deserialiser/Function ──────────────────────────────────────────────────
-- Source: Deserialiser/Function.luau
__MODULES["Deserialiser/Function"] = function()
	local Constant = __REQUIRE("Deserialiser/Constant")
	local Instruction = __REQUIRE("Deserialiser/Instruction")

	local Function = {}

	local function ParseLineInfo(Reader, CodeSize)
		if CodeSize == 0 then return {} end
		local LinegapLog2 = Reader:ReadU8()
		local Offsets = {}
		for I = 1, CodeSize do
			Offsets[I] = Reader:ReadU8()
		end
		local IntervalCount = bit32.rshift(CodeSize - 1, LinegapLog2) + 1
		local AbsLines = {}
		local LastLine = 0
		for I = 1, IntervalCount do
			LastLine += Reader:ReadI32()
			AbsLines[I] = LastLine
		end
		local Lines = {}
		for I = 1, CodeSize do
			local Interval = bit32.rshift(I - 1, LinegapLog2) + 1
			local Base = AbsLines[Interval] or 0
			local Offset = Offsets[I]
			if Offset >= 128 then
				Offset = Offset - 256
			end
			Lines[I] = Base + Offset
		end
		return Lines
	end

	local function ParseDebugInfo(Reader, StringTable)
		local Locals = {}
		local UpvalueNames = {}
		local NumLocals = Reader:ReadLEB128()
		for I = 1, NumLocals do
			local NameIdx = Reader:ReadLEB128()
			local StartPC = Reader:ReadLEB128()
			local EndPC = Reader:ReadLEB128()
			local Reg = Reader:ReadU8()
			local Name = ""
			if NameIdx > 0 and NameIdx <= #StringTable then
				Name = StringTable[NameIdx]
			end
			Locals[I] = {
				Name = Name,
				StartPC = StartPC,
				EndPC = EndPC,
				Reg = Reg,
			}
		end
		local NumUpvalueNames = Reader:ReadLEB128()
		for I = 1, NumUpvalueNames do
			local Idx = Reader:ReadLEB128()
			if Idx > 0 and Idx <= #StringTable then
				UpvalueNames[I] = StringTable[Idx]
			else
				UpvalueNames[I] = ""
			end
		end
		return Locals, UpvalueNames
	end

	function Function.Parse(Reader, Version, StringTable, EncodeKey)
		local MaxStackSize = Reader:ReadU8()
		local NumParameters = Reader:ReadU8()
		local NumUpvalues = Reader:ReadU8()
		local IsVararg = Reader:ReadU8() ~= 0

		if Version >= 4 then
			Reader:ReadU8()
		end

		local TypeSize = Reader:ReadLEB128()
		if TypeSize > 0 then
			Reader:Skip(TypeSize)
		end

		local CodeSize = Reader:ReadLEB128()
		local RawWords = {}
		for I = 1, CodeSize do
			RawWords[I] = Reader:ReadU32()
		end
		local Instructions = Instruction.ParseAll(RawWords, EncodeKey)
		local Constants = Constant.ParseList(Reader)

		local NumChildren = Reader:ReadLEB128()
		local Children = {}
		for I = 1, NumChildren do
			Children[I] = Reader:ReadLEB128()
		end

		local LineDefined = Reader:ReadLEB128()
		local FunctionName = Reader:ReadLEB128()

		local Lines = nil
		local HasLineInfo = Reader:ReadU8() ~= 0
		if HasLineInfo then
			Lines = ParseLineInfo(Reader, CodeSize)
		end

		local Locals = nil
		local UpvalueNames = nil
		local HasDebugInfo = Reader:ReadU8() ~= 0
		if HasDebugInfo then
			Locals, UpvalueNames = ParseDebugInfo(Reader, StringTable)
		end

		return {
			MaxStackSize = MaxStackSize,
			NumParameters = NumParameters,
			NumUpvalues = NumUpvalues,
			IsVararg = IsVararg,
			Instructions = Instructions,
			Constants = Constants,
			Children = Children,
			LineDefined = LineDefined,
			FunctionName = FunctionName,
			Lines = Lines,
			Locals = Locals,
			UpvalueNames = UpvalueNames,
		}
	end

	return Function
end
__MODULE_LINES["Deserialiser/Function"] = { offset = 791, source = "Deserialiser/Function.luau" }

-- ── Module: Deserialiser/Reader ──────────────────────────────────────────────────
-- Source: Deserialiser/Reader.luau
__MODULES["Deserialiser/Reader"] = function()
	local Reader = {}
	Reader.__index = Reader

	function Reader.New(Data: buffer)
		return setmetatable({
			Buffer = Data,
			Position = 0,
			Length = buffer.len(Data),
		}, Reader)
	end

	function Reader.FromString(Str: string)
		return Reader.New(buffer.fromstring(Str))
	end

	function Reader:ReadU8(): number
		local Value = buffer.readu8(self.Buffer, self.Position)
		self.Position += 1
		return Value
	end

	function Reader:ReadU16(): number
		local Value = buffer.readu16(self.Buffer, self.Position)
		self.Position += 2
		return Value
	end

	function Reader:ReadU32(): number
		local Value = buffer.readu32(self.Buffer, self.Position)
		self.Position += 4
		return Value
	end

	function Reader:ReadI16(): number
		local Value = buffer.readi16(self.Buffer, self.Position)
		self.Position += 2
		return Value
	end

	function Reader:ReadI32(): number
		local Value = buffer.readi32(self.Buffer, self.Position)
		self.Position += 4
		return Value
	end

	function Reader:ReadF32(): number
		local Value = buffer.readf32(self.Buffer, self.Position)
		self.Position += 4
		return Value
	end

	function Reader:ReadF64(): number
		local Value = buffer.readf64(self.Buffer, self.Position)
		self.Position += 8
		return Value
	end

	function Reader:ReadLEB128(): number
		local Result = 0
		local Shift = 0
		while true do
			local Byte = self:ReadU8()
			Result = bit32.bor(Result, bit32.lshift(bit32.band(Byte, 0x7F), Shift))
			if bit32.band(Byte, 0x80) == 0 then
				break
			end
			Shift += 7
		end
		return Result
	end

	function Reader:ReadString(): string
		local Length = self:ReadLEB128()
		if Length == 0 then
			return ""
		end
		local Str = buffer.readstring(self.Buffer, self.Position, Length)
		self.Position += Length
		return Str
	end

	function Reader:ReadBytes(Count: number): string
		local Str = buffer.readstring(self.Buffer, self.Position, Count)
		self.Position += Count
		return Str
	end

	function Reader:Skip(Count: number)
		self.Position += Count
	end

	function Reader:IsFinished(): boolean
		return self.Position >= self.Length
	end

	function Reader:Remaining(): number
		return self.Length - self.Position
	end

	return Reader
end
__MODULE_LINES["Deserialiser/Reader"] = { offset = 923, source = "Deserialiser/Reader.luau" }

-- ── Module: Deserialiser/init ──────────────────────────────────────────────────
-- Source: Deserialiser/init.luau
__MODULES["Deserialiser/init"] = function()
	local Reader = __REQUIRE("Deserialiser/Reader")
	local Function = __REQUIRE("Deserialiser/Function")

	local Deserialiser = {}

	function Deserialiser.Deserialise(Bytecode, EncodeKey)
		local R = Reader.New(Bytecode)
		local Key = EncodeKey or 1

		local Version = R:ReadU8()
		if Version == 0 then
			local Remaining = R:Remaining()
			local Msg = if Remaining > 0 then buffer.readstring(Bytecode, R.Position, Remaining) else "Unknown error"
			error(`Bytecode error: {Msg}`)
		end

		if Version < 3 or Version > 6 then
			error(`Unsupported bytecode version: {Version}`)
		end

		local TypesVersion = 0
		if Version >= 4 then
			TypesVersion = R:ReadU8()
		end

		local NumStrings = R:ReadLEB128()
		local StringTable = {}
		for I = 1, NumStrings do
			StringTable[I] = R:ReadString()
		end

		if TypesVersion == 3 then
			while true do
				local Index = R:ReadU8()
				if Index == 0 then break end
				R:ReadLEB128()
			end
		end

		local NumProtos = R:ReadLEB128()
		local Functions = {}
		for I = 1, NumProtos do
			Functions[I] = Function.Parse(R, Version, StringTable, Key)
		end

		local MainIndex = R:ReadLEB128()

		return {
			Version = Version,
			StringTable = StringTable,
			Functions = Functions,
			MainIndex = MainIndex,
		}
	end

	return Deserialiser
end
__MODULE_LINES["Deserialiser/init"] = { offset = 1029, source = "Deserialiser/init.luau" }

-- ── Module: ExpressionFolding ──────────────────────────────────────────────────
-- Source: ExpressionFolding.luau
__MODULES["ExpressionFolding"] = function()
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
end
__MODULE_LINES["ExpressionFolding"] = { offset = 1091, source = "ExpressionFolding.luau" }

-- ── Module: Formatter ──────────────────────────────────────────────────
-- Source: Formatter.luau
__MODULES["Formatter"] = function()
	local ControlFlow = __REQUIRE("ControlFlow")
	local ExpressionFolding = __REQUIRE("ExpressionFolding")

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

		local Structured = if State.StructuredCache and State.StructuredCache[FuncIndex]
			then State.StructuredCache[FuncIndex]
			else ExpressionFolding.Fold(ControlFlow.Recover(LiftedFunc))
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
			local ok, Structured = pcall(ExpressionFolding.Fold, ControlFlow.Recover(Lifted, ScanDeadline))
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

		local Structured = State.StructuredCache and State.StructuredCache[MainIndex]
			or ExpressionFolding.Fold(ControlFlow.Recover(LiftedMain, os.clock() + 15))
		FormatBlock(State, Structured, MainIndex)
		return table.concat(State.Output)
	end

	return Formatter
end
__MODULE_LINES["Formatter"] = { offset = 1717, source = "Formatter.luau" }

-- ── Module: Lifter/BlockDiscovery ──────────────────────────────────────────────────
-- Source: Lifter/BlockDiscovery.luau
__MODULES["Lifter/BlockDiscovery"] = function()
	local OpCode = __REQUIRE("Opcodes")

	local BlockDiscovery = {}

	function BlockDiscovery.Discover(Instructions: {any}): {number}
		local BlockStarts = {}
		BlockStarts[1] = true

		for Pc = 1, #Instructions do
			local Insn = Instructions[Pc]
			local Op = Insn.Op

			if Insn.Format == "BC" then
				if Op == OpCode.LOADB and Insn.C ~= 0 then
					local Dest = Pc + 1 + Insn.C
					if Dest >= 1 and Dest <= #Instructions then
						BlockStarts[Dest] = true
					end
					if Pc + 1 <= #Instructions then
						BlockStarts[Pc + 1] = true
					end
				elseif Op == OpCode.RETURN then
					if Pc + 1 <= #Instructions then
						BlockStarts[Pc + 1] = true
					end
				end
			elseif Insn.Format == "AD" then
				if Op == OpCode.JUMP or Op == OpCode.JUMPBACK then
					local Dest = Pc + 1 + Insn.D
					if Dest >= 1 and Dest <= #Instructions then
						BlockStarts[Dest] = true
					end
					if Pc + 1 <= #Instructions then
						BlockStarts[Pc + 1] = true
					end
				elseif Op == OpCode.JUMPIF or Op == OpCode.JUMPIFNOT then
					local Dest = Pc + 1 + Insn.D
					if Dest >= 1 and Dest <= #Instructions then
						BlockStarts[Dest] = true
					end
					if Pc + 1 <= #Instructions then
						BlockStarts[Pc + 1] = true
					end
				elseif Op == OpCode.JUMPIFEQ or Op == OpCode.JUMPIFLE or Op == OpCode.JUMPIFLT
					or Op == OpCode.JUMPIFNOTEQ or Op == OpCode.JUMPIFNOTLE or Op == OpCode.JUMPIFNOTLT
					or Op == OpCode.JUMPXEQKNIL or Op == OpCode.JUMPXEQKB
					or Op == OpCode.JUMPXEQKN or Op == OpCode.JUMPXEQKS then
					local Dest = Pc + 1 + Insn.D
					if Dest >= 1 and Dest <= #Instructions then
						BlockStarts[Dest] = true
					end
					if Pc + 2 <= #Instructions then
						BlockStarts[Pc + 2] = true
					end
				elseif Op == OpCode.FORNPREP then
					local Dest = Pc + 1 + Insn.D
					if Dest >= 1 and Dest <= #Instructions then
						BlockStarts[Dest] = true
					end
					if Pc + 1 <= #Instructions then
						BlockStarts[Pc + 1] = true
					end
				elseif Op == OpCode.FORNLOOP then
					local Dest = Pc + 1 + Insn.D
					if Dest >= 1 and Dest <= #Instructions then
						BlockStarts[Dest] = true
					end
					BlockStarts[Pc] = true
					if Pc + 1 <= #Instructions then
						BlockStarts[Pc + 1] = true
					end
				elseif Op == OpCode.FORGLOOP then
					local Dest = Pc + 1 + Insn.D
					if Dest >= 1 and Dest <= #Instructions then
						BlockStarts[Dest] = true
					end
					if Pc + 1 <= #Instructions then
						BlockStarts[Pc + 1] = true
					end
				elseif Op == OpCode.FORGPREP or Op == OpCode.FORGPREP_INEXT or Op == OpCode.FORGPREP_NEXT then
					local Dest = Pc + 1 + Insn.D
					if Dest >= 1 and Dest <= #Instructions then
						BlockStarts[Dest] = true
					end
					if Pc + 1 <= #Instructions then
						BlockStarts[Pc + 1] = true
					end
				end
			elseif Insn.Format == "E" then
				if Op == OpCode.JUMPX then
					local Dest = Pc + 1 + Insn.E
					if Dest >= 1 and Dest <= #Instructions then
						BlockStarts[Dest] = true
					end
					if Pc + 1 <= #Instructions then
						BlockStarts[Pc + 1] = true
					end
				end
			end
		end

		local Sorted = {}
		for Pc in BlockStarts do
			table.insert(Sorted, Pc)
		end
		table.sort(Sorted)
		return Sorted
	end

	function BlockDiscovery.BuildRanges(BlockStarts: {number}, InsnCount: number): {{number}}
		local Ranges = {}
		for I = 1, #BlockStarts do
			local Start = BlockStarts[I]
			local End = if I < #BlockStarts then BlockStarts[I + 1] - 1 else InsnCount
			table.insert(Ranges, {StartPC = Start, EndPC = End})
		end
		return Ranges
	end

	return BlockDiscovery
end
__MODULE_LINES["Lifter/BlockDiscovery"] = { offset = 2319, source = "Lifter/BlockDiscovery.luau" }

-- ── Module: Lifter/Instruction ──────────────────────────────────────────────────
-- Source: Lifter/Instruction.luau
__MODULES["Lifter/Instruction"] = function()
	local OpCode = __REQUIRE("Opcodes")

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
end
__MODULE_LINES["Lifter/Instruction"] = { offset = 2445, source = "Lifter/Instruction.luau" }

-- ── Module: Lifter/init ──────────────────────────────────────────────────
-- Source: Lifter/init.luau
__MODULES["Lifter/init"] = function()
	local BlockDiscovery = __REQUIRE("Lifter/BlockDiscovery")
	local InstructionLifter = __REQUIRE("Lifter/Instruction")

	local Lifter = {}

	function Lifter.LiftFunction(Chunk, FuncIndex)
		local Func = Chunk.Functions[FuncIndex + 1]
		if not Func then
			return nil
		end

		local IL = InstructionLifter.New(Chunk, FuncIndex)
		local BlockStarts = BlockDiscovery.Discover(Func.Instructions)
		local Ranges = BlockDiscovery.BuildRanges(BlockStarts, #Func.Instructions)

		local Blocks = {}
		local BlockMap = {}

		for I, Range in Ranges do
			local Block = {
				Id = I,
				StartPC = Range.StartPC,
				EndPC = Range.EndPC,
				Statements = {},
				Edges = {},
				Predecessors = {},
			}
			Blocks[I] = Block
			BlockMap[Range.StartPC] = I
		end

		for I, Block in Blocks do
			local Stmts, Edges = InstructionLifter.LiftBlock(IL, Block.StartPC, Block.EndPC, BlockStarts)
			Block.Statements = Stmts

			for _, Edge in Edges do
				local TargetIdx = BlockMap[Edge.Target]
				if TargetIdx and Blocks[TargetIdx] then
					table.insert(Block.Edges, {
						Target = TargetIdx,
						Type = Edge.Type,
					})
					table.insert(Blocks[TargetIdx].Predecessors, I)
				end
			end
		end

		return {
			Func = Func,
			FuncIndex = FuncIndex,
			Blocks = Blocks,
			BlockMap = BlockMap,
			RegisterMap = IL.RegisterMap,
			Upvalues = IL.Upvalues,
			ChildClosures = IL.ChildClosures,
			NumParameters = Func.NumParameters,
			IsVararg = Func.IsVararg,
		}
	end

	function Lifter.LiftChunk(Chunk)
		local Results = {}

		local MainFuncIndex = Chunk.MainIndex
		local Processed = {}

		local function ProcessFunction(FuncIdx)
			if Processed[FuncIdx] then
				return
			end
			Processed[FuncIdx] = true

			local Result = Lifter.LiftFunction(Chunk, FuncIdx)
			if Result then
				Results[FuncIdx] = Result
				for _, Child in Result.ChildClosures do
					ProcessFunction(Child.FuncIndex)
				end
			end
		end

		ProcessFunction(MainFuncIndex)
		return Results, MainFuncIndex
	end

	return Lifter
end
__MODULE_LINES["Lifter/init"] = { offset = 3256, source = "Lifter/init.luau" }

-- ── Module: init ──────────────────────────────────────────────────
-- Source: init.luau
__MODULES["init"] = function()
	local Deserialiser = __REQUIRE("Deserialiser/init")
	local Lifter = __REQUIRE("Lifter/init")
	local Formatter = __REQUIRE("Formatter")


		local Swab = {}

		function Swab.Decompile(Source, EncodeKey)
			local Bytecode
			EncodeKey = 203
			if typeof(Source) == "Instance" then
				Bytecode = buffer.fromstring((getscriptbytecode :: any)(Source))
			elseif type(Source) == "string" then
				Bytecode = buffer.fromstring(Source)
			else
				Bytecode = Source
			end
			local Chunk = Deserialiser.Deserialise(Bytecode, EncodeKey)
			local LiftedFunctions, MainIndex = Lifter.LiftChunk(Chunk)
			return Formatter.Format(Chunk, LiftedFunctions, MainIndex)
		end

		function Swab.DeserialiseChunk(Bytecode, EncodeKey)
			return Deserialiser.Deserialise(Bytecode, EncodeKey)
		end

		pcall(function()
			(getgenv :: any)().decompile = Swab.Decompile
		end)

		return Swab
end
__MODULE_LINES["init"] = { offset = 3348, source = "init.luau" }

-- ════════════════════════════════════════════════════════════
-- Entry Point
-- ════════════════════════════════════════════════════════════
local Root = __REQUIRE("init")
return Root
