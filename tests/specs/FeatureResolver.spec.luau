--!nocheck
-- tests/specs/FeatureResolver.spec.luau
-- The single source of truth for "what genre is running". Resolution is cached
-- per VM, so every scenario loads a FRESH FeatureResolver with a synthetic
-- FeatureToggles injected in place of the real config.

local T = require("../lune/harness")
local psu = require("../lune/psu")

-- Fresh resolver bound to a hand-built FeatureToggles stub.
local function freshResolver(toggles: any)
	return psu.loadWith("Shared/Modules/FeatureResolver", {
		["Shared/Config/FeatureToggles"] = toggles,
	})
end

T.suite("FeatureResolver")

T.test("exactly one enabled genre resolves to that genre", function()
	local FR = freshResolver({
		Genres = { Clicker_Farm = { Enabled = true }, Aura_Collector = { Enabled = false } },
		AllowMultipleGenres = false,
		GlobalFlags = {},
	})
	T.eq(FR.GetActiveGenre(), "Clicker_Farm")
	T.truthy(FR.IsCategoryActive("Clicker_Farm"))
	T.falsy(FR.IsCategoryActive("Aura_Collector"))
	local cats = FR.GetActiveCategories()
	T.eq(#cats, 1)
	T.eq(cats[1], "Clicker_Farm")
	FR.AssertGenreExclusivity("test") -- must not raise
end)

T.test("no enabled genre falls back to the default genre when it is a key", function()
	local FR = freshResolver({
		Genres = { Clicker_Farm = { Enabled = false }, Aura_Collector = { Enabled = false } },
		AllowMultipleGenres = false,
		GlobalFlags = {},
	})
	T.eq(FR.GetActiveGenre(), "Clicker_Farm")
end)

T.test("no enabled genre and no default key resolves to core-only (Global)", function()
	local FR = freshResolver({
		Genres = { FPS_Shooter = { Enabled = false } }, -- no Clicker_Farm key
		AllowMultipleGenres = false,
		GlobalFlags = {},
	})
	T.isNil(FR.GetActiveGenre())
	local cats = FR.GetActiveCategories()
	T.eq(#cats, 1)
	T.eq(cats[1], "Global")
end)

T.test("multiple genres with exclusivity: conflict recorded, Assert raises", function()
	local FR = freshResolver({
		Genres = { Aura_Collector = { Enabled = true }, Clicker_Farm = { Enabled = true } },
		AllowMultipleGenres = false,
		GlobalFlags = {},
	})
	-- keys iterate sorted, so the representative is the alphabetically-first one
	T.eq(FR.GetActiveGenre(), "Aura_Collector")
	T.truthy(FR.IsCategoryActive("Aura_Collector"))
	T.falsy(FR.IsCategoryActive("Clicker_Farm"))
	T.throws(function()
		FR.AssertGenreExclusivity("boot")
	end)
end)

T.test("multiple genres with AllowMultipleGenres: all active, no raise", function()
	local FR = freshResolver({
		Genres = {
			Aura_Collector = { Enabled = true },
			Clicker_Farm = { Enabled = true },
			FPS_Shooter = { Enabled = false },
		},
		AllowMultipleGenres = true,
		GlobalFlags = {},
	})
	FR.AssertGenreExclusivity("boot") -- must not raise
	T.truthy(FR.IsCategoryActive("Aura_Collector"))
	T.truthy(FR.IsCategoryActive("Clicker_Farm"))
	T.falsy(FR.IsCategoryActive("FPS_Shooter"))
	T.eq(#FR.GetActiveCategories(), 2)
end)

T.test("non-genre flags resolve across direct / Config-suffixed / GlobalFlags forms", function()
	local FR = freshResolver({
		Genres = { Clicker_Farm = { Enabled = true } },
		AllowMultipleGenres = false,
		Dash = true, -- direct boolean
		LeaderboardConfig = { Enabled = true }, -- name + "Config" table
		GlobalFlags = {
			Trading = true, -- GlobalFlags boolean
			Portals = { Enabled = false }, -- GlobalFlags table, disabled
		},
	})
	T.truthy(FR.IsCategoryActive("Dash"))
	T.truthy(FR.IsCategoryActive("Leaderboard"))
	T.truthy(FR.IsCategoryActive("Trading"))
	T.falsy(FR.IsCategoryActive("Portals"))
	T.falsy(FR.IsCategoryActive("Nonexistent"))
	T.eq(FR.GetFlag("Trading"), true)
	T.eq(FR.GetConfigField("Leaderboard", "Enabled", nil), true)
	T.eq(FR.GetConfigField("Leaderboard", "Missing", "dflt"), "dflt")
end)

T.test("currency names come from the active genre config", function()
	local FR = freshResolver({
		Genres = {
			Aura_Collector = {
				Enabled = true,
				Currencies = { PrimaryName = "Mana", SecondaryName = "Essence" },
			},
		},
		AllowMultipleGenres = false,
		GlobalFlags = {},
	})
	local names = FR.GetCurrencyNames()
	T.eq(names.Primary, "Mana")
	T.eq(names.Secondary, "Essence")
end)

T.test("currency names fall back to Coins/Gems when the genre omits them", function()
	local FR = freshResolver({
		Genres = { Clicker_Farm = { Enabled = true } },
		AllowMultipleGenres = false,
		GlobalFlags = {},
	})
	local names = FR.GetCurrencyNames()
	T.eq(names.Primary, "Coins")
	T.eq(names.Secondary, "Gems")
end)

return {}
