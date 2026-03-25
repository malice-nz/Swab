local Constant = require("./Constant")
local Instruction = require("./Instruction")

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