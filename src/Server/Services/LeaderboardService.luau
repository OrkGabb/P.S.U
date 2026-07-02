--!strict
--@author OrkGabb
--@module LeaderboardService.luau
--@version 1.0
-- src/Server/Services/LeaderboardService.luau
-- Global ranked leaderboard system using OrderedDataStore.
-- Boards (top 100 cached, refreshed every 60s).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataService: any = require(ServerScriptService.Server.Services.DataService)
local Shared: Folder = ReplicatedStorage:WaitForChild("Shared") :: Folder

local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver"))

local LeaderboardService = {}

export type LeaderboardEntry = {
	Rank: number,
	UserId: number,
	DisplayName: string,
	Value: number,
}

export type BoardConfig = {
	Key: string,
	DataField: string,
	DisplayName: string,
	Offset: Vector3,
	ColorPrimary: Color3,
	ColorAccent: Color3,
	Icon: string,
	FormatType: string,
}

local boardsRaw: any = FeatureResolver.GetConfigField("Leaderboards", "Boards", {})
local BOARDS: {BoardConfig} = type(boardsRaw) == "table" and boardsRaw or {}

local MAX_ENTRIES: number = 100
local UPDATE_INTERVAL: number = 60
local READ_INTERVAL: number = 60
local READ_OFFSET: number = 30

local cachedBoards: {[string]: {LeaderboardEntry}} = {}
local displayNameCache: {[number]: string} = {}

local plConfig: any = FeatureResolver.GetFlag("PhysicalLeaderboard")
local plEnabled: boolean = type(plConfig) == "table" and plConfig.Enabled == true
local plPosition: Vector3 = (type(plConfig) == "table" and typeof(plConfig.Position) == "Vector3")
	and plConfig.Position or Vector3.new(175.8, 33.65, 12.6)

local function GetDisplayName(userId: number): string
	if displayNameCache[userId] then
		return displayNameCache[userId]
	end

	local name: string = "Player"
	local success: boolean, result: string? = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if success and result then
		name = result
	end

	local successDisplay: boolean, displayResult: string? = pcall(function()
		local userInfo = game:GetService("UserService"):GetUserInfosByUserIdsAsync({userId})
		if userInfo and #userInfo > 0 then
			return userInfo[1].DisplayName
		end
		return nil
	end)
	if successDisplay and displayResult then
		name = displayResult
	end

	displayNameCache[userId] = name
	return name
end

local function FetchBoard(boardConfig: BoardConfig): ()
	local success: boolean, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(boardConfig.Key)
	end)
	if not success or not store then
		warn("[LeaderboardService] Failed to get OrderedDataStore:", boardConfig.Key)
		return
	end

	local fetchSuccess: boolean, pages = pcall(function()
		return store:GetSortedAsync(false, MAX_ENTRIES)
	end)
	if not fetchSuccess or not pages then
		warn("[LeaderboardService] GetSortedAsync failed for:", boardConfig.Key)
		return
	end

	local entries: {LeaderboardEntry} = {}
	local rank: number = 0

	while true do
		local pageData = pages:GetCurrentPage()
		for _, entry in ipairs(pageData) do
			rank += 1
			local userId: number = tonumber(string.match(entry.key, "%d+")) or 0
			table.insert(entries, {
				Rank = rank,
				UserId = userId,
				DisplayName = GetDisplayName(userId),
				Value = entry.value,
			})
		end

		if pages.IsFinished or rank >= MAX_ENTRIES then
			break
		end

		local advanceSuccess: boolean = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not advanceSuccess then
			break
		end
	end

	cachedBoards[boardConfig.Key] = entries
end

local function UpdateBoard(boardConfig: BoardConfig): ()
	local success: boolean, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(boardConfig.Key)
	end)
	if not success or not store then
		warn("[LeaderboardService] Failed to get OrderedDataStore for update:", boardConfig.Key)
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local data = DataService:GetProfileData(player)
		if data then
			local value: number = (data :: any)[boardConfig.DataField] or 0
			local intValue: number = math.floor(math.clamp(value, 0, 2^53))
			if intValue > 0 then
				pcall(function()
					store:SetAsync("Player_" .. player.UserId, intValue)
				end)
			end
		end
	end
end

