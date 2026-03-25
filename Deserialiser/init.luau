local Reader = require("./Reader")
local Function = require("./Function")

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