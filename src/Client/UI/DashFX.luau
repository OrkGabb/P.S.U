--!strict
--@author OrkGabb
--@module DashFX.luau
--@version 3.6
-- Default dash presentation layer, fully procedural — no keyframe assets.
-- Drives four effects:
--   * Glide pose: a RunService.PreSimulation loop that runs after the default
--     Animate script has evaluated, giving this module final authority over
--     the controlled joints — Motor6Ds on classic rigs (driven via C0 plus
--     Transform neutralization), Bones on skinned-mesh rigs, and
--     AnimationConstraints on physics-driven rigs (both driven via their
--     Transform). At dash start the default Animate script is disabled so no
--     new tracks can start mid-dash (jump/fall state changes included), and
--     the currently playing tracks are faded out once — limbs blend to the
--     rest pose and glide cleanly instead of locking mid-stride — while the
--     loop tilts the root joint into the dash direction, pins both arms
--     behind the back about the character's world axes, and blends the joint
--     Transforms so the configured pose lands exactly — the sharp
--     "ninja-glide" aerodynamic silhouette. On release the Animate script is
--     re-enabled; it restarts from the top and resumes locomotion on its own.
--   * Wind trail: cone ParticleEmitters attached to the arms (R6 arms / R15
--     upper arms; HumanoidRootPart fallback for rigs with no arm parts),
--     re-aimed opposite the dash in world space every frame so the bright
--     wisps stream along the sides of the torso — the wind-cutting effect.
--   * Camera juice: expands Camera.FieldOfView at the peak of the impulse and
--     eases it back to the original FOV as the velocity attenuates.
--   * Mobile dash button + physics debug vectors (utility surface).
--
-- DashController owns input/charges/networking/physics and resolves this
-- module optionally — deleting this file (or replacing it with your own
-- implementation of the same surface) never touches the dash backend.
--
-- Contract:
--   Begin(character, worldDirection) — capture baselines, blend into the pose.
--   Release(character)               — blend back to baseline (graceful end).
--   Cancel(character)                — interruption (death/stun/forced): blends
--                                      back to baseline exactly like Release,
--                                      so the avatar never pops mid-frame.
--
-- Known limitation: disabling Animate alone does NOT stop tracks that are
-- already playing (they would keep looping unmanaged), which is why Begin
-- also fades out the playing tracks once right after disabling the script.
-- Re-enabling a LocalScript restarts it from the top, so locomotion resumes
-- through Animate's own state evaluation — no track bookkeeping needed.
--
-- Axis handling: pose rotations are authored in WORLD axes relative to the
-- character's facing (lean and arm pin about the root's right vector, side
-- roll about its look vector), then conjugated into each joint's authored
-- local frame at Begin — Part0×C0 rotation for Motor6Ds, rest world rotation
-- for Bones, Attachment0 world rotation for AnimationConstraints. No
-- hardcoded local hinge axes and no per-rig sign flips: behavior is uniform
-- regardless of how the rig's local axes were authored in external modeling
-- software, and the conjugation reproduces the classic R6/R15 hinge math
-- exactly on standard rigs.
--
-- All tunables come from Shared/Config/MovementRegistry (SSoT).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local MovementRegistry = require(ReplicatedStorage.Shared.Config.MovementRegistry)

local LEAN_CONFIG = MovementRegistry.Dash.Lean
local CAMERA_CONFIG = MovementRegistry.Dash.Camera
local TRAIL_CONFIG = MovementRegistry.Dash.Trail

local IDENTITY = CFrame.identity

-- Parts the wind emitters attach to, in preference order (R6 arms, R15 upper
-- arms). Whichever of these exist on the rig get an emitter each.
local TRAIL_PARENT_NAMES = { "Left Arm", "Right Arm", "LeftUpperArm", "RightUpperArm" }

local DashFX = {}

