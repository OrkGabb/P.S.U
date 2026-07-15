--!strict
--@author OrkGabb
--@module QuestRegistry.luau
--@version 1.0
-- src/Shared/Modules/QuestRegistry.lua
-- Category-aware quest configuration registry.
-- Dynamically maps and resolves active quests based on enabled FeatureToggles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local QuestRegistry = {}

export type QuestDef = {
	Id: string,
	QuestType: string,
	ActionType: string,
	Target: number,
	BaseCoins: number,
	BaseEXP: number,
	Title: string,
	Desc: string,
}

local QuestLibrary: {[string]: {QuestDef}} = {
	["Clicker_Farm"] = {
		{
			Id         = "Click1000",
			QuestType  = "Daily",
			ActionType = "Click",
			Target     = 1000,
			BaseCoins  = 200,
			BaseEXP    = 1500,
			Title      = "Power Clicker",
			Desc       = "Click to generate coins 1,000 times.",
		},
		{
			Id         = "Potion2",
			QuestType  = "Daily",
			ActionType = "UsePotion",
			Target     = 2,
			BaseCoins  = 650,
			BaseEXP    = 1800,
			Title      = "Potion Connoisseur",
			Desc       = "Use 2 potions of any type.",
		}
	},
	["Aura_Collector"] = {
		{
			Id         = "Roll300",
			QuestType  = "Daily",
			ActionType = "Roll",
			Target     = 300,
			BaseCoins  = 1100,
			BaseEXP    = 2000,
			Title      = "Lucky Spinner",
			Desc       = "Roll for auras 300 times.",
		},
		{
			Id         = "RollUncommon10",
			QuestType  = "Daily",
			ActionType = "RollUncommon",
			Target     = 10,
			BaseCoins  = 1100,
			BaseEXP    = 2000,
			Title      = "Fortunate Finder",
			Desc       = "Roll 10 Uncommon or higher auras.",
		},
		{
			Id         = "Potion2",
			QuestType  = "Daily",
			ActionType = "UsePotion",
			Target     = 2,
			BaseCoins  = 650,
			BaseEXP    = 1800,
			Title      = "Potion Connoisseur",
			Desc       = "Use 2 potions of any type.",
		}
	},
	["FPS_Shooter"] = {
		{
			Id         = "Shoot1000",
			QuestType  = "Daily",
			ActionType = "Shoot",
			Target     = 1000,
			BaseCoins  = 1200,
			BaseEXP    = 2000,
			Title      = "Trigger Happy",
			Desc       = "Fire 1,000 rounds of ammo.",
		},
		{
			Id         = "DefeatTargets",
			QuestType  = "Daily",
			ActionType = "Kill",
			Target     = 30,
			BaseCoins  = 1500,
			BaseEXP    = 2500,
			Title      = "Marksman Target",
			Desc       = "Eliminate 30 target practice targets.",
		},
		{
			Id         = "Headshots5",
			QuestType  = "Daily",
			ActionType = "Headshot",
			Target     = 5,
			BaseCoins  = 800,
			BaseEXP    = 1800,
			Title      = "Deadeye Shot",
			Desc       = "Score 5 precision headshots.",
		}
	},
	["RPG_Adventure"] = {
		{
			Id         = "VanquishEnemies",
			QuestType  = "Daily",
			ActionType = "Kill",
			Target     = 25,
			BaseCoins  = 1400,
			BaseEXP    = 2200,
			Title      = "Arena Slayer",
			Desc       = "Defeat 25 arena monsters.",
		},
		{
			Id         = "ExploreRealms",
			QuestType  = "Daily",
			ActionType = "Explore",
			Target     = 5,
			BaseCoins  = 1000,
			BaseEXP    = 1800,
			Title      = "Realm Explorer",
			Desc       = "Travel to different zones 5 times.",
		}
	},
	["Pet_Simulator"] = {
		{
			Id         = "HatchEggs",
			QuestType  = "Daily",
			ActionType = "Hatch",
			Target     = 10,
			BaseCoins  = 1300,
			BaseEXP    = 2100,
			Title      = "Egg Collector",
			Desc       = "Hatch 10 pet eggs.",
		},
		{
			Id         = "TrainPets",
			QuestType  = "Daily",
			ActionType = "Train",
			Target     = 5,
			BaseCoins  = 900,
			BaseEXP    = 1700,
			Title      = "Pet Trainer",
			Desc       = "Upgrade or train your pets 5 times.",
		}
	},
	["Global"] = {
		{
			Id         = "Upgrade15",
			QuestType  = "Weekly",
			ActionType = "Upgrade",
			Target     = 15,
			BaseCoins  = 12000,
			BaseEXP    = 18000,
			Title      = "Mastery Progression",
			Desc       = "Purchase 15 Mastery Upgrades this week.",
		}
	}
}

QuestRegistry.Quests = {}

local function CompileQuests()
	table.clear(QuestRegistry.Quests)
	
	-- Global quests always load
	local globalQuests = QuestLibrary["Global"]
	if globalQuests then
		for _, q in ipairs(globalQuests) do
			table.insert(QuestRegistry.Quests, q)
		end
	end

	-- Layer in quests from the currently active category
	local activeCats = FeatureResolver.GetActiveCategories()
	for _, catName in ipairs(activeCats) do
		if catName == "Global" then continue end
		local quests = QuestLibrary[catName]
		if quests then
			for _, q in ipairs(quests) do
				table.insert(QuestRegistry.Quests, q)
			end
		end
	end
end

CompileQuests()

function QuestRegistry.GetMultiplier(level: number, rebirths: number?): number
	local R = rebirths or 0
	local L = math.max(1, level)
	return math.pow(L, 1.5) * (1 + R * 0.5)
end

return QuestRegistry
