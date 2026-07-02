--!strict
-- @Author @OrkGabb
-- src/Shared/Modules/UpgradeRegistry.luau
-- Category-aware upgrade registry — single source of truth for every upgrade's
-- identity, cost model and effect model. Consumers never compute costs
-- themselves; they call UpgradeRegistry.GetCost / GetMilestoneCost so server
-- validation and client display can never drift apart.
--
-- Cost models (exactly one per def):
--   • Formula: BaseCost × CostMultiplier^level      (classic exponential curve)
--   • Table:   CostTable[newLevel]                  (hand-tuned lookup table)
-- Either model may additionally carry a milestone gate: every MilestoneEvery
-- levels the purchase also charges MilestoneCosts[newLevel / MilestoneEvery]
-- in MilestoneCurrency (e.g. Clicker_Farm charges Cupcakes at levels 5, 10, …).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

export type UpgradeDef = {
	Name: string,
	MaxLevel: number,
	Category: string,

	-- Cost model — formula
	BaseCost: number?,
	CostMultiplier: number?,
	-- Cost model — lookup table: cost of buying INTO level i (1-based)
	CostTable: {number}?,
	-- Currency slot the base cost is charged in (default "Primary")
	CostCurrency: string?,

	-- Milestone gate — additional lookup-table cost in a second currency,
	-- charged when a purchase lands on a multiple of MilestoneEvery
	MilestoneEvery: number?,
	MilestoneCosts: {number}?,
	MilestoneCurrency: string?, -- default "Secondary"

	-- Effect model
	Kind: string?,       -- "PerClick" | "Passive" | "Mastery" (default "Mastery")
	BasePower: number?,  -- flat stat added per level (PerClick / Passive kinds)
	Increment: number?,  -- fractional bonus added per level (Mastery kind)

	-- UI hints
	StatLabel: string?,  -- e.g. "/TAP", "/SEC"
	Icon: string?,
}

export type UpgradeDefs = {[string]: UpgradeDef}