-- Exactly one of `motor`/`bone`/`animConstraint` is set per joint: classic
-- rigs are driven through Motor6D.C0 (+ Transform neutralization); skinned
-- and physics-driven rigs through Bone.Transform / AnimationConstraint
-- Transform. The Animator writes all three the same way each frame, so the
-- same PreSimulation authority model covers every driver.
type PoseJoint = {
	motor: Motor6D?,
	bone: Bone?,
	animConstraint: AnimationConstraint?,
	-- Pristine C0 baseline (Motor6D driver only; identity for bones).
	baseC0: CFrame,
	-- Builds this joint's target rotation in WORLD axes from the character's
	-- current facing and the dash direction amounts.
	computeWorldRotation: (rootRotation: CFrame, forwardAmount: number, sideAmount: number) -> CFrame,
	-- World rotation conjugated into this joint's local frame at Begin —
	-- the offset when the pose is fully applied.
	dashOffset: CFrame,
	-- Offset in effect when the current phase started (blend origin).
	fromOffset: CFrame,
	-- Offset applied on the most recent frame (blend continuity for chained
	-- dashes and early releases).
	currentOffset: CFrame,
}

type TrailPoint = {
	attachment: Attachment,
	emitter: ParticleEmitter,
}

-- In: blending from the captured pose into the glide pose.
-- Hold: glide pose fully applied, waiting for Release.
-- Out: blending back to baseline; the loop retires itself when it lands.
type Phase = "In" | "Hold" | "Out"

type FXState = {
	character: Model,
	animator: Animator?,
	joints: { PoseJoint },
	-- The default Animate LocalScript, captured only when Begin disabled it,
	-- so the exit paths re-enable exactly what was turned off.
	animateScript: LocalScript?,
	baseFov: number,
	fovTween: Tween?,
	phase: Phase,
	phaseElapsed: number,
	-- Authority over the Animator's Transform writes: 0 = animation-driven,
	-- 1 = fully procedural. Eased up during In, down during Out.
	weight: number,
	fromWeight: number,
	stepConnection: RBXScriptConnection?,
	trailPoints: { TrailPoint },
	-- Horizontal world-space dash direction; the emission cones aim opposite
	-- this every frame. Always overwritten in Begin before first use.
	dashWorldDirection: Vector3,
}

-- Single active record: DashFX runs on the local player's character only.
-- Baselines persist across chained dashes so a dash that starts during the
-- previous dash's blend-out never captures a mid-blend pose as "default".
local activeState: FXState? = nil

--- Collects the rig's controlled joints by NAME from a single descendant
--- sweep of the character, deliberately ignoring parent paths: hardcoded
--- parenting assumptions proved brittle live. Joints are matched by class in
--- preference order Motor6D > Bone > AnimationConstraint under the same
--- joint names (this game's characters carry AnimationConstraints named
--- Root/Waist/LeftShoulder/RightShoulder — established via the one-shot
--- descendant dump). Missing joints are simply skipped, so classic, skinned,
--- and physics-driven rigs all work.
local function collectPoseJoints(character: Model): { PoseJoint }
	local joints: { PoseJoint } = {}

	-- First instance seen per name wins; rig joint names are unique in
	-- practice (accessory attachments use Welds, not rig joints).
	local motorsByName: { [string]: Motor6D } = {}
	local bonesByName: { [string]: Bone } = {}
	local animConstraintsByName: { [string]: AnimationConstraint } = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and not motorsByName[descendant.Name] then
			motorsByName[descendant.Name] = descendant
		elseif descendant:IsA("Bone") and not bonesByName[descendant.Name] then
			bonesByName[descendant.Name] = descendant
		elseif descendant:IsA("AnimationConstraint") and not animConstraintsByName[descendant.Name] then
			animConstraintsByName[descendant.Name] = descendant
		end
	end

	local function add(jointName: string, computeWorldRotation: (CFrame, number, number) -> CFrame): ()
		local motor = motorsByName[jointName]
		local bone: Bone? = if motor then nil else bonesByName[jointName]
		local animConstraint: AnimationConstraint? = if motor or bone then nil else animConstraintsByName[jointName]
		if not motor and not bone and not animConstraint then
			return
		end
		table.insert(joints, {
			motor = motor,
			bone = bone,
			animConstraint = animConstraint,
			baseC0 = if motor then motor.C0 else IDENTITY,
			computeWorldRotation = computeWorldRotation,
			dashOffset = IDENTITY,
			fromOffset = IDENTITY,
			currentOffset = IDENTITY,
		})
	end

	-- World-axis lean: pitch into the dash about the character's right
	-- vector, roll into sideways dashes about its look vector. Negative pitch
	-- tips the torso forward.
	local function rootLean(scale: number): (CFrame, number, number) -> CFrame
		return function(rootRotation: CFrame, forwardAmount: number, sideAmount: number): CFrame
			local pitch = -math.rad(LEAN_CONFIG.ForwardAngleDegrees * forwardAmount * scale)
			local roll = math.rad(LEAN_CONFIG.SideAngleDegrees * sideAmount * scale)
			return CFrame.fromAxisAngle(rootRotation.RightVector, pitch)
				* CFrame.fromAxisAngle(rootRotation.LookVector, roll)
		end
	end

	-- World-axis arm pin: swing the arm backward about the character's right
	-- vector, regardless of dash direction or which side the arm is on — the
	-- per-joint conjugation at Begin handles every rig's local axes.
	local function armPin(rootRotation: CFrame, _forwardAmount: number, _sideAmount: number): CFrame
		return CFrame.fromAxisAngle(rootRotation.RightVector, -math.rad(LEAN_CONFIG.ArmPitchDegrees))
	end

	add("RootJoint", rootLean(1)) -- R6 root
	add("Root", rootLean(1)) -- R15 root (LowerTorso)
	if LEAN_CONFIG.WaistScale > 0 then
		add("Waist", rootLean(LEAN_CONFIG.WaistScale)) -- R15 secondary bend
	end

	if LEAN_CONFIG.ArmPitchDegrees > 0 then
		add("Left Shoulder", armPin) -- R6
		add("Right Shoulder", armPin) -- R6
		add("LeftShoulder", armPin) -- R15 / bone / constraint rigs
		add("RightShoulder", armPin) -- R15 / bone / constraint rigs
	end

	return joints
