--!strict
-- @Author @OrkGabb
-- src/Shared/Modules/FeatureResolver.luau
-- Centralized single source of truth for dynamic category/feature discovery and resolution.
-- Genre flags are mutually exclusive: exactly ---ONE--- genre is resolved per session.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FeatureToggles = require(ReplicatedStorage.Shared.Config.FeatureToggles)

local FeatureResolver = {}

-- No fallback genre: with nothing enabled in FeatureToggles.Genres, PSU boots
-- core-only (GetActiveCategories reports just "Global") and the consuming
-- project opts into exactly one genre. Set this to a genre key to restore a
-- default.
local DEFAULT_GENRE: string? = nil

-- Genre keys are derived from FeatureToggles.Genres (SSoT) — adding a new genre
-- to that table automatically registers it here, no core edits required.
-- Sorted for deterministic iteration order.
local function getGenreKeys(): {string}
	local keys: {string} = {}
	local genres: any = (FeatureToggles :: any).Genres
	if type(genres) == "table" then
		for key in pairs(genres) do
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys
end

local function isGenreKey(name: string): boolean
	local genres: any = (FeatureToggles :: any).Genres
	return type(genres) == "table" and type(genres[name]) == "table"
end

--------------------------------------------------------------------------------
-- Genre resolution (computed once per VM, then cached)
--------------------------------------------------------------------------------

local resolvedGenre: string? = nil
local conflictingGenres: {string} = {}
-- Full set of enabled genres when FeatureToggles.AllowMultipleGenres opted out of
-- exclusivity. Empty in the default (single-genre) path — IsCategoryActive/
-- GetActiveCategories fall back to resolvedGenre in that case.
local multiGenreSet: {string} = {}
-- Resolved once per VM lifetime and cached — this module does NOT re-evaluate if
-- FeatureToggles.Genres or AllowMultipleGenres change after first resolution (e.g.
-- hot-reloading config in Studio Play Solo, or a runtime admin panel toggling flags).
-- A changed flag only takes effect after a full server/client restart. If a future
-- use case needs live flag changes, this caching strategy must be revisited.
local resolutionDone = false

-- Exactly one enabled genre → that genre. None → DEFAULT_GENRE. Multiple →
-- conflict recorded for AssertGenreExclusivity, UNLESS FeatureToggles.AllowMultipleGenres
-- is true, in which case FeatureResolver does not arbitrate: every enabled genre is
-- recorded in multiGenreSet and IsCategoryActive/GetActiveCategories report the full
-- set. resolvedGenre still gets a "first enabled" representative value purely for
-- the handful of call sites that need a single genre string (currency naming, audio/
-- commerce config lookup, boot-log prints) — it is NOT authoritative for gating.
local function resolveGenre(): string?
	if resolutionDone then
		return resolvedGenre
	end
	resolutionDone = true

	local enabled: {string} = {}
	for _, key: string in ipairs(getGenreKeys()) do
		local cfg: any = (FeatureToggles :: any).Genres[key]
		if type(cfg) == "table" and cfg.Enabled == true then
			table.insert(enabled, key)
		end
	end

	if #enabled > 1 and (FeatureToggles :: any).AllowMultipleGenres == true then
		multiGenreSet = enabled
		resolvedGenre = enabled[1]
		warn(("[FeatureResolver] Multiple genre flags enabled: %s. FeatureToggles.AllowMultipleGenres is true — skipping exclusivity enforcement; all listed genres are active."):format(
			table.concat(enabled, ", ")))
	elseif #enabled > 1 then
		conflictingGenres = enabled
		resolvedGenre = enabled[1]
		warn(("[FeatureResolver] Conflicting genre flags enabled: %s. Genres are mutually exclusive — resolving to %q until FeatureToggles.Genres is fixed."):format(
			table.concat(enabled, ", "), enabled[1]))
	elseif #enabled == 1 then
		resolvedGenre = enabled[1]
	elseif DEFAULT_GENRE ~= nil and isGenreKey(DEFAULT_GENRE) then
		resolvedGenre = DEFAULT_GENRE
		warn(("[FeatureResolver] No genre enabled in FeatureToggles.Genres — defaulting to %q."):format(DEFAULT_GENRE))
	else
		resolvedGenre = nil
		print("[INFO] [FeatureResolver] No genre enabled in FeatureToggles.Genres — booting core-only.")
	end

	return resolvedGenre
end

-- Boot gate: raises when multiple genre flags are enabled, naming each one.
-- Called by ServerMain/ClientMain before any genre-gated module loads.
function FeatureResolver.AssertGenreExclusivity(context: string?): ()
	resolveGenre()
	if #conflictingGenres > 1 then
		error(("[%s] Conflicting genre flags enabled: %s. Genres are mutually exclusive — enable exactly one in FeatureToggles.Genres."):format(
			context or "FeatureResolver", table.concat(conflictingGenres, ", ")))
	end
