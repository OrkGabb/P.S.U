--!strict
--@author OrkGabb
--@module DoubleJumpController.luau
--@version 1.5
-- Double jump (client side): grants extra mid-air jumps up to a per-airtime
-- budget. Presentation lives entirely in the optional Client/UI/DoubleJumpFX
-- module (the procedurally generated BespokeJumpFX shockwave assembly); this
-- controller owns only input, the jump budget and the physics impulse.
--
-- Input rides UserInputService.JumpRequest, so keyboard (Space), gamepad (A)
-- and the native mobile jump button all trigger the air jump with zero extra
-- bindings. Every tunable (impulse scale, jump budget, VFX pacing/travel)
-- comes from Shared/Config/MovementRegistry (SSoT); FeatureToggles only
-- carries the executive Enabled/MobileEnabled/AllowMeshVFX switches.
--
-- Dash interop: the air jump first raises Humanoid.Jump — the exact property
-- DashController's dash-cancel listener watches — and applies its impulse one
-- deferred step later, after the dash's Y-locked LinearVelocity constraint
-- has been torn down. Without the defer, an active NegateGravity dash (huge
-- per-axis force, Y locked to zero) would flatten the fresh upward velocity
-- on its final physics step and the double jump would fizzle mid-dash.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MovementRegistry = require(ReplicatedStorage.Shared.Config.MovementRegistry)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver"))
local DebugUtility = require(Shared:WaitForChild("Modules"):WaitForChild("DebugUtility")) :: any

local LocalPlayer: Player = Players.LocalPlayer

local DOUBLE_JUMP_CONFIG = MovementRegistry.DoubleJump

-- Optional presentation layer. FindFirstChild (never WaitForChild) so a
-- deleted DoubleJumpFX module degrades to a working, invisible double jump
-- instead of hanging the boot sequence — same contract as DashController's
-- DashFX load.
local DoubleJumpFX: any = nil
do
	local fxModule = script.Parent.Parent:FindFirstChild("UI")
		and (script.Parent.Parent.UI :: Instance):FindFirstChild("DoubleJumpFX")
	if fxModule and fxModule:IsA("ModuleScript") then
		local ok, result = pcall(require, fxModule)
		if ok then
			DoubleJumpFX = result
		else
			warn("[DoubleJumpController] DoubleJumpFX failed to load — jumping without visuals: " .. tostring(result))
		end
	else
		warn("[DoubleJumpController] DoubleJumpFX module not found — jumping without visuals.")
	end
end

-- Input hygiene, not movement feel (which is why it lives here and not in the
-- registry): JumpRequest refires every frame while the jump input is held, so
-- a held button would otherwise convert the ground jump into an instant air
-- jump one frame after liftoff. Each counted jump re-arms the next one only
-- after this many seconds.
local REARM_SECONDS = 0.2

local DoubleJumpController = {}

local enabled: boolean = false
-- Jumps spent this airtime, including the natural ground jump; reset to zero
-- on Landed. MaxJumps is a true per-airtime total (2 = one extra mid-air).
local currentJumps: number = 0
local lastCountedJumpClock: number = 0
local characterConnections: { RBXScriptConnection } = {}

--- Vertical launch speed of a native ground jump, honoring the rig's active
--- jump model: JumpPower directly, or the equivalent sqrt(2gh) launch speed
--- when the Humanoid is configured with JumpHeight instead.
local function resolveBaseJumpVelocity(humanoid: Humanoid): number
	if humanoid.UseJumpPower then
		return humanoid.JumpPower
	end
	return math.sqrt(2 * Workspace.Gravity * humanoid.JumpHeight)
end

