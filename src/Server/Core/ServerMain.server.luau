--!strict
--@author OrkGabb
--@module ServerMain.server.luau
--@version 1.0
-- src/Server/Core/ServerMain.server.luau
-- Central Server Service Orchestrator (Bootstrapper).
-- Loads and initializes all services through a two-phase lifecycle (Init / Start).

local ServerScriptService: ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

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

-- NetworkService.Init (Phase 1, below) instantiates every remote declared in
-- RemoteNames.Schema with the correct class — the folder just has to exist first.

-- ═══════════════════════════════════════════════════════════════════════════════
-- Feature Resolution
-- ═══════════════════════════════════════════════════════════════════════════════
local FeatureResolver: any = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

-- Genres are mutually exclusive — abort boot naming the exact flags on conflict.
FeatureResolver.AssertGenreExclusivity("ServerMain")
print(("[ServerMain] Active genre: %s"):format(FeatureResolver.GetActiveGenre() or "Global"))

if RunService:IsStudio() then
	require(ReplicatedStorage.Shared.Modules.ConfigAudit).PrintReport()
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
local LevelService: any        = require(Services.LevelService)
local UpgradeService: any      = require(Services.UpgradeService)
local QuestService: any        = require(Services.QuestService)
local DailyService: any        = require(Services.DailyService)
local MonetizationService: any = require(Services.MonetizationService)
local AdminService: any        = require(Services.AdminService)
local ChatTagService: any      = require(Services.ChatTagService)
local AntiExploitService: any  = require(Services.AntiExploitService)
local VFXService: any          = require(Services.VFXService)
local ItemService: any         = require(Services.ItemService)

-- Genre-gated services (WeaponService, MatchStatsService, AuraService,
-- PetService, ClickService, …) are NOT loaded here: they register through
-- FrameworkServer's OPTIONAL_SERVICES table and boot in Phase 3. Loading any
-- of them here as well would run their Init/Start twice (doubled remote
-- connections) — keep this list to always-on core services only (OCP).

-- ═══════════════════════════════════════════════════════════════════════════════
-- Framework Registration
-- ═══════════════════════════════════════════════════════════════════════════════
local FrameworkServer: any = require(ServerScriptService.Server.Core.FrameworkServer)
local BootTelemetry: any = require(ServerScriptService.Server.Core.BootTelemetry)

FrameworkServer.RegisterService("NetworkService", NetworkService)
FrameworkServer.RegisterService("DataService", DataService)
FrameworkServer.RegisterService("LeaderstatsService", LeaderstatsService)
FrameworkServer.RegisterService("LevelService", LevelService)
FrameworkServer.RegisterService("UpgradeService", UpgradeService)
FrameworkServer.RegisterService("QuestService", QuestService)
FrameworkServer.RegisterService("DailyService", DailyService)
FrameworkServer.RegisterService("MonetizationService", MonetizationService)
FrameworkServer.RegisterService("AdminService", AdminService)
FrameworkServer.RegisterService("ChatTagService", ChatTagService)
FrameworkServer.RegisterService("AntiExploitService", AntiExploitService)
FrameworkServer.RegisterService("VFXService", VFXService)
FrameworkServer.RegisterService("ItemService", ItemService)

-- ═══════════════════════════════════════════════════════════════════════════════
-- Safe Lifecycle Call Helper
-- ═══════════════════════════════════════════════════════════════════════════════
-- DEAD CODE: superseded by BootTelemetry.TrackedCall at every call site below.
-- Left in place intentionally — removal is a separate future decision.
local function _SafeCall(mod: any, method: string): ()
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
BootTelemetry.BeginSequence()
BootTelemetry.TrackedCall(NetworkService, "Init", "NetworkService")
BootTelemetry.TrackedCall(DataService, "Init", "DataService")
BootTelemetry.TrackedCall(LeaderstatsService, "Init", "LeaderstatsService")
BootTelemetry.TrackedCall(LevelService, "Init", "LevelService")
BootTelemetry.TrackedCall(UpgradeService, "Init", "UpgradeService")
BootTelemetry.TrackedCall(QuestService, "Init", "QuestService")
BootTelemetry.TrackedCall(DailyService, "Init", "DailyService")
BootTelemetry.TrackedCall(MonetizationService, "Init", "MonetizationService")
BootTelemetry.TrackedCall(AdminService, "Init", "AdminService")
BootTelemetry.TrackedCall(ChatTagService, "Init", "ChatTagService")
BootTelemetry.TrackedCall(AntiExploitService, "Init", "AntiExploitService")
BootTelemetry.TrackedCall(VFXService, "Init", "VFXService")
BootTelemetry.TrackedCall(ItemService, "Init", "ItemService")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Phase 2: Start (Event connections, loop startup, network routines)
-- ═══════════════════════════════════════════════════════════════════════════════
BootTelemetry.TrackedCall(NetworkService, "Start", "NetworkService")
BootTelemetry.TrackedCall(DataService, "Start", "DataService")
BootTelemetry.TrackedCall(LeaderstatsService, "Start", "LeaderstatsService")
BootTelemetry.TrackedCall(LevelService, "Start", "LevelService")
BootTelemetry.TrackedCall(UpgradeService, "Start", "UpgradeService")
BootTelemetry.TrackedCall(QuestService, "Start", "QuestService")
BootTelemetry.TrackedCall(DailyService, "Start", "DailyService")
BootTelemetry.TrackedCall(MonetizationService, "Start", "MonetizationService")
BootTelemetry.TrackedCall(AdminService, "Start", "AdminService")
BootTelemetry.TrackedCall(ChatTagService, "Start", "ChatTagService")
BootTelemetry.TrackedCall(AntiExploitService, "Start", "AntiExploitService")
BootTelemetry.TrackedCall(VFXService, "Start", "VFXService")
BootTelemetry.TrackedCall(ItemService, "Start", "ItemService")
BootTelemetry.PrintSummary()

-- ═══════════════════════════════════════════════════════════════════════════════
-- Phase 3: Framework Boot
-- ═══════════════════════════════════════════════════════════════════════════════
FrameworkServer.Boot()

print("[ServerMain] Boot sequence complete. All services online.")