end

--- The world rotation of the frame a joint's offset is expressed in, used to
--- conjugate world-axis pose rotations into that joint's local space:
--- Motor6D offsets post-multiply C0 (frame = Part0 × C0 rotation), Bone
--- Transforms apply in the bone's rest frame, AnimationConstraint Transforms
--- in Attachment0's frame. Falls back to the root's rotation when a frame
--- can't be resolved.
local function jointFrameRotation(joint: PoseJoint, rootPart: BasePart): CFrame
	local motor = joint.motor
	if motor then
		local part0 = motor.Part0
		local partRotation = if part0 then part0.CFrame.Rotation else rootPart.CFrame.Rotation
		return partRotation * joint.baseC0.Rotation
	end
	local bone = joint.bone
	if bone then
		return bone.WorldCFrame.Rotation
	end
	local animConstraint = joint.animConstraint
	if animConstraint then
		local attachment0 = animConstraint.Attachment0
		if attachment0 then
			return attachment0.WorldCFrame.Rotation
		end
	end
	return rootPart.CFrame.Rotation
end

--- Freezes locomotion for the glide: disables the default Animate script so
--- no new tracks can start mid-dash (jump/fall state changes included — this
--- is what ends the mid-air fight over the Animator), then fades out the
--- tracks playing right now. Disabling alone is not enough: already-playing
--- tracks would keep looping unmanaged.
local function freezeLocomotion(state: FXState): ()
	local animate = state.character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") and not animate.Disabled then
		animate.Disabled = true
		state.animateScript = animate
	end
	local animator = state.animator
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(LEAN_CONFIG.AnimationFadeSeconds)
		end
	end
end

--- Hands locomotion back to the default Animate script. Re-enabling a
--- LocalScript restarts it from the top, so Animate re-evaluates the
--- humanoid state and plays the right animation on its own — no track
--- bookkeeping needed. Only touches the script when Begin was the one that
--- disabled it (a rig intentionally running without Animate stays that way).
local function enableAnimate(state: FXState): ()
	local animate = state.animateScript
	if animate and animate.Parent then
		animate.Disabled = false
	end
	state.animateScript = nil
end

--- Smoothstep-sampled fade from TransparencyStart to TransparencyEnd: the
--- wisp stays visible early, then eases out and lands on full fade with zero
--- slope — no pop-out at the end of its lifetime.
local function buildTransparencySequence(): NumberSequence
	local startValue = TRAIL_CONFIG.TransparencyStart
	local endValue = TRAIL_CONFIG.TransparencyEnd
	local keypoints: { NumberSequenceKeypoint } = {}
	local samples = 5
	for index = 0, samples - 1 do
		local t = index / (samples - 1)
		local smooth = t * t * (3 - 2 * t)
		table.insert(keypoints, NumberSequenceKeypoint.new(t, startValue + (endValue - startValue) * smooth))
	end
	return NumberSequence.new(keypoints)
