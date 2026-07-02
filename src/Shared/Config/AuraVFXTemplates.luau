--!strict
-- @Author @OrkGabb
-- src/Shared/Config/AuraVFXTemplates.luau
-- Aura VFX template specs — original, fully procedural effect definitions
-- (no third-party VFX pack assets; particle textures are Roblox engine
-- built-ins). AuraVFXController builds each spec once into a template
-- Attachment tree, then clones the attachments into the matching character
-- part by name at equip time. Roblox's native Attachment system makes the
-- effect follow rotation/animation correctly on any rig — the fix for the
-- legacy per-frame position-sync bug.
--
-- `Part` names target parts that exist on both R6 and R15 rigs (Head,
-- HumanoidRootPart); the controller also carries an alias map (e.g.
-- UpperTorso → Torso) for specs that target rig-specific parts.
--
-- Prefer Studio-authored effects? Drop a template rig (a Folder/Model whose
-- BaseParts are named after character parts and carry Attachments) into
-- ReplicatedStorage.Shared.GlobalAssets.VFXAssets.AuraTemplates/<name> — the
-- controller uses it instead of the spec below with the same name.

-- Engine-shipped particle textures (rbxasset:// = local Roblox content,
-- license-safe by definition)
local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"

export type EmitterSpec = {
	Texture: string,
	-- Explicit color; when nil the controller tints with the aura's Color
	Color: ColorSequence?,
	Size: NumberSequence,
	Transparency: NumberSequence,
	Lifetime: NumberRange,
	Rate: number,
	Speed: NumberRange,
	SpreadAngle: Vector2?,
	Acceleration: Vector3?,
	RotSpeed: NumberRange?,
	Rotation: NumberRange?,
	LightEmission: number?,
	LockedToPart: boolean?,
	EmissionDirection: Enum.NormalId?,
	Drag: number?,
	ZOffset: number?,
}

export type LightSpec = {
	Brightness: number,
	Range: number,
	-- Explicit color; when nil the controller tints with the aura's Color
	Color: Color3?,
}

export type AttachmentSpec = {
	Part: string,             -- character part name to mount on
	Offset: Vector3?,         -- attachment position relative to the part
	Emitters: {EmitterSpec},
	Light: LightSpec?,
}

export type TemplateSpec = {
	Attachments: {AttachmentSpec},
}

