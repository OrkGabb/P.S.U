--!strict
-- @Author @OrkGabb
-- src/Shared/Modules/AuraRegistry.luau
-- Aura_Collector single source of truth: every aura definition, drop weight,
-- rarity tier, income multiplier, roll cost and VFX template binding lives
-- here. Rebuilt (typed, strict) from the legacy plain-Lua LootTable of the
-- pre-simplification Aura game; logic salvaged, architecture modernized.
--
-- Drop odds: entry probability = Weight / Σ Weights of its biome pool.
-- GetProbabilities feeds the roll UI so displayed odds and server rolls can
-- never disagree — both read the same engine.

export type AuraDef = {
	Id: string,
	DisplayName: string,
	Weight: number,
	RarityTag: string,
	Color: Color3,
	CoinMult: number,
	ExpMult: number,
	IconId: string?,
	-- VFX template name: resolved first against a Studio-authored rig under
	-- ReplicatedStorage.Shared.GlobalAssets.VFXAssets.AuraTemplates, then
	-- against the procedural specs in Shared/Config/AuraVFXTemplates.luau
	VFXTemplate: string?,
	Paid: boolean?, -- never rolled; granted by purchases/events
}

export type BiomeDef = {
	Id: string,
	DisplayName: string,
	RollCost: number,     -- Currencies.Primary charged per roll
	LevelReq: number,
	UnlockCost: number?,  -- Currencies.Primary to unlock the biome (nil = free)
	Color: Color3?,
	Auras: {AuraDef},
}

export type RollEngine = {
	Roll: (self: RollEngine, luckMultiplier: number?) -> AuraDef,
	GetProbabilities: (self: RollEngine) -> {{Def: AuraDef, Chance: number}},
}

-- Presentation + reward metadata per rarity tag. Order ranks tiers for
-- sorting; FeedbackTier drives the roll UI's escalating juice
-- (none → subtle → medium → impactful → dramatic → cinematic);
-- AnticipationSecs delays the reveal for drama; EssenceOnDupe is the
-- Currencies.Secondary payout when a duplicate of this rarity is rolled.
export type RarityDef = {
	Order: number,
	Color: Color3,
	FeedbackTier: string,
	AnticipationSecs: number,
	EssenceOnDupe: number,
}

local FALLBACK_ICON = "rbxassetid://15059633013"

-- ── Aura content (salvaged progression curve from the original Aura game) ────

local AuraRegistry = {}