end

--- Builds one wind emitter under `parent`, aimed by orientTrail each frame.
local function createTrailPoint(parent: BasePart): TrailPoint
	local attachment = Instance.new("Attachment")
	attachment.Name = "DashWindAttachment"

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DashWindEmitter"
	emitter.Texture = TRAIL_CONFIG.Texture
	emitter.Rate = TRAIL_CONFIG.EmitRate
	-- Explicit white + self-illumination: reads as clean bright wind rather
	-- than scene-lit gray smoke.
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1))
	emitter.LightEmission = TRAIL_CONFIG.LightEmission
	emitter.LightInfluence = TRAIL_CONFIG.LightInfluence
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, TRAIL_CONFIG.SizeStart),
		NumberSequenceKeypoint.new(1, TRAIL_CONFIG.SizeEnd),
	})
	emitter.Transparency = buildTransparencySequence()
	emitter.Lifetime = NumberRange.new(TRAIL_CONFIG.LifetimeMin, TRAIL_CONFIG.LifetimeMax)
	emitter.Speed = NumberRange.new(TRAIL_CONFIG.SpeedMin, TRAIL_CONFIG.SpeedMax)
	emitter.SpreadAngle = Vector2.new(TRAIL_CONFIG.SpreadAngleDegrees, TRAIL_CONFIG.SpreadAngleDegrees)
	-- Front = the attachment's -Z face; orientTrail keeps that face pointed
	-- opposite the dash so the wisps stream behind the character.
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Parent = attachment

	attachment.Parent = parent
	return { attachment = attachment, emitter = emitter }
end

--- Creates (or re-uses, for chained dashes) one wind emitter per arm so the
--- trail cuts along the sides of the torso instead of the character's rear.
--- Rigs with no matching arm parts fall back to the HumanoidRootPart.
local function ensureTrail(state: FXState): ()
	local points = state.trailPoints
	local intact = #points > 0
	for _, point in points do
		if not point.attachment.Parent or not point.emitter.Parent then
			intact = false
			break
		end
	end

	if not intact then
		for _, point in points do
			point.attachment:Destroy()
		end
		table.clear(points)

		local character = state.character
		for _, partName in TRAIL_PARENT_NAMES do
			local part = character:FindFirstChild(partName)
			if part and part:IsA("BasePart") then
				table.insert(points, createTrailPoint(part))
			end
		end
		if #points == 0 then
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if rootPart and rootPart:IsA("BasePart") then
				table.insert(points, createTrailPoint(rootPart))
			end
		end
	end

	for _, point in points do
		point.emitter.Enabled = true
	end
end

--- Keeps every emission cone aimed opposite the dash in WORLD space. Runs
--- every frame because the arms carrying the attachments swing backward into
--- the pinned pose — a static local orientation would drift with them.
local function orientTrail(state: FXState): ()
	for _, point in state.trailPoints do
		local attachment = point.attachment
		if attachment.Parent then
			local position = attachment.WorldPosition
			attachment.WorldCFrame = CFrame.lookAt(position, position - state.dashWorldDirection)
		end
	end
end

--- Stops emission and schedules destruction after the last particle has died.
--- Already-emitted wisps fade out naturally instead of popping.
local function releaseTrail(state: FXState): ()
	for _, point in state.trailPoints do
		if point.emitter.Parent then
			point.emitter.Enabled = false
		end
		if point.attachment.Parent then
			Debris:AddItem(point.attachment, TRAIL_CONFIG.LifetimeMax)
		else
			point.attachment:Destroy()
		end
	end
	table.clear(state.trailPoints)
end

--- Drops the record once BOTH exits have settled: the pose loop has landed on
--- baseline (stepConnection nil) and the FOV return tween is no longer
--- playing. Called from whichever of the two finishes last. A chained Begin
--- flips the phase back to "In" and reconnects the loop, voiding this.
local function tryRetireState(state: FXState): ()
	if activeState ~= state then
		return
	end
	if state.phase ~= "Out" or state.stepConnection then
		return
	end
	local fovTween = state.fovTween
	if fovTween and fovTween.PlaybackState == Enum.PlaybackState.Playing then
		return
	end
	activeState = nil
