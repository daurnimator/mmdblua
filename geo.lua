#!/usr/bin/env ujit

local argparse = require "argparse"
local mmdb     = require "mmdb"
local json     = require "dkjson"

local function get_args()
    local parser = argparse("geo", "Get info from MMDB database")

    parser:argument("ip", "IP v4/v6 address"):args "?"

    parser:flag("-i --info", "Infromation about database")

    parser
        :option("-d --mmdb", "MaxMind2 database", "/usr/share/GeoIP/GeoIP2-City.mmdb")

    return parser:parse()
end

local args = get_args()

local geodb, err = mmdb.read(args.mmdb, true)
if not geodb then
    io.stderr:write(err)
    os.exit(-1)
end

if args.info then
    io.stdout:write(string.format(
        "%s (%s); Support IPv%d; Nodes: %d\n",
        geodb.data.database_type,
        os.date("%F %T%z", tonumber(geodb.data.build_epoch)),
        geodb.data.ip_version,
        geodb.data.node_count
    ))
end

if args.ip then
    local info
    if string.find(args.ip, ':') then
        info = geodb:search_ipv6(args.ip)
    else
        info = geodb:search_ipv4(args.ip)
    end
    if not info then
        io.stderr:write('Not found info: ' .. args.ip)
        os.exit(-2)
    end
    io.stdout:write(json.encode(info, { indent = true }))
end