end

-- Returns whether a category or feature flag is active in FeatureToggles.
-- Genre keys answer against the resolved genre set — never the raw flag.
-- Default: exactly one genre reads as active framework-wide. When
-- FeatureToggles.AllowMultipleGenres is true and multiple flags are enabled,
-- every enabled genre reads as active (membership in multiGenreSet).
function FeatureResolver.IsCategoryActive(name: string): boolean
	if isGenreKey(name) then
		resolveGenre()
		if #multiGenreSet > 0 then
			return table.find(multiGenreSet, name) ~= nil
		end
		return name == resolvedGenre
	end
	local toggle: any = (FeatureToggles :: any)[name]
	if toggle == nil then
		toggle = (FeatureToggles :: any)[name .. "Config"]
	end
	if toggle == nil and FeatureToggles.GlobalFlags then
		toggle = (FeatureToggles.GlobalFlags :: any)[name]
		if toggle == nil then
			toggle = (FeatureToggles.GlobalFlags :: any)[name .. "Config"]
		end
	end
	if type(toggle) == "table" then
		return toggle.Enabled == true
	end
	return toggle == true
end

-- Returns the active gameplay categories: every enabled genre when
-- FeatureToggles.AllowMultipleGenres opted out of exclusivity, otherwise the
-- single resolved genre, or "Global" when running core-only.
function FeatureResolver.GetActiveCategories(): {string}
	local genre: string? = resolveGenre()
	if #multiGenreSet > 0 then
		local copy: {string} = {}
		for _, key in ipairs(multiGenreSet) do
			table.insert(copy, key)
		end
		return copy
	end
	if genre then
		return { genre }
	end
	return { "Global" }
end

-- Returns a single representative resolved genre key (default applied), or nil
-- if core-only. NOT authoritative for gating in multi-genre mode — when
-- FeatureToggles.AllowMultipleGenres allows several genres to be active at
-- once, this returns only the alphabetically-first one, for the sake of call
-- sites that structurally need one genre (currency naming, audio/commerce
-- config lookup, boot-log prints). Use IsCategoryActive or GetActiveCategories
-- for correct multi-genre gating.
function FeatureResolver.GetActiveGenre(): string?
	return resolveGenre()
end

-- Resolves the display names for the two abstract currency slots
-- (Currencies.Primary / Currencies.Secondary) from the active genre's config.
-- Single source of truth for leaderstats naming, UI labels and store text.
function FeatureResolver.GetCurrencyNames(): {Primary: string, Secondary: string}
	local primary: string = "Coins"
	local secondary: string = "Gems"

	local genre: string? = FeatureResolver.GetActiveGenre()
	if genre then
		local cfg: any = FeatureResolver.GetCategoryConfig(genre)
		if type(cfg) == "table" and type(cfg.Currencies) == "table" then
			if type(cfg.Currencies.PrimaryName) == "string" then
				primary = cfg.Currencies.PrimaryName
			end
			if type(cfg.Currencies.SecondaryName) == "string" then
				secondary = cfg.Currencies.SecondaryName
			end
		end
	end

	return { Primary = primary, Secondary = secondary }
end

-- Retrieves a GlobalFlags entry by name, returns nil if missing
function FeatureResolver.GetFlag(name: string): any
	if FeatureToggles.GlobalFlags then
		return (FeatureToggles.GlobalFlags :: any)[name]
	end
	return nil
end

-- Safely retrieves configuration table for a category.
-- Note: genre configs stay readable even for inactive genres — activation
-- gating is IsCategoryActive's job, not this accessor's.
function FeatureResolver.GetCategoryConfig(name: string): any
	local config: any = (FeatureToggles :: any)[name]
	if config == nil then
		config = (FeatureToggles :: any)[name .. "Config"]
	end
	if config == nil and FeatureToggles.GlobalFlags then
		config = (FeatureToggles.GlobalFlags :: any)[name]
		if config == nil then
			config = (FeatureToggles.GlobalFlags :: any)[name .. "Config"]
		end
	end
	if config == nil and (FeatureToggles :: any).Genres then
		config = (FeatureToggles :: any).Genres[name]
		if config == nil then
			config = (FeatureToggles :: any).Genres[name .. "Config"]
		end
	end
	return config
end

-- Safely retrieves a specific field from a category configuration table
function FeatureResolver.GetConfigField(categoryName: string, field: string, defaultValue: any): any
	local config: any = FeatureResolver.GetCategoryConfig(categoryName)
	if type(config) == "table" then
		if config[field] ~= nil then
			return config[field]
		end
	end
	return defaultValue
end

return FeatureResolver
