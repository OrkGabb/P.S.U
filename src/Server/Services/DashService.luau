--!strict
--@author OrkGabb
--@module DashService.luau
--@version 2.0
--- @description Server-side Dash ability validator.
---   - Receives DashRequest RemoteEvent from the client.
---   - Validates cooldown and charges server-side (never trusts client timing).
---   - Validates Humanoid.Health > 0 and a sane, near-unit dash direction.
---   - Fires DashGranted RemoteEvent back to the requesting client.
---   - Uses a disposal map to clean all connections on player removal.
---
--- The dash impulse itself is client-driven: DashController manages an eased
--- LinearVelocity constraint on the client-owned character assembly, so a
--- second server-side force here would only fight that constraint. Shared
--- tunables (cooldown, charges) come from Shared/Config/MovementRegistry.
---
--- This module is conditionally loaded by FrameworkServer when
--- FeatureToggles.GlobalFlags.Dash.Enabled == true. When false, this file is
--- never required.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local MovementRegistry = require(ReplicatedStorage.Shared.Config.MovementRegistry)

type DashPlayerState = {
	lastDashTime: number,       -- os.clock() of last granted dash
	activeCharges: number,      -- charges currently on cooldown
	connections: { RBXScriptConnection },
}

-- Constants sourced from MovementRegistry (SSoT)
local COOLDOWN: number = MovementRegistry.Dash.Cooldown
local MAX_CHARGES: number = MovementRegistry.Dash.MaxCharges

-- Direction sanity bounds: the client sends a horizontal unit vector.
local MIN_DIRECTION_MAGNITUDE: number = 0.9
local MAX_DIRECTION_MAGNITUDE: number = 1.1
local MAX_VERTICAL_COMPONENT: number = 0.5

local DashService = {}

local stateMap: { [Player]: DashPlayerState } = {}

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

--- Rejects malformed dash directions: NaN components, non-unit magnitudes,
--- and vectors that try to dash meaningfully out of the horizontal plane.
local function IsDirectionValid(direction: Vector3): boolean
	local magnitude: number = direction.Magnitude
	if magnitude ~= magnitude then -- NaN never equals itself
		return false
	end
	if magnitude < MIN_DIRECTION_MAGNITUDE or magnitude > MAX_DIRECTION_MAGNITUDE then
		return false
	end
	if math.abs(direction.Y) > MAX_VERTICAL_COMPONENT then
		return false
	end
	return true
end

local function OnDashRequest(player: Player, directionRaw: any): ()
	if typeof(directionRaw) ~= "Vector3" then
		return
	end
	local direction: Vector3 = directionRaw :: Vector3
	if not IsDirectionValid(direction) then
		return
	end

	local character: Model? = player.Character
	if not character then
		return
	end
	local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Cooldown validation is server-authoritative
	local state: DashPlayerState = GetState(player)
	local now: number = os.clock()

	if state.activeCharges >= MAX_CHARGES then
		return
	end

	if (now - state.lastDashTime) < COOLDOWN then
		return
	end

	state.lastDashTime = now
	state.activeCharges += 1

	local remotes: Folder? = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
	if remotes then
		local dashGranted: RemoteEvent? = remotes:FindFirstChild(RemoteNames.DashGranted) :: RemoteEvent?
		if dashGranted then
			dashGranted:FireClient(player)
		end
	end

	task.delay(COOLDOWN, function()
		local s: DashPlayerState? = stateMap[player]
		if s then
			s.activeCharges = math.max(0, s.activeCharges - 1)
		end
	end)
end

function DashService.Init(): ()
	Players.PlayerRemoving:Connect(CleanupPlayer)
end

function DashService.Start(): ()
	local remotes: Instance? = ReplicatedStorage:WaitForChild("Remotes")
	if not remotes then
		warn("[DashService] Remotes folder not found; aborting.")
		return
	end

	local existing = remotes:FindFirstChild(RemoteNames.DashRequest)
	local dashRequest: RemoteEvent
	if existing and existing:IsA("RemoteEvent") then
		dashRequest = existing
	else
		-- Create the remote if NetworkService hasn't created it yet
		dashRequest = Instance.new("RemoteEvent")
		dashRequest.Name = RemoteNames.DashRequest
		dashRequest.Parent = remotes
	end

	dashRequest.OnServerEvent:Connect(OnDashRequest)
	print("[DashService] Started — listening for DashRequest events.")
end

return DashService