--- JumpRequest handler: spends one slot of the per-airtime jump budget while
--- mid-air, then applies the upward impulse and fires the shockwave burst.
local function performAirJump(): ()
	local character = LocalPlayer.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then
		return
	end
	if humanoid.Health <= 0 then
		return
	end

	local state = humanoid:GetState()
	if state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping then
		return
	end

	local now = os.clock()
	if now - lastCountedJumpClock < REARM_SECONDS then
		return
	end

	if currentJumps == 0 then
		-- Airtime began without a counted jump (walked off a ledge): the
		-- forfeited ground jump still counts against the budget, so MaxJumps
		-- stays a true per-airtime total.
		currentJumps = 1
	end
	if currentJumps >= DOUBLE_JUMP_CONFIG.MaxJumps then
		return
	end
	currentJumps += 1
	lastCountedJumpClock = now

	-- Raise the jump intent first: DashController's dash-cancel listener
	-- rides this exact property, so an active dash tears down its Y-locked
	-- constraint before the impulse lands (see header).
	humanoid.Jump = true
	task.defer(function(): ()
		if humanoid.Health <= 0 or rootPart.Parent == nil then
			return
		end
		local velocity = rootPart.AssemblyLinearVelocity
		local jumpVelocity = resolveBaseJumpVelocity(humanoid) * DOUBLE_JUMP_CONFIG.ForceMultiplier
		rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X, jumpVelocity, velocity.Z)
		-- Forced state refresh: pushes the jump through the Humanoid state
		-- machine (server replication) and lets Animate play the jump clip.
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end)

	-- AllowMeshVFX gating lives inside Burst (live-read per burst).
	-- pcall isolation: the impulse above is already queued via task.defer, and
	-- this keeps a throwing FX layer from ever aborting the input handler —
	-- the jump lands regardless of visual execution status.
	if DoubleJumpFX then
		local ok, err = pcall(DoubleJumpFX.Burst, rootPart, humanoid)
		if not ok then
			warn("[DoubleJumpController] DoubleJumpFX.Burst failed — jump unaffected: " .. tostring(err))
		end
	end
end

local function clearCharacterConnections(): ()
	for _, connection in characterConnections do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(characterConnections)
end

local function onCharacterAdded(character: Model): ()
	clearCharacterConnections()
	currentJumps = 0
	lastCountedJumpClock = 0

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	table.insert(characterConnections, humanoid.StateChanged:Connect(function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
		if new == Enum.HumanoidStateType.Landed then
			currentJumps = 0
		elseif new == Enum.HumanoidStateType.Jumping and currentJumps == 0 then
			-- The natural ground jump spends the first slot of the budget.
			currentJumps = 1
			lastCountedJumpClock = os.clock()
		end
		-- Known limitation: grabbing a ladder (Climbing) or getting seated
		-- mid-air skips Landed, so a stale spent budget survives until the
		-- next Landed. Harmless in practice — the next real landing resets.
	end))
end

function DoubleJumpController.Init(): ()
	-- Defense in depth: ClientMain's skip list already gates this module by
	-- the same toggle, but the controller stays inert if required directly.
	if not FeatureResolver.IsCategoryActive("DoubleJump") then
		DebugUtility.Log("DoubleJumpController", "Disabled by FeatureToggles — aborting init.")
		enabled = false
		return
	end
	enabled = true

	DebugUtility.Log("DoubleJumpController", "Initializing Double Jump Controller...")
end

function DoubleJumpController.Start(): ()
	if not enabled then
		return
	end

	-- Touch-only devices honor the executive MobileEnabled switch. The native
	-- mobile jump button fires JumpRequest, so the gate lives here rather
	-- than in any UI layer.
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled then
		local mobileRaw: any = FeatureResolver.GetConfigField("DoubleJump", "MobileEnabled", true)
		if type(mobileRaw) == "boolean" and not mobileRaw then
			DebugUtility.Log("DoubleJumpController", "MobileEnabled=false on a touch-only device — double jump inactive.")
			return
		end
	end

	LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
	if LocalPlayer.Character then
		onCharacterAdded(LocalPlayer.Character :: Model)
	end

	UserInputService.JumpRequest:Connect(performAirJump)

	DebugUtility.Log("DoubleJumpController", "Double Jump Controller Started.")
end

return DoubleJumpController
