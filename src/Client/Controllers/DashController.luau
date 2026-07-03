--!strict
--@author OrkGabb
--@module DashController.luau
--@version 1.0
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

-- Treat the rest of the codebase as fixed external context
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver"))
local DebugUtility = require(Shared:WaitForChild("Modules"):WaitForChild("DebugUtility")) :: any

local LocalPlayer: Player = Players.LocalPlayer
local dashRequestEvent: RemoteEvent? = nil

local DashController = {}

-- Animation Resolution Registry
local activeAnimations: {[string]: string} = {
	DashForward = "rbxassetid://5989939664",
	DashAlternative = "rbxassetid://3084314259",
}

local isDashing: boolean = false
local lastDashTime: number = 0
local currentChargesRaw: any = FeatureResolver.GetConfigField("Dash", "MaxCharges", 3)
local currentCharges: number = type(currentChargesRaw) == "number" and currentChargesRaw or 3

-- Resolves the dash animation based on configuration
local function getAnimationId(): string
	local keyRaw: any = FeatureResolver.GetConfigField("Dash", "ActiveAnimationKey", "DashForward")
	local key: string = type(keyRaw) == "string" and keyRaw or "DashForward"
	return activeAnimations[key] or activeAnimations.DashForward
end

-- Debug Vector Visualizations
local function drawPhysicsVectors(origin: Vector3, direction: Vector3)
	-- Red cylinder ring at origin
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

	-- Neon-green vector line for force direction
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

-- Dash Execution Pipeline
local function performDash()
	if isDashing then return end
	
	local now = os.clock()
	local cooldownRaw: any = FeatureResolver.GetConfigField("Dash", "Cooldown", 2.0)
	local cooldown: number = type(cooldownRaw) == "number" and cooldownRaw or 2.0
	
	-- Simulated charge and cooldown management
	if currentCharges <= 0 then
		if now - lastDashTime < cooldown then
			return
		else
			local maxChargesRaw: any = FeatureResolver.GetConfigField("Dash", "MaxCharges", 3)
			currentCharges = type(maxChargesRaw) == "number" and maxChargesRaw or 3
		end
	end
	
	if now - lastDashTime < 0.1 then return end -- Short debounce
	
	local character = LocalPlayer.Character
	if not character then return end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid
	if not humanoidRootPart or not humanoid then return end
	
	isDashing = true
	lastDashTime = now
	currentCharges -= 1
	
	local forceRaw: any = FeatureResolver.GetConfigField("Dash", "Force", 50.0)
	local forceMagnitude: number = type(forceRaw) == "number" and forceRaw or 50.0
	local moveDirection = humanoid.MoveDirection
	
	if moveDirection.Magnitude < 0.01 then
		moveDirection = humanoidRootPart.CFrame.LookVector
	end
	
	local impulse = moveDirection * forceMagnitude * humanoidRootPart.AssemblyMass
	
	-- Apply physical impulse
	humanoidRootPart:ApplyImpulse(impulse)
	
	-- Network & Authority: Fire validated dash request to server
	if dashRequestEvent then
		dashRequestEvent:FireServer(moveDirection)
	end
	
	-- Hookups: Debug Visualizations
	local debugRaw: any = FeatureResolver.GetConfigField("DebugConfig", "DrawPhysicsVectors", false)
	if type(debugRaw) == "boolean" and debugRaw then
		drawPhysicsVectors(humanoidRootPart.Position, moveDirection * forceMagnitude)
	end
	
	-- Animation Resolution
	local animId = getAnimationId()
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local animation = Instance.new("Animation")
		animation.AnimationId = animId
		local track = animator:LoadAnimation(animation)
		track:Play()
	end
	
	-- Simulated completion duration
	task.delay(0.3, function()
		isDashing = false
	end)
end

-- Auto-Generating Mobile UI
local function setupMobileUI()
	if not UserInputService.TouchEnabled then return end
	local mobileEnabledRaw: any = FeatureResolver.GetConfigField("Dash", "MobileEnabled", true)
	if type(mobileEnabledRaw) == "boolean" and not mobileEnabledRaw then return end
	
	local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
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
	
	dashButton.Activated:Connect(function()
		performDash()
	end)
	
	screenGui.Parent = playerGui
	DebugUtility.Log("DashController", "Mobile Dash UI Generated via Scale Dimensions.")
end

function DashController.Init(): ()
	DebugUtility.Log("DashController", "Initializing Universal Dash Controller...")
	
	-- DashService owns this remote under ReplicatedStorage.Remotes. The old
	-- code looked in the ReplicatedStorage root, never found it, and created
	-- a client-side remote the server never listened on — dashes were
	-- silently dropped.
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:WaitForChild(RemoteNames.DashRequest, 10)
	if remote and remote:IsA("RemoteEvent") then
		dashRequestEvent = remote
	else
		warn("[DashController] DashRequest remote not found — dash disabled.")
	end
end

function DashController.Start(): ()
	DebugUtility.Log("DashController", "Universal Dash Controller Started.")
	
	setupMobileUI()
	
	-- Dual-Binding Keyboards
	local desktopKeybindsRaw: any = FeatureResolver.GetConfigField("Dash", "DesktopKeybinds", {Enum.KeyCode.Q, Enum.KeyCode.LeftShift})
	local desktopKeybinds: {Enum.KeyCode} = type(desktopKeybindsRaw) == "table" and desktopKeybindsRaw or {Enum.KeyCode.Q, Enum.KeyCode.LeftShift}
	
	ContextActionService:BindAction("PerformDash", function(actionName: string, inputState: Enum.UserInputState, inputObject: InputObject)
		if inputState == Enum.UserInputState.Begin then
			performDash()
		end
		return Enum.ContextActionResult.Pass
	end, false, unpack(desktopKeybinds))
end

return DashController
