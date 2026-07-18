--!strict
--@author OrkGabb
--@module DashController.luau
--@version 3.0
-- Dash backend (client side): input bindings, charge/cooldown prediction,
-- the DashRequest remote, and the dash impulse itself — a LinearVelocity
-- constraint whose speed eases down smoothly toward the end of the duration
-- instead of cutting out abruptly.
--
-- All presentation (procedural body lean, camera FOV juice, mobile button,
-- debug draw) lives in the optional DashFX module — swap or delete that file
-- to change the dash's look without touching this logic. Every tunable
-- (speed, duration, easing, cooldown, keybinds) comes from
-- Shared/Config/MovementRegistry (SSoT); FeatureToggles only carries the
-- executive Enabled/MobileEnabled switches.
--
-- Interruption safety: death, seating, ragdoll/physics states, platform-stand
-- stuns, and character removal all tear the constraint down instantly and
-- tell DashFX to snap joints and camera back to their recorded baselines.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local MovementRegistry = require(ReplicatedStorage.Shared.Config.MovementRegistry)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver"))
local DebugUtility = require(Shared:WaitForChild("Modules"):WaitForChild("DebugUtility")) :: any

local LocalPlayer: Player = Players.LocalPlayer
local dashRequestEvent: RemoteEvent? = nil

local DASH_CONFIG = MovementRegistry.Dash
local PHYSICS_CONFIG = DASH_CONFIG.Physics

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

type ActiveDash = {
	character: Model,
	humanoid: Humanoid,
	attachment: Attachment,
	velocity: LinearVelocity,
	connections: { RBXScriptConnection },
}

local activeDash: ActiveDash? = nil
-- Bumped on every dash start and every cancel; pending task.delay phase
-- callbacks compare against it so a stale timer can never touch a newer dash.
local dashGeneration: number = 0
local lastDashTime: number = 0
local currentCharges: number = DASH_CONFIG.MaxCharges

--- Disconnects watchers and destroys the physics constraint of a dash.
local function teardownDash(dash: ActiveDash): ()
	for _, connection in dash.connections do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(dash.connections)
	if dash.velocity.Parent then
		dash.velocity:Destroy()
	end
	if dash.attachment.Parent then
		dash.attachment:Destroy()
	end
	if activeDash == dash then
		activeDash = nil
	end
end

--- Graceful end of a completed dash: DashFX has already been released and its
--- return tweens restore the baselines on their own.
local function finishDash(dash: ActiveDash): ()
	teardownDash(dash)
end

--- Interruption path (death, stun, seat, ragdoll, character removal): tear the
--- physics down and snap all presentation state back to baseline instantly.
local function cancelDash(dash: ActiveDash): ()
	dashGeneration += 1
	teardownDash(dash)
	if DashFX then
		DashFX.Cancel(dash.character)
	end
end

--- Wires every interruption source to the cancel path for this dash.
local function watchForInterruption(dash: ActiveDash, generation: number): ()
	local function onInterrupted(): ()
		if dashGeneration ~= generation or activeDash ~= dash then
			return
		end
		cancelDash(dash)
	end

	table.insert(dash.connections, dash.humanoid.Died:Connect(onInterrupted))
	table.insert(dash.connections, dash.humanoid.Seated:Connect(function(active: boolean)
		if active then
			onInterrupted()
		end
	end))
	table.insert(dash.connections, dash.humanoid.StateChanged:Connect(function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
		if new == Enum.HumanoidStateType.Physics
			or new == Enum.HumanoidStateType.Ragdoll
			or new == Enum.HumanoidStateType.Dead
		then
			onInterrupted()
		end
	end))
	table.insert(dash.connections, dash.humanoid:GetPropertyChangedSignal("PlatformStand"):Connect(function()
		if dash.humanoid.PlatformStand then
			onInterrupted()
		end
	end))
	table.insert(dash.connections, dash.character.AncestryChanged:Connect(function(_child: Instance, parent: Instance?)
		if parent == nil then
			onInterrupted()
		end
	end))
end

