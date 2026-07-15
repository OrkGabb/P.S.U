--!strict
--@author OrkGabb
-- src/Shared/Modules/PetRegistry.luau
-- Pet_Simulator single source of truth: every egg, pet definition, hatch
-- weight, rarity tier and hatch cost lives here. Pets are cosmetic
-- companions only — no stat multipliers (that pattern is demonstrated by
-- Aura_Collector; the two systems are deliberately independent).
--
-- Hatch odds: entry probability = Weight / Σ Weights of its egg pool.
-- GetProbabilities feeds the egg-shop UI so displayed odds and server
-- hatches can never disagree — both resolve through the same shared
-- RollEngine core.
--
-- Visuals: `Build` describes an original, procedurally-built part model
-- (PetController constructs it at runtime — no third-party assets shipped).
-- To use hand-made rigs instead, drop a Model named after the pet Id under
-- ReplicatedStorage.Shared.GlobalAssets.PetModels — PetController prefers it
-- over the procedural build automatically.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RollEngineModule = require(ReplicatedStorage.Shared.Modules.RollEngine)

-- Procedural model recipe. Kept deliberately small: a body shape, a head,
-- ears and a tail, all tinted from two colors. Enough to make each pet
-- readable and distinct without shipping binary assets.
export type PetBuild = {
	BodyShape: "Ball" | "Block",     -- body/head primitive
	BodyColor: Color3,
	AccentColor: Color3,             -- ears, tail
	EyeColor: Color3?,               -- default near-black
	Scale: number,                   -- 1 = house-cat sized
	Glow: boolean?,                  -- neon body material + point light
}

export type PetDef = {
	Id: string,
	DisplayName: string,
	Weight: number,
	RarityTag: string,
	Build: PetBuild,
}

export type EggDef = {
	Id: string,
	DisplayName: string,
	HatchCost: number,  -- Currencies.Primary charged per hatch
	LevelReq: number,
	Color: Color3,
	Pets: {PetDef},
}

export type RarityDef = {
	Order: number,
	Color: Color3,
}

export type HatchEngine = {
	Roll: (self: HatchEngine, luckMultiplier: number?) -> PetDef,
	GetProbabilities: (self: HatchEngine) -> {{Def: PetDef, Chance: number}},
}

local PetRegistry = {}

-- ── Rarity tiers (SSoT for ordering + presentation colors) ───────────────────

PetRegistry.Rarities = {
	["COMMON"]    = { Order = 1, Color = Color3.fromRGB(180, 180, 180) },
	["UNCOMMON"]  = { Order = 2, Color = Color3.fromRGB(80, 200, 120) },
	["RARE"]      = { Order = 3, Color = Color3.fromRGB(45, 107, 228) },
	["EPIC"]      = { Order = 4, Color = Color3.fromRGB(180, 50, 255) },
	["LEGENDARY"] = { Order = 5, Color = Color3.fromRGB(228, 167, 45) },
	["MYTHIC"]    = { Order = 6, Color = Color3.fromRGB(228, 45, 45) },
} :: {[string]: RarityDef}

local FALLBACK_RARITY: RarityDef = { Order = 0, Color = Color3.fromRGB(200, 200, 200) }

function PetRegistry.GetRarity(rarityTag: string): RarityDef
	return PetRegistry.Rarities[rarityTag] or FALLBACK_RARITY
end

-- ── Egg + pet content ─────────────────────────────────────────────────────────

