local Deserialiser = require("./Deserialiser")
local Lifter = require("./Lifter")
local Formatter = require("./Formatter")


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