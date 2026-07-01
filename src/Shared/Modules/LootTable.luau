--!strict
--@author OrkGabb
--@module LootTable.luau
--@version 1.0
-- src/Shared/Modules/LootTable.lua
-- Category-driven universal gacha and item rollout system.
-- Optimized to support dynamic category resolution and clear universal terminology.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

export type LootEntry = {
	name: string,
	weight: number,
	displayName: string,
	rarityTag: string, 
	color: Color3,
	coinMult: number,
	expMult: number,
	trait: string?, 
	iconId: string?,
	paid: boolean?,
}

export type BiomeDef = {
	Id: string,
	DisplayName: string?,
	Name: string?,
	Cost: number,
	LevelReq: number?,
	UnlockCost: number?,
	Currency: string?,
	Color: Color3?,
	Items: {[number]: LootEntry},
	Auras: {[number]: LootEntry}, -- Legacy alias for backwards compatibility
}

export type LootTableImpl = {
	entries: {[number]: LootEntry},
	cumulativeWeights: {[number]: number},
	totalWeight: number,
	Roll: (self: LootTableImpl, luckMultiplier: number?) -> LootEntry,
	GetProbabilities: (self: LootTableImpl) -> {[string]: number},
}

local LootTable = {}
LootTable.__index = LootTable

local FALLBACK_ICON: string = "rbxassetid://15059633013"

