--!strict
--@author OrkGabb
--@module ItemRegistry.luau
--@version 1.0
-- src/Shared/Modules/ItemRegistry.lua
-- Category-aware Item and Recipe Registry.
-- Dynamically compiles item and recipe databases based on resolved active categories.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local UI = (AssetRegistry and AssetRegistry.UI) or {}

export type PotionDef = {
	Name: string,
	Type: string,
	Stat: string,
	Boost: number,
	Duration: number,
	Color: Color3,
	IconId: string,
}

export type RecipeDef = {
	Ingredients: {[string]: number},
	Cost: number,
}

local ItemRegistry = {
	Potions = {} :: {[string]: PotionDef},
	Essences = {} :: {[string]: any},
	Recipes = {} :: {[string]: RecipeDef}
}

-- Raw Material / Essence items (always loaded as universal resources)
local EssencesLibrary = {
	["Essence_COMMON"] = { Name = "Common Essence", Type = "Material", Color = Color3.fromRGB(180, 180, 180), IconId = (UI.EssencesSprite or ""), ImageRectOffset = Vector2.new(0, 0), ImageRectSize = Vector2.new(256, 256) },
	["Essence_UNCOMMON"] = { Name = "Uncommon Essence", Type = "Material", Color = Color3.fromRGB(80, 255, 80), IconId = (UI.EssencesSprite or ""), ImageRectOffset = Vector2.new(256, 0), ImageRectSize = Vector2.new(256, 256) },
	["Essence_RARE"] = { Name = "Rare Essence", Type = "Material", Color = Color3.fromRGB(80, 150, 255), IconId = (UI.EssencesSprite or ""), ImageRectOffset = Vector2.new(512, 0), ImageRectSize = Vector2.new(256, 256) },
	["Essence_EPIC"] = { Name = "Epic Essence", Type = "Material", Color = Color3.fromRGB(150, 80, 255), IconId = (UI.EssencesSprite or ""), ImageRectOffset = Vector2.new(768, 0), ImageRectSize = Vector2.new(256, 256) },
	["Essence_LEGENDARY"] = { Name = "Legendary Essence", Type = "Material", Color = Color3.fromRGB(255, 215, 0), IconId = (UI.EssencesSprite or ""), ImageRectOffset = Vector2.new(0, 256), ImageRectSize = Vector2.new(256, 256) },
	["Essence_MYTHIC"] = { Name = "Mythic Essence", Type = "Material", Color = Color3.fromRGB(255, 50, 50), IconId = (UI.EssencesSprite or ""), ImageRectOffset = Vector2.new(256, 256), ImageRectSize = Vector2.new(256, 256) },
	["Essence_MUTANT"] = { Name = "Mutant Essence", Type = "Material", Color = Color3.fromRGB(255, 100, 200), IconId = (UI.EssencesSprite or ""), ImageRectOffset = Vector2.new(512, 256), ImageRectSize = Vector2.new(256, 256) },
	["Essence_ABYSSAL"] = { Name = "Abyssal Essence", Type = "Material", Color = Color3.fromRGB(50, 0, 100), IconId = (UI.EssencesSprite or ""), ImageRectOffset = Vector2.new(768, 256), ImageRectSize = Vector2.new(256, 256) },
	["Essence_COSMIC"] = { Name = "Cosmic Essence", Type = "Material", Color = Color3.fromRGB(0, 255, 255), IconId = (UI.EssencesSprite or ""), ImageRectOffset = Vector2.new(0, 512), ImageRectSize = Vector2.new(256, 256) },
	["Essence_SINGULARITY"] = { Name = "Singularity Essence", Type = "Material", Color = Color3.fromRGB(200, 255, 255), IconId = (UI.EssencesSprite or ""), ImageRectOffset = Vector2.new(256, 512), ImageRectSize = Vector2.new(256, 256) },
	["Essence_EXOTIC"] = { Name = "Exotic Essence", Type = "Material", Color = Color3.fromRGB(0, 255, 100), IconId = (UI.EssencesSprite or ""), ImageRectOffset = Vector2.new(512, 512), ImageRectSize = Vector2.new(256, 256) },
	["Essence_OMNI"] = { Name = "Omni Essence", Type = "Material", Color = Color3.fromRGB(255, 255, 255), IconId = (UI.EssencesSprite or ""), ImageRectOffset = Vector2.new(768, 512), ImageRectSize = Vector2.new(256, 256) }
}

