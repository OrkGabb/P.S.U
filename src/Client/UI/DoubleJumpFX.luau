--!strict
--@author OrkGabb
--@module DoubleJumpFX.luau
--@version 2.4
-- Bespoke procedural shockwave for the double jump: a radially symmetric
-- "BespokeJumpFX" assembly generated at runtime (lazy, once per client) and
-- cloned per burst. Replaces the v1.x fractured-shard rim — the hash-sine
-- jitter read as jagged broken geometry, and 14 overlapping translucent
-- slabs stacked into a solid white mass.
--
-- Assembly layers (all offsets in assembly-local space around the Core):
--   * InnerRing/OuterRing — two perfect concentric glass torus rings built
--                      on the published hollow-ring FileMesh, transparent
--                      enough to read as screen-space refraction (air
--                      displacement) rather than solid geometry. During
--                      the burst they scale outward with a micro
--                      counter-twist (inner +, outer -) while dissolving
--                      on a linear ramp.
--   * Core.CondensationCloud — one tamed single-burst emitter: a faint puff
--                      whose high Drag brakes it mid-air.
--   * Air spread     — a flat radial escaping-gas blast underneath the
--                      rings, delegated to the shared Client/UI/AirSpreadFX
--                      module (optional: missing/broken module or config
--                      degrades to rings-only, never an error). Fires even
--                      when AllowMeshVFX is false: the gate is the glass
--                      kill switch, and the dash exit burst this mirrors
--                      runs ungated.
--
-- The rings use a published FileMesh, never EditableMesh: runtime mesh
-- content decays to SourceType=None on save/Clone and renders as a bare
-- gray box. The legacy ring mesh imports STANDING VERTICAL — diameter
-- spanning mesh X/Y, thickness along mesh Z — so each ring part is rolled
-- 90° to lie flat and every Scale value is expressed in those mesh-local
-- axes (thin value in Z, never Y).
--
-- Burst pacing (VFXFadeSeconds) and ring scales (VFXStartScale/VFXMaxScale)
-- are registry-driven; everything else in this file is the fixed artistic
-- identity of the effect, same as DashFX's hardcoded curve construction.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local MovementRegistry = require(ReplicatedStorage.Shared.Config.MovementRegistry)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver"))

local DOUBLE_JUMP_CONFIG = MovementRegistry.DoubleJump

-- Optional shared burst layer, resolved with the same defensive contract
-- DoubleJumpController uses for this module: FindFirstChild + pcall so a
-- deleted or broken AirSpreadFX degrades to rings-only visuals.
local AirSpreadFX: any = nil
do
	local airSpreadModule = script.Parent:FindFirstChild("AirSpreadFX")
	if airSpreadModule and airSpreadModule:IsA("ModuleScript") then
		local ok, result = pcall(require, airSpreadModule)
		if ok then
			AirSpreadFX = result
		else
			warn("[DoubleJumpFX] AirSpreadFX failed to load — bursting without the air-spread layer: " .. tostring(result))
		end
	else
		warn("[DoubleJumpFX] AirSpreadFX module not found — bursting without the air-spread layer.")
	end
end

local TORUS_MESH_ID = "rbxassetid://3270017" -- public hollow torus (published asset)
local RING_COLOR = Color3.new(1, 1, 1)
-- The refraction sweet spot, found the hard way: 0.35 stacked the two rings
-- into solid white concrete, 0.97 vanished entirely (and sat past the ~0.95
-- cutoff where Glass renders fully invisible on low graphics quality). 0.85
-- keeps enough presence to bend screen pixels without reading as plastic,
-- and stays visible on low-end clients; the burst tween dissolves it the
-- rest of the way to 1.
local RING_TRANSPARENCY = 0.85
-- The inner ring runs the same registry scale curve multiplied by this
-- ratio, keeping it concentric inside the outer ring for the whole burst.
local INNER_RING_RATIO = 0.65
-- Y separation between the two rings, avoiding coplanar-glass shimmer.
local RING_Y_OFFSET = 0.08
-- Signed in-plane micro-twist per ring (degrees): inner clockwise, outer
-- counter-clockwise. Art-direction hard limit — keep this subtle: ±180° in
-- a 0.25s burst read as a hyper-speed drill vortex instead of an expanding
-- shockwave. The visual focus belongs on the radial expansion; the twist is
-- only a hint of air shear.
local INNER_RING_SPIN_DEGREES = 15
local OUTER_RING_SPIN_DEGREES = -15