-- Universal Content Libraries grouped by active Category
local ContentLibrary = {
	["Global"] = {
		Default = {
			{ name = "Starter Badge", weight = 10000000, displayName = "Starter Badge", rarityTag = "COMMON", color = Color3.fromRGB(180, 180, 180), coinMult = 1, expMult = 1, iconId = FALLBACK_ICON },
			{ name = "Bronze Medal", weight = 2500000, displayName = "Bronze Medal", rarityTag = "UNCOMMON", color = Color3.fromRGB(80, 255, 80), coinMult = 3, expMult = 2, iconId = FALLBACK_ICON },
			{ name = "Silver Medal", weight = 500000, displayName = "Silver Medal", rarityTag = "RARE", color = Color3.fromRGB(80, 150, 255), coinMult = 10, expMult = 5, iconId = FALLBACK_ICON },
			{ name = "Gold Medal", weight = 100000, displayName = "Gold Medal", rarityTag = "EPIC", color = Color3.fromRGB(150, 80, 255), coinMult = 35, expMult = 15, iconId = FALLBACK_ICON },
			{ name = "Star Trophy", weight = 20000, displayName = "Star Trophy", rarityTag = "LEGENDARY", color = Color3.fromRGB(255, 215, 0), coinMult = 150, expMult = 60, iconId = FALLBACK_ICON },
			{ name = "Crown Jewel", weight = 4000, displayName = "Crown Jewel", rarityTag = "MYTHIC", color = Color3.fromRGB(255, 50, 50), coinMult = 800, expMult = 300, iconId = FALLBACK_ICON },
		},
		Blossom = {
			{ name = "Forest Token", weight = 2000000, displayName = "Forest Token", rarityTag = "UNCOMMON", color = Color3.fromRGB(255, 183, 197), coinMult = 5, expMult = 3, iconId = FALLBACK_ICON },
			{ name = "Woodland Crest", weight = 500000, displayName = "Woodland Crest", rarityTag = "RARE", color = Color3.fromRGB(255, 105, 180), coinMult = 15, expMult = 8, iconId = FALLBACK_ICON },
			{ name = "Ancient Bark", weight = 10000, displayName = "Ancient Bark", rarityTag = "LEGENDARY", color = Color3.fromRGB(255, 69, 0), coinMult = 300, expMult = 100, iconId = FALLBACK_ICON },
			{ name = "Nature Core", weight = 500, displayName = "Nature Core", rarityTag = "MUTANT", color = Color3.fromRGB(138, 43, 226), coinMult = 10000, expMult = 3000, iconId = FALLBACK_ICON },
		},
		AbyssalRift = {
			{ name = "Rift Pearl", weight = 100000, displayName = "Rift Pearl", rarityTag = "ABYSSAL", color = Color3.fromRGB(40, 0, 80), coinMult = 600000, expMult = 200000, iconId = FALLBACK_ICON },
			{ name = "Cosmic Core", weight = 25000, displayName = "Cosmic Core", rarityTag = "COSMIC", color = Color3.fromRGB(0, 50, 150), coinMult = 3500000, expMult = 1000000, iconId = FALLBACK_ICON },
			{ name = "Infinity Relic", weight = 0.2, displayName = "Infinity Relic", rarityTag = "SINGULARITY", color = Color3.fromRGB(100, 255, 200), coinMult = 18000000, expMult = 5000000, iconId = FALLBACK_ICON },
		},
		Paid = {
			{ name = "VIP Tag", weight = 0, displayName = "VIP Tag", rarityTag = "VIP", color = Color3.fromRGB(255, 215, 0), coinMult = 12000000, expMult = 3500000, trait = "VIPGlow", iconId = FALLBACK_ICON, paid = true }
		}
	},
	["Clicker_Farm"] = {
		Default = {
			{ name = "Speed Booster I", weight = 10000000, displayName = "Speed Booster I", rarityTag = "COMMON", color = Color3.fromRGB(180, 180, 180), coinMult = 1, expMult = 1, iconId = FALLBACK_ICON },
			{ name = "Coin Booster I", weight = 2500000, displayName = "Coin Booster I", rarityTag = "UNCOMMON", color = Color3.fromRGB(80, 255, 80), coinMult = 3, expMult = 2, iconId = FALLBACK_ICON },
			{ name = "Coin Booster II", weight = 500000, displayName = "Coin Booster II", rarityTag = "RARE", color = Color3.fromRGB(80, 150, 255), coinMult = 10, expMult = 5, iconId = FALLBACK_ICON },
			{ name = "Luck Booster I", weight = 100000, displayName = "Luck Booster I", rarityTag = "EPIC", color = Color3.fromRGB(150, 80, 255), coinMult = 35, expMult = 15, iconId = FALLBACK_ICON },
			{ name = "Super Booster I", weight = 20000, displayName = "Super Booster I", rarityTag = "LEGENDARY", color = Color3.fromRGB(255, 215, 0), coinMult = 150, expMult = 60, iconId = FALLBACK_ICON },
			{ name = "Hyper Booster I", weight = 4000, displayName = "Hyper Booster I", rarityTag = "MYTHIC", color = Color3.fromRGB(255, 50, 50), coinMult = 800, expMult = 300, iconId = FALLBACK_ICON },
		},
		Blossom = {
			{ name = "Bloom Charm", weight = 2000000, displayName = "Bloom Charm", rarityTag = "UNCOMMON", color = Color3.fromRGB(255, 183, 197), coinMult = 5, expMult = 3, iconId = FALLBACK_ICON },
			{ name = "Solar Petal", weight = 500000, displayName = "Solar Petal", rarityTag = "RARE", color = Color3.fromRGB(255, 105, 180), coinMult = 15, expMult = 8, iconId = FALLBACK_ICON },
			{ name = "Master Charm", weight = 10000, displayName = "Master Charm", rarityTag = "LEGENDARY", color = Color3.fromRGB(255, 69, 0), coinMult = 300, expMult = 100, iconId = FALLBACK_ICON },
			{ name = "Spirit Blossom", weight = 500, displayName = "Spirit Blossom", rarityTag = "MUTANT", color = Color3.fromRGB(138, 43, 226), coinMult = 10000, expMult = 3000, iconId = FALLBACK_ICON },
		},
		AbyssalRift = {
			{ name = "Void Core", weight = 100000, displayName = "Void Core", rarityTag = "ABYSSAL", color = Color3.fromRGB(40, 0, 80), coinMult = 600000, expMult = 200000, iconId = FALLBACK_ICON },
			{ name = "Eclipse Core", weight = 25000, displayName = "Eclipse Core", rarityTag = "COSMIC", color = Color3.fromRGB(0, 50, 150), coinMult = 3500000, expMult = 1000000, iconId = FALLBACK_ICON },
			{ name = "Astral Shard", weight = 0.2, displayName = "Astral Shard", rarityTag = "SINGULARITY", color = Color3.fromRGB(100, 255, 200), coinMult = 18000000, expMult = 5000000, iconId = FALLBACK_ICON },
		},
		Paid = {
			{ name = "VIP Booster", weight = 0, displayName = "VIP Booster", rarityTag = "VIP", color = Color3.fromRGB(255, 215, 0), coinMult = 12000000, expMult = 3500000, trait = "VIPGlow", iconId = FALLBACK_ICON, paid = true }
		}
	},
	["FPS_Shooter"] = {
		Default = {
			{ name = "Rusty Pistol", weight = 10000000, displayName = "Rusty Pistol", rarityTag = "COMMON", color = Color3.fromRGB(180, 180, 180), coinMult = 1, expMult = 1, iconId = FALLBACK_ICON },
			{ name = "Standard Pistol", weight = 2500000, displayName = "Standard Pistol", rarityTag = "UNCOMMON", color = Color3.fromRGB(80, 255, 80), coinMult = 3, expMult = 2, iconId = FALLBACK_ICON },
			{ name = "Tactical Pistol", weight = 500000, displayName = "Tactical Pistol", rarityTag = "RARE", color = Color3.fromRGB(80, 150, 255), coinMult = 10, expMult = 5, iconId = FALLBACK_ICON },
			{ name = "Light SMG", weight = 100000, displayName = "Light SMG", rarityTag = "EPIC", color = Color3.fromRGB(150, 80, 255), coinMult = 35, expMult = 15, iconId = FALLBACK_ICON },
			{ name = "Heavy Shotgun", weight = 20000, displayName = "Heavy Shotgun", rarityTag = "LEGENDARY", color = Color3.fromRGB(255, 215, 0), coinMult = 150, expMult = 60, iconId = FALLBACK_ICON },
			{ name = "Golden Pistol", weight = 4000, displayName = "Golden Pistol", rarityTag = "MYTHIC", color = Color3.fromRGB(255, 50, 50), coinMult = 800, expMult = 300, iconId = FALLBACK_ICON },
		},
		Blossom = {
			{ name = "Forest Crossbow", weight = 2000000, displayName = "Forest Crossbow", rarityTag = "UNCOMMON", color = Color3.fromRGB(255, 183, 197), coinMult = 5, expMult = 3, iconId = FALLBACK_ICON },
			{ name = "Burst Rifle", weight = 500000, displayName = "Burst Rifle", rarityTag = "RARE", color = Color3.fromRGB(255, 105, 180), coinMult = 15, expMult = 8, iconId = FALLBACK_ICON },
			{ name = "Hunter Carbine", weight = 10000, displayName = "Hunter Carbine", rarityTag = "LEGENDARY", color = Color3.fromRGB(255, 69, 0), coinMult = 300, expMult = 100, iconId = FALLBACK_ICON },
			{ name = "Poison SMG", weight = 500, displayName = "Poison SMG", rarityTag = "MUTANT", color = Color3.fromRGB(138, 43, 226), coinMult = 10000, expMult = 3000, iconId = FALLBACK_ICON },
		},
		AbyssalRift = {
			{ name = "Void Blaster", weight = 100000, displayName = "Void Blaster", rarityTag = "ABYSSAL", color = Color3.fromRGB(40, 0, 80), coinMult = 600000, expMult = 200000, iconId = FALLBACK_ICON },
			{ name = "Cosmic Sniper", weight = 25000, displayName = "Cosmic Sniper", rarityTag = "COSMIC", color = Color3.fromRGB(0, 50, 150), coinMult = 3500000, expMult = 1000000, iconId = FALLBACK_ICON },
			{ name = "Laser Railgun", weight = 0.2, displayName = "Laser Railgun", rarityTag = "SINGULARITY", color = Color3.fromRGB(100, 255, 200), coinMult = 18000000, expMult = 5000000, iconId = FALLBACK_ICON },
		},
		Paid = {
			{ name = "VIP Rifle", weight = 0, displayName = "VIP Rifle", rarityTag = "VIP", color = Color3.fromRGB(255, 215, 0), coinMult = 12000000, expMult = 3500000, trait = "VIPGlow", iconId = FALLBACK_ICON, paid = true }
		}
	},
	["RPG_Adventure"] = {
		Default = {
			{ name = "Wooden Club", weight = 10000000, displayName = "Wooden Club", rarityTag = "COMMON", color = Color3.fromRGB(180, 180, 180), coinMult = 1, expMult = 1, iconId = FALLBACK_ICON },
			{ name = "Stone Sword", weight = 2500000, displayName = "Stone Sword", rarityTag = "UNCOMMON", color = Color3.fromRGB(80, 255, 80), coinMult = 3, expMult = 2, iconId = FALLBACK_ICON },
			{ name = "Iron Dagger", weight = 500000, displayName = "Iron Dagger", rarityTag = "RARE", color = Color3.fromRGB(80, 150, 255), coinMult = 10, expMult = 5, iconId = FALLBACK_ICON },
			{ name = "Steel Greatsword", weight = 100000, displayName = "Steel Greatsword", rarityTag = "EPIC", color = Color3.fromRGB(150, 80, 255), coinMult = 35, expMult = 15, iconId = FALLBACK_ICON },
			{ name = "Champion Blade", weight = 20000, displayName = "Champion Blade", rarityTag = "LEGENDARY", color = Color3.fromRGB(255, 215, 0), coinMult = 150, expMult = 60, iconId = FALLBACK_ICON },
			{ name = "Relic Sword", weight = 4000, displayName = "Relic Sword", rarityTag = "MYTHIC", color = Color3.fromRGB(255, 50, 50), coinMult = 800, expMult = 300, iconId = FALLBACK_ICON },
		},
		Blossom = {
			{ name = "Elven Bow", weight = 2000000, displayName = "Elven Bow", rarityTag = "UNCOMMON", color = Color3.fromRGB(255, 183, 197), coinMult = 5, expMult = 3, iconId = FALLBACK_ICON },
			{ name = "Forest Staff", weight = 500000, displayName = "Forest Staff", rarityTag = "RARE", color = Color3.fromRGB(255, 105, 180), coinMult = 15, expMult = 8, iconId = FALLBACK_ICON },
			{ name = "Sun Blade", weight = 10000, displayName = "Sun Blade", rarityTag = "LEGENDARY", color = Color3.fromRGB(255, 69, 0), coinMult = 300, expMult = 100, iconId = FALLBACK_ICON },
			{ name = "Spirit Shield", weight = 500, displayName = "Spirit Shield", rarityTag = "MUTANT", color = Color3.fromRGB(138, 43, 226), coinMult = 10000, expMult = 3000, iconId = FALLBACK_ICON },
		},
		AbyssalRift = {
			{ name = "Void Greatsword", weight = 100000, displayName = "Void Greatsword", rarityTag = "ABYSSAL", color = Color3.fromRGB(40, 0, 80), coinMult = 600000, expMult = 200000, iconId = FALLBACK_ICON },
			{ name = "Cosmic Scepter", weight = 25000, displayName = "Cosmic Scepter", rarityTag = "COSMIC", color = Color3.fromRGB(0, 50, 150), coinMult = 3500000, expMult = 1000000, iconId = FALLBACK_ICON },
			{ name = "Infinity Saber", weight = 0.2, displayName = "Infinity Saber", rarityTag = "SINGULARITY", color = Color3.fromRGB(100, 255, 200), coinMult = 18000000, expMult = 5000000, iconId = FALLBACK_ICON },
		},
		Paid = {
			{ name = "VIP Sword", weight = 0, displayName = "VIP Sword", rarityTag = "VIP", color = Color3.fromRGB(255, 215, 0), coinMult = 12000000, expMult = 3500000, trait = "VIPGlow", iconId = FALLBACK_ICON, paid = true }
		}
	},
	["Pet_Simulator"] = {
		Default = {
			{ name = "Common Cat", weight = 10000000, displayName = "Common Cat", rarityTag = "COMMON", color = Color3.fromRGB(180, 180, 180), coinMult = 1, expMult = 1, iconId = FALLBACK_ICON },
			{ name = "Common Dog", weight = 2500000, displayName = "Common Dog", rarityTag = "UNCOMMON", color = Color3.fromRGB(80, 255, 80), coinMult = 3, expMult = 2, iconId = FALLBACK_ICON },
			{ name = "Spotted Bunny", weight = 500000, displayName = "Spotted Bunny", rarityTag = "RARE", color = Color3.fromRGB(80, 150, 255), coinMult = 10, expMult = 5, iconId = FALLBACK_ICON },
			{ name = "Red Fox", weight = 100000, displayName = "Red Fox", rarityTag = "EPIC", color = Color3.fromRGB(150, 80, 255), coinMult = 35, expMult = 15, iconId = FALLBACK_ICON },
			{ name = "Royal Pegasus", weight = 20000, displayName = "Royal Pegasus", rarityTag = "LEGENDARY", color = Color3.fromRGB(255, 215, 0), coinMult = 150, expMult = 60, iconId = FALLBACK_ICON },
			{ name = "Phoenix Pet", weight = 4000, displayName = "Phoenix Pet", rarityTag = "MYTHIC", color = Color3.fromRGB(255, 50, 50), coinMult = 800, expMult = 300, iconId = FALLBACK_ICON },
		},
		Blossom = {
			{ name = "Forest Pixie", weight = 2000000, displayName = "Forest Pixie", rarityTag = "UNCOMMON", color = Color3.fromRGB(255, 183, 197), coinMult = 5, expMult = 3, iconId = FALLBACK_ICON },
			{ name = "Sakura Deer", weight = 500000, displayName = "Sakura Deer", rarityTag = "RARE", color = Color3.fromRGB(255, 105, 180), coinMult = 15, expMult = 8, iconId = FALLBACK_ICON },
			{ name = "Moss Golem", weight = 10000, displayName = "Moss Golem", rarityTag = "LEGENDARY", color = Color3.fromRGB(255, 69, 0), coinMult = 300, expMult = 100, iconId = FALLBACK_ICON },
			{ name = "Leafy Wolf", weight = 500, displayName = "Leafy Wolf", rarityTag = "MUTANT", color = Color3.fromRGB(138, 43, 226), coinMult = 10000, expMult = 3000, iconId = FALLBACK_ICON },
		},
		AbyssalRift = {
			{ name = "Void Kitten", weight = 100000, displayName = "Void Kitten", rarityTag = "ABYSSAL", color = Color3.fromRGB(40, 0, 80), coinMult = 600000, expMult = 200000, iconId = FALLBACK_ICON },
			{ name = "Cosmic Dragon", weight = 25000, displayName = "Cosmic Dragon", rarityTag = "COSMIC", color = Color3.fromRGB(0, 50, 150), coinMult = 3500000, expMult = 1000000, iconId = FALLBACK_ICON },
			{ name = "Nebula Phoenix", weight = 0.2, displayName = "Nebula Phoenix", rarityTag = "SINGULARITY", color = Color3.fromRGB(100, 255, 200), coinMult = 18000000, expMult = 5000000, iconId = FALLBACK_ICON },
		},
		Paid = {
			{ name = "VIP Griffin", weight = 0, displayName = "VIP Griffin", rarityTag = "VIP", color = Color3.fromRGB(255, 215, 0), coinMult = 12000000, expMult = 3500000, trait = "VIPGlow", iconId = FALLBACK_ICON, paid = true }
		}
	}
}

