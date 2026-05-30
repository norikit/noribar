/* lua_shims.h — Swift-visible wrappers for Lua's function-like macros.
 *
 * Lua exposes a lot of its C API as preprocessor macros (lua_pcall, lua_pop,
 * lua_pushcfunction, lua_tostring, ...). Swift's Clang importer does not import
 * function-like macros, so those names are invisible from Swift. We re-export
 * each one we need as a `static inline` function with a `cl_` prefix.
 *
 * This is the one piece of glue the real project will also need; keeping it in
 * a single audited header is the cleanest option.
 */
#ifndef LUA_SHIMS_H
#define LUA_SHIMS_H

#include "lua.h"
#include "lauxlib.h"

/* --- calling --- */
static inline int cl_pcall(lua_State *L, int nargs, int nresults, int errfunc) {
    return lua_pcall(L, nargs, nresults, errfunc);
}
static inline void cl_call(lua_State *L, int nargs, int nresults) {
    lua_call(L, nargs, nresults);
}

/* --- stack management --- */
static inline void cl_pop(lua_State *L, int n) { lua_pop(L, n); }
static inline void cl_newtable(lua_State *L) { lua_newtable(L); }
static inline void cl_insert(lua_State *L, int idx) { lua_insert(L, idx); }
static inline void cl_remove(lua_State *L, int idx) { lua_remove(L, idx); }
static inline void cl_replace(lua_State *L, int idx) { lua_replace(L, idx); }

/* --- pushing --- */
static inline void cl_pushcfunction(lua_State *L, lua_CFunction f) {
    lua_pushcfunction(L, f);
}
static inline void cl_register(lua_State *L, const char *name, lua_CFunction f) {
    lua_register(L, name, f);
}

/* --- type predicates --- */
static inline int cl_isnil(lua_State *L, int n)      { return lua_isnil(L, n); }
static inline int cl_isnumber(lua_State *L, int n)   { return lua_isnumber(L, n); }
static inline int cl_isstring(lua_State *L, int n)   { return lua_isstring(L, n); }
static inline int cl_istable(lua_State *L, int n)    { return lua_istable(L, n); }
static inline int cl_isfunction(lua_State *L, int n) { return lua_isfunction(L, n); }
static inline int cl_isboolean(lua_State *L, int n)  { return lua_isboolean(L, n); }

/* --- conversions (the macro-flavored ones) --- */
static inline lua_Number cl_tonumber(lua_State *L, int n)   { return lua_tonumber(L, n); }
static inline lua_Integer cl_tointeger(lua_State *L, int n) { return lua_tointeger(L, n); }
static inline const char *cl_tostring(lua_State *L, int n)  { return lua_tostring(L, n); }

/* --- registry / refs helpers (luaL_ref against the registry) --- */
static inline int cl_ref(lua_State *L) { return luaL_ref(L, LUA_REGISTRYINDEX); }
static inline void cl_unref(lua_State *L, int ref) { luaL_unref(L, LUA_REGISTRYINDEX, ref); }
static inline int cl_rawgeti_registry(lua_State *L, int ref) {
    return lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
}

/* Upvalue pseudo-index (a macro in lua.h). Swift calls cl_upvalueindex(1). */
static inline int cl_upvalueindex(int i) { return lua_upvalueindex(i); }

/* Expose the registry pseudo-index as a real constant for Swift. */
static const int CL_REGISTRYINDEX = LUA_REGISTRYINDEX;

#endif /* LUA_SHIMS_H */
