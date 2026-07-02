--!strict
-- @Author @OrkGabb
-- src/Shared/Config/CommerceRegistry.luau
-- Genre-scoped monetization registry — single source of truth for GamePass and
-- Developer Product definitions across every genre preset. Nothing in a
-- service should ever hardcode a product ID: services consume the compiled
-- view for the active genre (via StoreRegistry or directly from here).
--
-- ⚠️ All Id values below are PLACEHOLDERS. Replace them with your real IDs
--    from the Roblox Creator Hub before publishing.
--
-- Effect metadata is interpreted by genre services:
--   IncomeMultiplier — multiplies all currency income (stacks multiplicatively)
--   AutoClicksPerSecond — server-side auto-clicker cadence (Clicker_Farm)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

export type CommerceEffect = {
	Type: string,
	Value: number,
}

export type GamepassDef = {
	Id: number,
	Name: string,
	Description: string,
	Price: number, -- Robux, display only (live price comes from MarketplaceService)
	Icon: string?,
	Color: Color3?,
	Effect: CommerceEffect?,
}

export type DevProductReward = {
	Type: string,     -- "Currency" | "Boost" | "Item" | "VIP"
	Amount: number,
	ItemId: string?,  -- currency slot ("Primary"/"Secondary") or item id
	DurationSeconds: number?, -- for timed boosts
}

export type DevProductDef = {
	Id: number,
	Name: string,
	Description: string,
	Price: number,
	Icon: string?,
	Color: Color3?,
	Reward: DevProductReward,
}

export type GenreCommerce = {
	Gamepasses: {[string]: GamepassDef},
	DevProducts: {[string]: DevProductDef},
}

local Library: {[string]: GenreCommerce} = {
	["Clicker_Farm"] = {
		Gamepasses = {
			["Income2x"] = {
				Id = 99000001,
				Name = "Sugar Rush (2×)",
				Description = "Permanently doubles all Sugar income.",
				Price = 199,
				Color = Color3.fromRGB(255, 170, 60),
				Effect = { Type = "IncomeMultiplier", Value = 2 },
			},
			["AutoClicker"] = {
				Id = 99000002,
				Name = "Auto-Baker",
				Description = "Automatically taps twice per second, even while idle.",
				Price = 149,
				Color = Color3.fromRGB(120, 200, 255),
				Effect = { Type = "AutoClicksPerSecond", Value = 2 },
			},
			["VIP"] = {
				Id = 99000003,
				Name = "VIP Pâtissier",
				Description = "3× income and a golden chat badge.",
				Price = 499,
				Color = Color3.fromRGB(255, 215, 0),
				Effect = { Type = "IncomeMultiplier", Value = 3 },
			},
		},
		DevProducts = {
			["SugarBag"] = {
				Id = 99000005,
				Name = "Bag of Sugar",
				Description = "Instantly grants 50,000 Sugar.",
				Price = 79,
				Color = Color3.fromRGB(240, 240, 255),
				Reward = { Type = "Currency", Amount = 50000, ItemId = "Primary" },
			},
			["SugarChest"] = {
				Id = 99000006,
				Name = "Sugar Chest",
				Description = "Instantly grants 1,000,000 Sugar.",
				Price = 299,
				Color = Color3.fromRGB(200, 160, 90),
				Reward = { Type = "Currency", Amount = 1000000, ItemId = "Primary" },
			},
		},
	},

	["FPS_Shooter"] = {
		Gamepasses = {},
		DevProducts = {},
	},

	["Aura_Collector"] = {
		Gamepasses = {},
		DevProducts = {},
	},

	["Pet_Simulator"] = {
		Gamepasses = {},
		DevProducts = {},
	},
}

local CommerceRegistry = {}

CommerceRegistry.Library = Library

-- ── Compiled views for the active genre ──────────────────────────────────────

-- passKey → GamepassDef for every pass in the active genre
CommerceRegistry.ActiveGamepasses = {} :: {[string]: GamepassDef}
-- passKey → numeric GamePass ID (shape consumed by MonetizationService)
CommerceRegistry.GamepassIDs = {} :: {[string]: number}
-- numeric product ID → reward definition (shape consumed by ProcessReceipt)
CommerceRegistry.DevProducts = {} :: {[number]: DevProductReward}
-- productKey → DevProductDef for UI listings
CommerceRegistry.ActiveDevProducts = {} :: {[string]: DevProductDef}

function CommerceRegistry.Recompile(): ()
	table.clear(CommerceRegistry.ActiveGamepasses)
	table.clear(CommerceRegistry.GamepassIDs)
	table.clear(CommerceRegistry.DevProducts)
	table.clear(CommerceRegistry.ActiveDevProducts)

	local genre = FeatureResolver.GetActiveGenre()
	local commerce = genre and Library[genre]
	if not commerce then return end

	for key, pass in pairs(commerce.Gamepasses) do
		CommerceRegistry.ActiveGamepasses[key] = pass
		CommerceRegistry.GamepassIDs[key] = pass.Id
	end
	for key, product in pairs(commerce.DevProducts) do
		CommerceRegistry.ActiveDevProducts[key] = product
		CommerceRegistry.DevProducts[product.Id] = product.Reward
	end
end

-- Product of every owned gamepass's IncomeMultiplier effect.
-- `ownsPass` is injected (server: MonetizationService.HasGamepass) so this
-- module stays side-effect free and shared-safe.
function CommerceRegistry.GetIncomeMultiplier(ownsPass: (passKey: string) -> boolean): number
	local multiplier = 1
	for key, pass in pairs(CommerceRegistry.ActiveGamepasses) do
		local effect = pass.Effect
		if effect and effect.Type == "IncomeMultiplier" and ownsPass(key) then
			multiplier *= effect.Value
		end
	end
	return multiplier
end

-- Highest AutoClicksPerSecond effect among owned passes (0 = none owned).
function CommerceRegistry.GetAutoClicksPerSecond(ownsPass: (passKey: string) -> boolean): number
	local best = 0
	for key, pass in pairs(CommerceRegistry.ActiveGamepasses) do
		local effect = pass.Effect
		if effect and effect.Type == "AutoClicksPerSecond" and ownsPass(key) then
			best = math.max(best, effect.Value)
		end
	end
	return best
end

CommerceRegistry.Recompile()

return CommerceRegistry