AuraRegistry.Biomes = {
	["Default"] = {
		Id = "Default",
		DisplayName = "Origin Realm",
		RollCost = 50,
		LevelReq = 1,
		UnlockCost = nil,
		Color = Color3.fromRGB(120, 170, 255),
		Auras = {
			-- Base tiers
			{ Id = "Breeze",    DisplayName = "Breeze",    Weight = 10000000, RarityTag = "COMMON",      Color = Color3.fromRGB(180, 180, 180), CoinMult = 1,           ExpMult = 1,          IconId = FALLBACK_ICON, VFXTemplate = "SparkleWisp" },
			{ Id = "Aqua",      DisplayName = "Aqua",      Weight = 2500000,  RarityTag = "UNCOMMON",    Color = Color3.fromRGB(80, 200, 255),  CoinMult = 3,           ExpMult = 2,          IconId = FALLBACK_ICON, VFXTemplate = "SparkleWisp" },
			{ Id = "Ember",     DisplayName = "Ember",     Weight = 500000,   RarityTag = "RARE",        Color = Color3.fromRGB(255, 120, 40),  CoinMult = 10,          ExpMult = 5,          IconId = FALLBACK_ICON, VFXTemplate = "EmberTrail" },
			{ Id = "Blood",     DisplayName = "Blood",     Weight = 100000,   RarityTag = "EPIC",        Color = Color3.fromRGB(200, 20, 40),   CoinMult = 35,          ExpMult = 15,         IconId = FALLBACK_ICON, VFXTemplate = "EmberTrail" },
			{ Id = "Solar",     DisplayName = "Solar",     Weight = 20000,    RarityTag = "LEGENDARY",   Color = Color3.fromRGB(255, 215, 0),   CoinMult = 150,         ExpMult = 60,         IconId = FALLBACK_ICON, VFXTemplate = "RadiantCrown" },
			{ Id = "Doom",      DisplayName = "Doom",      Weight = 4000,     RarityTag = "MYTHIC",      Color = Color3.fromRGB(255, 50, 50),   CoinMult = 800,         ExpMult = 300,        IconId = FALLBACK_ICON, VFXTemplate = "VoidShroud" },
			-- Mutant tiers (mid-game spike)
			{ Id = "Starlight", DisplayName = "Starlight", Weight = 800,      RarityTag = "MUTANT",      Color = Color3.fromRGB(200, 200, 255), CoinMult = 4500,        ExpMult = 1500,       IconId = FALLBACK_ICON, VFXTemplate = "RadiantCrown" },
			{ Id = "Nebula",    DisplayName = "Nebula",    Weight = 150,      RarityTag = "MUTANT",      Color = Color3.fromRGB(255, 100, 200), CoinMult = 25000,       ExpMult = 8000,       IconId = FALLBACK_ICON, VFXTemplate = "CelestialOrbit" },
			{ Id = "Supernova", DisplayName = "Supernova", Weight = 30,       RarityTag = "MUTANT",      Color = Color3.fromRGB(255, 150, 50),  CoinMult = 120000,      ExpMult = 40000,      IconId = FALLBACK_ICON, VFXTemplate = "CelestialOrbit" },
			{ Id = "Abyssal",   DisplayName = "Abyssal",   Weight = 5,        RarityTag = "ABYSSAL",     Color = Color3.fromRGB(50, 0, 100),    CoinMult = 600000,      ExpMult = 200000,     IconId = FALLBACK_ICON, VFXTemplate = "VoidShroud" },
			{ Id = "Cosmic",    DisplayName = "Cosmic",    Weight = 1,        RarityTag = "COSMIC",      Color = Color3.fromRGB(0, 255, 255),   CoinMult = 3500000,     ExpMult = 1000000,    IconId = FALLBACK_ICON, VFXTemplate = "CelestialOrbit" },
			-- Singularity tiers (end-game dream)
			{ Id = "Astral",    DisplayName = "Astral",    Weight = 0.2,      RarityTag = "SINGULARITY", Color = Color3.fromRGB(100, 255, 200), CoinMult = 18000000,    ExpMult = 5000000,    IconId = FALLBACK_ICON, VFXTemplate = "CelestialOrbit" },
			{ Id = "Ethereal",  DisplayName = "Ethereal",  Weight = 0.05,     RarityTag = "SINGULARITY", Color = Color3.fromRGB(200, 255, 255), CoinMult = 90000000,    ExpMult = 25000000,   IconId = FALLBACK_ICON, VFXTemplate = "CelestialOrbit" },
			{ Id = "Quantum",   DisplayName = "Quantum",   Weight = 0.01,     RarityTag = "EXOTIC",      Color = Color3.fromRGB(0, 255, 100),   CoinMult = 500000000,   ExpMult = 120000000,  IconId = FALLBACK_ICON, VFXTemplate = "CelestialOrbit" },
			{ Id = "Oblivion",  DisplayName = "Oblivion",  Weight = 0.002,    RarityTag = "EXOTIC",      Color = Color3.fromRGB(20, 20, 20),    CoinMult = 2500000000,  ExpMult = 600000000,  IconId = FALLBACK_ICON, VFXTemplate = "VoidShroud" },
			{ Id = "Eternal",   DisplayName = "Eternal",   Weight = 0.0005,   RarityTag = "OMNI",        Color = Color3.fromRGB(255, 255, 255), CoinMult = 15000000000, ExpMult = 3000000000, IconId = FALLBACK_ICON, VFXTemplate = "RadiantCrown" },
		},
	},

	["AbyssalRift"] = {
		Id = "AbyssalRift",
		DisplayName = "Abyssal Rift",
		RollCost = 5000000,
		LevelReq = 25,
		UnlockCost = 25000000,
		Color = Color3.fromRGB(130, 40, 220),
		Auras = {
			{ Id = "Void",    DisplayName = "Void",    Weight = 100000, RarityTag = "ABYSSAL", Color = Color3.fromRGB(40, 0, 80),   CoinMult = 1200000, ExpMult = 400000,  IconId = FALLBACK_ICON, VFXTemplate = "VoidShroud" },
			{ Id = "Eclipse", DisplayName = "Eclipse", Weight = 25000,  RarityTag = "COSMIC",  Color = Color3.fromRGB(0, 50, 150),  CoinMult = 7500000, ExpMult = 2500000, IconId = FALLBACK_ICON, VFXTemplate = "CelestialOrbit" },
		},
	},
} :: {[string]: BiomeDef}

