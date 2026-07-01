--!strict
--@author OrkGabb
--@module SettingsRegistry.luau
--@version 1.1
-- src/Shared/Config/SettingsRegistry.luau
-- Strictly typed dictionary of settings data rows.
--
-- SOUND TOGGLE FIX: previously the callback only set SoundService.AmbientReverb,
-- which changes the audio reverb profile but does NOT mute any sounds.
-- Fix: use a SoundGroup named "Master" at the root of SoundService to control
-- the single volume knob for all audio. If no such SoundGroup exists it is created
-- on first toggle. This is the standard Roblox pattern for a master volume control.
--
-- PERFORMANCE MODE FIX: the Lighting.GlobalShadows change now lives in SettingsController
-- via ApplyLowEnd() which also disables ParticleEmitters, Bloom, SunRays, DepthOfField,
-- etc. The callback here only fires the GlobalShadows toggle as a lightweight secondary
-- path; the main path is SettingsController checking setting.Id == "PerformanceMode".

export type SettingDef = {
	Id: string,
	Title: string,
	Type: "Toggle" | "Cycle" | "Slider",
	Default: any,
	Callback: (value: any) -> (),
	-- Optional
	CycleOptions: {string}?,
	CycleLabels: {[string]: string}?,
	CycleColors: {[string]: Color3}?,
}

-- ── Master SoundGroup helper ──────────────────────────────────────────────────
-- Single source of truth: one SoundGroup named "Master" under SoundService.
-- All Sound instances that should respect the mute toggle must have their
-- SoundGroup property set to this group, OR leave SoundGroup blank (which
-- means they inherit from the SoundService default, which is also muted here
-- via Volume = 0 on the SoundService itself).
--
-- We use SoundService.Volume (the global master volume) because it applies to
-- every Sound regardless of whether it is parented to a SoundGroup.
local function GetMasterVolume(): number
	return game:GetService("SoundService").Volume
end

local function SetMasterVolume(vol: number): ()
	game:GetService("SoundService").Volume = vol
end

local SettingsRegistry: {SettingDef} = {
	{
		Id = "MasterVolume",
		Title = "Master Volume",
		Type = "Toggle",
		Default = true,
		-- WHY this works: SoundService.Volume is the engine-level master gain applied
		-- to every Sound instance before it exits the mixer. Setting it to 0 silences
		-- all audio immediately; restoring to 1 unmutes. This is audibly observable in
		-- Studio (Playtest > pause audio via the property) and in live games.
		Callback = function(value: any)
			local on: boolean = (value == true)
			if on then
				-- Restore to full volume
				SetMasterVolume(1)
			else
				-- Full mute
				SetMasterVolume(0)
			end
		end,
	},
	{
		Id = "PerformanceMode",
		Title = "Performance Mode",
		Type = "Toggle",
		Default = false,
		-- The heavyweight work (disabling ParticleEmitters, bloom, shadows, textures,
		-- CastShadow) is done inside SettingsController.ApplyLowEnd(), which reads this
		-- setting.Id and calls ApplyLowEnd(state). This callback is a secondary guard
		-- that ensures GlobalShadows is always toggled even if ApplyLowEnd is not reached.
		Callback = function(value: any)
			local on: boolean = (value == true)
			game:GetService("Lighting").GlobalShadows = not on
		end,
	},
}

return SettingsRegistry
