--!strict
-- @Author @OrkGabb
-- src/Shared/Modules/ItemRegistry.luau
-- Category-aware consumable item registry — single source of truth for potion
-- definitions. Compiles the active genre's potion set at load; ItemService
-- (server) validates consumption against it and BagController / BuffHUD
-- (client) render from it, so effects and display can never disagree.
--
-- Potions are volatile buffs: ItemService holds them in memory only, they are
-- never persisted. `Stat` names what the buff multiplies; each genre's
-- services decide which stats they honour (e.g. Aura_Collector reads "Luck"
-- and "Speed", Clicker_Farm reads "Coin" and "EXP").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local UI = AssetRegistry.UI

export type PotionDef = {
	Name: string,
	Type: string,
	Stat: string,
	Boost: number,
	Duration: number,
	Color: Color3,
	IconId: string,
}

local ItemRegistry = {
	Potions = {} :: {[string]: PotionDef},
}

-- Potion templates by category. Only the active genre's set (plus Global) is
-- compiled into ItemRegistry.Potions.
local PotionsLibrary: {[string]: {[string]: PotionDef}} = {
	["Clicker_Farm"] = {
		["CoinPotion_1"]  = { Name = "Coins Potion I",  Type = "Buff", Stat = "Coin",  Boost = 1.0, Duration = 1800, Color = Color3.fromRGB(255, 200, 0),  IconId = UI.CoinPotionIcon },
		["CoinPotion_2"]  = { Name = "Coins Potion II", Type = "Buff", Stat = "Coin",  Boost = 1.5, Duration = 1800, Color = Color3.fromRGB(255, 200, 0),  IconId = UI.CoinPotionIcon },
		["EXPPotion_1"]   = { Name = "EXP Potion I",    Type = "Buff", Stat = "EXP",   Boost = 1.0, Duration = 1800, Color = Color3.fromRGB(150, 80, 255), IconId = UI.EXPPotionIcon },
		["EXPPotion_2"]   = { Name = "EXP Potion II",   Type = "Buff", Stat = "EXP",   Boost = 1.5, Duration = 1800, Color = Color3.fromRGB(150, 80, 255), IconId = UI.EXPPotionIcon },
	},

	-- Luck feeds the roll engine's weight bias, Speed divides the roll
	-- cooldown, Coin/EXP scale idle income (all read by AuraService).
	["Aura_Collector"] = {
		["LuckPotion_1"]  = { Name = "Luck Potion I",       Type = "Buff", Stat = "Luck",  Boost = 0.5, Duration = 600,  Color = Color3.fromRGB(0, 255, 100),  IconId = UI.LuckPotionIcon },
		["LuckPotion_2"]  = { Name = "Luck Potion II",      Type = "Buff", Stat = "Luck",  Boost = 1.0, Duration = 600,  Color = Color3.fromRGB(0, 255, 100),  IconId = UI.LuckPotionIcon },
		["SpeedPotion_1"] = { Name = "Roll Speed Potion I", Type = "Buff", Stat = "Speed", Boost = 0.5, Duration = 600,  Color = Color3.fromRGB(0, 150, 255),  IconId = UI.SpeedPotionIcon },
		["CoinPotion_1"]  = { Name = "Coins Potion I",      Type = "Buff", Stat = "Coin",  Boost = 1.0, Duration = 1800, Color = Color3.fromRGB(255, 200, 0),  IconId = UI.CoinPotionIcon },
		["EXPPotion_1"]   = { Name = "EXP Potion I",        Type = "Buff", Stat = "EXP",   Boost = 1.0, Duration = 1800, Color = Color3.fromRGB(150, 80, 255), IconId = UI.EXPPotionIcon },
	},

	["FPS_Shooter"] = {
		["DamagePotion_1"] = { Name = "Damage Potion I", Type = "Buff", Stat = "Damage",      Boost = 0.25, Duration = 600, Color = Color3.fromRGB(255, 60, 60),   IconId = UI.CoinPotionIcon },
		["ReloadPotion_1"] = { Name = "Reload Potion I", Type = "Buff", Stat = "ReloadSpeed", Boost = 0.2,  Duration = 600, Color = Color3.fromRGB(100, 200, 255), IconId = UI.SpeedPotionIcon },
	},

	["RPG_Adventure"] = {
		["HealthPotion_1"]  = { Name = "Health Potion I",  Type = "Buff", Stat = "HealthMax", Boost = 0.3, Duration = 900, Color = Color3.fromRGB(50, 220, 100),  IconId = UI.LuckPotionIcon },
		["DefensePotion_1"] = { Name = "Defense Potion I", Type = "Buff", Stat = "Defense",   Boost = 0.2, Duration = 900, Color = Color3.fromRGB(180, 180, 200), IconId = UI.VIPPassIcon },
	},

	["Pet_Simulator"] = {
		["PetXPPotion_1"] = { Name = "Pet EXP Potion I", Type = "Buff", Stat = "PetEXP", Boost = 1.0, Duration = 1200, Color = Color3.fromRGB(200, 80, 255), IconId = UI.EXPPotionIcon },
	},

	["Global"] = {},
}

-- Compose active category collections dynamically
local function CompileItems(): ()
	table.clear(ItemRegistry.Potions)

	local activeCats: {string} = FeatureResolver.GetActiveCategories()
	for _, catName in ipairs(activeCats) do
		local lib = PotionsLibrary[catName]
		if lib then
			for k, pDef in pairs(lib) do
				ItemRegistry.Potions[k] = pDef
			end
		end
	end
end

CompileItems()

return ItemRegistry