-- Potion templates by category
local PotionsLibrary = {
	["Clicker_Farm"] = {
		Potions = {
			-- TIER 1
			["LuckPotion_1"] = { Name = "Luck Potion I", Type = "Buff", Stat = "Luck", Boost = 0.5, Duration = 600, Color = Color3.fromRGB(0, 255, 100), IconId = (UI.LuckPotionIcon or "") },
			["EXPPotion_1"] = { Name = "EXP Potion I", Type = "Buff", Stat = "EXP", Boost = 1.0, Duration = 1800, Color = Color3.fromRGB(150, 80, 255), IconId = (UI.EXPPotionIcon or "") },
			["CoinPotion_1"] = { Name = "Coins Potion I", Type = "Buff", Stat = "Coin", Boost = 1.0, Duration = 1800, Color = Color3.fromRGB(255, 200, 0), IconId = (UI.CoinPotionIcon or "") },
			["SpeedPotion_1"] = { Name = "Roll Speed Potion I", Type = "Buff", Stat = "Speed", Boost = 0.5, Duration = 600, Color = Color3.fromRGB(0, 150, 255), IconId = (UI.SpeedPotionIcon or "") },
			["StrengthPotion_1"] = { Name = "Strength Potion I", Type = "Buff", Stat = "Strength", Boost = 1.0, Duration = 1800, Color = Color3.fromRGB(255, 50, 50), IconId = (UI.StrengthPotionIcon or "") },
			-- TIER 2
			["LuckPotion_2"] = { Name = "Luck Potion II", Type = "Buff", Stat = "Luck", Boost = 1.0, Duration = 600, Color = Color3.fromRGB(0, 255, 100), IconId = (UI.LuckPotionIcon or "") },
			["EXPPotion_2"] = { Name = "EXP Potion II", Type = "Buff", Stat = "EXP", Boost = 1.5, Duration = 1800, Color = Color3.fromRGB(150, 80, 255), IconId = (UI.EXPPotionIcon or "") },
			["CoinPotion_2"] = { Name = "Coins Potion II", Type = "Buff", Stat = "Coin", Boost = 1.5, Duration = 1800, Color = Color3.fromRGB(255, 200, 0), IconId = (UI.CoinPotionIcon or "") },
			["SpeedPotion_2"] = { Name = "Roll Speed Potion II", Type = "Buff", Stat = "Speed", Boost = 1.0, Duration = 600, Color = Color3.fromRGB(0, 150, 255), IconId = (UI.SpeedPotionIcon or "") },
			["StrengthPotion_2"] = { Name = "Strength Potion II", Type = "Buff", Stat = "Strength", Boost = 2.0, Duration = 1800, Color = Color3.fromRGB(255, 50, 50), IconId = (UI.StrengthPotionIcon or "") },
			-- TIER 3
			["LuckPotion_3"] = { Name = "Luck Potion III", Type = "Buff", Stat = "Luck", Boost = 2.0, Duration = 900, Color = Color3.fromRGB(0, 255, 100), IconId = (UI.LuckPotionIcon or "") },
			["EXPPotion_3"] = { Name = "EXP Potion III", Type = "Buff", Stat = "EXP", Boost = 2.0, Duration = 1800, Color = Color3.fromRGB(150, 80, 255), IconId = (UI.EXPPotionIcon or "") },
			["CoinPotion_3"] = { Name = "Coins Potion III", Type = "Buff", Stat = "Coin", Boost = 2.0, Duration = 1800, Color = Color3.fromRGB(255, 200, 0), IconId = (UI.CoinPotionIcon or "") },
			["SpeedPotion_3"] = { Name = "Roll Speed Potion III", Type = "Buff", Stat = "Speed", Boost = 2.0, Duration = 900, Color = Color3.fromRGB(0, 150, 255), IconId = (UI.SpeedPotionIcon or "") },
			["StrengthPotion_3"] = { Name = "Strength Potion III", Type = "Buff", Stat = "Strength", Boost = 3.0, Duration = 1800, Color = Color3.fromRGB(255, 50, 50), IconId = (UI.StrengthPotionIcon or "") }
		},
		Recipes = {
			["LuckPotion_1"] = { Ingredients = { ["Essence_COMMON"] = 5, ["Essence_UNCOMMON"] = 2 }, Cost = 1000 },
			["EXPPotion_1"] = { Ingredients = { ["Essence_COMMON"] = 5, ["Essence_UNCOMMON"] = 2 }, Cost = 1000 },
			["CoinPotion_1"] = { Ingredients = { ["Essence_COMMON"] = 5, ["Essence_UNCOMMON"] = 2 }, Cost = 1000 },
			["SpeedPotion_1"] = { Ingredients = { ["Essence_COMMON"] = 5, ["Essence_UNCOMMON"] = 2 }, Cost = 1000 },
			["StrengthPotion_1"] = { Ingredients = { ["Essence_COMMON"] = 5, ["Essence_UNCOMMON"] = 2 }, Cost = 1000 },

			["LuckPotion_2"] = { Ingredients = { ["Essence_RARE"] = 5, ["Essence_EPIC"] = 2, ["LuckPotion_1"] = 1 }, Cost = 5000 },
			["EXPPotion_2"] = { Ingredients = { ["Essence_RARE"] = 5, ["Essence_EPIC"] = 2, ["EXPPotion_1"] = 1 }, Cost = 5000 },
			["CoinPotion_2"] = { Ingredients = { ["Essence_RARE"] = 5, ["Essence_EPIC"] = 2, ["CoinPotion_1"] = 1 }, Cost = 5000 },
			["SpeedPotion_2"] = { Ingredients = { ["Essence_RARE"] = 5, ["Essence_EPIC"] = 2, ["SpeedPotion_1"] = 1 }, Cost = 5000 },
			["StrengthPotion_2"] = { Ingredients = { ["Essence_RARE"] = 5, ["Essence_EPIC"] = 2, ["StrengthPotion_1"] = 1 }, Cost = 5000 },

			["LuckPotion_3"] = { Ingredients = { ["Essence_LEGENDARY"] = 3, ["Essence_MYTHIC"] = 1, ["LuckPotion_2"] = 1 }, Cost = 25000 },
			["EXPPotion_3"] = { Ingredients = { ["Essence_LEGENDARY"] = 3, ["Essence_MYTHIC"] = 1, ["EXPPotion_2"] = 1 }, Cost = 25000 },
			["CoinPotion_3"] = { Ingredients = { ["Essence_LEGENDARY"] = 3, ["Essence_MYTHIC"] = 1, ["CoinPotion_2"] = 1 }, Cost = 25000 },
			["SpeedPotion_3"] = { Ingredients = { ["Essence_LEGENDARY"] = 3, ["Essence_MYTHIC"] = 1, ["SpeedPotion_2"] = 1 }, Cost = 25000 },
			["StrengthPotion_3"] = { Ingredients = { ["Essence_LEGENDARY"] = 3, ["Essence_MYTHIC"] = 1, ["StrengthPotion_2"] = 1 }, Cost = 25000 }
		}
	},
	["FPS_Shooter"] = {
		Potions = {
			["DamagePotion_1"] = { Name = "Damage Potion I", Type = "Buff", Stat = "Damage", Boost = 0.25, Duration = 600, Color = Color3.fromRGB(255, 60, 60), IconId = (UI.StrengthPotionIcon or "") },
			["ReloadPotion_1"] = { Name = "Reload Potion I", Type = "Buff", Stat = "ReloadSpeed", Boost = 0.2, Duration = 600, Color = Color3.fromRGB(100, 200, 255), IconId = (UI.SpeedPotionIcon or "") }
		},
		Recipes = {
			["DamagePotion_1"] = { Ingredients = { ["Essence_COMMON"] = 6, ["Essence_UNCOMMON"] = 3 }, Cost = 1200 },
			["ReloadPotion_1"] = { Ingredients = { ["Essence_COMMON"] = 6, ["Essence_UNCOMMON"] = 3 }, Cost = 1200 }
		}
	},
	["RPG_Adventure"] = {
		Potions = {
			["HealthPotion_1"] = { Name = "Health Potion I", Type = "Buff", Stat = "HealthMax", Boost = 0.3, Duration = 900, Color = Color3.fromRGB(50, 220, 100), IconId = (UI.LuckPotionIcon or "") },
			["DefensePotion_1"] = { Name = "Defense Potion I", Type = "Buff", Stat = "Defense", Boost = 0.2, Duration = 900, Color = Color3.fromRGB(180, 180, 200), IconId = (UI.VIPPassIcon or "") }
		},
		Recipes = {
			["HealthPotion_1"] = { Ingredients = { ["Essence_COMMON"] = 5, ["Essence_UNCOMMON"] = 2 }, Cost = 1000 },
			["DefensePotion_1"] = { Ingredients = { ["Essence_COMMON"] = 5, ["Essence_UNCOMMON"] = 2 }, Cost = 1000 }
		}
	},
	["Pet_Simulator"] = {
		Potions = {
			["PetXPPotion_1"] = { Name = "Pet EXP Potion I", Type = "Buff", Stat = "PetEXP", Boost = 1.0, Duration = 1200, Color = Color3.fromRGB(200, 80, 255), IconId = (UI.EXPPotionIcon or "") }
		},
		Recipes = {
			["PetXPPotion_1"] = { Ingredients = { ["Essence_COMMON"] = 8, ["Essence_UNCOMMON"] = 2 }, Cost = 1500 }
		}
	},
	["Global"] = {
		Potions = {
			["SpeedPotion_1"] = { Name = "Speed Potion I", Type = "Buff", Stat = "Speed", Boost = 0.5, Duration = 600, Color = Color3.fromRGB(0, 150, 255), IconId = (UI.SpeedPotionIcon or "") },
			["LuckPotion_1"] = { Name = "Luck Potion I", Type = "Buff", Stat = "Luck", Boost = 0.5, Duration = 600, Color = Color3.fromRGB(0, 255, 100), IconId = (UI.LuckPotionIcon or "") }
		},
		Recipes = {
			["SpeedPotion_1"] = { Ingredients = { ["Essence_COMMON"] = 5, ["Essence_UNCOMMON"] = 2 }, Cost = 1000 },
			["LuckPotion_1"] = { Ingredients = { ["Essence_COMMON"] = 5, ["Essence_UNCOMMON"] = 2 }, Cost = 1000 }
		}
	}
}

-- Populate Essences (always active)
for key, def in pairs(EssencesLibrary) do
	ItemRegistry.Essences[key] = def
end

-- Compose active category collections dynamically
local function CompileItems()
	table.clear(ItemRegistry.Potions)
	table.clear(ItemRegistry.Recipes)

	local activeCats = FeatureResolver.GetActiveCategories()
	for _, catName in ipairs(activeCats) do
		local lib = PotionsLibrary[catName]
		if lib then
			for k, pDef in pairs(lib.Potions) do
				ItemRegistry.Potions[k] = pDef
			end
			for k, rDef in pairs(lib.Recipes) do
				ItemRegistry.Recipes[k] = rDef
			end
		end
	end
end

CompileItems()

return ItemRegistry