-- Zone/Area Structure (renamed display names to be universal)
LootTable.Biomes = {
	["Default"] = {
		Id = "Default", DisplayName = "Zone 1", Cost = 250, LevelReq = 1,
		Items = {}, Auras = {}
	},
	["Blossom"] = {
		Id = "Blossom", Name = "Zone 2", DisplayName = "Zone 2", Cost = 150000, LevelReq = 1, UnlockCost = 150000, Currency = "Coins", Color = Color3.fromRGB(255, 183, 197),
		Items = {}, Auras = {}
	},
	["AbyssalRift"] = {
		Id = "AbyssalRift", Name = "Zone 3", DisplayName = "Zone 3", Cost = 25000000, LevelReq = 1, UnlockCost = 5000000, Currency = "Coins", Color = Color3.fromRGB(130, 40, 220),
		Items = {}, Auras = {}
	}
}

LootTable.PaidAuras = {}

-- Dynamic Composition based on resolved active categories
local function BuildRegistry()
	local activeCats = FeatureResolver.GetActiveCategories()

	-- Clear and assemble
	table.clear(LootTable.PaidAuras)
	for _, bDef in pairs(LootTable.Biomes) do
		table.clear(bDef.Items)
		table.clear(bDef.Auras)
	end

	for _, catName in ipairs(activeCats) do
		local catLib = ContentLibrary[catName]
		if not catLib then continue end

		-- Append items to zones
		for bKey, items in pairs(catLib) do
			if bKey == "Paid" then
				for _, item in ipairs(items) do
					table.insert(LootTable.PaidAuras, item)
				end
			else
				local targetBiome = LootTable.Biomes[bKey]
				if targetBiome then
					for _, item in ipairs(items) do
						table.insert(targetBiome.Items, item)
						table.insert(targetBiome.Auras, item) -- backwards compatibility mapping
					end
				end
			end
		end
	end
