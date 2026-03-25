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