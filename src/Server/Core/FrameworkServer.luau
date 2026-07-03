--!strict
--@author OrkGabb
--@module FrameworkServer.luau
--@version 1.0
--- @description Server-side toggle-aware bootstrap layer.
---              Reads FeatureToggles and conditionally loads optional services.
---              Services gated behind a `false` toggle are never required —
---              no memory allocation, no event connections.
---
--- NOTE: This module supplements the existing ServerMain.server.lua orchestrator.
---       ServerMain handles always-on core services; FrameworkServer handles
---       toggleable optional services (Dash, Pets, Portals, Trading, Collections, Leaderboards).

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

--------------------------------------------------------------------------------
-- Shared imports
--------------------------------------------------------------------------------
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

--- A service module that conforms to the Init/Start lifecycle contract.
type ServiceModule = {
	Init: (() -> ())?,
	Start: (() -> ())?,
}

--- Map of toggle key → ModuleScript path resolver.
--- Each entry returns the ModuleScript instance for that optional system.
type ToggleEntry = {
	toggleKey: string,
	registerName: string?,
	resolver: () -> ModuleScript,
}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local Services = ServerScriptService.Server.Services

--- Registry of optional server services gated by FeatureToggles.
--- Add new toggleable services here; the bootstrap loop handles the rest.
local OPTIONAL_SERVICES: { ToggleEntry } = {
	{
		toggleKey = "Dash",
		registerName = "DashService",
		resolver  = function(): ModuleScript
			return Services:WaitForChild("DashService") :: ModuleScript
		end,
	},
	{
		toggleKey = "Pet_Simulator",
		registerName = "PetService",
		resolver  = function(): ModuleScript
			return Services:WaitForChild("PetService") :: ModuleScript
		end,
	},
	{
		toggleKey = "Clicker_Farm",
		registerName = "ClickService",
		resolver  = function(): ModuleScript
			return Services:WaitForChild("ClickService") :: ModuleScript
		end,
	},
	{
		toggleKey = "Clicker_Farm",
		registerName = "GoldenDropService",
		resolver  = function(): ModuleScript
			return Services:WaitForChild("GoldenDropService") :: ModuleScript
		end,
	},
	{
		toggleKey = "Aura_Collector",
		registerName = "AuraService",
		resolver  = function(): ModuleScript
			return Services:WaitForChild("AuraService") :: ModuleScript
		end,
	},
	{
		toggleKey = "FPS_Shooter",
		registerName = "WeaponService",
		resolver  = function(): ModuleScript
			return Services:WaitForChild("WeaponService") :: ModuleScript
		end,
	},
	{
		-- FPS-scoped; MatchStatsService.Init additionally self-gates on the
		-- MatchStats config category (both must be enabled).
		toggleKey = "FPS_Shooter",
		registerName = "MatchStatsService",
		resolver  = function(): ModuleScript
			return Services:WaitForChild("MatchStatsService") :: ModuleScript
		end,
	},
	{
		toggleKey = "Portals",
		registerName = "PortalService",
		resolver  = function(): ModuleScript
			return Services:WaitForChild("PortalService") :: ModuleScript
		end,
	},
	{
		toggleKey = "Leaderboards",
		registerName = "LeaderboardService",
		resolver  = function(): ModuleScript
			return Services:WaitForChild("LeaderboardService") :: ModuleScript
		end,
	},
}

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local FrameworkServer = {}
local services: { [string]: any } = {}

--- Registers a service to the service locator pattern.
function FrameworkServer.RegisterService(name: string, module: any): ()
	services[name] = module
end

--- Retrieves a registered service, or a safe dummy if it's missing or toggled off.
function FrameworkServer.GetService(name: string): any?
	local service: any? = services[name]
	if not service then
		return setmetatable({}, {
			__index = function()
				return function()
					return nil
				end
			end
		})
	end
	return service
end

--- Resolves if a feature toggle is enabled.
--- Delegates to FeatureResolver — the SSoT for toggle resolution. (A local
--- reimplementation here previously missed GlobalFlags/Genres sub-tables, so
--- every genre-keyed optional service was silently skipped at boot.)
local function isFeatureEnabled(key: string): boolean
	return FeatureResolver.IsCategoryActive(key) == true
end

--- Loads, initialises, and starts all optional services whose toggle is `true`.
--- Called once from ServerMain at the end of its own boot sequence.
function FrameworkServer.Boot(): ()
	local loaded: { ServiceModule } = {}

	-- Phase 1: Conditionally require + Init
	for _, entry: ToggleEntry in OPTIONAL_SERVICES do
		local enabled: boolean = isFeatureEnabled(entry.toggleKey)
		if enabled then
			local ok: boolean, result: any = pcall(function(): any
				return require(entry.resolver())
			end)

			if ok and type(result) == "table" then
				local service: ServiceModule = result :: ServiceModule
				if type(service.Init) == "function" then
					local initOk: boolean, initErr: any = pcall(service.Init :: () -> ())
					if not initOk then
						warn(("[FrameworkServer] %s.Init() FAILED: %s"):format(
							entry.toggleKey, tostring(initErr)))
					end
				end
				table.insert(loaded, service)

				local regName: string = entry.registerName or (entry.toggleKey .. "Service")
				FrameworkServer.RegisterService(regName, service)
				print(("[FrameworkServer] Loaded optional service: %s"):format(entry.toggleKey))
			else
				warn(("[FrameworkServer] Failed to require %s: %s"):format(
					entry.toggleKey, tostring(result)))
			end
		else
			print(("[FrameworkServer] Skipped disabled service: %s"):format(entry.toggleKey))
		end
	end

	-- Phase 2: Start (all Inits complete before any Start runs)
	for _, service: ServiceModule in loaded do
		if type(service.Start) == "function" then
			local startOk: boolean, startErr: any = pcall(service.Start :: () -> ())
			if not startOk then
				warn(("[FrameworkServer] .Start() FAILED: %s"):format(tostring(startErr)))
			end
		end
	end

	print("[FrameworkServer] Optional services boot complete.")
end

return FrameworkServer
