package = "mmdblua"
version = "0.1-0"

source = {
	url = "https://github.com/daurnimator/mmdblua/archive/v0.1.zip";
	dir = "mmdblua-0.1";
}

description = {
	summary = "Library for reading MaxMind's Geolocation database format.";
	license = "MIT";
}

dependencies = {
	"lua >= 5.1";
	"compat53 >= 0.3"; -- Only if lua < 5.3
}

build = {
	type = "builtin";
	modules = {
		["mmdb"] = "mmdb/init.lua";
	};
}
