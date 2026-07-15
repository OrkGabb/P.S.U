--!strict
-- @Author @OrkGabb
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
