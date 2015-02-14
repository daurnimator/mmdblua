package = "mmdblua"
version = "scm-0"

description = {
	summary = "Library for reading MaxMind's Geolocation database format.";
	license = "MIT/X11";
}

dependencies = {
	"lua >= 5.1";
	"luabitop";
}

source = {
	url = "git://github.com/daurnimator/mmdblua.git";
}

build = {
	type = "builtin" ;
	modules = {
		["mmdb"]     = "mmdb.lua";
		["IEEE-754"] = "IEEE-754.lua";
	} ;
}
