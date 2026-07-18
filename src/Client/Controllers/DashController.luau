--!strict
--@author OrkGabb
--@module DashController.luau
--@version 2.0
-- Dash backend (client side): input bindings, charge/cooldown prediction, and
-- the DashRequest remote. All presentation (animation, mobile button, debug
-- draw) lives in the optional DashFX module — swap or delete that file to
-- change the dash's look without touching this logic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver"))
local DebugUtility = require(Shared:WaitForChild("Modules"):WaitForChild("DebugUtility")) :: any

local LocalPlayer: Player = Players.LocalPlayer
local dashRequestEvent: RemoteEvent? = nil

-- Optional presentation layer. FindFirstChild (never WaitForChild) so a
-- deleted DashFX module degrades to a working, invisible dash instead of
-- hanging the boot sequence.
local DashFX: any = nil
do
	local fxModule = script.Parent.Parent:FindFirstChild("UI")
		and (script.Parent.Parent.UI :: Instance):FindFirstChild("DashFX")
	if fxModule and fxModule:IsA("ModuleScript") then
		local ok, result = pcall(require, fxModule)
		if ok then
			DashFX = result
		else
			warn("[DashController] DashFX failed to load — dashing without visuals: " .. tostring(result))
		end
	else
		warn("[DashController] DashFX module not found — dashing without visuals.")
	end
end

local DashController = {}

local isDashing: boolean = false
local lastDashTime: number = 0
local currentChargesRaw: any = FeatureResolver.GetConfigField("Dash", "MaxCharges", 3)
local currentCharges: number = type(currentChargesRaw) == "number" and currentChargesRaw or 3

local function performDash()
	if isDashing then return end

	local now = os.clock()
	local cooldownRaw: any = FeatureResolver.GetConfigField("Dash", "Cooldown", 2.0)
	local cooldown: number = type(cooldownRaw) == "number" and cooldownRaw or 2.0

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

	humanoidRootPart:ApplyImpulse(impulse)

	if dashRequestEvent then
		dashRequestEvent:FireServer(moveDirection)
	end

	if DashFX then
		local debugRaw: any = FeatureResolver.GetConfigField("DebugConfig", "DrawPhysicsVectors", false)
		if type(debugRaw) == "boolean" and debugRaw then
			DashFX.DrawPhysicsVectors(humanoidRootPart.Position, moveDirection * forceMagnitude)
		end

		local keyRaw: any = FeatureResolver.GetConfigField("Dash", "ActiveAnimationKey", "DashForward")
		local animKey: string = type(keyRaw) == "string" and keyRaw or "DashForward"
		DashFX.PlayDashAnimation(humanoid, animKey)
	end

	task.delay(0.3, function()
		isDashing = false
	end)
end

local function setupMobileUI()
	if not UserInputService.TouchEnabled then return end
	local mobileEnabledRaw: any = FeatureResolver.GetConfigField("Dash", "MobileEnabled", true)
	if type(mobileEnabledRaw) == "boolean" and not mobileEnabledRaw then return end
	if not DashFX then return end

	local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	DashFX.BuildMobileButton(playerGui, performDash)
	DebugUtility.Log("DashController", "Mobile Dash UI Generated via DashFX.")
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