local UpgradeLibrary: {[string]: UpgradeDefs} = {
	-- ── Clicker_Farm ─────────────────────────────────────────────────────────
	-- Ten-upgrade idle economy: perClick raises manual click power, Passive
	-- raises idle income. The five late-game upgrades additionally charge
	-- Cupcakes (Secondary) every 5th level via the milestone lookup table.
	["Clicker_Farm"] = (function(): UpgradeDefs
		local function milestones(count: number, cost: number): {number}
			local t = table.create(count)
			for i = 1, count do
				t[i] = cost
			end
			return t
		end

		return {
			["whisk_wand"] = {
				Name = "Whisk Wand", MaxLevel = 1000, Category = "Clicker_Farm",
				BaseCost = 1, CostMultiplier = 1.15,
				Kind = "PerClick", BasePower = 1, StatLabel = "/TAP",
				Icon = "rbxassetid://99770665507528",
			},
			["enchanted_oven"] = {
				Name = "Enchanted Oven", MaxLevel = 1000, Category = "Clicker_Farm",
				BaseCost = 3162, CostMultiplier = 1.18,
				Kind = "Passive", BasePower = 2, StatLabel = "/SEC",
				Icon = "rbxassetid://117877381237551",
			},
			["fairy_yeast"] = {
				Name = "Fairy Yeast", MaxLevel = 1000, Category = "Clicker_Farm",
				BaseCost = 10000, CostMultiplier = 1.16,
				Kind = "PerClick", BasePower = 4, StatLabel = "/TAP",
				Icon = "rbxassetid://120107547442628",
			},
			["celestial_sifter"] = {
				Name = "Celestial Sifter", MaxLevel = 1000, Category = "Clicker_Farm",
				BaseCost = 31623, CostMultiplier = 1.19,
				Kind = "Passive", BasePower = 6, StatLabel = "/SEC",
				Icon = "rbxassetid://91402692787215",
			},
			["gingerbread_golem"] = {
				Name = "Gingerbread Golem", MaxLevel = 1000, Category = "Clicker_Farm",
				BaseCost = 100000, CostMultiplier = 1.20,
				Kind = "Passive", BasePower = 14, StatLabel = "/SEC",
				Icon = "rbxassetid://97063621982493",
			},
			["sugar_sprite"] = {
				Name = "Sugar Sprite", MaxLevel = 100, Category = "Clicker_Farm",
				BaseCost = 316228, CostMultiplier = 1.17,
				Kind = "PerClick", BasePower = 20, StatLabel = "/TAP",
				Icon = "rbxassetid://139847478458309",
				MilestoneEvery = 5, MilestoneCosts = milestones(20, 20), MilestoneCurrency = "Secondary",
			},
			["moon_mixer"] = {
				Name = "Moon Mixer", MaxLevel = 100, Category = "Clicker_Farm",
				BaseCost = 1000000, CostMultiplier = 1.21,
				Kind = "Passive", BasePower = 45, StatLabel = "/SEC",
				Icon = "rbxassetid://70558779392071",
				MilestoneEvery = 5, MilestoneCosts = milestones(20, 20), MilestoneCurrency = "Secondary",
			},
			["cloud_kitchen"] = {
				Name = "Cloud Kitchen", MaxLevel = 100, Category = "Clicker_Farm",
				BaseCost = 3162278, CostMultiplier = 1.22,
				Kind = "Passive", BasePower = 120, StatLabel = "/SEC",
				Icon = "rbxassetid://128190000216583",
				MilestoneEvery = 5, MilestoneCosts = milestones(20, 20), MilestoneCurrency = "Secondary",
			},
			["stardust_sprinkles"] = {
				Name = "Stardust Sprinkles", MaxLevel = 100, Category = "Clicker_Farm",
				BaseCost = 10000000, CostMultiplier = 1.18,
				Kind = "PerClick", BasePower = 250, StatLabel = "/TAP",
				Icon = "rbxassetid://78281860129702",
				MilestoneEvery = 5, MilestoneCosts = milestones(20, 20), MilestoneCurrency = "Secondary",
			},
			["cosmic_patissier"] = {
				Name = "Cosmic Pâtissier", MaxLevel = 5, Category = "Clicker_Farm",
				BaseCost = 1000000000, CostMultiplier = 1.25,
				Kind = "Passive", BasePower = 800, StatLabel = "/SEC",
				Icon = "rbxassetid://113071135390923",
				MilestoneEvery = 5, MilestoneCosts = { 200 }, MilestoneCurrency = "Secondary",
			},
		}
	end)(),

	-- ── Aura_Collector ───────────────────────────────────────────────────────
	-- Roll/luck masteries consumed by AuraService. Priced in Essence
	-- (Currencies.Secondary), which only duplicate rolls mint — the sink that
	-- replaced the old transmutation system: rolls → dupes → Essence →
	-- masteries → better rolls.
	["Aura_Collector"] = {
		["LuckMastery"] = {
			Name = "Luck Mastery", MaxLevel = 100, Category = "Aura_Collector",
			BaseCost = 25, CostMultiplier = 1.35, CostCurrency = "Secondary",
			Kind = "Mastery", Increment = 0.04,
		},
		["CoinMastery"] = {
			Name = "Coin Mastery", MaxLevel = 100, Category = "Aura_Collector",
			BaseCost = 25, CostMultiplier = 1.35, CostCurrency = "Secondary",
			Kind = "Mastery", Increment = 0.05,
		},
		["EXPMastery"] = {
			Name = "EXP Mastery", MaxLevel = 100, Category = "Aura_Collector",
			BaseCost = 25, CostMultiplier = 1.35, CostCurrency = "Secondary",
			Kind = "Mastery", Increment = 0.05,
		},
		["SpeedMastery"] = {
			Name = "Roll Speed Mastery", MaxLevel = 30, Category = "Aura_Collector",
			BaseCost = 100, CostMultiplier = 1.6, CostCurrency = "Secondary",
			Kind = "Mastery", Increment = 0.01,
		},
	},

	-- ── FPS_Shooter ──────────────────────────────────────────────────────────
	["FPS_Shooter"] = {
		["DamageMastery"] = {
			Name = "Damage Mastery", MaxLevel = 50, Category = "FPS_Shooter",
			BaseCost = 1000, CostMultiplier = 1.5,
			Kind = "Mastery", Increment = 0.05,
		},
		["ReloadMastery"] = {
			Name = "Reload Mastery", MaxLevel = 50, Category = "FPS_Shooter",
			BaseCost = 1000, CostMultiplier = 1.5,
			Kind = "Mastery", Increment = 0.02,
		},
	},

	-- ── Pet_Simulator ────────────────────────────────────────────────────────
	["Pet_Simulator"] = {},

	-- ── Global ───────────────────────────────────────────────────────────────
	["Global"] = {},
}

