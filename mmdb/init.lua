-- This implements a lua parser of http://maxmind.github.io/MaxMind-DB/

local has_bit, bit = pcall(require, "bit")
local has_ffi, ffi = pcall(require, "ffi")
local sunpack = string.unpack or require "compat53.string".unpack

local mmdb_separator = "\171\205\239MaxMind.com"

local geodb_methods = {}
local geodb_mt = {
	__name = "mmdblua-database";
	__index = geodb_methods;
}
local data_types = {}
local getters = {}

local function open_db(filename)
	local fd = assert(io.open(filename, "rb"))
	local contents = assert(fd:read("*a"))

	local start_metadata do
		-- Find data section seperator; at most it's 128kb from the end
		local init = math.max(1, #contents-(128*1024))
		while true do
			local s, e = contents:find(mmdb_separator, start_metadata or init, true)
			if s == nil then break end
			start_metadata = e + 1
		end
		if start_metadata == nil then
			error("Invalid MaxMind Database")
		end
	end

	local self = setmetatable({
		contents = contents;
		start_metadata = start_metadata;
		data = nil;
		left = nil;
		right = nil;
		ipv4_start = 0;
	}, geodb_mt)

	local _, data = self:read_data(start_metadata, 0)
	self.data = data

	local getter = getters[data.record_size]
	if getter == nil then
		error("Unsupported record size: " .. data.record_size)
	end
	self.left, self.right, self.record_length = getter.left, getter.right, getter.record_length

	self.start_data = self.record_length * self.data.node_count + 16 + 1

	if self.data.ip_version == 6 then
		self.ipv4_start = self:ipv6_find_ipv4_start()
	end

	return self
end

function geodb_methods:read_data(base, offset)
	local control_byte = self.contents:byte(base + offset)
	offset = offset + 1

	-- The first three bits of the control byte tell you what type the field is.
	local data_type = math.floor(control_byte / 32)
	-- If these bits are all 0, then this is an "extended" type,
	-- which means that the next byte contains the actual type.
	if data_type == 0 then
		data_type = self.contents:byte(base + offset) + 7
		offset = offset + 1
	end

	local func = data_types[data_type]
	if func == nil then
		error("Unknown data section: " .. data_type)
	end

	-- The next five bits in the control byte tell you how long the data
	-- field's payload is, except for maps and pointers.
	local data_size = control_byte % 32
	if data_type == 1 then -- luacheck: ignore 542
		-- Ignore for pointers
	elseif data_size == 29 then
		-- If the value is 29, then the size is 29 + the next byte after the type specifying bytes as an unsigned integer.
		data_size = 29 + self.contents:byte(base + offset)
		offset = offset + 1
	elseif data_size == 30 then
		-- If the value is 30, then the size is 285 + the next two bytes after the type specifying bytes as a single unsigned integer.
		local hi, lo = self.contents:byte(base + offset, base + offset+1)
		offset = offset + 2
		data_size = 285 + hi*256 + lo
	elseif data_size == 31 then
		-- If the value is 31, then the size is 65,821 + the next three bytes after the type specifying bytes as a single unsigned integer.
		local o1, o2, o3, o4 = self.contents:byte(base + offset, base + offset+3)
		offset = offset + 4
		data_size = 65821 + o1*16777216 + o2*65536 + o3*256 + o4
	end

	return func(self, base, offset, data_size)
end

function geodb_methods:read_pointer(base, offset, magic)
	local size = math.floor(magic/8)
	local pointer
	if size == 0 then
		-- If the size is 0, the pointer is built by appending the next byte to the last three bits to produce an 11-bit value
		local o1 = self.contents:byte(base + offset)
		offset = offset + 1
		pointer = (magic % 8)*256 + o1
	elseif size == 1 then
		-- If the size is 1, the pointer is built by appending the next two bytes to the last three bits to produce a 19-bit value + 2048.
		local o1, o2 = self.contents:byte(base + offset, base + offset + 1)
		offset = offset + 2
		pointer = (magic % 8)*65536 + o1*256 + o2 + 2048
	elseif size == 2 then
		-- If the size is 2, the pointer is built by appending the next three bytes to the last three bits to produce a 27-bit value + 526336.
		local o1, o2, o3 = self.contents:byte(base + offset, base + offset + 2)
		offset = offset + 3
		pointer = (magic % 8)*16777216 + o1*65536 + o2*256 + o3 + 526336
	elseif size == 3 then
		-- Finally, if the size is 3, the pointer's value is contained in the next four bytes as a 32-bit value.
		-- In this case, the last three bits of the control byte are ignored.
		local o1, o2, o3, o4 = self.contents:byte(base + offset, base + offset+3)
		offset = offset + 4
		pointer = o1*16777216 + o2*65536 + o3*256 + o4
	end
	local _, val = self:read_data(base, pointer)
	return offset, val
end
data_types[1] = geodb_methods.read_pointer -- Pointer

function geodb_methods:read_string(base, offset, length)
	return offset + length, self.contents:sub(base + offset, base + offset + length - 1)
end

data_types[2] = geodb_methods.read_string -- UTF-8
data_types[4] = geodb_methods.read_string -- Binary

function geodb_methods:read_double(base, offset, length)
	assert(length == 8, "double of non-8 length")
	return offset + 8, sunpack(">d", self.contents, base + offset)
end
data_types[3] = geodb_methods.read_double -- Double

function geodb_methods:read_float(base, offset, length)
	assert(length == 4, "float of non-4 length")
	return offset + 4, sunpack(">f", self.contents, base + offset)
end
data_types[15] = geodb_methods.read_float -- Float

-- Integer types
-- The number of bytes used is determined by the length specifier in the control byte.

-- General function
function geodb_methods:read_unsigned(base, offset, length)
	if length == 0 then return offset, 0 end
	return offset + length, sunpack(">I" .. length, self.contents, base + offset)
end
function geodb_methods:read_signed(base, offset, length)
	if length == 0 then return offset, 0 end
	return offset + length, sunpack(">i" .. length, self.contents, base + offset)
end

data_types[5] = geodb_methods.read_unsigned -- unsigned 16-bit int
data_types[6] = geodb_methods.read_unsigned -- unsigned 32-bit int
data_types[8] = geodb_methods.read_signed -- signed 32-bit int
data_types[9] = geodb_methods.read_unsigned -- unsigned 64-bit int
data_types[10] = geodb_methods.read_unsigned -- unsigned 128-bit int

-- Specialise if we have ffi
if has_ffi and has_bit then
	local const_char_a = ffi.typeof("const char*")
	local buff = ffi.new("char[8]")
	local uint16_p = ffi.typeof("uint16_t*")
	local uint32_p = ffi.typeof("uint32_t*")
	local int32_p = ffi.typeof("int32_t*")
	local uint64_p = ffi.typeof("uint64_t*")
	if ffi.abi("le") then
		function geodb_methods:read_uint16(base, offset, length)
			local src = ffi.cast(const_char_a, self.contents) + base + offset - 1
			ffi.copy(buff+4-length, src, length)
			local x = ffi.cast(uint32_p, buff)[0]
			ffi.fill(buff+4-length, length)
			x = bit.bswap(x)
			return offset + length, x
		end
		function geodb_methods:read_uint32(base, offset, length)
			local src = ffi.cast(const_char_a, self.contents) + base + offset - 1
			ffi.copy(buff+4-length, src, length)
			local x = ffi.cast(uint32_p, buff)[0]
			ffi.fill(buff+4-length, length)
			x = bit.bswap(x)
			return offset + length, x
		end
		function geodb_methods:read_int32(base, offset, length)
			local src = ffi.cast(const_char_a, self.contents) + base + offset - 1
			ffi.copy(buff+4-length, src, length)
			local x = ffi.cast(int32_p, buff)[0]
			ffi.fill(buff+4-length, length)
			x = bit.bswap(x)
			return offset + length, x
		end
		function geodb_methods:read_uint64(base, offset, length)
			local src = ffi.cast(const_char_a, self.contents) + base + offset - 1
			ffi.copy(buff+8-length, src, length)
			-- Do uint64 in two parts; as we only have a 32bit swap operation
			local as_u32 = ffi.cast(uint32_p, buff)
			as_u32[0], as_u32[1] = bit.bswap(as_u32[1]), bit.bswap(as_u32[0])
			local x = ffi.cast(uint64_p, buff)[0]
			ffi.fill(buff, length) -- Data has been moved; no increment of buff
			return offset + length, x
		end
	else
		function geodb_methods:read_uint16(base, offset, length)
			local src = ffi.cast(const_char_a, self.contents) + base + offset - 1
			ffi.copy(buff+2-length, src, length)
			local x = ffi.cast(uint16_p, buff)[0]
			ffi.fill(buff+2-length, length)
			return offset + length, x
		end
		function geodb_methods:read_uint32(base, offset, length)
			local src = ffi.cast(const_char_a, self.contents) + base + offset - 1
			ffi.copy(buff+4-length, src, length)
			local x = ffi.cast(uint32_p, buff)[0]
			ffi.fill(buff+4-length, length)
			return offset + length, x
		end
		function geodb_methods:read_int32(base, offset, length)
			local src = ffi.cast(const_char_a, self.contents) + base + offset - 1
			ffi.copy(buff+4-length, src, length)
			local x = ffi.cast(int32_p, buff)[0]
			ffi.fill(buff+4-length, length)
			return offset + length, x
		end
		function geodb_methods:read_uint64(base, offset, length)
			local src = ffi.cast(const_char_a, self.contents) + base + offset - 1
			ffi.copy(buff+8-length, src, length)
			local x = ffi.cast(uint64_p, buff)[0]
			ffi.fill(buff+8-length, length)
			return offset + length, x
		end
	end
	data_types[5] = geodb_methods.read_uint16 -- unsigned 16-bit int
	data_types[6] = geodb_methods.read_uint32 -- unsigned 32-bit int
	data_types[8] = geodb_methods.read_int32 -- signed 32-bit int
	data_types[9] = geodb_methods.read_uint64 -- unsigned 64-bit int
	-- data_types[10] = geodb_methods.read_unsigned -- unsigned 128-bit int
end

function geodb_methods:read_map(base, offset, n_pairs) -- Map
	local map = {}
	for _ = 1, n_pairs do
		local key, val
		offset, key = self:read_data(base, offset)
		assert(type(key) == "string")
		offset, val = self:read_data(base, offset)
		map[key] = val
	end
	return offset, map
end
data_types[7] = geodb_methods.read_map

function geodb_methods:read_array(base, offset, n_items) -- Array
	local array = {}
	for i = 1, n_items do
		local val
		offset, val = self:read_data(base, offset)
		array[i] = val
	end
	return offset, array
end
data_types[11] = geodb_methods.read_array

-- End Marker
data_types[13] = function(self, base, offset, zero) -- luacheck: ignore 212
	return nil
end

-- Boolean
data_types[14] = function(self, base, offset, length) -- luacheck: ignore 212
	return offset + length, length == 1
end

getters[24] = {
	left = function(self, offset)
		local o1, o2, o3 = self.contents:byte(offset, offset + 2)
		return o1*65536 + o2*256 + o3
	end;
	right = function(self, offset)
		local o1, o2, o3 = self.contents:byte(offset + 3, offset + 5)
		return o1*65536 + o2*256 + o3
	end;
	record_length = 6;
}
getters[28] = {
	left = function(self, offset)
		local o1, o2, o3, o4 = self.contents:byte(offset, offset + 3)
		return math.floor(o4 / 16)*16777216 + o1*65536 + o2*256 + o3
	end;
	right = function(self, offset)
		local o1, o2, o3, o4 = self.contents:byte(offset + 3, offset + 6)
		return (o1 % 16)*16777216 + o2*65536 + o3*256 + o4
	end;
	record_length = 7;
}
getters[32] = {
	left = function(self, offset)
		local o1, o2, o3, o4 = self.contents:byte(offset, offset + 3)
		return o1*16777216 + o2*65536 + o3*256 + o4
	end;
	right = function(self, offset)
		local o1, o2, o3, o4 = self.contents:byte(offset + 4, offset + 7)
		return o1*16777216 + o2*65536 + o3*256 + o4
	end;
	record_length = 8;
}
function geodb_methods:search(bits, node)
	node = node or 0
	local seen = { [node] = true }
	for _, direction in ipairs(bits) do
		local offset = node * self.record_length + 1
		local record_value
		if direction then
			record_value = self:right(offset)
		else
			record_value = self:left(offset)
		end

		if seen[record_value] then
			error("Cyclical tree")
		end
		seen[record_value] = true

		if record_value == self.data.node_count then
			-- If the record value is equal to the number of nodes, that means that
			-- we do not have any data for the IP address, and the search ends here.
			return nil
		elseif record_value > self.data.node_count then
			-- If the record value is greater than the number of nodes in the search tree,
			-- then it is an actual pointer value pointing into the data section.
			-- The value of the pointer is calculated from the start of the data section,
			-- not from the start of the file.
			local data_offset = record_value - self.data.node_count - 16
			local _, res = self:read_data(self.start_data, data_offset)
			return node, res
		else
			node = record_value
		end
	end
	return node
end

do -- Use IPv4-mapped IPv6 addresses located at ::ffff:/80
	local bits = {}
	for i = 1, 80 do
		bits[i] = false
	end
	for i = 81, 96 do
		bits[i] = true
	end
	function geodb_methods:ipv6_find_ipv4_start()
		return self:search(bits, 0)
	end
end

local function ipv4_to_bit_array(str)
	local o1, o2, o3, o4 = str:match("(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)")
	assert(o1, "invalid IPv4 address")
	o1 = tonumber(o1, 10)
	o2 = tonumber(o2, 10)
	o3 = tonumber(o3, 10)
	o4 = tonumber(o4, 10)
	assert(o1 <= 255 and o2 <= 255 and o3 <= 255 and o4 <= 255, "invalid IPv4 address")
	return {
		math.floor(o1 / 128) % 2 == 1;
		math.floor(o1 / 64) % 2 == 1;
		math.floor(o1 / 32) % 2 == 1;
		math.floor(o1 / 16) % 2 == 1;
		math.floor(o1 / 8) % 2 == 1;
		math.floor(o1 / 4) % 2 == 1;
		math.floor(o1 / 2) % 2 == 1;
		o1 % 2 == 1;
		math.floor(o2 / 128) % 2 == 1;
		math.floor(o2 / 64) % 2 == 1;
		math.floor(o2 / 32) % 2 == 1;
		math.floor(o2 / 16) % 2 == 1;
		math.floor(o2 / 8) % 2 == 1;
		math.floor(o2 / 4) % 2 == 1;
		math.floor(o2 / 2) % 2 == 1;
		o2 % 2 == 1;
		math.floor(o3 / 128) % 2 == 1;
		math.floor(o3 / 64) % 2 == 1;
		math.floor(o3 / 32) % 2 == 1;
		math.floor(o3 / 16) % 2 == 1;
		math.floor(o3 / 8) % 2 == 1;
		math.floor(o3 / 4) % 2 == 1;
		math.floor(o3 / 2) % 2 == 1;
		o3 % 2 == 1;
		math.floor(o4 / 128) % 2 == 1;
		math.floor(o4 / 64) % 2 == 1;
		math.floor(o4 / 32) % 2 == 1;
		math.floor(o4 / 16) % 2 == 1;
		math.floor(o4 / 8) % 2 == 1;
		math.floor(o4 / 4) % 2 == 1;
		math.floor(o4 / 2) % 2 == 1;
		o4 % 2 == 1;
	}
end

function geodb_methods:search_ipv4(str)
	return select(2, self:search(ipv4_to_bit_array(str), self.ipv4_start))
end

local function ipv6_split(str)
	local components = {}
	local n = 0
	for u16 in str:gmatch("(%x%x?%x?%x?):?") do
		n = n + 1
		u16 = tonumber(u16, 16)
		assert(u16, "invalid IPv6 address")
		components[n] = u16
	end
	return components, n
end

local function ipv6_to_bit_array(str)
	local a, b = str:match("^([%x:]-)::([%x:]*)$")
	local components, n = ipv6_split(a or str)
	if a ~= nil then
		local end_components, m = ipv6_split(b)
		assert(m+n <= 7, "invalid IPv6 address")
		for i = n+1, 8-m do
			components[i] = 0
		end
		for i = 8-m+1, 8 do
			components[i] = end_components[i-8+m]
		end
	else
		assert(n == 8, "invalid IPv6 address")
	end
	-- Now components is an array of 16bit components
	local bits = {}
	for i = 1, 8 do
		local u16 = components[i]
		for j = 1, 16 do
			bits[(i-1)*16+j] = math.floor(u16 / 2^(16-j)) % 2 == 1
		end
	end
	return bits
end

function geodb_methods:search_ipv6(str)
	return select(2, self:search(ipv6_to_bit_array(str)))
end

return {
	open = open_db;
}