end

--- Hard reset: disconnects the loop and snaps every touched joint, the
--- stopped animations, the camera, and the trail back to baseline instantly.
--- Reserved for the one case a blend is impossible — a stale record from a
--- previous character discovered on respawn. Live interruptions blend out
--- through beginOutPhase instead.
local function restoreInstantly(state: FXState): ()
	if state.stepConnection then
		state.stepConnection:Disconnect()
		state.stepConnection = nil
	end
	if state.fovTween then
		state.fovTween:Cancel()
		state.fovTween = nil
	end
	enableAnimate(state)
	releaseTrail(state)
	for _, joint in state.joints do
		local motor = joint.motor
		if motor and motor.Parent then
			motor.C0 = joint.baseC0
		end
		local bone = joint.bone
		if bone and bone.Parent then
			-- Identity Transform = the rig's authored rest pose; playing
			-- animations overwrite it again on the very next frame.
			bone.Transform = IDENTITY
		end
		local animConstraint = joint.animConstraint
		if animConstraint and animConstraint.Parent then
			animConstraint.Transform = IDENTITY
		end
		joint.currentOffset = IDENTITY
		joint.fromOffset = IDENTITY
	end
	state.weight = 0
	state.fromWeight = 0
	local camera = Workspace.CurrentCamera
	if camera then
		camera.FieldOfView = state.baseFov
	end
end

--- Graceful landing of the Out phase: exact baseline C0s and identity bone
--- Transforms, loop disconnected, authority already at zero so the Animator
--- owns the joints again.
local function retireJoints(state: FXState): ()
	if state.stepConnection then
		state.stepConnection:Disconnect()
		state.stepConnection = nil
	end
	for _, joint in state.joints do
		local motor = joint.motor
		if motor and motor.Parent then
			motor.C0 = joint.baseC0
		end
		local bone = joint.bone
		if bone and bone.Parent then
			-- Identity Transform = the rig's authored rest pose; playing
			-- animations overwrite it again on the very next frame.
			bone.Transform = IDENTITY
		end
		local animConstraint = joint.animConstraint
		if animConstraint and animConstraint.Parent then
			animConstraint.Transform = IDENTITY
		end
		joint.currentOffset = IDENTITY
		joint.fromOffset = IDENTITY
	end
	state.weight = 0
	state.fromWeight = 0
	tryRetireState(state)
end

--- Transitions the record into the Out phase: the pose lerps from wherever it
--- currently is back to the saved baselines over Lean.EaseOutSeconds, the
--- Animate script is re-enabled (locomotion fades back in on its own), the
--- trail stops emitting, and the camera eases home. Shared by Release
--- (graceful end) and Cancel (interruption) — both exits blend; nothing ever
--- snaps.
local function beginOutPhase(state: FXState): ()
	state.phase = "Out"
	state.phaseElapsed = 0
	state.fromWeight = state.weight
	for _, joint in state.joints do
		joint.fromOffset = joint.currentOffset
	end

	enableAnimate(state)
	releaseTrail(state)

	if state.fovTween then
		state.fovTween:Cancel()
		state.fovTween = nil
	end
	local camera = Workspace.CurrentCamera
	if camera then
		local fovInfo = TweenInfo.new(CAMERA_CONFIG.EaseOutSeconds, CAMERA_CONFIG.EasingStyle, CAMERA_CONFIG.EasingDirection)
		local fovTween = TweenService:Create(camera, fovInfo, { FieldOfView = state.baseFov })
		state.fovTween = fovTween
		fovTween.Completed:Once(function()
			tryRetireState(state)
		end)
		fovTween:Play()
	end
end

