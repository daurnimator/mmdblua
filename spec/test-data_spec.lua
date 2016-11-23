-- TODO: a real 'ls', this is a quick hack
local function ls(dir)
	return assert(io.popen("ls -1 " .. dir)):lines()
end

describe("mmdb", function()
	local mmdb = require "mmdb"
	for file in ls("spec/MaxMind-DB/test-data/*.mmdb") do
		it("can open MaxMind test data file " .. file, function()
			mmdb.open(file)
		end)
	end
end)
