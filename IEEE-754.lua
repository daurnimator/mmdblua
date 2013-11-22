local has_ffi , ffi = pcall ( require , "ffi" )
local has_bit , bit = pcall ( require , "bit" )

local read_float , read_double
if has_ffi and has_bit then
	local cast = ffi.cast
	local band , bor = bit.band , bit.bor
	local split_int32_p = ffi.typeof ( "struct { int32_t " .. ( ffi.abi("le") and "lo, hi" or "hi, lo" ) .. "; } *" )
	local double_p = ffi.typeof ( "double*" )
	local int32_p = ffi.typeof ( "int32_t*" )
	local float_p = ffi.typeof ( "float*" )
	local function double_isnan ( buff )
		local q = cast ( split_int32_p , buff )
		return band ( q.hi , 0x7FF00000 ) == 0x7FF00000
			and bor ( q.lo , band ( q.hi , 0xFFFFF ) ) ~= 0
	end
	function read_double ( src )
		-- Luajit uses NAN tagging, make sure we have the canonical NAN
		if double_isnan ( src ) then
			return 0/0
		else
			return cast ( double_p , src )[0]
		end
	end
	local function float_isnan ( buff )
		local as_int = cast ( int32_p , buff )[0]
		return band ( as_int , 0x7F800000 ) == 0x7F800000
			and band ( as_int , 0x7FFFFF ) ~= 0
	end
	function read_float ( src )
		-- Luajit uses NAN tagging, make sure we have the canonical NAN
		if float_isnan ( src ) then
			return 0/0
		else
			return cast ( float_p , src )[0]
		end
	end
else
	-- Use the power of loadstring for reading doubles
	local d = string.dump ( loadstring ( [[return 523123.123145345]] ) )
	local s , e = d:find ( "\3\54\208\25\126\204\237\31\65" )
	if s == nil then
		error ( "Unable to set up IEEE-754 double reading" )
	end
	local s = d:sub ( 1 , s )
	local e = d:sub ( e + 1 , -1 )
	function read_double ( src )
		return loadstring ( s .. src .. e ) ( )
	end
	-- lua has no native support for floats.... so out of luck there
	-- function read_float ( src )
	-- 	error ( "TODO: non-ffi float reading" )
	-- end
end

return {
	read_float = read_float ;
	read_double = read_double ;
}
