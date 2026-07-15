--!strict
--@author OrkGabb
--@module VFXRegistry.luau
--@version 1.0
-- Metadata override table for the VFX subsystem.

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
