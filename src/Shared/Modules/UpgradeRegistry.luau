--!strict
--@author OrkGabb
--@module UpgradeRegistry.luau
--@version 1.0
-- src/Shared/Modules/UpgradeRegistry.lua
-- Category-aware upgrades registry. Calibrated for progression safety.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

export type UpgradeDef = {
	Name: string,
	MaxLevel: number,
	BaseCost: number,
	CostMultiplier: number,
	Increment: number,
	Category: string,
}

local UpgradeRegistry: {[string]: UpgradeDef} = {}

local UpgradeLibrary: {[string]: {[string]: UpgradeDef}} = {
	["Clicker_Farm"] = {
		["LuckMastery"] = {
			Name           = "Luck Mastery",
			MaxLevel       = 100,
			BaseCost       = 500,
			CostMultiplier = 1.49,
			Increment      = 0.04,
			Category       = "Clicker_Farm",
		},
		["CoinMastery"] = {
			Name           = "Coin Mastery",
			MaxLevel       = 100,
			BaseCost       = 500,
			CostMultiplier = 1.49,
			Increment      = 0.05,
			Category       = "Clicker_Farm",
		},
		["EXPMastery"] = {
			Name           = "EXP Mastery",
			MaxLevel       = 100,
			BaseCost       = 500,
			CostMultiplier = 1.49,
			Increment      = 0.05,
			Category       = "Clicker_Farm",
		},
		["SpeedMastery"] = {
			Name           = "Roll Speed Mastery",
			MaxLevel       = 30,
			BaseCost       = 25000,
			CostMultiplier = 3.0,
			Increment      = 0.01,
			Category       = "Clicker_Farm",
		},
		["StrengthMastery"] = {
			Name           = "Strength Mastery",
			MaxLevel       = 80,
			BaseCost       = 1000,
			CostMultiplier = 1.61,
			Increment      = 0.04,
			Category       = "Clicker_Farm",
		},
	},

	["FPS_Shooter"] = {
		["DamageMastery"] = {
			Name           = "Damage Mastery",
			MaxLevel       = 50,
			BaseCost       = 1000,
			CostMultiplier = 1.5,
			Increment      = 0.05,
			Category       = "FPS_Shooter",
		},
		["ReloadMastery"] = {
			Name           = "Reload Mastery",
			MaxLevel       = 50,
			BaseCost       = 1000,
			CostMultiplier = 1.5,
			Increment      = 0.02,
			Category       = "FPS_Shooter",
		},
	},

	["RPG_Adventure"] = {
		["HealthMastery"] = {
			Name           = "Health Mastery",
			MaxLevel       = 50,
			BaseCost       = 800,
			CostMultiplier = 1.4,
			Increment      = 0.05,
			Category       = "RPG_Adventure",
		},
		["DefenseMastery"] = {
			Name           = "Defense Mastery",
			MaxLevel       = 50,
			BaseCost       = 800,
			CostMultiplier = 1.4,
			Increment      = 0.04,
			Category       = "RPG_Adventure",
		},
	},

	["Pet_Simulator"] = {
		["PetXPMastery"] = {
			Name           = "Pet EXP Mastery",
			MaxLevel       = 50,
			BaseCost       = 1500,
			CostMultiplier = 1.6,
			Increment      = 0.05,
			Category       = "Pet_Simulator",
		},
	},

	["Global"] = {
		-- Fallback upgrades or global upgrades can be defined here
	}
}

local function CompileUpgrades()
	table.clear(UpgradeRegistry)

	-- 1. Always load Global upgrades
	local globalUpgrades = UpgradeLibrary["Global"]
	if globalUpgrades then
		for k, u in pairs(globalUpgrades) do
			UpgradeRegistry[k] = u
		end
	end

	-- 2. Dynamically compile upgrades from active categories resolved by FeatureResolver
	local activeCats = FeatureResolver.GetActiveCategories()
	for _, catName in ipairs(activeCats) do
		if catName == "Global" then continue end
		local upgrades = UpgradeLibrary[catName]
		if upgrades then
			for k, u in pairs(upgrades) do
				UpgradeRegistry[k] = u
			end
		end
	end
end

CompileUpgrades()

return UpgradeRegistry
