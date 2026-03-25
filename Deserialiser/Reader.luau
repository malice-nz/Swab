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