--- Per-frame pose driver, bound to RunService.PreSimulation for the whole
--- dash. PreSimulation fires after the Animator has written this frame's
--- animation pose into each Motor6D.Transform, so writes made here are the
--- final word on the joints before physics and rendering see them.
local function step(state: FXState, deltaTime: number): ()
	state.phaseElapsed += deltaTime

	local outward = state.phase == "Out"
	local eased: number
	if state.phase == "Hold" then
		eased = 1
	else
		-- Zero-division safety: a zero (or negative) configured lerp window
		-- degrades to an instant blend (progress 1) instead of dividing.
		local duration = if outward then LEAN_CONFIG.EaseOutSeconds else LEAN_CONFIG.EaseInSeconds
		local progress = if duration > 0 then math.min(state.phaseElapsed / duration, 1) else 1
		eased = TweenService:GetValue(progress, LEAN_CONFIG.EasingStyle, LEAN_CONFIG.EasingDirection)
		if progress >= 1 then
			if outward then
				retireJoints(state)
				return
			end
			state.phase = "Hold"
			eased = 1
		end
	end

	local weightTarget = if outward then 0 else 1
	state.weight = state.fromWeight + (weightTarget - state.fromWeight) * eased

	if not outward then
		orientTrail(state)
	end

	for _, joint in state.joints do
		local targetOffset = if outward then IDENTITY else joint.dashOffset
		joint.currentOffset = joint.fromOffset:Lerp(targetOffset, eased)
		local motor = joint.motor
		local bone = joint.bone
		if motor and motor.Parent then
			-- Post-multiplying rotates the child about the joint's anchor in
			-- the C0 frame; the offset was conjugated into that frame at
			-- Begin, so this holds for roots and shoulders on every rig.
			motor.C0 = joint.baseC0 * joint.currentOffset
			-- Scale this frame's Animator output toward identity by the
			-- authority weight: at 1 the configured pose lands exactly; while
			-- blending, residual animation mixes in for a soft hand-off.
			motor.Transform = motor.Transform:Lerp(IDENTITY, state.weight)
		elseif bone and bone.Parent then
			-- Bone driver: Transform IS the local pose offset. Blending from
			-- this frame's Animator write toward our offset by the authority
			-- weight gives the same soft hand-off as the Motor6D path.
			bone.Transform = bone.Transform:Lerp(joint.currentOffset, state.weight)
		else
			local animConstraint = joint.animConstraint
			if animConstraint and animConstraint.Parent then
				-- AnimationConstraint driver: same authority model — Transform
				-- is the target relative transform the constraint drives the
				-- attachments toward, written by the Animator when tracks play.
				animConstraint.Transform = animConstraint.Transform:Lerp(joint.currentOffset, state.weight)
			end
		end
	end
end

--- Starts the procedural glide pose, wind trail, and FOV push for a dash
--- along `worldDirection`.
function DashFX.Begin(character: Model, worldDirection: Vector3): ()
	local previous = activeState
	if previous then
		if previous.character == character then
			-- Chained dash: keep the recorded baselines; the loop blends from
			-- whatever pose it is currently in, so there is never a pop.
			if previous.fovTween then
				previous.fovTween:Cancel()
				previous.fovTween = nil
			end
		else
			-- Stale record from a previous character (respawn): hard-reset it.
			restoreInstantly(previous)
			activeState = nil
			previous = nil
		end
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local state: FXState
	if previous then
		state = previous
	else
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		state = {
			character = character,
			animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil,
			joints = collectPoseJoints(character),
			animateScript = nil,
			baseFov = camera.FieldOfView,
			fovTween = nil,
			phase = "In",
			phaseElapsed = 0,
			weight = 0,
			fromWeight = 0,
			stepConnection = nil,
			trailPoints = {},
			dashWorldDirection = Vector3.zAxis,
		}
		activeState = state

		-- Diagnostic breadcrumb: an empty sweep means the rig carries no
		-- Motor6Ds, Bones, or AnimationConstraints under the expected joint
		-- names, which would otherwise silently disable the pose while the
		-- trail and camera keep working.
		if #state.joints == 0 then
			warn("[DashFX] No controllable Motor6D, Bone, or AnimationConstraint joints found on this rig — glide pose disabled (trail/camera unaffected).")
		end
	end

	-- Character-space dash direction: -Z is forward, +X is right.
	local localDirection = rootPart.CFrame:VectorToObjectSpace(worldDirection)
	local forwardAmount = math.clamp(-localDirection.Z, -1, 1)
	local sideAmount = math.clamp(localDirection.X, -1, 1)

	state.phase = "In"
	state.phaseElapsed = 0
	state.fromWeight = state.weight
	-- Author each joint's rotation in world axes, then conjugate it into the
	-- joint's own frame — correct on any rig without per-rig axis knowledge.
	local rootRotation = rootPart.CFrame.Rotation
	for _, joint in state.joints do
		local worldRotation = joint.computeWorldRotation(rootRotation, forwardAmount, sideAmount)
		local frame = jointFrameRotation(joint, rootPart)
		joint.dashOffset = frame:Inverse() * worldRotation * frame
		joint.fromOffset = joint.currentOffset
	end

	freezeLocomotion(state)

	-- The dash is planar, so this can only degenerate on a malformed caller;
	-- fall back to the facing direction rather than a zero axis.
	local flatWorld = Vector3.new(worldDirection.X, 0, worldDirection.Z)
	state.dashWorldDirection = if flatWorld.Magnitude > 0.001 then flatWorld.Unit else rootPart.CFrame.LookVector
	ensureTrail(state)
	orientTrail(state)

	if not state.stepConnection then
		state.stepConnection = RunService.PreSimulation:Connect(function(deltaTime: number)
			step(state, deltaTime)
		end)
	end

	local fovInfo = TweenInfo.new(CAMERA_CONFIG.EaseInSeconds, CAMERA_CONFIG.EasingStyle, CAMERA_CONFIG.EasingDirection)
	local fovTween = TweenService:Create(camera, fovInfo, { FieldOfView = state.baseFov + CAMERA_CONFIG.FovBoost })
	state.fovTween = fovTween
	fovTween:Play()
