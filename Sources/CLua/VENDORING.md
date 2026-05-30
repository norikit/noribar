# Vendored Lua

- **Version:** Lua 5.4.7
- **Source:** https://www.lua.org/ftp/lua-5.4.7.tar.gz
- **SHA-256:** `9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30`
- **License:** MIT (see `LUA-LICENSE.txt`) — compatible with this project's AGPL-3.0.

## What's here

- `src/` — every `.c` from the upstream `src/` **except** `lua.c` (the `lua`
  interpreter's `main`) and `luac.c` (the `luac` compiler's `main`). We embed the
  library, not the command-line tools.
- `include/` — all upstream `.h` files (so the `.c` sources compile), plus:
  - `clua.h` — umbrella header; exposes **only** the public API (`lua.h`,
    `lualib.h`, `lauxlib.h`) + our shims to the Swift `CLua` module.
  - `lua_shims.h` — `static inline` wrappers (`cl_*`) for Lua's function-like
    macros (`lua_pcall`, `lua_pop`, `lua_pushcfunction`, ...), which Clang's
    importer does not surface to Swift. This is the only hand-written C.
  - `module.modulemap` — declares the `CLua` module over `clua.h`.

## Build configuration

`Package.swift` compiles this as a SwiftPM C target with `-DLUA_USE_MACOSX`
(Lua's own macOS switch → enables `LUA_USE_POSIX` + dlopen-based package loading).
No source files were modified from upstream.

## To update

Download the new tarball, verify its SHA-256, copy `src/*.c` (minus `lua.c`/`luac.c`)
and `src/*.h`, and re-check this file. The shims only touch public macros and are
stable across 5.4.x.