end

BuildRegistry()

local ItemDictionary: {[string]: LootEntry} = {}

local function RebuildDictionary()
	table.clear(ItemDictionary)
	-- Index rollable biome items
	for _, biome in pairs(LootTable.Biomes) do
		for _, entry in ipairs(biome.Items) do
			ItemDictionary[entry.name] = entry
			if entry.displayName and entry.displayName ~= entry.name then
				ItemDictionary[entry.displayName] = entry
			end
			local lowerName: string = string.lower(entry.name)
			if lowerName ~= entry.name then
				ItemDictionary[lowerName] = entry
			end
			if entry.displayName then
				local lowerDisplay: string = string.lower(entry.displayName)
				if lowerDisplay ~= entry.displayName and lowerDisplay ~= lowerName then
					ItemDictionary[lowerDisplay] = entry
				end
			end
		end
	end
	-- Index paid/exclusive items
	for _, entry in ipairs(LootTable.PaidAuras) do
		ItemDictionary[entry.name] = entry
		ItemDictionary[string.lower(entry.name)] = entry
		if entry.displayName and entry.displayName ~= entry.name then
			ItemDictionary[entry.displayName] = entry
			ItemDictionary[string.lower(entry.displayName)] = entry
		end
	end
	-- Fallback for missing elements
	ItemDictionary["None"] = { name = "None", weight = 99999999, displayName = "None", rarityTag = "NONE", color = Color3.fromRGB(255, 255, 255), coinMult = 1, expMult = 1, iconId = FALLBACK_ICON }
	ItemDictionary["none"] = ItemDictionary["None"]
