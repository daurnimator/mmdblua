package = "mmdblua"
version = "scm-0"

source = {
	url = "git://github.com/daurnimator/mmdblua.git";
}

description = {
	summary = "Library for reading MaxMind's Geolocation database format.";
	license = "MIT";
}

dependencies = {
	"lua >= 5.1";
	"compat53 >= 0.3"; -- Only if lua < 5.3
	"luabitop";
}

build = {
	type = "builtin";
	modules = {
		["mmdb"] = "mmdb/init.lua";
	};
}
