--!strict
--@author OrkGabb
--@module ServerMain.server.luau
--@version 1.0
-- src/Server/Core/ServerMain.server.luau
-- Central Server Service Orchestrator (Bootstrapper).
-- Loads and initializes all services through a two-phase lifecycle (Init / Start).

local ServerScriptService: ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Defensive Network Layer: Instantiate critical remote bridges BEFORE any
-- module requires. This prevents client-side WaitForChild stalls even if
-- downstream services crash or are skipped by feature gating.
-- ═══════════════════════════════════════════════════════════════════════════════
local remotesFolder: Folder
do
	local existing: Instance? = ReplicatedStorage:FindFirstChild("Remotes")
	if existing and existing:IsA("Folder") then
		remotesFolder = existing
	else
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end
end

-- Pre-instantiate FPS network bridge so client never blocks on WaitForChild
if not remotesFolder:FindFirstChild("WeaponFireRemote") then
	local weaponRemote: RemoteEvent = Instance.new("RemoteEvent")
	weaponRemote.Name = "WeaponFireRemote"
	weaponRemote.Parent = remotesFolder
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Feature Resolution
-- ═══════════════════════════════════════════════════════════════════════════════
local FeatureResolver: any = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

-- Exclusivity Check
local activeGenres: {string} = FeatureResolver.GetActiveCategories()
local primaryCount: number = 0
for _, genre: string in ipairs(activeGenres) do
	if genre ~= "Global" then
		primaryCount += 1
	end
end
if primaryCount > 1 then
	error("[ServerMain] Hard verification failed: Multiple primary genres active simultaneously. Enforcing single-genre rule.")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Service Imports
-- ═══════════════════════════════════════════════════════════════════════════════
-- Server scripts are all present at server start — direct paths are safe
-- and keep the requires statically resolvable for tooling.
local Services = ServerScriptService.Server.Services

local NetworkService: any      = require(Services.NetworkService)
local DataService: any         = require(Services.DataService)
local LeaderstatsService: any  = require(Services.LeaderstatsService)
local EconomyService: any      = require(Services.EconomyService)
local LevelService: any        = require(Services.LevelService)
local UpgradeService: any      = require(Services.UpgradeService)
local QuestService: any        = require(Services.QuestService)
local MonetizationService: any = require(Services.MonetizationService)
local AdminService: any        = require(Services.AdminService)
local ChatTagService: any      = require(Services.ChatTagService)
local AntiExploitService: any  = require(Services.AntiExploitService)
local VFXService: any          = require(Services.VFXService)

-- Genre-gated services: FPS_Shooter
local WeaponService:    any? = nil
local MatchStatsService: any? = nil
local isFPSActive: boolean = FeatureResolver.IsCategoryActive("FPS_Shooter")
if isFPSActive then
	local function LoadService(name: string): any?
		local mod: Instance? = Services:FindFirstChild(name)
		if not mod then
			warn("[ServerMain] " .. name .. " module not found in Services folder.")
			return nil
		end
		local ok: boolean, result: any = pcall(require, mod)
		if ok then
			print("[ServerMain] " .. name .. " loaded for FPS_Shooter genre.")
			return result
		end
		warn("[ServerMain] " .. name .. " require failed: " .. tostring(result))
		return nil
	end
	WeaponService     = LoadService("WeaponService")
	MatchStatsService = LoadService("MatchStatsService")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Framework Registration
-- ═══════════════════════════════════════════════════════════════════════════════
local FrameworkServer: any = require(ServerScriptService.Server.Core.FrameworkServer)

FrameworkServer.RegisterService("NetworkService", NetworkService)
FrameworkServer.RegisterService("DataService", DataService)
FrameworkServer.RegisterService("LeaderstatsService", LeaderstatsService)
FrameworkServer.RegisterService("EconomyService", EconomyService)
FrameworkServer.RegisterService("LevelService", LevelService)
FrameworkServer.RegisterService("UpgradeService", UpgradeService)
FrameworkServer.RegisterService("QuestService", QuestService)
FrameworkServer.RegisterService("MonetizationService", MonetizationService)
FrameworkServer.RegisterService("AdminService", AdminService)
FrameworkServer.RegisterService("ChatTagService", ChatTagService)
FrameworkServer.RegisterService("AntiExploitService", AntiExploitService)
FrameworkServer.RegisterService("VFXService", VFXService)

if WeaponService then
	FrameworkServer.RegisterService("WeaponService", WeaponService)
end
if MatchStatsService then
	FrameworkServer.RegisterService("MatchStatsService", MatchStatsService)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Safe Lifecycle Call Helper
-- ═══════════════════════════════════════════════════════════════════════════════
local function SafeCall(mod: any, method: string): ()
    if typeof(mod) == "table" and type(mod[method]) == "function" then
        local ok: boolean, err: any = pcall(mod[method])
        if not ok then
            warn(("[ServerMain] %s() failed: %s"):format(method, tostring(err)))
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Phase 1: Init (Remote creation, DataStore initialization, Instance setup)
-- ═══════════════════════════════════════════════════════════════════════════════
SafeCall(NetworkService, "Init")
SafeCall(DataService, "Init")
SafeCall(LeaderstatsService, "Init")
SafeCall(EconomyService, "Init")
SafeCall(LevelService, "Init")
SafeCall(UpgradeService, "Init")
SafeCall(QuestService, "Init")
SafeCall(MonetizationService, "Init")
SafeCall(AdminService, "Init")
SafeCall(ChatTagService, "Init")
SafeCall(AntiExploitService, "Init")
SafeCall(VFXService, "Init")

if WeaponService then
	SafeCall(WeaponService, "Init")
end
if MatchStatsService then
	SafeCall(MatchStatsService, "Init")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Phase 2: Start (Event connections, loop startup, network routines)
-- ═══════════════════════════════════════════════════════════════════════════════
SafeCall(NetworkService, "Start")
SafeCall(DataService, "Start")
SafeCall(LeaderstatsService, "Start")
SafeCall(EconomyService, "Start")
SafeCall(LevelService, "Start")
SafeCall(UpgradeService, "Start")
SafeCall(QuestService, "Start")
SafeCall(MonetizationService, "Start")
SafeCall(AdminService, "Start")
SafeCall(ChatTagService, "Start")
SafeCall(AntiExploitService, "Start")
SafeCall(VFXService, "Start")

if WeaponService then
	SafeCall(WeaponService, "Start")
end
if MatchStatsService then
	SafeCall(MatchStatsService, "Start")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Phase 3: Framework Boot
-- ═══════════════════════════════════════════════════════════════════════════════
FrameworkServer.Boot()

print("[ServerMain] Boot sequence complete. All services online.")
