// A monotonic clock for the Lua harness (Lua's os.clock is CPU time, os.time whole seconds):
// require("benchclock").now() returns CLOCK_MONOTONIC in nanoseconds as a number. Built by
// ../build.sh lua for LuaJIT and for Lua 5.5, next to their cjson.so.
#include <lauxlib.h>
#include <lua.h>
#include <time.h>

static int now(lua_State *L)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	lua_pushnumber(L, (lua_Number)ts.tv_sec * 1e9 + (lua_Number)ts.tv_nsec);
	return 1;
}

int luaopen_benchclock(lua_State *L)
{
	lua_newtable(L);
	lua_pushcfunction(L, now);
	lua_setfield(L, -2, "now");
	return 1;
}
