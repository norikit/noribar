-- noribar sample config (M1).
--
-- Items are declared with bar.add{}; bar.every() runs host-driven timers; bar.subscribe()
-- reacts to native provider events. item:set{} mutates an item — and may request a native
-- SF Symbol `effect`. Edit + save this file while noribar runs to hot-reload it.

-- A live clock on the right.
local clock = bar.add({ position = "right", icon = "clock", label = "" })
clock:set({ label = os.date("%H:%M:%S") })
bar.every(1.0, function()
	clock:set({ label = os.date("%H:%M:%S") })
end)

-- A center heartbeat (proves multiple independent timers).
local beat = bar.add({ position = "center", icon = "heart.fill", label = "noribar" })
local ticks = 0
bar.every(0.5, function()
	ticks = ticks + 1
	beat:set({ icon = (ticks % 2 == 0) and "heart.fill" or "heart" })
end)

-- Front-app item on the left, driven by the real FrontAppProvider. Switching apps swaps
-- the icon with a native magic-`replace` symbol transition — the M1 headline.
local front = bar.add({ position = "left", icon = "app.dashed", label = "—" })
bar.subscribe("front_app_switched", function(p)
	front:set({ label = p.app, icon = "app.badge.fill", effect = "replace" })
end)
