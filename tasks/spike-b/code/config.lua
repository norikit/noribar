-- Spike B sample config — drives the bar entirely from Lua.
-- Edit and save this file while the app runs to see hot reload in action.

-- Declarative item creation.
local clock = bar.add({ type = "item", position = "right", icon = "clock", label = "" })
local front = bar.add({ type = "item", position = "left", icon = "app.dashed", label = "—" })
local beat = bar.add({ type = "item", position = "center", icon = "heart.fill", label = "noribar" })

-- A live clock: the host run loop calls back into Lua once per second.
clock:set({ label = os.date("%H:%M:%S") })
bar.every(1.0, function()
	clock:set({ label = os.date("%H:%M:%S") })
end)

-- A second, faster timer mutating the center item (proves multiple timers).
local ticks = 0
bar.every(0.5, function()
	ticks = ticks + 1
	beat:set({ icon = (ticks % 2 == 0) and "heart.fill" or "heart" })
end)

-- Subscribe to a (simulated, for this spike) system event.
bar.subscribe("front_app_switched", function(payload)
	front:set({ label = payload.app })
end)
