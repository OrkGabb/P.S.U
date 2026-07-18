--!strict
--@author OrkGabb
--@module DashFX.luau
--@version 2.0
-- Default dash presentation layer, fully procedural — no keyframe assets.
-- Drives three effects:
--   * Body lean: tweens the rig's core Motor6D C0s (R6 RootJoint / R15 Root,
--     plus a scaled R15 Waist assist) so the avatar inclines into the dash
--     direction, then returns to the recorded baseline when the dash ends.
--   * Camera juice: expands Camera.FieldOfView at the peak of the impulse and
--     eases it back to the original FOV as the velocity attenuates.
--   * Mobile dash button + physics debug vectors (utility surface).
--
-- DashController owns input/charges/networking/physics and resolves this
-- module optionally — deleting this file (or replacing it with your own
-- implementation of the same surface) never touches the dash backend.
--
-- Contract:
--   Begin(character, worldDirection) — capture baselines, tween into the lean.
--   Release(character)               — smooth return to baseline (graceful end).
--   Cancel(character)                — instant baseline restore (death/stun/interrupt).
--
-- All tunables come from Shared/Config/MovementRegistry (SSoT).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local MovementRegistry = require(ReplicatedStorage.Shared.Config.MovementRegistry)

local LEAN_CONFIG = MovementRegistry.Dash.Lean
local CAMERA_CONFIG = MovementRegistry.Dash.Camera

local DashFX = {}

type LeanJoint = {
	motor: Motor6D,
	baseC0: CFrame,
	scale: number,
}

type FXState = {
	character: Model,
	joints: { LeanJoint },
	baseFov: number,
	tweens: { Tween },
	generation: number,
}

-- Single active record: DashFX runs on the local player's character only.
-- Baselines persist across chained dashes so a dash that starts during the
-- previous dash's return tween never captures a mid-tween pose as "default".
local activeState: FXState? = nil

local function cancelTweens(state: FXState): ()
	for _, tween in state.tweens do
		tween:Cancel()
	end
	table.clear(state.tweens)
end

--- Instantly snaps every touched joint and the camera back to baseline.
local function restoreInstantly(state: FXState): ()
	cancelTweens(state)
	for _, joint in state.joints do
		if joint.motor.Parent then
			joint.motor.C0 = joint.baseC0
		end
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera.FieldOfView = state.baseFov
	end
end

--- Collects the rig's core joints: R6 RootJoint, R15 Root, and (scaled) R15
--- Waist. Missing joints are simply skipped, so both rig types work.
local function collectLeanJoints(character: Model): { LeanJoint }
	local joints: { LeanJoint } = {}

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		local rootJoint = rootPart:FindFirstChild("RootJoint") -- R6
		if rootJoint and rootJoint:IsA("Motor6D") then
			table.insert(joints, { motor = rootJoint, baseC0 = rootJoint.C0, scale = 1 })
		end
	end

	local lowerTorso = character:FindFirstChild("LowerTorso") -- R15
	if lowerTorso then
		local root = lowerTorso:FindFirstChild("Root")
		if root and root:IsA("Motor6D") then
			table.insert(joints, { motor = root, baseC0 = root.C0, scale = 1 })
		end
	end

	local upperTorso = character:FindFirstChild("UpperTorso") -- R15 secondary bend
	if upperTorso and LEAN_CONFIG.WaistScale > 0 then
		local waist = upperTorso:FindFirstChild("Waist")
		if waist and waist:IsA("Motor6D") then
			table.insert(joints, { motor = waist, baseC0 = waist.C0, scale = LEAN_CONFIG.WaistScale })
		end
	end

	return joints
end

--- Starts the procedural lean + FOV push for a dash along `worldDirection`.
function DashFX.Begin(character: Model, worldDirection: Vector3): ()
	local previous = activeState
	if previous then
		if previous.character == character then
			-- Chained dash: keep the recorded baselines, drop in-flight tweens.
			cancelTweens(previous)
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
		state = {
			character = character,
			joints = collectLeanJoints(character),
			baseFov = camera.FieldOfView,
			tweens = {},
			generation = 0,
		}
		activeState = state
	end
	state.generation += 1

	-- Character-space dash direction: -Z is forward, +X is right.
	local localDirection = rootPart.CFrame:VectorToObjectSpace(worldDirection)
	local forwardAmount = math.clamp(-localDirection.Z, -1, 1)
	local sideAmount = math.clamp(localDirection.X, -1, 1)

	local leanInfo = TweenInfo.new(LEAN_CONFIG.EaseInSeconds, LEAN_CONFIG.EasingStyle, LEAN_CONFIG.EasingDirection)
	for _, joint in state.joints do
		if not joint.motor.Parent then
			continue
		end
		local pitch = math.rad(-LEAN_CONFIG.ForwardAngleDegrees * forwardAmount * joint.scale)
		local roll = math.rad(-LEAN_CONFIG.SideAngleDegrees * sideAmount * joint.scale)
		-- Pre-multiplying keeps the lean in the parent part's character-aligned
		-- frame, so the same math holds for R6 and R15 joint spaces.
		local goalC0 = CFrame.Angles(pitch, 0, roll) * joint.baseC0
		local tween = TweenService:Create(joint.motor, leanInfo, { C0 = goalC0 })
		tween:Play()
		table.insert(state.tweens, tween)
	end

	local fovInfo = TweenInfo.new(CAMERA_CONFIG.EaseInSeconds, CAMERA_CONFIG.EasingStyle, CAMERA_CONFIG.EasingDirection)
	local fovTween = TweenService:Create(camera, fovInfo, { FieldOfView = state.baseFov + CAMERA_CONFIG.FovBoost })
	fovTween:Play()
	table.insert(state.tweens, fovTween)
end

--- Graceful end: eases every joint and the camera back to baseline as the
--- dash velocity attenuates, then drops the record once the tweens land.
function DashFX.Release(character: Model): ()
	local current = activeState
	if not current or current.character ~= character then
		return
	end
	local state: FXState = current
	cancelTweens(state)
	local generation = state.generation

	local leanInfo = TweenInfo.new(LEAN_CONFIG.EaseOutSeconds, LEAN_CONFIG.EasingStyle, LEAN_CONFIG.EasingDirection)
	for _, joint in state.joints do
		if not joint.motor.Parent then
			continue
		end
		local tween = TweenService:Create(joint.motor, leanInfo, { C0 = joint.baseC0 })
		tween:Play()
		table.insert(state.tweens, tween)
	end

	local camera = Workspace.CurrentCamera
	if camera then
		local fovInfo = TweenInfo.new(CAMERA_CONFIG.EaseOutSeconds, CAMERA_CONFIG.EasingStyle, CAMERA_CONFIG.EasingDirection)
		local fovTween = TweenService:Create(camera, fovInfo, { FieldOfView = state.baseFov })
		fovTween:Play()
		table.insert(state.tweens, fovTween)
	end

	-- Clear the record after the longest return tween; a chained Begin bumps
	-- the generation (and Cancel nils the record), voiding this cleanup.
	local settleSeconds = math.max(LEAN_CONFIG.EaseOutSeconds, CAMERA_CONFIG.EaseOutSeconds)
	task.delay(settleSeconds, function()
		if activeState == state and state.generation == generation then
			activeState = nil
		end
	end)
end

--- Interruption path (death, stun, forced cancel): instant baseline restore so
--- the avatar is never left tilted and the camera never stuck zoomed.
function DashFX.Cancel(character: Model): ()
	local state = activeState
	if not state or state.character ~= character then
		return
	end
	restoreInstantly(state)
	activeState = nil
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
