package = "mmdblua"
version = "0.2-0"

source = {
	url = "https://github.com/daurnimator/mmdblua/archive/v0.2.zip";
	dir = "mmdblua-0.2";
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