-- Never rolled — granted through purchases or events. Paid=true survives any
-- future collection wipe mechanics.
AuraRegistry.PaidAuras = {
	{ Id = "VIP", DisplayName = "VIP Aura", Weight = 0, RarityTag = "VIP", Color = Color3.fromRGB(255, 215, 0), CoinMult = 12000000, ExpMult = 3500000, IconId = FALLBACK_ICON, VFXTemplate = "RadiantCrown", Paid = true },
} :: {AuraDef}

-- ── Rarity tiers (SSoT for colors, roll feedback and duplicate payouts) ──────

AuraRegistry.Rarities = {
	["COMMON"]      = { Order = 1,  Color = Color3.fromRGB(180, 180, 180), FeedbackTier = "none",      AnticipationSecs = 0,   EssenceOnDupe = 1 },
	["UNCOMMON"]    = { Order = 2,  Color = Color3.fromRGB(80, 200, 120),  FeedbackTier = "none",      AnticipationSecs = 0,   EssenceOnDupe = 2 },
	["RARE"]        = { Order = 3,  Color = Color3.fromRGB(45, 107, 228),  FeedbackTier = "subtle",    AnticipationSecs = 0,   EssenceOnDupe = 5 },
	["EPIC"]        = { Order = 4,  Color = Color3.fromRGB(180, 50, 255),  FeedbackTier = "medium",    AnticipationSecs = 0.1, EssenceOnDupe = 12 },
	["LEGENDARY"]   = { Order = 5,  Color = Color3.fromRGB(228, 167, 45),  FeedbackTier = "impactful", AnticipationSecs = 0.2, EssenceOnDupe = 30 },
	["MYTHIC"]      = { Order = 6,  Color = Color3.fromRGB(228, 45, 45),   FeedbackTier = "dramatic",  AnticipationSecs = 0.4, EssenceOnDupe = 75 },
	["MUTANT"]      = { Order = 7,  Color = Color3.fromRGB(255, 100, 220), FeedbackTier = "dramatic",  AnticipationSecs = 0.4, EssenceOnDupe = 200 },
	["ABYSSAL"]     = { Order = 8,  Color = Color3.fromRGB(120, 0, 180),   FeedbackTier = "dramatic",  AnticipationSecs = 0.5, EssenceOnDupe = 500 },
	["COSMIC"]      = { Order = 9,  Color = Color3.fromRGB(0, 200, 255),   FeedbackTier = "dramatic",  AnticipationSecs = 0.5, EssenceOnDupe = 1200 },
	["SINGULARITY"] = { Order = 10, Color = Color3.fromRGB(255, 255, 255), FeedbackTier = "cinematic", AnticipationSecs = 0.8, EssenceOnDupe = 3000 },
	["EXOTIC"]      = { Order = 11, Color = Color3.fromRGB(0, 255, 120),   FeedbackTier = "cinematic", AnticipationSecs = 0.8, EssenceOnDupe = 8000 },
	["OMNI"]        = { Order = 12, Color = Color3.fromRGB(255, 255, 255), FeedbackTier = "cinematic", AnticipationSecs = 1.2, EssenceOnDupe = 20000 },
	["VIP"]         = { Order = 9,  Color = Color3.fromRGB(255, 215, 0),   FeedbackTier = "dramatic",  AnticipationSecs = 0,   EssenceOnDupe = 0 },
} :: {[string]: RarityDef}

local FALLBACK_RARITY: RarityDef = {
	Order = 0, Color = Color3.fromRGB(200, 200, 200),
	FeedbackTier = "none", AnticipationSecs = 0, EssenceOnDupe = 0,
}