local CLOUD_TEXTURE = "rbxassetid://6034141151"
local CLOUD_BURST_COUNT = 14
local CLOUD_LIFETIME_SECONDS = 0.2

local DoubleJumpFX = {}

local function applyFXPartDefaults(part: BasePart): ()
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

--- One perfect torus ring. The 90° X-roll lays the vertically-imported mesh
--- flat on the ground plane; after it the ring's normal is the part's local
--- Z, which is the axis the burst spins about. Scale ratio and spin are
--- stamped as attributes so Burst can drive each clone without re-deriving
--- which ring is which.
local function buildRing(name: string, scaleRatio: number, yOffset: number, spinDegrees: number): Part
	local ring = Instance.new("Part")
	ring.Name = name
	ring.Material = Enum.Material.Glass
	ring.Color = RING_COLOR
	ring.Transparency = RING_TRANSPARENCY
	applyFXPartDefaults(ring)
	ring.Size = Vector3.new(1, 1, 1)
	ring.CFrame = CFrame.new(0, yOffset, 0) * CFrame.Angles(math.pi / 2, 0, 0)

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = TORUS_MESH_ID
	mesh.Scale = DOUBLE_JUMP_CONFIG.VFXStartScale * scaleRatio
	mesh.Parent = ring

	ring:SetAttribute("ScaleRatio", scaleRatio)
	ring:SetAttribute("SpinDegrees", spinDegrees)
	return ring
end

--- The tamed condensation puff: a single faint burst braked hard by Drag so
--- it hangs at the jump point instead of flying off as debris.
local function buildCloudEmitter(): ParticleEmitter
	local cloud = Instance.new("ParticleEmitter")
	cloud.Name = "CondensationCloud"
	cloud.Texture = CLOUD_TEXTURE
	cloud.Enabled = false -- burst-only: no continuous emission
	cloud.Rate = 0
	cloud.Lifetime = NumberRange.new(CLOUD_LIFETIME_SECONDS)
	cloud.Speed = NumberRange.new(15, 35)
	cloud.Drag = 12
	cloud.SpreadAngle = Vector2.new(180, 180) -- omnidirectional shockwave puff
	cloud.Rotation = NumberRange.new(0, 360)
	-- Static random orientation only: any spin while the puffs travel reads
	-- as churn instead of straight outward displacement.
	cloud.RotSpeed = NumberRange.new(0)
	cloud.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 8),
	})
	-- Present at spawn for the readable "PUFF", then a clean straight fade —
	-- the tuning war so far: 0.15 blobbed solid, 0.6 was imperceptible.
	cloud.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	cloud.LightEmission = 0.15
	return cloud
end

--- Generates the complete BespokeJumpFX assembly around the origin. Public
--- so Studio tooling can place an inspectable preview with the exact same
--- math the runtime uses.
function DoubleJumpFX.BuildAssembly(): Model
	local assembly = Instance.new("Model")
	assembly.Name = "BespokeJumpFX"

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Transparency = 1
	applyFXPartDefaults(core)
	core.Size = Vector3.new(0.5, 0.5, 0.5)
	core.CFrame = CFrame.identity
	buildCloudEmitter().Parent = core
	core.Parent = assembly
	assembly.PrimaryPart = core

	buildRing("InnerRing", INNER_RING_RATIO, RING_Y_OFFSET, INNER_RING_SPIN_DEGREES).Parent = assembly
	buildRing("OuterRing", 1, -RING_Y_OFFSET, OUTER_RING_SPIN_DEGREES).Parent = assembly

	return assembly
end

-- Template built lazily on the first burst, then cloned per burst — the
-- generation math runs once per client session.
local template: Model? = nil

local function getTemplate(): Model
	local current = template
	if current then
		return current
	end
	local built = DoubleJumpFX.BuildAssembly()
	template = built
	return built
end

