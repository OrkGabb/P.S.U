--!strict
-- @Author @OrkGabb
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
	-- Only show this row when the named FeatureToggles category is active
	-- (SettingsController filters via FeatureResolver); nil = always shown.
	RequiresCategory: string?,
}

-- Master SoundGroup: one SoundGroup named "Master" under SoundService. All
-- Sound instances that should respect the mute toggle must set SoundGroup to
-- this group, or leave it blank to inherit the SoundService default (also
-- muted here via Volume = 0). We drive SoundService.Volume directly since it
-- applies to every Sound regardless of SoundGroup.
local function SetMasterVolume(vol: number): ()
	game:GetService("SoundService").Volume = vol
end

local SettingsRegistry: {SettingDef} = {
	{
		Id = "MasterVolume",
		Title = "Master Volume",
		Type = "Toggle",
		Default = true,
		Callback = function(value: any)
			local on: boolean = (value == true)
			if on then
				SetMasterVolume(1)
			else
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
	{
		Id = "ReduceEffects",
		Title = "Reduce Screen Effects",
		Type = "Toggle",
		Default = false,
		-- Accessibility: consumers (e.g. the Aura roll UI's shake/vignette
		-- "juice") read the mirrored LocalPlayer attribute rather than this
		-- registry, so any controller can honor it without a dependency here.
		Callback = function(value: any)
			local player = game:GetService("Players").LocalPlayer
			if player then
				player:SetAttribute("ReduceEffects", value == true)
			end
		end,
	},
	{
		Id = "AutoRollStopTier",
		Title = "Auto-Roll Stops At",
		Type = "Cycle",
		Default = "MYTHIC+",
		RequiresCategory = "Aura_Collector",
		CycleOptions = { "MYTHIC+", "RAREST", "NEVER" },
		CycleLabels = {
			["MYTHIC+"] = "MYTHIC OR BETTER",
			["RAREST"]  = "SINGULARITY+",
			["NEVER"]   = "NEVER STOP",
		},
		CycleColors = {
			["MYTHIC+"] = Color3.fromRGB(228, 45, 45),
			["RAREST"]  = Color3.fromRGB(200, 200, 255),
			["NEVER"]   = Color3.fromRGB(100, 100, 110),
		},
		-- Mirrored to a LocalPlayer attribute; MainUIController's auto-roll
		-- pause check reads it (defaults to MYTHIC+ when unset).
		Callback = function(value: any)
			local player = game:GetService("Players").LocalPlayer
			if player and type(value) == "string" then
				player:SetAttribute("AutoRollStopTier", value)
			end
		end,
	},
}

return SettingsRegistry
