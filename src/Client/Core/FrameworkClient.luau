--!strict
--@author OrkGabb
--@module FrameworkClient.luau
--@version 1.0
--- @description Client-side toggle-aware bootstrap layer.
---              Reads FeatureToggles and conditionally loads optional controllers.
---              Controllers gated behind a `false` toggle are never required —
---              no memory allocation, no event connections, no UI elements.
---
--- NOTE: This module supplements the existing ClientMain.client.lua orchestrator.
---       ClientMain handles always-on core controllers; FrameworkClient handles
---       toggleable optional controllers (Dash, Pets, Portals, MatchStats).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------------------------------------
-- Shared imports
--------------------------------------------------------------------------------
local FeatureToggles = require(ReplicatedStorage.Shared.Config.FeatureToggles)

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

--- A controller module that conforms to the Init/Start lifecycle contract.
type ControllerModule = {
	Init: (() -> ())?,
	Start: (() -> ())?,
}

--- Map of toggle key → ModuleScript path resolver.
type ToggleEntry = {
	toggleKey: string,
	registerName: string?,
	resolver: () -> ModuleScript,
}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local Controllers = script.Parent.Parent:WaitForChild("Controllers")

--- Registry of optional client controllers gated by FeatureToggles.
--- Add new toggleable controllers here; the bootstrap loop handles the rest.
---
--- IMPORTANT: Only add entries for ModuleScripts that physically exist in
--- the Controllers folder. Missing modules cause infinite WaitForChild yields.
local OPTIONAL_CONTROLLERS: { ToggleEntry } = {
	{
		toggleKey = "Dash",
		registerName = "DashController",
		resolver  = function(): ModuleScript
			return Controllers:WaitForChild("DashController") :: ModuleScript
		end,
	},
	{
		toggleKey = "Portals",
		registerName = "PortalController",
		resolver  = function(): ModuleScript
			return Controllers:WaitForChild("PortalController") :: ModuleScript
		end,
	},
	{
		toggleKey = "FPS_Shooter",
		registerName = "ViewmodelController",
		resolver  = function(): ModuleScript
			return Controllers:WaitForChild("ViewmodelController") :: ModuleScript
		end,
	},
	{
		-- MatchStatsController must Init before WeaponController.Start references it.
		-- WeaponController also requires it directly, so this entry is a safety Init/Start guarantee.
		toggleKey    = "MatchStats",
		registerName = "MatchStatsController",
		resolver     = function(): ModuleScript
			return Controllers:WaitForChild("MatchStatsController") :: ModuleScript
		end,
	},
	-- NOTE: LeaderboardController is NOT listed here because no LeaderboardController
	-- module exists in the Controllers folder. The LeaderboardService (server-side)
	-- handles physical leaderboard board spawning independently and requires no
	-- client-side counterpart at this time. Adding it here would cause an infinite
	-- WaitForChild yield that freezes the entire boot sequence.
}

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local FrameworkClient = {}
local controllers: { [string]: any } = {}

--- Registers a controller to the service locator pattern.
function FrameworkClient.RegisterController(name: string, module: any): ()
	controllers[name] = module
end

--- Retrieves a registered controller, or a safe dummy if it's missing or toggled off.
function FrameworkClient.GetController(name: string): any?
	local controller: any? = controllers[name]
	if not controller then
		return setmetatable({}, {
			__index = function()
				return function()
					return nil
				end
			end,
		})
	end
	return controller
end

--- Resolves if a feature toggle is enabled, supporting both boolean values and table configs.
local function isFeatureEnabled(key: string): boolean
	if type(FeatureToggles) ~= "table" then return false end
	local toggle: any = (FeatureToggles :: any)[key]
	if toggle == nil then
		toggle = (FeatureToggles :: any)[key .. "Config"]
	end
	if type(toggle) == "table" then
		return toggle.Enabled == true
	end
	return type(toggle) == "boolean" and toggle or false
end

--- Loads, initialises, and starts all optional controllers whose toggle is `true`.
--- Called once from ClientMain at the end of its own boot sequence.
function FrameworkClient.Boot(): ()
	local loaded: { ControllerModule } = {}

	-- Phase 1: Conditionally require + Init
	for _, entry: ToggleEntry in OPTIONAL_CONTROLLERS do
		local enabled: boolean = isFeatureEnabled(entry.toggleKey)
		if enabled then
			local ok: boolean, result: any = pcall(function(): any
				return require(entry.resolver())
			end)

			if ok and type(result) == "table" then
				local controller: ControllerModule = result :: ControllerModule
				if type(controller.Init) == "function" then
					local initOk: boolean, initErr: any = pcall(controller.Init :: () -> ())
					if not initOk then
						warn(("[FrameworkClient] %s.Init() FAILED: %s"):format(
							entry.toggleKey, tostring(initErr)))
					end
				end
				table.insert(loaded, controller)

				local regName: string = entry.registerName or (entry.toggleKey .. "Controller")
				FrameworkClient.RegisterController(regName, controller)
				print(("[FrameworkClient] Loaded optional controller: %s"):format(entry.toggleKey))
			else
				warn(("[FrameworkClient] Failed to require %s: %s"):format(
					entry.toggleKey, tostring(result)))
			end
		else
			print(("[FrameworkClient] Skipped disabled controller: %s"):format(entry.toggleKey))
		end
	end

	-- Phase 2: Start (all Inits complete before any Start runs)
	for _, controller: ControllerModule in loaded do
		if type(controller.Start) == "function" then
			task.spawn(function(): ()
				local startOk: boolean, startErr: any = pcall(controller.Start :: () -> ())
				if not startOk then
					warn(("[FrameworkClient] .Start() FAILED: %s"):format(tostring(startErr)))
				end
			end)
		end
	end

	print("[FrameworkClient] Optional controllers boot complete.")
end

return FrameworkClient
