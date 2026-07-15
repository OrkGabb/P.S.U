--!strict
-- @Author @OrkGabb
-- Shared strict-type contracts for the P.S.U framework domain layer.
-- Consumed by ConfigAudit, BootTelemetry, and future Shared modules that
-- need typed access to FeatureToggles-shaped data and the abstract profile
-- schema WITHOUT introducing a runtime dependency on FeatureResolver. Pure
-- type definitions — zero executable logic, zero side effects, safe to
-- require from anywhere.

export type CurrencyNames = {
	Primary: string,
	Secondary: string,
}

export type GenreCurrencyConfig = {
	PrimaryName: string?,
	SecondaryName: string?,
}

-- Shape of a single entry under FeatureToggles.Genres.
-- `Enabled` is the only field FeatureResolver strictly requires; everything
-- else is genre-specific config data, hence the open `[string]: any` tail —
-- this keeps the type honest about what's actually enforced vs. convention.
export type GenreConfig = {
	Enabled: boolean,
	Currencies: GenreCurrencyConfig?,
	[string]: any,
}

export type GenreTable = {
	[string]: GenreConfig,
}

-- Shape of a single entry under FeatureToggles.GlobalFlags. Accepts either
-- shape FeatureResolver already reads: a bare boolean, or a table carrying
-- an Enabled field alongside arbitrary config.
export type GlobalFlagConfig = boolean | {
	Enabled: boolean,
	[string]: any,
}

export type GlobalFlagsTable = {
	[string]: GlobalFlagConfig,
}

-- Root shape of the FeatureToggles config module. Intentionally permissive
-- on unknown top-level keys ([string]: any) since FeatureResolver supports
-- ad-hoc top-level category tables beyond Genres/GlobalFlags (OCP: new
-- categories don't require touching this type).
export type FeatureTogglesShape = {
	Genres: GenreTable?,
	GlobalFlags: GlobalFlagsTable?,
	[string]: any,
}

-- Generic service/controller lifecycle contract shared by ServerMain,
-- FrameworkServer, and FrameworkClient. Centralizing this avoids each
-- bootstrap file re-declaring an identical local type (DRY).
export type LifecycleModule = {
	Init: (() -> ())?,
	Start: (() -> ())?,
}

-- Player-profile schema: shapes of profile.Data sub-tables as declared by DataService.ProfileTemplate
-- and broadcast to clients via the UpdateProfileData remote. Fields the
-- template guarantees (ProfileService:Reconcile backfills them on every load)
-- are non-optional; genre payload fields are optional because each genre
-- service initializes its own sub-table lazily. Keep in sync with
-- DataService.ProfileTemplate.

-- Quest persistence (QuestService). Lives at Progression.Quests; the service
-- lazily creates and backfills it (ValidateQuestData), so the sub-table is
-- optional on ProgressionData while its own fields are guaranteed.
export type QuestSaveData = {
	Progress: { [string]: number },
	Claimed: { [string]: boolean },
	LastReset: number,
	LastWeeklyReset: number,
}

-- Client-side view of the UpdateQuests payload (QuestService always fires the
-- validated Progression.Quests table, so Progress/Claimed are guaranteed —
-- unlike the lazily-built genre payloads above, no optionality needed). The
-- reset timestamps are server-side bookkeeping and deliberately omitted.
export type QuestClientData = {
	Progress: { [string]: number },
	Claimed: { [string]: boolean },
}

export type ProgressionData = {
	Level: number,
	Experience: number,
	Milestones: { [string]: any },
	UnlockedZones: { [string]: boolean },
	-- Not in ProfileTemplate: created on first quest write, absent until then.
	Quests: QuestSaveData?,
}

export type InventoryData = {
	Equipment: { [string]: any },
	Cosmetics: { [string]: any },
	Consumables: { [string]: number },
}

-- GenreData is a map of genre key → genre-owned sub-table. The map shape is
-- universal; entry shapes belong to each genre (client payload views below).
export type GenreDataMap = { [string]: { [string]: any } }

-- Client-side view of GenreData.Aura_Collector as received over the wire
-- (AuraService owns the authoritative server-side type).
export type AuraCollectorData = {
	Collection: { [string]: number }?,
	Equipped: string?,
	ManualEquip: boolean?,
	PityCounter: number?,
	CurrentBiome: string?,
	UnlockedBiomes: { [string]: boolean }?,
}

-- Client-side view of GenreData.Pet_Simulator as received over the wire
-- (PetService owns the authoritative server-side type).
export type PetSimulatorData = {
	Inventory: { [string]: number }?,
	Equipped: string?,
}

return {}
