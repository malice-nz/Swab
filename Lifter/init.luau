local BlockDiscovery = require("./BlockDiscovery")
local InstructionLifter = require("./Instruction")

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