end

RebuildDictionary()

function LootTable.LoadEvent(eventModule: any)
	if eventModule.Biomes then
		for bId, bDef in pairs(eventModule.Biomes) do
			LootTable.Biomes[bId] = bDef
		end
	end
	RebuildDictionary()
end

-- Universal helper name
function LootTable.GetItemData(itemName: string): LootEntry
	return ItemDictionary[itemName]
		or ItemDictionary[string.lower(itemName)]
		or ItemDictionary["None"]
end

-- Legacy wrapper alias for backward compatibility (Server services use this)
function LootTable.GetAuraData(auraName: string): LootEntry
	return LootTable.GetItemData(auraName)
end

function LootTable.new(entries: {[number]: LootEntry}): LootTableImpl
	local self = setmetatable({}, LootTable)
	local sortedEntries = table.clone(entries)
	-- Ascending order: rare items (lower weight) come first in the array
	table.sort(sortedEntries, function(a, b) return a.weight < b.weight end)
	
	local cumulativeWeights: {[number]: number} = {}
	local total: number = 0
	for i, entry in ipairs(sortedEntries) do 
		total += entry.weight 
		cumulativeWeights[i] = total
	end
	
	self.entries = sortedEntries
	self.cumulativeWeights = cumulativeWeights
	self.totalWeight = total
	return (self :: any) :: LootTableImpl
end

function LootTable:Roll(luckMultiplier: number?): LootEntry
	local luck: number = math.max(1, luckMultiplier or 1)
	
	-- 'luck' artificially reduces totalWeight in the equation, pushing the roll
	-- toward the beginning of the array (where the lowest weight/rarest items are)
	local target: number = math.random() * (self.totalWeight / luck)

	-- [O(log N)] Binary search for server optimization
	local low: number, high: number = 1, #self.cumulativeWeights
	local bestIdx: number = #self.entries

	while low <= high do
		local mid: number = math.floor((low + high) / 2)
		if target <= self.cumulativeWeights[mid] then
			bestIdx = mid
			high = mid - 1 -- Try to find a tighter match to the left
		else
			low = mid + 1
		end
	end

	return self.entries[bestIdx]
end

function LootTable:GetProbabilities(): {[string]: number}
	local probabilities: {[string]: number} = {}
	local total: number = self.totalWeight
	
	if total <= 0 then
		return probabilities
	end
	
	for _, entry: LootEntry in ipairs(self.entries) do
		probabilities[entry.name] = entry.weight / total
	end
	
	return probabilities
end

return LootTable
