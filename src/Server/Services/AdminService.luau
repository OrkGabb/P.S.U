--!strict
--@author OrkGabb
--@module AdminService.luau
--@version 1.0
-- src/Server/Services/AdminService.luau
-- Secure Administration Service. Gated by FeatureResolver to remain completely inactive under fallback.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: Folder
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver")) :: any
local DataService = require(ServerScriptService.Server.Services.DataService) :: any

local AdminService = {}

-- ========================================================================
-- SECURITY: Single Source of Truth for Administrators.
-- ========================================================================
local ADMIN_IDS: {number} = {
	538185175, -- TR4_Gabriel
}

local function IsAdmin(player: Player): boolean
	for _, id in ipairs(ADMIN_IDS) do
		if player.UserId == id then return true end
	end
	return false
end

local function LogAction(player: Player, action: string, detail: string?)
	local ts = os.date("%H:%M:%S")
	print(string.format("[ADMIN %s] %s -> %s%s", ts, player.Name, action, if detail then (" | " .. detail) else ""))
end

local function GetTarget(player: Player, targetName: any): (Player?, string?)
	if not targetName or targetName == "" then return player, nil end
	local searchLower = string.lower(tostring(targetName))
	
	for _, p in ipairs(Players:GetPlayers()) do
		if string.lower(p.Name) == searchLower then return p, nil end
	end
	
	local matches = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if string.sub(string.lower(p.Name), 1, #searchLower) == searchLower then
			table.insert(matches, p)
		end
	end
	
	if #matches == 1 then return matches[1], nil end
	if #matches > 1 then return nil, "Ambiguous name detected" end
	return nil, "Player not found"
end

local function SendFeedback(player: Player, action: string, success: boolean, msg: string)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local adminRemote = remotes and remotes:FindFirstChild("sys_adm") :: RemoteEvent?
	if adminRemote then adminRemote:FireClient(player, action, success, msg) end
end

-- ========================================================================
-- ACTION COMMANDS REGISTRY
-- ========================================================================

type ActionHandler = (player: Player, args: {any}) -> (boolean, string?)
local Actions: {[string]: ActionHandler} = {}

Actions["give_currency"] = function(player, args)
	local currencyType = tostring(args[1] or "Primary")
	local amount = tonumber(args[2])
	if not amount or amount == 0 then return false, "Invalid amount" end

	local target, err = GetTarget(player, args[3])
	if not target then return false, err or "Target not found" end

	local profileData = DataService:GetProfileData(target)
	if not profileData or not profileData.Currencies then return false, "Profile data not found" end
	
	if profileData.Currencies[currencyType] == nil then return false, "Invalid currency type" end

	profileData.Currencies[currencyType] += amount
	LogAction(player, "GIVE_CURRENCY", string.format("%s -> %s %s", target.Name, tostring(amount), currencyType))
	return true, string.format("Gave %s %s to %s", tostring(amount), currencyType, target.Name)
end

Actions["give_exp"] = function(player, args)
	local amount = tonumber(args[1])
	if not amount or amount <= 0 then return false, "Invalid EXP amount" end

	local target, err = GetTarget(player, args[2])
	if not target then return false, err or "Target not found" end

	local profileData = DataService:GetProfileData(target)
	if not profileData or not profileData.Progression then return false, "Profile data not found" end

	profileData.Progression.Experience += amount
	LogAction(player, "GIVE_EXP", string.format("%s -> +%s", target.Name, tostring(amount)))
	return true, string.format("+%s EXP to %s", tostring(amount), target.Name)
end

Actions["set_level"] = function(player, args)
	local targetLvl = tonumber(args[1])
	if not targetLvl or targetLvl <= 0 then return false, "Invalid Level" end

	local target, err = GetTarget(player, args[2])
	if not target then return false, err or "Target not found" end

	local profileData = DataService:GetProfileData(target)
	if not profileData or not profileData.Progression then return false, "Profile data not found" end

	profileData.Progression.Level = math.floor(targetLvl)
	LogAction(player, "SET_LEVEL", string.format("%s -> Lv%d", target.Name, targetLvl))
	return true, string.format("%s set to Lv%d", target.Name, targetLvl)
end

Actions["set_rebirth"] = function(player, args)
	local targetVal = tonumber(args[1])
	if not targetVal or targetVal < 0 then return false, "Invalid Rebirth" end

	local target, err = GetTarget(player, args[2])
	if not target then return false, err or "Target not found" end

	local profileData = DataService:GetProfileData(target)
	if not profileData or not profileData.Progression then return false, "Profile data not found" end

	profileData.Progression.Rebirths = math.floor(targetVal)
	LogAction(player, "SET_REBIRTH", string.format("%s -> Rb%d", target.Name, targetVal))
	return true, string.format("%s set to Rb%d", target.Name, targetVal)
end

Actions["reset_player"] = function(player, args)
	local target, err = GetTarget(player, args[1])
	if not target then return false, err or "Target not found" end

	local profileData = DataService:GetProfileData(target)
	if not profileData then return false, "Profile data not found" end

	profileData.Currencies = { ["Primary"] = 0, ["Secondary"] = 0, ["Premium"] = 0 }
	profileData.Inventory = { ["Equipment"] = {}, ["Cosmetics"] = {}, ["Consumables"] = {} }
	profileData.Progression = { ["Level"] = 1, ["Experience"] = 0, ["Milestones"] = {}, ["UnlockedZones"] = {} }
	profileData.Upgrades = {}

	LogAction(player, "RESET_PLAYER", target.Name)
	return true, target.Name .. " has been reset"
end

-- ========================================================================
-- LIFECYCLE & REMOTE CREATION
-- ========================================================================
function AdminService.Init(): ()
	if not FeatureResolver.IsCategoryActive("Admin") then
		print("[INFO] AdminService: Aborted initialization (Zero-Footprint Mode).")
		return
	end

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	local adminRemote = remotes:FindFirstChild("sys_adm") :: RemoteEvent?
	if not adminRemote then
		adminRemote = Instance.new("RemoteEvent")
		adminRemote.Name = "sys_adm"
		adminRemote.Parent = remotes
	end

	local adminCheck = remotes:FindFirstChild("sys_adm_chk") :: RemoteFunction?
	if not adminCheck then
		adminCheck = Instance.new("RemoteFunction")
		adminCheck.Name = "sys_adm_chk"
		adminCheck.Parent = remotes
	end

	adminCheck.OnServerInvoke = function(player: Player): boolean
		return IsAdmin(player)
	end
end

function AdminService.Start(): ()
	if not FeatureResolver.IsCategoryActive("Admin") then
		return
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local adminRemote = remotes:WaitForChild("sys_adm") :: RemoteEvent

	adminRemote.OnServerEvent:Connect(function(player: Player, action: unknown, ...)
		if type(action) ~= "string" or not IsAdmin(player) then return end

		local rawArgs = { ... }
		local safeArgs = {}
		for _, v in ipairs(rawArgs) do
			if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then table.insert(safeArgs, v) end
		end

		local handler = Actions[action]
		if handler then
			local ok, success, msg = pcall(handler, player, safeArgs)
			if ok then
				SendFeedback(player, action, success, msg or "Success")
			else
				SendFeedback(player, action, false, "Server Error: " .. tostring(success))
			end
		end
	end)
	print("[AdminService] Booted successfully.")
end

return AdminService
