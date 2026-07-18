--!strict
--@author OrkGabb
--@module DashFX.luau
--@version 1.0
-- Default dash presentation layer: dash animation, mobile dash button, and
-- the physics debug vectors. DashController owns input/charges/networking and
-- resolves this module optionally — deleting this file (or replacing it with
-- your own implementation of the same three functions) never touches the
-- dash backend.
--
-- Animation ids come from AssetRegistry.Animations.Dash (SSoT), selected by
-- FeatureToggles.GlobalFlags.Dash.ActiveAnimationKey.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)

local DashFX = {}

local function getAnimationId(key: string): string?
	local dashAnims = AssetRegistry.Animations.Dash
	local entry = dashAnims[key] or dashAnims.DashForward
	return if entry then entry.Id else nil
end

--- Plays the dash animation selected by `key` on the character's Animator.
function DashFX.PlayDashAnimation(humanoid: Humanoid, key: string): ()
	local animId = getAnimationId(key)
	if not animId then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	local animation = Instance.new("Animation")
	animation.AnimationId = animId
	local track = animator:LoadAnimation(animation)
	track:Play()
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