-- Resolves a rarity tag to its presentation/reward def (inert fallback for
-- unknown tags — callers never nil-check).
function AuraRegistry.GetRarity(rarityTag: string): RarityDef
	return AuraRegistry.Rarities[rarityTag] or FALLBACK_RARITY
end

-- ── Lookup dictionary ─────────────────────────────────────────────────────────

local NONE_DEF: AuraDef = {
	Id = "None", DisplayName = "None", Weight = math.huge, RarityTag = "NONE",
	Color = Color3.fromRGB(255, 255, 255), CoinMult = 1, ExpMult = 1,
	IconId = FALLBACK_ICON, VFXTemplate = nil, Paid = nil,
}

local auraById: {[string]: AuraDef} = {}

local function RebuildDictionary(): ()
	table.clear(auraById)
	for _, biome in pairs(AuraRegistry.Biomes) do
		for _, def in ipairs(biome.Auras) do
			auraById[def.Id] = def
			auraById[string.lower(def.Id)] = def
		end
	end
	for _, def in ipairs(AuraRegistry.PaidAuras) do
		auraById[def.Id] = def
		auraById[string.lower(def.Id)] = def
	end
end

RebuildDictionary()

-- Resolves an aura by id (case-insensitive). Unknown ids resolve to the inert
-- "None" definition so callers never nil-check multipliers.
function AuraRegistry.GetAuraData(auraId: string): AuraDef
	return auraById[auraId] or auraById[string.lower(auraId)] or NONE_DEF
end

function AuraRegistry.GetBiome(biomeId: string): BiomeDef?
	return AuraRegistry.Biomes[biomeId]
end

-- ── Roll engine ───────────────────────────────────────────────────────────────

local Engine = {}
Engine.__index = Engine

-- Builds a weighted roll engine over a biome's aura pool.
-- Entries are sorted rarest-first; a cumulative-weight binary search keeps
-- rolls O(log N) (vital for auto-rollers).
function AuraRegistry.NewEngine(auras: {AuraDef}): RollEngine
	local sorted = table.clone(auras)
	table.sort(sorted, function(a, b)
		return a.Weight < b.Weight
	end)

	local cumulative: {number} = table.create(#sorted)
	local total = 0
	for i, def in ipairs(sorted) do
		total += def.Weight
		cumulative[i] = total
	end

	local self = setmetatable({
		entries = sorted,
		cumulativeWeights = cumulative,
		totalWeight = total,
	}, Engine)

	return (self :: any) :: RollEngine
end

-- Cached per-biome engines. Server rolls and client odds displays resolve
-- through here, so both sides always read the same weights.
local engineCache: {[string]: RollEngine} = {}

function AuraRegistry.GetEngine(biomeId: string): RollEngine?
	local cached = engineCache[biomeId]
	if cached then
		return cached
	end
	local biome = AuraRegistry.Biomes[biomeId]
	if not biome then
		return nil
	end
	local engine = AuraRegistry.NewEngine(biome.Auras)
	engineCache[biomeId] = engine
	return engine
end

-- Luck shrinks the effective total weight, pushing the roll toward the start
-- of the array where the rarest (lowest-weight) entries live.
function Engine.Roll(self: any, luckMultiplier: number?): AuraDef
	local luck: number = math.max(1, luckMultiplier or 1)
	local target: number = math.random() * (self.totalWeight / luck)

	local low: number, high: number = 1, #self.cumulativeWeights
	local bestIdx: number = #self.entries

	while low <= high do
		local mid = (low + high) // 2
		if target <= self.cumulativeWeights[mid] then
			bestIdx = mid
			high = mid - 1
		else
			low = mid + 1
		end
	end

	return self.entries[bestIdx]
end

-- Ordered (rarest-first) list of {Def, Chance} for odds display.
function Engine.GetProbabilities(self: any): {{Def: AuraDef, Chance: number}}
	local out: {{Def: AuraDef, Chance: number}} = {}
	if self.totalWeight <= 0 then
		return out
	end
	for _, def in ipairs(self.entries) do
		table.insert(out, { Def = def, Chance = def.Weight / self.totalWeight })
	end
	return out
end

return AuraRegistry
