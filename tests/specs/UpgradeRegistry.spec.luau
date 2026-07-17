--!nocheck
-- tests/specs/UpgradeRegistry.spec.luau
-- Cost/milestone/effect math that server validation and UI display both read.
-- Loaded with the real on-disk config, so the compiled Defs reflect whichever
-- genre FeatureToggles has enabled (Clicker_Farm by default).

local T = require("../lune/harness")
local psu = require("../lune/psu")

local UpgradeRegistry = psu.load("Shared/Modules/UpgradeRegistry")

T.suite("UpgradeRegistry")

-- ── Config-agnostic contract (holds for whatever genre is compiled in) ────────

T.test("GetDef / GetCost reject unknown ids", function()
	T.isNil(UpgradeRegistry.GetDef("does_not_exist"))
	local cost, currency = UpgradeRegistry.GetCost("does_not_exist", 0)
	T.isNil(cost)
	T.eq(currency, "Primary")
end)

T.test("GetMilestoneCost returns (0, Secondary) for unknown ids", function()
	local cost, currency = UpgradeRegistry.GetMilestoneCost("does_not_exist", 5)
	T.eq(cost, 0)
	T.eq(currency, "Secondary")
end)

T.test("GetCost matches each active def's own cost model, and nils at MaxLevel", function()
	for id, def in pairs(UpgradeRegistry.Defs) do
		-- buying into level 1 (from level 0)
		local cost, currency = UpgradeRegistry.GetCost(id, 0)
		if def.CostTable then
			T.eq(cost, def.CostTable[1], id .. " table cost@0")
		else
			local expected = math.floor((def.BaseCost or 0) * math.pow(def.CostMultiplier or 1, 0))
			T.eq(cost, expected, id .. " formula cost@0")
		end
		T.eq(currency, def.CostCurrency or "Primary", id .. " currency")

		-- at/above MaxLevel there is nothing left to buy
		T.isNil(UpgradeRegistry.GetCost(id, def.MaxLevel), id .. " cost at MaxLevel")
	end
end)

T.test("GetMilestoneCost fires only on multiples of MilestoneEvery", function()
	for id, def in pairs(UpgradeRegistry.Defs) do
		if def.MilestoneEvery and def.MilestoneCosts then
			local onCost = UpgradeRegistry.GetMilestoneCost(id, def.MilestoneEvery)
			T.eq(onCost, def.MilestoneCosts[1], id .. " milestone@Every")
			local offCost = UpgradeRegistry.GetMilestoneCost(id, def.MilestoneEvery - 1)
			T.eq(offCost, 0, id .. " milestone off-cadence")
			T.eq((UpgradeRegistry.GetMilestoneCost(id, 0)), 0, id .. " milestone@0")
		end
	end
end)

T.test("ComputeStat sums BasePower * level and ignores other kinds / zero levels", function()
	T.eq(UpgradeRegistry.ComputeStat({}, "PerClick"), 0)
	-- pick any active PerClick def and verify it scales linearly
	for id, def in pairs(UpgradeRegistry.Defs) do
		if def.Kind == "PerClick" and def.BasePower then
			-- stay within MaxLevel so the clamp inside ComputeStat is not what we
			-- end up measuring here
			local level = math.min(2, def.MaxLevel)
			local owned = { [id] = level }
			-- other PerClick defs stay at level 0 -> contribute nothing
			T.eq(UpgradeRegistry.ComputeStat(owned, "PerClick"), level * def.BasePower, id .. " perclick scale")
			break
		end
	end
end)

-- ── Concrete Clicker_Farm assertions (only when that genre is active) ─────────

if UpgradeRegistry.GetDef("whisk_wand") then
	T.test("Clicker_Farm whisk_wand follows BaseCost * mult^level", function()
		local c0 = UpgradeRegistry.GetCost("whisk_wand", 0)
		T.eq(c0, 1) -- floor(1 * 1.15^0)
		local c10 = UpgradeRegistry.GetCost("whisk_wand", 10)
		T.eq(c10, math.floor(1 * math.pow(1.15, 10))) -- 4
	end)

	T.test("Clicker_Farm sugar_sprite milestone charges 20 Secondary every 5th level", function()
		local at5, cur5 = UpgradeRegistry.GetMilestoneCost("sugar_sprite", 5)
		T.eq(at5, 20)
		T.eq(cur5, "Secondary")
		T.eq((UpgradeRegistry.GetMilestoneCost("sugar_sprite", 10)), 20)
		T.eq((UpgradeRegistry.GetMilestoneCost("sugar_sprite", 4)), 0)
	end)
end

return {}
