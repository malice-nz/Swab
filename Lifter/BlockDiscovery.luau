local OpCode = require("../Opcodes")

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
