--!strict
-- @Author @OrkGabb
-- Server-authoritative daily reward claims. Mirrors QuestService's pattern:
-- validates against DailyRegistry (the SSoT for reward data), persists
-- claim state on the profile, and pushes state to the client via
-- RemoteNames-declared remotes only. Core capability — available to every
-- genre, exactly like QuestService and UpgradeService.
--
-- v2: rewards Coins (Currencies.Primary) + CoreFragments (Stats.CoreFragments)
-- only — both genre-agnostic. v1 rewarded genre-locked ItemRegistry potions
-- inherited from a pre-P.S.U. project; removed per the framework's own
-- plug-n-play guarantee (see DailyRegistry v2 header for full rationale).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local DailyRegistry = require(ReplicatedStorage.Shared.Modules.DailyRegistry)
local DataService = require(ServerScriptService.Server.Services.DataService)

local DailyService = {}

local SECONDS_PER_DAY = 86400

-- Midnight UTC boundary, matching the client's own GetMidnightUTC in
-- DailyUIController / SidebarController — claim eligibility must agree on
-- both sides or the notification dot and the server's accept/reject will
-- silently disagree.
local function GetMidnightUTC(): number
	local now: number = os.time()
	return now - (now % SECONDS_PER_DAY)
end

-- Ensures profile.Data.Progression.Daily exists with the shape this service
-- owns. Additive only, per DataService's schema-extension contract — never
-- touches Currencies, Stats, or any other core sub-table directly.
local function EnsureDailyData(profile: any): ()
	if type(profile.Data.Progression) ~= "table" then
		profile.Data.Progression = {}
	end
	if type(profile.Data.Progression.Daily) ~= "table" then
		profile.Data.Progression.Daily = {
			LastClaim = 0,
			CurrentDay = 0,
		}
	end
end

-- Returns true if the player has not yet claimed since the last midnight
-- UTC boundary — the same rule the client uses to show/hide the notif dot.
local function CanClaim(dailyData: any): boolean
	local lastClaim: number = dailyData.LastClaim or 0
	return lastClaim < GetMidnightUTC()
end

-- Applies one day's reward: Coins scaled by DailyRegistry's dynamic level
-- multiplier, plus CoreFragments — a universal milestone resource stored in
-- Stats (the schema slot DataService reserves for core-owned counters).
-- Advances CurrentDay, wrapping back to day 1 after the registry's final
-- day (31) so long-term players keep cycling the reward table.
local function ApplyReward(profile: any): ()
	local dailyData: any = profile.Data.Progression.Daily
	local nextDay: number = (dailyData.CurrentDay or 0) + 1

	local maxDay = 0
	for day: number in pairs(DailyRegistry.Days) do
		if day > maxDay then
			maxDay = day
		end
	end
	if nextDay > maxDay then
		nextDay = 1
	end

	local entry = DailyRegistry.Days[nextDay]
	if entry == nil then
		return
	end

	local level: number = profile.Data.Progression.Level or 1
	local rebirths: number? = profile.Data.Progression.Rebirths
	local multiplier: number = DailyRegistry.GetMultiplier(level, rebirths)
	local finalCoins: number = math.floor(entry.Coins * multiplier)

	if type(profile.Data.Currencies) ~= "table" then
		profile.Data.Currencies = { Primary = 0, Secondary = 0, Premium = 0 }
	end
	profile.Data.Currencies.Primary = (profile.Data.Currencies.Primary or 0) + finalCoins

	if entry.Fragments > 0 then
		if type(profile.Data.Stats) ~= "table" then
			profile.Data.Stats = {}
		end
		profile.Data.Stats.CoreFragments = (profile.Data.Stats.CoreFragments or 0) + entry.Fragments
	end

	dailyData.CurrentDay = nextDay
	dailyData.LastClaim = os.time()
end

-- Pushes the current Daily sub-table to the client via UpdateDaily.
-- DailyUIController and SidebarController both read `data.LastClaim` from
-- this exact payload shape to gate the notification dot.
local function PushState(player: Player, profile: any): ()
	local remotes: Folder? = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
	if remotes == nil then
		return
	end
	local event = remotes:FindFirstChild(RemoteNames.UpdateDaily) :: RemoteEvent?
	if event then
		event:FireClient(player, profile.Data.Progression.Daily)
	end
end

local function OnClaimRequest(player: Player): ()
	local profile: any = DataService.Profiles[player]
	if profile == nil then
		return
	end

	EnsureDailyData(profile)
	local dailyData: any = profile.Data.Progression.Daily

	if not CanClaim(dailyData) then
		return
	end

	ApplyReward(profile)
	DataService:SyncFullState(player)
	PushState(player, profile)
end

function DailyService.Init(): ()
	local remotes: Folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder

	if not remotes:FindFirstChild(RemoteNames.ClaimDailyRequest) then
		local event = Instance.new("RemoteEvent")
		event.Name = RemoteNames.ClaimDailyRequest
		event.Parent = remotes
	end

	if not remotes:FindFirstChild(RemoteNames.UpdateDaily) then
		local event = Instance.new("RemoteEvent")
		event.Name = RemoteNames.UpdateDaily
		event.Parent = remotes
	end
end

function DailyService.Start(): ()
	local remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	local claimEvent = remotes:WaitForChild(RemoteNames.ClaimDailyRequest) :: RemoteEvent

	claimEvent.OnServerEvent:Connect(function(player: Player)
		OnClaimRequest(player)
	end)
end

return DailyService
