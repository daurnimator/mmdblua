package = "mmdblua"
version = "scm-0"

description = {
	summary = "Library for reading MaxMind's Geolocation database format.";
	license = "MIT";
}

dependencies = {
	"lua >= 5.1";
	"compat53 >= 0.3"; -- Only if lua < 5.3
	"luabitop";
}

source = {
	url = "git://github.com/daurnimator/mmdblua.git";
}

build = {
	type = "builtin" ;
	modules = {
		["mmdb"] = "mmdb.lua";
	} ;
}
