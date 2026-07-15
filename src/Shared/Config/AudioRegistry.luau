--!strict
-- @Author @OrkGabb
-- Genre-scoped audio configuration — single source of truth for background
-- music playlists and named UI/gameplay sound effects. Controllers never
-- hardcode a SoundId; they resolve named entries for the active genre here
-- (with a Global fallback for shared UI sounds).
--
-- NOTE: weapon-specific FPS sounds (fire/reload/equip) intentionally live in
-- the per-weapon config inside FeatureToggles — they are weapon properties,
-- not genre-wide audio. This registry covers everything else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

export type SfxDef = {
	SoundId: string,
	Volume: number?,        -- default 0.5
	PlaybackSpeed: number?, -- default 1 (randomised ±10% when RandomPitch)
	RandomPitch: boolean?,
}

export type GenreAudio = {
	-- Played in order, looping, by AudioController. Empty = no BGM.
	-- ⚠️ Placeholder-free by default: add your own licensed track IDs.
	BGM: {string},
	BGMVolume: number,
	SFX: {[string]: SfxDef},
}

local Library: {[string]: GenreAudio} = {
	["Global"] = {
		BGM = {},
		BGMVolume = 0.35,
		SFX = {
			["UIClick"]  = { SoundId = "rbxassetid://8217058484", Volume = 0.4 },
			["Purchase"] = { SoundId = "rbxassetid://3742927091", Volume = 0.5 },
		},
	},

	["Clicker_Farm"] = {
		BGM = {},
		BGMVolume = 0.3,
		SFX = {
			["Click"]       = { SoundId = "rbxassetid://6895079853", Volume = 0.4, RandomPitch = true },
			["GoldenClaim"] = { SoundId = "rbxassetid://3742927091", Volume = 0.6 },
			["Milestone"]   = { SoundId = "rbxassetid://3666863095", Volume = 0.5 },
		},
	},

	["FPS_Shooter"] = {
		BGM = {},
		BGMVolume = 0.25,
		SFX = {},
	},

	["Aura_Collector"] = {
		BGM = {},
		BGMVolume = 0.3,
		-- Roll-reveal stingers, escalating with AuraRegistry FeedbackTier.
		SFX = {
			["RollSubtle"]    = { SoundId = "rbxassetid://95154184427705",  Volume = 0.4, PlaybackSpeed = 1.1 },
			["RollMedium"]    = { SoundId = "rbxassetid://122136024332497", Volume = 0.6, PlaybackSpeed = 1.0 },
			["RollImpactful"] = { SoundId = "rbxassetid://115447313733239", Volume = 0.8, PlaybackSpeed = 0.95 },
			["RollDramatic"]  = { SoundId = "rbxassetid://79552398776329",  Volume = 0.9, PlaybackSpeed = 0.85 },
			["RollCinematic"] = { SoundId = "rbxassetid://95851961981936",  Volume = 1.0, PlaybackSpeed = 0.8 },
			["RollOmniSwell"] = { SoundId = "rbxassetid://134160561050962", Volume = 0.8, PlaybackSpeed = 0.8 },
		},
	},

	["Pet_Simulator"] = {
		BGM = {},
		BGMVolume = 0.3,
		SFX = {
			["HatchReveal"] = { SoundId = "rbxassetid://3742927091", Volume = 0.6, RandomPitch = true },
		},
	},
}

local AudioRegistry = {}

AudioRegistry.Library = Library

-- Resolves a named SFX for the active genre, falling back to Global.
function AudioRegistry.GetSFX(name: string): SfxDef?
	local genre = FeatureResolver.GetActiveGenre()
	if genre then
		local audio = Library[genre]
		if audio and audio.SFX[name] then
			return audio.SFX[name]
		end
	end
	local globalAudio = Library["Global"]
	return globalAudio and globalAudio.SFX[name]
end

-- Returns the active genre's BGM playlist (Global fallback) and its volume.
function AudioRegistry.GetBGM(): ({string}, number)
	local genre = FeatureResolver.GetActiveGenre()
	if genre then
		local audio = Library[genre]
		if audio and #audio.BGM > 0 then
			return audio.BGM, audio.BGMVolume
		end
	end
	local globalAudio = Library["Global"]
	if globalAudio then
		return globalAudio.BGM, globalAudio.BGMVolume
	end
	return {}, 0.35
end

return AudioRegistry
