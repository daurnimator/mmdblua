-- TODO: a real 'ls', this is a quick hack
local function ls(dir)
	return assert(io.popen("ls -1 " .. dir)):lines()
end

describe("Works on the official MaxMind test data", function()
	local mmdb = require "mmdb"
	local dbs = {}
	it("Can open all of the databases without error", function()
		for file in ls("spec/MaxMind-DB/test-data/*.mmdb") do
			local db = mmdb.open(file)
			dbs[file] = db
		end
	end)
end)
