--!strict
--@author OrkGabb
--@module FrameworkServer.luau
--@version 1.0
--- Server-side toggle-aware bootstrap layer. Reads FeatureToggles and
--- conditionally loads optional services — a service gated behind a `false`
--- toggle is never required, so there's no allocation or event connections.
---
--- Supplements ServerMain.server.lua: ServerMain handles always-on core
--- services, this handles toggleable optional ones (Dash, Pets, Portals,
--- Trading, Collections, Leaderboards).

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

type ServiceModule = {
	Init: (() -> ())?,
	Start: (() -> ())?,
}

type ToggleEntry = {
	toggleKey: string,
	registerName: string?,
	resolver: () -> ModuleScript,
}

local Services = ServerScriptService.Server.Services

-- Add new toggleable services here; the bootstrap loop handles the rest.
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

local FrameworkServer = {}
local services: { [string]: any } = {}

function FrameworkServer.RegisterService(name: string, module: any): ()
	services[name] = module
end

-- Returns a safe no-op dummy if the service is missing or toggled off, so
-- callers don't need to nil-check before calling into an optional service.
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

-- Delegates to FeatureResolver, the SSoT for toggle resolution. (A local
-- reimplementation here previously missed the GlobalFlags/Genres sub-tables,
-- so every genre-keyed optional service was silently skipped at boot.)
local function isFeatureEnabled(key: string): boolean
	return FeatureResolver.IsCategoryActive(key) == true
end

-- Called once from ServerMain at the end of its own boot sequence.
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