local UpgradeRegistry = {}

-- Compiled view: only upgrades whose category is currently active.
UpgradeRegistry.Defs = {} :: UpgradeDefs

function UpgradeRegistry.Recompile(): ()
	table.clear(UpgradeRegistry.Defs)

	local globalDefs = UpgradeLibrary["Global"]
	if globalDefs then
		for id, def in pairs(globalDefs) do
			UpgradeRegistry.Defs[id] = def
		end
	end

	for _, catName in ipairs(FeatureResolver.GetActiveCategories()) do
		if catName == "Global" then continue end
		local defs = UpgradeLibrary[catName]
		if defs then
			for id, def in pairs(defs) do
				UpgradeRegistry.Defs[id] = def
			end
		end
	end
end

function UpgradeRegistry.GetDef(id: string): UpgradeDef?
	return UpgradeRegistry.Defs[id]
end

-- Cost (and currency slot) of buying an upgrade from `level` to `level + 1`.
-- Returns nil when the upgrade is unknown or already maxed.
function UpgradeRegistry.GetCost(id: string, level: number): (number?, string)
	local def = UpgradeRegistry.Defs[id]
	if not def or level >= def.MaxLevel then
		return nil, "Primary"
	end

	local currency = def.CostCurrency or "Primary"

	if def.CostTable then
		local cost = def.CostTable[level + 1]
		if cost == nil then
			return nil, currency
		end
		return cost, currency
	end

	local baseCost = def.BaseCost or 0
	local multiplier = def.CostMultiplier or 1
	return math.floor(baseCost * math.pow(multiplier, level)), currency
end

-- Milestone gate cost (and currency slot) for the purchase that lands ON
-- `newLevel`. Returns 0 when the def has no milestone table or the purchase
-- is not a milestone level.
function UpgradeRegistry.GetMilestoneCost(id: string, newLevel: number): (number, string)
	local def = UpgradeRegistry.Defs[id]
	if not def or not def.MilestoneCosts or not def.MilestoneEvery then
		return 0, "Secondary"
	end
	local currency = def.MilestoneCurrency or "Secondary"
	if newLevel <= 0 or newLevel % def.MilestoneEvery ~= 0 then
		return 0, currency
	end
	return def.MilestoneCosts[newLevel // def.MilestoneEvery] or 0, currency
end

-- Sums BasePower × ownedLevel across all active defs of the given Kind.
-- Drives the Clicker_Farm economy: "PerClick" → click power, "Passive" → CPS.
function UpgradeRegistry.ComputeStat(ownedUpgrades: {[string]: number}, kind: string): number
	local total = 0
	for id, def in pairs(UpgradeRegistry.Defs) do
		if def.Kind == kind and def.BasePower then
			local level = ownedUpgrades[id] or 0
			if level > 0 then
				total += math.min(level, def.MaxLevel) * def.BasePower
			end
		end
	end
	return total
end

UpgradeRegistry.Recompile()

return UpgradeRegistry