end

--- Graceful end: lerps the pose back to the saved C0 baselines as the dash
--- velocity attenuates, resumes the looping animations, stops the wind trail,
--- and eases the camera home. The loop retires the record once everything has
--- settled.
function DashFX.Release(character: Model): ()
	local state = activeState
	if not state or state.character ~= character then
		return
	end
	beginOutPhase(state)
end

--- Interruption path (death, stun, forced cancel): identical smooth blend
--- back to the saved C0 baselines — the avatar is never left posed and never
--- pops, the animations resume (unless dead), and the camera eases home.
function DashFX.Cancel(character: Model): ()
	local state = activeState
	if not state or state.character ~= character then
		return
	end
	beginOutPhase(state)
end

--- Debug visualization: red origin ring + green direction vector, auto-cleaned.
function DashFX.DrawPhysicsVectors(origin: Vector3, direction: Vector3): ()
	local ring = Instance.new("Part")
	ring.Name = "DashDebugRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.5, 4, 4)
	ring.Color = Color3.fromRGB(255, 0, 0)
	ring.Material = Enum.Material.Neon
	ring.Anchored = true
	ring.CanCollide = false
	ring.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = Workspace
	Debris:AddItem(ring, 1)

	local line = Instance.new("Part")
	line.Name = "DashDebugVector"
	line.Anchored = true
	line.CanCollide = false
	line.Material = Enum.Material.Neon
	line.Color = Color3.fromRGB(0, 255, 0)

	local distance = direction.Magnitude
	line.Size = Vector3.new(0.2, 0.2, distance)
	line.CFrame = CFrame.lookAt(origin + direction / 2, origin + direction)
	line.Parent = Workspace
	Debris:AddItem(line, 1)
end

--- Builds the touch-screen dash button and wires it to `onActivate`.
function DashFX.BuildMobileButton(playerGui: PlayerGui, onActivate: () -> ()): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MobileDashUI"
	screenGui.ResetOnSpawn = false

	local dashButton = Instance.new("TextButton")
	dashButton.Name = "DashButton"
	dashButton.Size = UDim2.fromScale(0.15, 0.15)
	dashButton.Position = UDim2.fromScale(0.8, 0.6)
	dashButton.AnchorPoint = Vector2.new(0.5, 0.5)
	dashButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	dashButton.BackgroundTransparency = 0.5
	dashButton.Text = "DASH"
	dashButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	dashButton.TextScaled = true
	dashButton.Parent = screenGui

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0.5, 0)
	uiCorner.Parent = dashButton

	-- Prevents UI warping by keeping absolute aspect ratio
	local aspectRatio = Instance.new("UIAspectRatioConstraint")
	aspectRatio.AspectRatio = 1
	aspectRatio.Parent = dashButton

	dashButton.Activated:Connect(onActivate)

	screenGui.Parent = playerGui
	return screenGui
end

return DashFX
