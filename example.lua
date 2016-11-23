-- Simple pretty printer
local function pp(ob, indent, stream)
	stream = stream or io.stderr
	if type(ob) == "table" then
		indent = indent or 0
		stream:write("{\n")
		do
			for k,v in pairs(ob) do
				stream:write(("\t"):rep(indent+1), k, " = ")
				pp(v, indent+1)
			end
		end
		assert(stream:write(("\t"):rep(indent), "}\n"))
	elseif type(ob) == "string" then
		assert(stream:write(string.format("%q\n", ob)))
	else
		assert(stream:write(tostring(ob), "\n"))
	end
end

-- Download from http://dev.maxmind.com/geoip/geoip2/geolite2/
local geodb = require "mmdb".open("GeoLite2-City.mmdb")

if arg[1] then
	pp(geodb:search_ipv4(arg[1]))
else
	pp(geodb:search_ipv4 "213.215.63.11") -- french hotel near lua workshop 2013
	pp(geodb:search_ipv6 "2607:f8b0:4004:801::100e") -- google.com for me one day
end
