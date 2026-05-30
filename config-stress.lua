-- noribar stress config — exercises the D6 one-animation-per-view rule under load.
--
-- A single item is hammered every 0.1 s with BOTH an icon swap AND a discrete effect.
-- This is exactly the shape Spike A found could crash Apple's RenderBox animation thread
-- if a content transition and a discrete effect are stacked on one view in one turn.
-- noribar's SymbolAnimator must coalesce/serialize these so the bar runs indefinitely
-- with no crash. Run: `swift run noribar --stress` and leave it up for a few minutes.

local box = bar.add({ position = "center", icon = "square", label = "stress" })

local n = 0
bar.every(0.1, function()
	n = n + 1
	-- Alternate icon AND request a discrete effect on the same set — the trap.
	box:set({
		icon = (n % 2 == 0) and "square.fill" or "square",
		effect = (n % 3 == 0) and "bounce" or "pulse",
	})
end)

-- A second fast timer requesting a content transition on the SAME item, to also exercise
-- the "never stack a content transition + a discrete effect in one turn" path.
bar.every(0.1, function()
	box:set({ icon = "circle", effect = "replace" })
end)
