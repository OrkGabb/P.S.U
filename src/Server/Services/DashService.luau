--!strict
--@author OrkGabb
--@module DashService.luau
--@version 1.0
--- @description Server-side Dash ability system.
---   - Receives DashRequest RemoteEvent from the client.
---   - Validates cooldown server-side (never trusts client timing).
---   - Validates Humanoid.Health > 0.
---   - Applies a VectorForce impulse in the requested direction.
---   - Fires DashGranted RemoteEvent back to the client to play the animation.
---   - Uses a disposal map to clean all connections on player removal.
---
--- This module is conditionally loaded by FrameworkServer when
--- FeatureToggles.Dash == true. When false, this file is never required.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------------------------------------
-- Shared imports
--------------------------------------------------------------------------------
local FeatureResolver = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("FeatureResolver"))

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

type DashPlayerState = {
	lastDashTime: number,       -- os.clock() of last granted dash
	activeCharges: number,      -- charges currently on cooldown
	connections: { RBXScriptConnection },
}

--------------------------------------------------------------------------------
-- Constants (sourced from FeatureResolver — SSoT)
--------------------------------------------------------------------------------

local cooldownRaw: any = FeatureResolver.GetConfigField("Dash", "Cooldown", 2.0)
local COOLDOWN: number = type(cooldownRaw) == "number" and cooldownRaw or 2.0

local forceRaw: any = FeatureResolver.GetConfigField("Dash", "Force", 50.0)
local FORCE: number = type(forceRaw) == "number" and forceRaw or 50.0

local maxChargesRaw: any = FeatureResolver.GetConfigField("Dash", "MaxCharges", 3)
local MAX_CHARGES: number = type(maxChargesRaw) == "number" and maxChargesRaw or 3

local IMPULSE_DURATION: number = 0.2  -- seconds the VectorForce stays active

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local DashService = {}

local stateMap: { [Player]: DashPlayerState } = {}

--------------------------------------------------------------------------------
-- Internals
--------------------------------------------------------------------------------

local function GetState(player: Player): DashPlayerState
	local state: DashPlayerState? = stateMap[player]
	if state then
		return state
	end
	local newState: DashPlayerState = {
		lastDashTime  = 0,
		activeCharges = 0,
		connections   = {},
	}
	stateMap[player] = newState
	return newState
end

local function CleanupPlayer(player: Player): ()
	local state: DashPlayerState? = stateMap[player]
	if not state then
		return
	end
	for _, conn in state.connections do
		if conn.Connected then
			conn:Disconnect()
		end
	end
	stateMap[player] = nil
end

--- Applies a temporary VectorForce impulse to the character's HumanoidRootPart.
--- The force is cleaned up after IMPULSE_DURATION seconds via task.delay.
local function ApplyImpulse(character: Model, direction: Vector3): ()
	local rootPart: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	-- Normalise and scale the direction
	local safeDirection: Vector3
	if direction.Magnitude > 0.001 then
		safeDirection = direction.Unit * FORCE
	else
		-- Fallback: dash forward relative to character facing
		safeDirection = rootPart.CFrame.LookVector * FORCE
	end

	-- Create attachment for the VectorForce
	local attachment: Attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = rootPart

	local vectorForce: VectorForce = Instance.new("VectorForce")
	vectorForce.Name = "DashImpulse"
	vectorForce.Attachment0 = attachment
	vectorForce.Force = safeDirection * rootPart.AssemblyMass
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.Parent = rootPart

	-- Clean up after impulse duration
	task.delay(IMPULSE_DURATION, function()
		if vectorForce and vectorForce.Parent then
			vectorForce:Destroy()
		end
		if attachment and attachment.Parent then
			attachment:Destroy()
		end
	end)
end

--- Handles an incoming DashRequest from a client.
local function OnDashRequest(player: Player, directionRaw: any): ()
	-- ── Input sanitisation ───────────────────────────────────────────────
	if typeof(directionRaw) ~= "Vector3" then
		return
	end
	local direction: Vector3 = directionRaw :: Vector3

	-- ── Character & health validation ────────────────────────────────────
	local character: Model? = player.Character
	if not character then
		return
	end
	local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- ── Cooldown validation (server-authoritative) ───────────────────────
	local state: DashPlayerState = GetState(player)
	local now: number = os.clock()

	if state.activeCharges >= MAX_CHARGES then
		return
	end

	if (now - state.lastDashTime) < COOLDOWN then
		return
	end

	-- ── Grant the dash ───────────────────────────────────────────────────
	state.lastDashTime = now
	state.activeCharges += 1

	-- Apply physics impulse
	ApplyImpulse(character, direction)

	-- Notify client to play animation
	local remotes: Folder? = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
	if remotes then
		local dashGranted: RemoteEvent? = remotes:FindFirstChild("DashGranted") :: RemoteEvent?
		if dashGranted then
			dashGranted:FireClient(player)
		end
	end

	-- Release the charge after cooldown
	task.delay(COOLDOWN, function()
		local s: DashPlayerState? = stateMap[player]
		if s then
			s.activeCharges = math.max(0, s.activeCharges - 1)
		end
	end)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function DashService.Init(): ()
	-- Player cleanup disposal
	Players.PlayerRemoving:Connect(CleanupPlayer)
end

function DashService.Start(): ()
	local remotes: Instance? = ReplicatedStorage:WaitForChild("Remotes")
	if not remotes then
		warn("[DashService] Remotes folder not found; aborting.")
		return
	end

	local existing = remotes:FindFirstChild("DashRequest")
	local dashRequest: RemoteEvent
	if existing and existing:IsA("RemoteEvent") then
		dashRequest = existing
	else
		-- Create the remote if NetworkService hasn't created it yet
		dashRequest = Instance.new("RemoteEvent")
		dashRequest.Name = "DashRequest"
		dashRequest.Parent = remotes
	end

	dashRequest.OnServerEvent:Connect(OnDashRequest)
	print("[DashService] Started — listening for DashRequest events.")
end

return DashService
