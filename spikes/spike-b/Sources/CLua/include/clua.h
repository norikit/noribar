/* Umbrella header exposing the public Lua 5.4 C API as the `CLua` module.
 * Only the three public Lua headers are surfaced to Swift; the remaining
 * headers in this directory are Lua internals, present so the vendored .c
 * sources compile, but intentionally not part of the module's API. */
#ifndef CLUA_UMBRELLA_H
#define CLUA_UMBRELLA_H

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "lua_shims.h"

#endif /* CLUA_UMBRELLA_H */
