--!strict
--@author OrkGabb
--@module AirSpreadFX.luau
--@version 1.0
-- Shared "air spread" burst (the "FUUU" effect): a wide, flat radial blast
-- of high-velocity air escaping horizontally outward from an effect
-- boundary, braked almost instantly by heavy drag — expanding gas, not
-- lingering smoke. Consumed by:
--   * Client/UI/DoubleJumpFX — under the shockwave rings at the jump frame
--   * Client/UI/DashFX      — at the dash exit/evacuation point (finish or
--                             cancel), leaving the displaced-air cloud where
--                             the character evacuated from
--
-- This module is also the fail-safe resolver for its registry config:
-- Burst accepts the raw MovementRegistry.<System>.AirSpread table as `any`
-- and sanitizes every field — a typoed texture id, a mangled number, or a
-- missing table degrades to native defaults with a once-per-field warning.
-- Visuals degrade; nothing throws; gameplay never notices.

local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

-- Native fallbacks used whenever the registry value fails validation.
local FALLBACK_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local FALLBACK_SPREAD_VELOCITY = 40
local FALLBACK_LIFETIME = 0.2

-- Fixed artistic identity of the burst (same registry/module split as the
-- other FX modules: designers tune texture/velocity/lifetime in the
-- registry; the shape of the blast is authored here).
local BURST_PARTICLE_COUNT = 18
local BURST_COLOR = Color3.fromRGB(235, 240, 245)
local BURST_DRAG = 20

local AirSpreadFX = {}

-- One warning per distinct broken field per session: a bad config should
-- tell the developer once, not spam the output on every jump and dash.
local warnedFields: { [string]: boolean } = {}

local function warnOnce(fieldKey: string, detail: string): ()
	if warnedFields[fieldKey] then
		return
	end
	warnedFields[fieldKey] = true
	warn(("[AirSpreadFX] %s — using the native fallback."):format(detail))
end

type SanitizedConfig = {
	texture: string,
	spreadVelocity: number,
	lifetime: number,
}

--- Validates a raw registry AirSpread table field-by-field. Every failure
--- path lands on a working native default, so the burst below can assume
--- clean typed values no matter what the registry actually contained.
local function sanitizeConfig(rawConfig: any): SanitizedConfig
	local sanitized: SanitizedConfig = {
		texture = FALLBACK_TEXTURE,
		spreadVelocity = FALLBACK_SPREAD_VELOCITY,
		lifetime = FALLBACK_LIFETIME,
	}

	if type(rawConfig) ~= "table" then
		warnOnce("config", "AirSpread config is missing or not a table")
		return sanitized
	end

	local texture = rawConfig.ParticleTextureId
	if type(texture) == "string" and texture ~= "" then
		sanitized.texture = texture
	else
		warnOnce("ParticleTextureId", "AirSpread.ParticleTextureId is not a non-empty string")
	end

	local spreadVelocity = rawConfig.SpreadVelocity
	if type(spreadVelocity) == "number" and spreadVelocity > 0 then
		sanitized.spreadVelocity = spreadVelocity
	else
		warnOnce("SpreadVelocity", "AirSpread.SpreadVelocity is not a positive number")
	end

	local lifetime = rawConfig.Lifetime
	if type(lifetime) == "number" and lifetime > 0 then
		sanitized.lifetime = lifetime
	else
		warnOnce("Lifetime", "AirSpread.Lifetime is not a positive number")
	end

	return sanitized
end

--- Fires one escaping-air blast at `originCFrame` (expected: a foot-baseline
--- CFrame). The emitter host is a world-anchored invisible disc, so the
--- cloud stays where it was born instead of following the character — the
--- "left behind at the evacuation point" read. `rawConfig` is deliberately
--- `any`: it is sanitized above and can be absent or arbitrarily broken.
function AirSpreadFX.Burst(originCFrame: CFrame, rawConfig: any): ()
	local config = sanitizeConfig(rawConfig)

	local anchor = Instance.new("Part")
	anchor.Name = "AirSpreadBurst"
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	-- Flat disc footprint: with Shape=Disc the particles spawn across this
	-- horizontal area, so the blast escapes from the effect's boundary rather
	-- than a single point.
	anchor.Size = Vector3.new(3, 0.2, 3)
	anchor.CFrame = originCFrame

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AirSpreadEmitter"
	emitter.Texture = config.texture
	emitter.Enabled = false -- burst-only: no continuous emission
	emitter.Rate = 0
	-- Disc + Outward = a flat 360° radial blast in the horizontal plane; the
	-- particles' velocity is the outward escape direction.
	emitter.Shape = Enum.ParticleEmitterShape.Disc
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	-- Velocity-aligned and stretched along the motion axis: reads as gas
	-- shooting outward, not floating puffs.
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.Squash = NumberSequence.new(1.5)
	emitter.Speed = NumberRange.new(config.spreadVelocity * 0.7, config.spreadVelocity)
	-- Massive drag: the violent launch brakes almost instantly, dumping the
	-- expanded air right at the boundary.
	emitter.Drag = BURST_DRAG
	emitter.Lifetime = NumberRange.new(config.lifetime * 0.7, config.lifetime)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 3.2),
	})
	-- Dense but highly transparent: presence without white stacking.
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.6, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(BURST_COLOR)
	emitter.LightEmission = 0.2
	-- Straight outward travel only: spin reads as churn, not displacement.
	emitter.RotSpeed = NumberRange.new(0)
	emitter.Parent = anchor

	anchor.Parent = Workspace
	emitter:Emit(BURST_PARTICLE_COUNT)

	Debris:AddItem(anchor, config.lifetime + 0.05)
end

return AirSpreadFX
