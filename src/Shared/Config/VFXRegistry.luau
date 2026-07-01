--!strict
--@author OrkGabb
--@module VFXRegistry.luau
--@version 1.0
-- src/Shared/Config/VFXRegistry.luau
-- Clean metadata configuration override table for the VFX subsystem.

export type VFXEffectConfig = {
	ScaleMultiplier: number?,
	SoundId: string?,
	AudioPitch: number?,
}

export type VFXRegistryType = {
	[string]: VFXEffectConfig,
}

local VFXRegistry: VFXRegistryType = {}

return VFXRegistry
