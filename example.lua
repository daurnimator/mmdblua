-- Simple pretty printer
local function pp ( ob , indent , stream )
	indent = indent or ""
	stream = stream or io.stderr
	if type(ob) == "table" then
		stream:write("{\n")
		do
			local indent = indent.."\t"
			for k,v in pairs(ob) do
				stream:write(indent,k," = ")
				pp(v,indent)
			end
		end
		stream:write(indent,"}\n")
	elseif type(ob) == "string" then
		stream:write(string.format("%q\n",ob))
	else
		stream:write(tostring(ob),"\n")
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
