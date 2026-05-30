-- luacheck configuration for noribar.
--
-- noribar Lua configs are executed by the embedded host runtime (see decision
-- D4 / Spike B), which injects the `bar` API table as a global. Without this,
-- luacheck reports every `bar.*` call as "accessing undefined variable bar".
std = "lua54"
read_globals = {
  "bar",
}