local function seq(pairs_: {{number}}): NumberSequence
	local keypoints = table.create(#pairs_)
	for i, p in ipairs(pairs_) do
		keypoints[i] = NumberSequenceKeypoint.new(p[1], p[2])
	end
	return NumberSequence.new(keypoints)
end

local AuraVFXTemplates: {[string]: TemplateSpec} = {
	-- Gentle drifting sparkles around the lower body — the common-tier glow.
	["SparkleWisp"] = {
		Attachments = {
			{
				Part = "HumanoidRootPart",
				Offset = Vector3.new(0, -1, 0),
				Emitters = {
					{
						Texture = TEX_SPARKLE,
						Size = seq({ {0, 0.35}, {1, 0} }),
						Transparency = seq({ {0, 0.4}, {0.8, 0.7}, {1, 1} }),
						Lifetime = NumberRange.new(0.8, 1.4),
						Rate = 8,
						Speed = NumberRange.new(0.5, 1.2),
						SpreadAngle = Vector2.new(180, 180),
						Acceleration = Vector3.new(0, 1.5, 0),
						LightEmission = 0.8,
					},
				},
			},
		},
	},

	-- Embers rising up the body with a warm underglow.
	["EmberTrail"] = {
		Attachments = {
			{
				Part = "HumanoidRootPart",
				Offset = Vector3.new(0, -2.2, 0),
				Emitters = {
					{
						Texture = TEX_FIRE,
						Size = seq({ {0, 0.5}, {0.5, 0.3}, {1, 0} }),
						Transparency = seq({ {0, 0.25}, {0.7, 0.6}, {1, 1} }),
						Lifetime = NumberRange.new(0.7, 1.3),
						Rate = 18,
						Speed = NumberRange.new(1.5, 3),
						SpreadAngle = Vector2.new(35, 35),
						Acceleration = Vector3.new(0, 4, 0),
						EmissionDirection = Enum.NormalId.Top,
						LightEmission = 1,
					},
					{
						Texture = TEX_SMOKE,
						Color = ColorSequence.new(Color3.fromRGB(40, 40, 40)),
						Size = seq({ {0, 0.8}, {1, 2} }),
						Transparency = seq({ {0, 0.75}, {1, 1} }),
						Lifetime = NumberRange.new(1, 1.8),
						Rate = 4,
						Speed = NumberRange.new(0.8, 1.5),
						SpreadAngle = Vector2.new(25, 25),
						EmissionDirection = Enum.NormalId.Top,
						ZOffset = -1,
					},
				},
				Light = { Brightness = 0.8, Range = 8 },
			},
		},
	},

	-- A slow halo of radiant motes above the head — sits at the template
	-- offset, so it can never clip into the head on any rig.
	["RadiantCrown"] = {
		Attachments = {
			{
				Part = "Head",
				Offset = Vector3.new(0, 1.4, 0),
				Emitters = {
					{
						Texture = TEX_SPARKLE,
						Size = seq({ {0, 0.25}, {0.5, 0.4}, {1, 0} }),
						Transparency = seq({ {0, 0.2}, {0.8, 0.5}, {1, 1} }),
						Lifetime = NumberRange.new(0.6, 1),
						Rate = 25,
						Speed = NumberRange.new(0.4, 0.8),
						SpreadAngle = Vector2.new(85, 85),
						RotSpeed = NumberRange.new(60, 120),
						LockedToPart = true,
						LightEmission = 1,
					},
				},
				Light = { Brightness = 1.2, Range = 10 },
			},
			{
				Part = "HumanoidRootPart",
				Offset = Vector3.new(0, -2.2, 0),
				Emitters = {
					{
						Texture = TEX_SPARKLE,
						Size = seq({ {0, 0.2}, {1, 0} }),
						Transparency = seq({ {0, 0.5}, {1, 1} }),
						Lifetime = NumberRange.new(1, 1.6),
						Rate = 6,
						Speed = NumberRange.new(1, 2),
						SpreadAngle = Vector2.new(15, 15),
						EmissionDirection = Enum.NormalId.Top,
						LightEmission = 0.9,
					},
				},
			},
		},
	},

	-- Heavy dark shroud swallowing the whole body.
	["VoidShroud"] = {
		Attachments = {
			{
				Part = "HumanoidRootPart",
				Emitters = {
					{
						Texture = TEX_SMOKE,
						Size = seq({ {0, 1.5}, {0.5, 2.5}, {1, 3.5} }),
						Transparency = seq({ {0, 0.45}, {0.7, 0.7}, {1, 1} }),
						Lifetime = NumberRange.new(1.2, 2),
						Rate = 14,
						Speed = NumberRange.new(0.3, 0.8),
						SpreadAngle = Vector2.new(180, 180),
						RotSpeed = NumberRange.new(-40, 40),
						Rotation = NumberRange.new(0, 360),
						ZOffset = -2,
					},
					{
						Texture = TEX_SPARKLE,
						Size = seq({ {0, 0.3}, {1, 0} }),
						Transparency = seq({ {0, 0.3}, {1, 1} }),
						Lifetime = NumberRange.new(0.5, 0.9),
						Rate = 10,
						Speed = NumberRange.new(1, 2.5),
						SpreadAngle = Vector2.new(180, 180),
						Drag = 2,
						LightEmission = 1,
					},
				},
				Light = { Brightness = 0.6, Range = 12 },
			},
		},
	},

	-- Fast star-streams circling the torso and head — the top-tier effect.
	["CelestialOrbit"] = {
		Attachments = {
			{
				Part = "HumanoidRootPart",
				Emitters = {
					{
						Texture = TEX_SPARKLE,
						Size = seq({ {0, 0.45}, {0.5, 0.3}, {1, 0} }),
						Transparency = seq({ {0, 0}, {0.8, 0.4}, {1, 1} }),
						Lifetime = NumberRange.new(0.9, 1.4),
						Rate = 30,
						Speed = NumberRange.new(2, 4),
						SpreadAngle = Vector2.new(180, 0),
						RotSpeed = NumberRange.new(120, 240),
						Drag = 1.5,
						LockedToPart = true,
						LightEmission = 1,
					},
					{
						Texture = TEX_SMOKE,
						Color = ColorSequence.new(Color3.fromRGB(15, 10, 35)),
						Size = seq({ {0, 1}, {1, 2.2} }),
						Transparency = seq({ {0, 0.7}, {1, 1} }),
						Lifetime = NumberRange.new(1, 1.6),
						Rate = 6,
						Speed = NumberRange.new(0.2, 0.6),
						SpreadAngle = Vector2.new(180, 180),
						ZOffset = -2,
					},
				},
				Light = { Brightness = 1.5, Range = 14 },
			},
			{
				Part = "Head",
				Offset = Vector3.new(0, 1, 0),
				Emitters = {
					{
						Texture = TEX_SPARKLE,
						Size = seq({ {0, 0.2}, {1, 0} }),
						Transparency = seq({ {0, 0.2}, {1, 1} }),
						Lifetime = NumberRange.new(0.5, 0.8),
						Rate = 15,
						Speed = NumberRange.new(0.6, 1.2),
						SpreadAngle = Vector2.new(60, 60),
						LockedToPart = true,
						LightEmission = 1,
					},
				},
			},
		},
	},
}

return AuraVFXTemplates