--- Creates the eased LinearVelocity impulse and schedules its two phases:
--- full-speed sustain, then a tweened ramp-down to zero before removal.
local function beginDash(character: Model, rootPart: BasePart, humanoid: Humanoid, direction: Vector3): ()
	dashGeneration += 1
	local generation = dashGeneration

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = rootPart

	-- Line mode drives speed along the dash axis only, leaving the remaining
	-- axes to the humanoid and gravity — no floating, no fighting strafe input.
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DashVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	velocity.LineDirection = direction
	velocity.LineVelocity = PHYSICS_CONFIG.Speed
	velocity.MaxForce = PHYSICS_CONFIG.MaxForce
	velocity.Parent = rootPart

	local dash: ActiveDash = {
		character = character,
		humanoid = humanoid,
		attachment = attachment,
		velocity = velocity,
		connections = {},
	}
	activeDash = dash

	watchForInterruption(dash, generation)

	if DashFX then
		DashFX.Begin(character, direction)
	end

	local sustainSeconds = math.max(PHYSICS_CONFIG.Duration - PHYSICS_CONFIG.EaseOutSeconds, 0)
	task.delay(sustainSeconds, function()
		if dashGeneration ~= generation or activeDash ~= dash then
			return
		end
		local easeInfo = TweenInfo.new(PHYSICS_CONFIG.EaseOutSeconds, PHYSICS_CONFIG.EasingStyle, PHYSICS_CONFIG.EasingDirection)
		local easeTween = TweenService:Create(velocity, easeInfo, { LineVelocity = 0 })
		easeTween:Play()
		if DashFX then
			DashFX.Release(character)
		end
	end)

	task.delay(PHYSICS_CONFIG.Duration, function()
		if dashGeneration ~= generation or activeDash ~= dash then
			return
		end
		finishDash(dash)
	end)
end

local function performDash(): ()
	if activeDash then
		return
	end

	local now = os.clock()
	if currentCharges <= 0 then
		if now - lastDashTime < DASH_CONFIG.Cooldown then
			return
		else
			currentCharges = DASH_CONFIG.MaxCharges
		end
	end

	if now - lastDashTime < DASH_CONFIG.InputDebounceSeconds then
		return
	end

	local character = LocalPlayer.Character
	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoidRootPart or not humanoid then
		return
	end
	if humanoid.Health <= 0 then
		return
	end

	local moveDirection = humanoid.MoveDirection
	if moveDirection.Magnitude < 0.01 then
		moveDirection = humanoidRootPart.CFrame.LookVector
	end

	-- Dash stays in the horizontal plane; gravity keeps its authority over Y.
	local flatDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	if flatDirection.Magnitude < 0.001 then
		return
	end
	local dashDirection = flatDirection.Unit

	lastDashTime = now
	currentCharges -= 1

	beginDash(character, humanoidRootPart, humanoid, dashDirection)

	if dashRequestEvent then
		dashRequestEvent:FireServer(dashDirection)
	end

	if DashFX then
		local debugRaw: any = FeatureResolver.GetConfigField("DebugConfig", "DrawPhysicsVectors", false)
		if type(debugRaw) == "boolean" and debugRaw then
			DashFX.DrawPhysicsVectors(humanoidRootPart.Position, dashDirection * PHYSICS_CONFIG.Speed)
		end
	end
end

local function setupMobileUI(): ()
	if not UserInputService.TouchEnabled then
		return
	end
	local mobileEnabledRaw: any = FeatureResolver.GetConfigField("Dash", "MobileEnabled", true)
	if type(mobileEnabledRaw) == "boolean" and not mobileEnabledRaw then
		return
	end
	if not DashFX then
		return
	end

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

	ContextActionService:BindAction("PerformDash", function(actionName: string, inputState: Enum.UserInputState, inputObject: InputObject)
		if inputState == Enum.UserInputState.Begin then
			performDash()
		end
		return Enum.ContextActionResult.Pass
	end, false, unpack(DASH_CONFIG.DesktopKeybinds))
end

return DashController
