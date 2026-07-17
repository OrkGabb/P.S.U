--!nocheck
-- tests/specs/RollEngine.spec.luau
-- Weighted-roll core shared by every RNG genre (Aura rolls, Pet hatches).

local T = require("../lune/harness")
local psu = require("../lune/psu")

local RollEngine = psu.load("Shared/Modules/RollEngine")

T.suite("RollEngine")

T.test("New sums TotalWeight across the input weights", function()
	local engine = RollEngine.New({ 1, 3, 6 })
	T.eq(engine.TotalWeight, 10)
end)

T.test("GetChances returns Weight/TotalWeight, index-aligned", function()
	local engine = RollEngine.New({ 1, 1, 2 })
	local chances = engine:GetChances()
	T.eq(#chances, 3)
	T.near(chances[1], 0.25)
	T.near(chances[2], 0.25)
	T.near(chances[3], 0.5)
end)

T.test("GetChances sums to 1 for a non-trivial distribution", function()
	local engine = RollEngine.New({ 5, 12, 0.5, 90, 2 })
	local total = 0
	for _, c in ipairs(engine:GetChances()) do
		total += c
	end
	T.near(total, 1)
end)

T.test("GetChances guards against divide-by-zero when TotalWeight is 0", function()
	local engine = RollEngine.New({ 0, 0, 0 })
	T.eq(engine.TotalWeight, 0)
	local chances = engine:GetChances()
	T.eq(#chances, 3)
	for _, c in ipairs(chances) do
		T.eq(c, 0)
	end
end)

T.test("Roll always returns the only bucket for a single-weight engine", function()
	local engine = RollEngine.New({ 42 })
	for _ = 1, 100 do
		T.eq(engine:Roll(), 1)
	end
end)

T.test("Roll stays within [1, #weights] across many samples", function()
	local engine = RollEngine.New({ 3, 3, 3, 3 })
	for _ = 1, 500 do
		local idx = engine:Roll()
		T.truthy(idx >= 1 and idx <= 4, "index out of range: " .. tostring(idx))
	end
end)

T.test("high luck deterministically forces the lowest (rarest) index", function()
	-- luck shrinks the effective total weight so target -> ~0, and the binary
	-- search resolves to the first cumulative bucket. Entries are rarest-first,
	-- so extreme luck must always land on index 1.
	local engine = RollEngine.New({ 1, 1, 1, 1, 1 })
	for _ = 1, 200 do
		T.eq(engine:Roll(1e9), 1)
	end
end)

T.test("luck below 1 is clamped and never errors or leaves range", function()
	local engine = RollEngine.New({ 2, 2, 2 })
	for _, luck in ipairs({ 0, 0.001, -5 }) do
		local idx = engine:Roll(luck)
		T.truthy(idx >= 1 and idx <= 3, "clamped luck produced bad index for luck=" .. tostring(luck))
	end
end)

T.test("New clones the input weights (later mutation does not leak in)", function()
	local weights = { 1, 1 }
	local engine = RollEngine.New(weights)
	weights[1] = 999
	T.eq(engine.TotalWeight, 2)
end)

return {}
