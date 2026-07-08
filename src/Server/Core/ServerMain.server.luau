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

-- NetworkService.Init (Phase 1, below) instantiates every remote declared in
-- RemoteNames.Schema with the correct class — the folder just has to exist first.

-- ═══════════════════════════════════════════════════════════════════════════════
-- Feature Resolution
-- ═══════════════════════════════════════════════════════════════════════════════
local FeatureResolver: any = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

-- Genres are mutually exclusive — abort boot naming the exact flags on conflict.
FeatureResolver.AssertGenreExclusivity("ServerMain")
print(("[ServerMain] Active genre: %s"):format(FeatureResolver.GetActiveGenre() or "Global"))

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
local MonetizationService: any = require(Services.MonetizationService)
local AdminService: any        = require(Services.AdminService)
local ChatTagService: any      = require(Services.ChatTagService)
local AntiExploitService: any  = require(Services.AntiExploitService)
local VFXService: any          = require(Services.VFXService)

-- Genre-gated services (WeaponService, MatchStatsService, AuraService,
-- PetService, ClickService, …) are NOT loaded here: they register through
-- FrameworkServer's OPTIONAL_SERVICES table and boot in Phase 3. Loading any
-- of them here as well would run their Init/Start twice (doubled remote
-- connections) — keep this list to always-on core services only (OCP).

-- ═══════════════════════════════════════════════════════════════════════════════
-- Framework Registration
-- ═══════════════════════════════════════════════════════════════════════════════
local FrameworkServer: any = require(ServerScriptService.Server.Core.FrameworkServer)

FrameworkServer.RegisterService("NetworkService", NetworkService)
FrameworkServer.RegisterService("DataService", DataService)
FrameworkServer.RegisterService("LeaderstatsService", LeaderstatsService)
FrameworkServer.RegisterService("LevelService", LevelService)
FrameworkServer.RegisterService("UpgradeService", UpgradeService)
FrameworkServer.RegisterService("QuestService", QuestService)
FrameworkServer.RegisterService("MonetizationService", MonetizationService)
FrameworkServer.RegisterService("AdminService", AdminService)
FrameworkServer.RegisterService("ChatTagService", ChatTagService)
FrameworkServer.RegisterService("AntiExploitService", AntiExploitService)
FrameworkServer.RegisterService("VFXService", VFXService)

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
SafeCall(LevelService, "Init")
SafeCall(UpgradeService, "Init")
SafeCall(QuestService, "Init")
SafeCall(MonetizationService, "Init")
SafeCall(AdminService, "Init")
SafeCall(ChatTagService, "Init")
SafeCall(AntiExploitService, "Init")
SafeCall(VFXService, "Init")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Phase 2: Start (Event connections, loop startup, network routines)
-- ═══════════════════════════════════════════════════════════════════════════════
SafeCall(NetworkService, "Start")
SafeCall(DataService, "Start")
SafeCall(LeaderstatsService, "Start")
SafeCall(LevelService, "Start")
SafeCall(UpgradeService, "Start")
SafeCall(QuestService, "Start")
SafeCall(MonetizationService, "Start")
SafeCall(AdminService, "Start")
SafeCall(ChatTagService, "Start")
SafeCall(AntiExploitService, "Start")
SafeCall(VFXService, "Start")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Phase 3: Framework Boot
-- ═══════════════════════════════════════════════════════════════════════════════
FrameworkServer.Boot()

print("[ServerMain] Boot sequence complete. All services online.")
