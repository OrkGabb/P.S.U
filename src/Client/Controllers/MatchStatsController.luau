--!strict
--@author OrkGabb
--@module MatchStatsController.luau
--@version 1.0
-- src/Client/Controllers/MatchStatsController.luau
-- Thin client-side cache for in-match K/D/A data broadcast by MatchStatsService.
-- WeaponController reads the cached scoreboard to populate the Tab overlay.

local ReplicatedStorage = game:GetService("ReplicatedStorage") :: ReplicatedStorage

local Shared      = ReplicatedStorage:WaitForChild("Shared")   :: Folder
local Remotes     = ReplicatedStorage:WaitForChild("Remotes")  :: Folder

local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver")) :: any
local RemoteNames     = require(Shared:WaitForChild("Network"):WaitForChild("RemoteNames"))     :: any

-- ── Types (mirrors MatchStatsService.ScoreboardEntry) ────────────────────────

export type ScoreboardEntry = {
	UserId:      number,
	DisplayName: string,
	Kills:       number,
	Deaths:      number,
	Assists:     number,
}

-- ── Module ────────────────────────────────────────────────────────────────────

local MatchStatsController = {}

local isActive:         boolean              = false
local cachedScoreboard: { ScoreboardEntry } = {}

-- Callbacks registered by WeaponController to react to scoreboard updates
local _onUpdateCallbacks: { () -> () } = {}

-- ── Public API ────────────────────────────────────────────────────────────────

-- Returns the most-recently received scoreboard snapshot.
function MatchStatsController.GetScoreboard(): { ScoreboardEntry }
	return cachedScoreboard
end

-- Fetches current scoreboard from server via RemoteFunction (used on Tab open).
function MatchStatsController.FetchScoreboard(): { ScoreboardEntry }
	if not isActive then return {} end
	local rf: Instance? = Remotes:FindFirstChild(RemoteNames.MatchStatsRequest)
	if not (rf and rf:IsA("RemoteFunction")) then return cachedScoreboard end
	local ok, result = pcall(function(): { ScoreboardEntry }
		return (rf :: RemoteFunction):InvokeServer()
	end)
	if ok and type(result) == "table" then
		cachedScoreboard = result :: { ScoreboardEntry }
		return cachedScoreboard
	end
	return cachedScoreboard
end

-- Registers a callback to be fired whenever the cached scoreboard is updated.
function MatchStatsController.OnUpdate(callback: () -> ()): ()
	table.insert(_onUpdateCallbacks, callback)
end

-- ── Init ──────────────────────────────────────────────────────────────────────

function MatchStatsController.Init(): ()
	local cfg: any = FeatureResolver.GetCategoryConfig("MatchStats")
	if not (cfg and cfg.Enabled) then return end
	isActive = true
end

-- ── Start ─────────────────────────────────────────────────────────────────────

function MatchStatsController.Start(): ()
	if not isActive then return end

	task.spawn(function(): ()
		local remote: Instance = Remotes:WaitForChild(RemoteNames.MatchStatsSync, 10)
		if not (remote and remote:IsA("RemoteEvent")) then
			warn("[MatchStatsController] MatchStatsSync remote not found after 10s.")
			return
		end
		;(remote :: RemoteEvent).OnClientEvent:Connect(function(board: any): ()
			if type(board) == "table" then
				cachedScoreboard = board :: { ScoreboardEntry }
				for _, cb in ipairs(_onUpdateCallbacks) do
					cb()
				end
			end
		end)
	end)

	print("[MatchStatsController] Listening for MatchStatsSync.")
end

return MatchStatsController
