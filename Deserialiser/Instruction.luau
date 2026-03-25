local OpCode = require("../Opcodes")

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