PetRegistry.Eggs = {
	["BasicEgg"] = {
		Id = "BasicEgg",
		DisplayName = "Basic Egg",
		HatchCost = 250,
		LevelReq = 1,
		Color = Color3.fromRGB(235, 220, 180),
		Pets = {
			{ Id = "Doggo",       DisplayName = "Doggo",        Weight = 450, RarityTag = "COMMON",    Build = { BodyShape = "Ball",  BodyColor = Color3.fromRGB(196, 152, 102), AccentColor = Color3.fromRGB(150, 110, 70),  Scale = 1 } },
			{ Id = "Kitty",       DisplayName = "Kitty",        Weight = 300, RarityTag = "COMMON",    Build = { BodyShape = "Ball",  BodyColor = Color3.fromRGB(120, 120, 130), AccentColor = Color3.fromRGB(90, 90, 100),   Scale = 0.9 } },
			{ Id = "Bunny",       DisplayName = "Bunny",        Weight = 150, RarityTag = "UNCOMMON",  Build = { BodyShape = "Ball",  BodyColor = Color3.fromRGB(240, 240, 240), AccentColor = Color3.fromRGB(255, 190, 200), Scale = 0.85 } },
			{ Id = "Foxy",        DisplayName = "Foxy",         Weight = 70,  RarityTag = "RARE",      Build = { BodyShape = "Ball",  BodyColor = Color3.fromRGB(226, 110, 40),  AccentColor = Color3.fromRGB(250, 245, 235), Scale = 0.95 } },
			{ Id = "Dragonling",  DisplayName = "Dragonling",   Weight = 25,  RarityTag = "EPIC",      Build = { BodyShape = "Block", BodyColor = Color3.fromRGB(70, 180, 120),  AccentColor = Color3.fromRGB(40, 120, 80),   Scale = 1.05 } },
			{ Id = "GoldenDoggo", DisplayName = "Golden Doggo", Weight = 5,   RarityTag = "LEGENDARY", Build = { BodyShape = "Ball",  BodyColor = Color3.fromRGB(255, 215, 0),   AccentColor = Color3.fromRGB(230, 180, 30),  Scale = 1, Glow = true } },
		},
	},

	["RoyalEgg"] = {
		Id = "RoyalEgg",
		DisplayName = "Royal Egg",
		HatchCost = 5000,
		LevelReq = 10,
		Color = Color3.fromRGB(170, 120, 255),
		Pets = {
			{ Id = "RoyalCorgi",      DisplayName = "Royal Corgi",      Weight = 400, RarityTag = "UNCOMMON",  Build = { BodyShape = "Ball",  BodyColor = Color3.fromRGB(230, 170, 90),  AccentColor = Color3.fromRGB(250, 245, 235), Scale = 0.95 } },
			{ Id = "CrystalCat",      DisplayName = "Crystal Cat",      Weight = 350, RarityTag = "RARE",      Build = { BodyShape = "Block", BodyColor = Color3.fromRGB(130, 220, 255), AccentColor = Color3.fromRGB(80, 160, 220),  Scale = 0.9, Glow = true } },
			{ Id = "PhoenixChick",    DisplayName = "Phoenix Chick",    Weight = 200, RarityTag = "EPIC",      Build = { BodyShape = "Ball",  BodyColor = Color3.fromRGB(255, 120, 40),  AccentColor = Color3.fromRGB(255, 200, 60),  Scale = 0.8, Glow = true } },
			{ Id = "VoidPup",         DisplayName = "Void Pup",         Weight = 45,  RarityTag = "LEGENDARY", Build = { BodyShape = "Ball",  BodyColor = Color3.fromRGB(40, 20, 70),    AccentColor = Color3.fromRGB(120, 60, 200),  Scale = 1, Glow = true } },
			{ Id = "CelestialDragon", DisplayName = "Celestial Dragon", Weight = 5,   RarityTag = "MYTHIC",    Build = { BodyShape = "Block", BodyColor = Color3.fromRGB(90, 240, 255),  AccentColor = Color3.fromRGB(255, 255, 255), Scale = 1.2, Glow = true } },
		},
	},
} :: {[string]: EggDef}

-- ── Lookup dictionary ─────────────────────────────────────────────────────────

local NONE_DEF: PetDef = {
	Id = "None", DisplayName = "None", Weight = math.huge, RarityTag = "NONE",
	Build = {
		BodyShape = "Ball" :: "Ball", BodyColor = Color3.fromRGB(255, 255, 255),
		AccentColor = Color3.fromRGB(255, 255, 255), Scale = 1,
	},
}

local petById: {[string]: PetDef} = {}
local eggOfPet: {[string]: string} = {}

for eggId, egg in pairs(PetRegistry.Eggs) do
	for _, def in ipairs(egg.Pets) do
		petById[def.Id] = def
		eggOfPet[def.Id] = eggId
	end
end

-- Unknown ids resolve to an inert "None" definition so callers never nil-check.
function PetRegistry.GetPetData(petId: string): PetDef
	return petById[petId] or NONE_DEF
end

function PetRegistry.GetEgg(eggId: string): EggDef?
	return PetRegistry.Eggs[eggId]
end

-- Home egg of a pet (for UI grouping); nil for unknown pets.
function PetRegistry.GetEggOfPet(petId: string): string?
	return eggOfPet[petId]
end

-- ── Hatch engine (shared RollEngine core, same as Aura rolls) ─────────────────

local Engine = {}
Engine.__index = Engine

function Engine.Roll(self: any, luckMultiplier: number?): PetDef
	return self.entries[self.core:Roll(luckMultiplier)]
end

-- Ordered (rarest-first) list of {Def, Chance} for the egg-shop odds display.
function Engine.GetProbabilities(self: any): {{Def: PetDef, Chance: number}}
	local out: {{Def: PetDef, Chance: number}} = {}
	for i, chance in ipairs(self.core:GetChances()) do
		table.insert(out, { Def = self.entries[i], Chance = chance })
	end
	return out
end

local engineCache: {[string]: HatchEngine} = {}

function PetRegistry.GetEngine(eggId: string): HatchEngine?
	local cached = engineCache[eggId]
	if cached then
		return cached
	end
	local egg = PetRegistry.Eggs[eggId]
	if not egg then
		return nil
	end

	local sorted = table.clone(egg.Pets)
	table.sort(sorted, function(a, b)
		return a.Weight < b.Weight
	end)
	local weights: {number} = table.create(#sorted)
	for i, def in ipairs(sorted) do
		weights[i] = def.Weight
	end

	local engine = (setmetatable({
		entries = sorted,
		core = RollEngineModule.New(weights),
	}, Engine) :: any) :: HatchEngine
	engineCache[eggId] = engine
	return engine
end

return PetRegistry
