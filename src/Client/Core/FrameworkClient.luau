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

local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

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

--- Registry of optional client controllers gated by FeatureToggles.
--- Add new toggleable controllers here; the bootstrap loop handles the rest.
---
--- IMPORTANT: Only add entries for ModuleScripts that physically exist in
--- the Controllers folder. Missing modules cause infinite WaitForChild yields.
local OPTIONAL_CONTROLLERS: { ToggleEntry } = {
	-- INTENTIONALLY EMPTY. Every controller that ships in the Controllers
	-- folder is loaded (and genre-gated) by ClientMain's folder scan + skip
	-- lists — the single client-side loader. Listing one of those modules
	-- here as well would run its Init/Start twice (doubled connections).
	--
	-- Use this table only for buyer-added controllers that live OUTSIDE the
	-- scanned Controllers folder and need toggle-gated lifecycle management.
	-- Only reference ModuleScripts that physically exist: a missing module
	-- infinite-yields the boot sequence on WaitForChild.
}

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

--- Resolves if a feature toggle is enabled.
--- Delegates to FeatureResolver — the SSoT for toggle resolution. (A local
--- reimplementation here previously missed GlobalFlags/Genres sub-tables, so
--- genre-keyed optional controllers — ViewmodelController, DashController —
--- were silently skipped at boot.)
local function isFeatureEnabled(key: string): boolean
	return FeatureResolver.IsCategoryActive(key) == true
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