function LeaderboardService.Init(): ()
	local remotes: Folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder

	local getLeaderboardRF: RemoteFunction = remotes:FindFirstChild("GetLeaderboardData") :: RemoteFunction
		or Instance.new("RemoteFunction", remotes)
	getLeaderboardRF.Name = "GetLeaderboardData"

	getLeaderboardRF.OnServerInvoke = function(_player: Player, boardKey: string?): any
		if not FeatureResolver.IsCategoryActive("Leaderboards") then
			return {}
		end

		if boardKey and cachedBoards[boardKey] then
			return cachedBoards[boardKey]
		end

		local result: {[string]: {LeaderboardEntry}} = {}
		for _, boardConfig in ipairs(BOARDS) do
			if type(boardConfig) == "table" and boardConfig.Key then
				result[boardConfig.Key] = cachedBoards[boardConfig.Key] or {}
			end
		end
		return result
	end

	local getBoardConfigRF: RemoteFunction = remotes:FindFirstChild("GetBoardConfigs") :: RemoteFunction
		or Instance.new("RemoteFunction", remotes)
	getBoardConfigRF.Name = "GetBoardConfigs"

	getBoardConfigRF.OnServerInvoke = function(_player: Player): any
		if not FeatureResolver.IsCategoryActive("Leaderboards") then
			return {}
		end

		local configs: {any} = {}
		for _, bc in ipairs(BOARDS) do
			if type(bc) == "table" and bc.Key then
				table.insert(configs, {
					Key = bc.Key,
					DisplayName = bc.DisplayName,
					ColorPrimary = bc.ColorPrimary,
					ColorAccent = bc.ColorAccent,
					Icon = bc.Icon,
					FormatType = bc.FormatType,
				})
			end
		end
		return configs
	end
end

local function EnsurePhysicalBoards(): ()
	if not FeatureResolver.IsCategoryActive("Leaderboards") then return end

	local leaderboardParts: Folder? = workspace:FindFirstChild("LeaderboardBoards") :: Folder?
	if not leaderboardParts then
		local newFolder: Folder = Instance.new("Folder")
		newFolder.Name = "LeaderboardBoards"
		newFolder.Parent = workspace
		leaderboardParts = newFolder

		for _, cfg in ipairs(BOARDS) do
			if type(cfg) == "table" and cfg.Key then
				local part: Part = Instance.new("Part")
				part.Name = cfg.Key .. "_Board"
				part.Size = Vector3.new(6, 8, 0.4)
				part.Position = plPosition + (cfg.Offset or Vector3.new())
				part.CFrame = CFrame.new(part.Position)
				part.Anchored = true
				part.CanCollide = true
				part.Material = Enum.Material.Glass
				part.Color = Color3.fromRGB(20, 22, 30)
				part.Transparency = 0.1
				part:SetAttribute("BoardKey", cfg.Key)
				part.Parent = leaderboardParts

				local stand: Part = Instance.new("Part")
				stand.Name = cfg.Key .. "_Stand"
				stand.Size = Vector3.new(1, 4, 1)
				stand.Position = part.Position - Vector3.new(0, 6, 0)
				stand.Anchored = true
				stand.CanCollide = true
				stand.Material = Enum.Material.Metal
				stand.Color = Color3.fromRGB(80, 80, 85)
				stand.Parent = leaderboardParts
			end
		end
		
		print("[LeaderboardService] Spawned physical leaderboard parts at", plPosition)
	end
end

function LeaderboardService.Start(): ()
	if not FeatureResolver.IsCategoryActive("Leaderboards") then return end

	local activeGenre: string? = FeatureResolver.GetActiveGenre()
	if activeGenre == "FPS_Shooter" then
		print("[LeaderboardService] FPS_Shooter active — DataStore leaderboards disabled.")
		return
	end

	if plEnabled then
		EnsurePhysicalBoards()
	end

	task.spawn(function()
		while true do
			for _, boardConfig in ipairs(BOARDS) do
				UpdateBoard(boardConfig)
				task.wait(1)
			end
			task.wait(UPDATE_INTERVAL)
		end
	end)

	task.spawn(function()
		task.wait(READ_OFFSET)
		while true do
			for _, boardConfig in ipairs(BOARDS) do
				FetchBoard(boardConfig)
				task.wait(1)
			end
			task.wait(READ_INTERVAL)
		end
	end)

	print("[LeaderboardService] Started. Boards:", #BOARDS)
end

return LeaderboardService
