--!strict
-- @Author @OrkGabb
-- In-match session K/D/A tracker. No DataStore — match-scoped only.
-- Exposes a RemoteFunction (MatchStatsRequest) for Tab-scoreboard fetches and
-- broadcasts MatchStatsSync RemoteEvent to all clients on any stat change.
-- Integrated by WeaponService via RecordKill/RecordDeath/RecordAssist API.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared      = ReplicatedStorage:WaitForChild("Shared")   :: Folder
local Remotes     = ReplicatedStorage:WaitForChild("Remotes")  :: Folder

local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver")) :: any
local RemoteNames     = require(Shared:WaitForChild("Network"):WaitForChild("RemoteNames"))     :: any

export type PlayerStats = {
	Kills:   number,
	Deaths:  number,
	Assists: number,
}

export type ScoreboardEntry = {
	UserId:      number,
	DisplayName: string,
	Kills:       number,
	Deaths:      number,
	Assists:     number,
}

local MatchStatsService = {}

local isActive:         boolean = false
local syncDebounce:     number  = 0.5
local pendingSync:      boolean = false

local statsMap: { [Player]: PlayerStats } = {}

local statsSyncRemote:    RemoteEvent?    = nil
local statsRequestRemote: RemoteFunction? = nil

local function GetStats(player: Player): PlayerStats
	local s: PlayerStats? = statsMap[player]
	if s then return s end
	local newStats: PlayerStats = { Kills = 0, Deaths = 0, Assists = 0 }
	statsMap[player] = newStats
	return newStats
end

local function BuildScoreboard(): { ScoreboardEntry }
	local entries: { ScoreboardEntry } = {}
	for _, player in Players:GetPlayers() do
		local s: PlayerStats = GetStats(player)
		table.insert(entries, {
			UserId      = player.UserId,
			DisplayName = player.DisplayName,
			Kills       = s.Kills,
			Deaths      = s.Deaths,
			Assists      = s.Assists,
		})
	end
	-- Sort by kills descending, then deaths ascending
	table.sort(entries, function(a: ScoreboardEntry, b: ScoreboardEntry): boolean
		if a.Kills ~= b.Kills then return a.Kills > b.Kills end
		return a.Deaths < b.Deaths
	end)
	return entries
end

-- Debounced broadcast — collapses rapid stat changes into one network event
local function ScheduleSync(): ()
	if pendingSync then return end
	pendingSync = true
	task.delay(syncDebounce, function(): ()
		pendingSync = false
		if not statsSyncRemote then return end
		local board: { ScoreboardEntry } = BuildScoreboard()
		statsSyncRemote:FireAllClients(board)
	end)
end

-- killer: Player who fired the killing shot. victim: Player | nil (NPC kill).
function MatchStatsService.RecordKill(killer: Player, victim: Player?): ()
	if not isActive then return end

	local ks: PlayerStats = GetStats(killer)
	ks.Kills += 1

	if victim then
		local vs: PlayerStats = GetStats(victim)
		vs.Deaths += 1
	end

	ScheduleSync()
end

function MatchStatsService.RecordAssist(assister: Player): ()
	if not isActive then return end
	local s: PlayerStats = GetStats(assister)
	s.Assists += 1
	ScheduleSync()
end

function MatchStatsService.Init(): ()
	local cfg: any = FeatureResolver.GetCategoryConfig("MatchStats")
	if not (cfg and cfg.Enabled) then return end
	isActive = true

	local debounceRaw: any = FeatureResolver.GetConfigField("MatchStats", "SyncDebounce", 0.5)
	syncDebounce = type(debounceRaw) == "number" and debounceRaw or 0.5

	local existingSync: Instance? = Remotes:FindFirstChild(RemoteNames.MatchStatsSync)
	if existingSync and existingSync:IsA("RemoteEvent") then
		statsSyncRemote = existingSync :: RemoteEvent
	else
		local r      = Instance.new("RemoteEvent")
		r.Name       = RemoteNames.MatchStatsSync
		r.Parent     = Remotes
		statsSyncRemote = r
	end

	local existingReq: Instance? = Remotes:FindFirstChild(RemoteNames.MatchStatsRequest)
	if existingReq and existingReq:IsA("RemoteFunction") then
		statsRequestRemote = existingReq :: RemoteFunction
	else
		local rf   = Instance.new("RemoteFunction")
		rf.Name    = RemoteNames.MatchStatsRequest
		rf.Parent  = Remotes
		statsRequestRemote = rf
	end

	if statsRequestRemote then
		statsRequestRemote.OnServerInvoke = function(_player: Player): { ScoreboardEntry }
			if not isActive then return {} end
			return BuildScoreboard()
		end
	end

	print("[MatchStatsService] Initialized. Sync debounce:", syncDebounce, "s")
end

function MatchStatsService.Start(): ()
	if not isActive then return end

	-- Seed entries for players already present (Studio test)
	for _, p in Players:GetPlayers() do
		GetStats(p)
	end

	Players.PlayerAdded:Connect(function(player: Player): ()
		GetStats(player)
		ScheduleSync()
	end)

	Players.PlayerRemoving:Connect(function(player: Player): ()
		statsMap[player] = nil
		ScheduleSync()
	end)

	print("[MatchStatsService] Started.")
end

return MatchStatsService