--- Fires the full burst at the character's foot baseline: clones the
--- assembly, scales both rings outward with their micro-twist (Quad/Out)
--- while they dissolve on a linear ramp of the same duration, and emits the
--- single condensation puff. One Debris timer covers the whole clone.
function DoubleJumpFX.Burst(rootPart: BasePart, humanoid: Humanoid): ()
	-- Foot baseline, fully world-flattened: position-only, NO character
	-- rotation. The air-spread Disc emitter must fire perfectly flat in the
	-- world XZ plane, and the rings/cloud are radially symmetric so they
	-- never needed the yaw anyway. (HipHeight is measured from the BOTTOM of
	-- the root part, hence the half-height term — without it the burst
	-- hovers at the knees.)
	local rootPosition = rootPart.Position
	local baseCFrame = CFrame.new(
		rootPosition.X,
		rootPosition.Y - (humanoid.HipHeight + rootPart.Size.Y / 2),
		rootPosition.Z
	)

	-- Air-spread layer FIRST and outside the AllowMeshVFX gate below: the
	-- gate is the glass/mesh kill switch, and gating this particle layer as
	-- a side effect of its position was the one logic path that could kill
	-- the jump burst while the ungated dash exit burst kept working.
	-- pcall-isolated with a loud warn — failures here are never silent.
	if AirSpreadFX then
		local ok, err = pcall(AirSpreadFX.Burst, baseCFrame, DOUBLE_JUMP_CONFIG.AirSpread)
		if not ok then
			warn("[DoubleJumpFX] AirSpreadFX.Burst failed — ring burst unaffected: " .. tostring(err))
		else
			-- Diagnostic breadcrumb (DebugConfig.VerboseLogging): positive
			-- confirmation the air-spread hook fired on this jump frame with
			-- a config that passed sanitization.
			local verboseRaw: any = FeatureResolver.GetConfigField("DebugConfig", "VerboseLogging", false)
			if type(verboseRaw) == "boolean" and verboseRaw then
				print("[DoubleJumpFX] AirSpread burst fired at the foot baseline.")
			end
		end
	end

	-- Live-read like Dash's NegateGravity so the switch can be flipped at
	-- runtime without a rejoin. Gates only the glass assembly + cloud; the
	-- air-spread layer above stays, matching dash.
	local allowRaw: any = FeatureResolver.GetConfigField("DoubleJump", "AllowMeshVFX", true)
	if type(allowRaw) == "boolean" and not allowRaw then
		return
	end

	local assembly = getTemplate():Clone()
	assembly:PivotTo(baseCFrame)
	assembly.Parent = Workspace

	-- Quad/Out on the geometry: snappy but with enough readable frames for
	-- the eye to track the ring growing from the center outward —
	-- Quint/Exponential collapsed the expansion into a one-frame flash.
	local expandInfo = TweenInfo.new(
		DOUBLE_JUMP_CONFIG.VFXFadeSeconds,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	-- Linear on the dissolve: an Out-eased fade dumps most of the opacity in
	-- the first frames, killing the ring's presence mid-expansion; a straight
	-- 0.85 -> 1 ramp keeps it visible for the whole travel.
	local dissolveInfo = TweenInfo.new(DOUBLE_JUMP_CONFIG.VFXFadeSeconds, Enum.EasingStyle.Linear)

	for _, ringName in { "InnerRing", "OuterRing" } do
		local ring = assembly:FindFirstChild(ringName)
		if ring and ring:IsA("BasePart") then
			local ratioRaw = ring:GetAttribute("ScaleRatio")
			local scaleRatio = if type(ratioRaw) == "number" then ratioRaw else 1
			local spinRaw = ring:GetAttribute("SpinDegrees")
			local spinDegrees = if type(spinRaw) == "number" then spinRaw else 0

			local mesh = ring:FindFirstChildOfClass("SpecialMesh")
			if mesh then
				TweenService:Create(mesh, expandInfo, {
					Scale = DOUBLE_JUMP_CONFIG.VFXMaxScale * scaleRatio,
				}):Play()
			end
			-- Micro-twist about the ring's own normal (local Z after the 90°
			-- roll), riding the same eased clock as the expansion.
			TweenService:Create(ring, expandInfo, {
				CFrame = ring.CFrame * CFrame.Angles(0, 0, math.rad(spinDegrees)),
			}):Play()
			TweenService:Create(ring, dissolveInfo, {
				Transparency = 1,
			}):Play()
		end
	end

	local core = assembly:FindFirstChild("Core")
	if core then
		local cloud = core:FindFirstChild("CondensationCloud")
		if cloud and cloud:IsA("ParticleEmitter") then
			cloud:Emit(CLOUD_BURST_COUNT)
		end
	end

	Debris:AddItem(assembly, math.max(DOUBLE_JUMP_CONFIG.VFXFadeSeconds, CLOUD_LIFETIME_SECONDS))
end

return DoubleJumpFX
