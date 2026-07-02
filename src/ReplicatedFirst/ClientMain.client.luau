--!strict
--@author OrkGabb
--@module ClientMain.client.luau
--@version 1.0
-- src/ReplicatedFirst/ClientMain.client.luau
-- Client-side bootstrapper that dynamically loads and manages the lifecycle of controllers.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui: StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

-- Immediate Bootstrapper UI and preloading
local LoadingController = require(script.Parent:WaitForChild("LoadingController")) :: any
LoadingController.Init()
LoadingController.Start()

local ClientMain = {}

local ClientFolder = StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("Client")
local FrameworkClient: any = require(
	ClientFolder:WaitForChild("Core"):WaitForChild("FrameworkClient")
)
local FeatureResolver: any = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("FeatureResolver")
)

local function start(): ()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)



	local controllersFolder: Folder = ClientFolder:WaitForChild("Controllers") :: Folder
	local startupOrder: { any } = {}

	local SKIP_CONTROLLERS: { [string]: boolean } = {
		SidebarController = true, -- Consolidated into UIController
	}

	-- Dynamic Category Resolution for Gating
	local isClickerActive: boolean = FeatureResolver.IsCategoryActive("Clicker_Farm")
	local isAuraActive: boolean = FeatureResolver.IsCategoryActive("Aura_Collector")
	local isRPGActive: boolean = FeatureResolver.IsCategoryActive("RPG_Adventure")
	local isPetActive: boolean = FeatureResolver.IsCategoryActive("Pet_Simulator")
	local isFPSActive: boolean = FeatureResolver.IsCategoryActive("FPS_Shooter")
	local isMonetizationActive: boolean = FeatureResolver.IsCategoryActive("Monetization")
	local isDailyActive: boolean = FeatureResolver.IsCategoryActive("Retention") or FeatureResolver.IsCategoryActive("Daily")
	local isDashActive: boolean = FeatureResolver.IsCategoryActive("Dash") or FeatureResolver.IsCategoryActive("DashConfig")
	local isForgeActive: boolean = FeatureResolver.IsCategoryActive("Forge")
	local isInventoryActive: boolean = isRPGActive or isPetActive or FeatureResolver.IsCategoryActive("Inventory") or isForgeActive

	-- Exclusivity Check
	local activeGenres = FeatureResolver.GetActiveCategories()
	local primaryCount = 0
	for _, genre in ipairs(activeGenres) do
		if genre ~= "Global" then
			primaryCount += 1
		end
	end
	if primaryCount > 1 then
		error("[ClientMain] Hard verification failed: Multiple primary genres active simultaneously. Enforcing single-genre rule.")
	end

	-- Clicker category
	if not isClickerActive then
		SKIP_CONTROLLERS["ClickController"] = true
		SKIP_CONTROLLERS["GoldenDropController"] = true
	end

	-- Aura category (roll UI + collection index are Aura_Collector systems)
	if not isAuraActive then
		SKIP_CONTROLLERS["IndexController"] = true
		SKIP_CONTROLLERS["MainUIController"] = true
	end

	-- RPG category
	if not isRPGActive then
		SKIP_CONTROLLERS["QuestsController"] = true
	end

	-- Forge category
	if not isForgeActive then
		SKIP_CONTROLLERS["ForgeController"] = true
	end

	-- RPG or FPS category
	if not (isRPGActive or isFPSActive) then
		SKIP_CONTROLLERS["WeaponController"] = true
		SKIP_CONTROLLERS["StatusHUDController"] = true
	end

	-- Inventory category
	if not isInventoryActive then
		SKIP_CONTROLLERS["BagController"] = true
	end

	-- Daily rewards
	if not isDailyActive then
		SKIP_CONTROLLERS["DailyUIController"] = true
	end

	-- Monetization
	if not isMonetizationActive then
		SKIP_CONTROLLERS["StoreController"] = true
	end

	-- Dash
	if not isDashActive then
		SKIP_CONTROLLERS["DashController"] = true
	end

	-- Onboarding
	if not (isClickerActive or isRPGActive) then
		SKIP_CONTROLLERS["OnboardingController"] = true
	end

	-- Skills category
	local isSkillsActive: boolean = isClickerActive or isRPGActive or isFPSActive or isPetActive
	if not isSkillsActive then
		SKIP_CONTROLLERS["SkillsController"] = true
	end

	-- Phase 1: Requirement and Initialization (pcall-protected)
	for _, child: Instance in ipairs(controllersFolder:GetChildren()) do
		if child:IsA("ModuleScript") and not SKIP_CONTROLLERS[child.Name] then
			local ok: boolean, controller: any = pcall(require, child)
			if ok and type(controller) == "table" then
				table.insert(startupOrder, controller)
				FrameworkClient.RegisterController(child.Name, controller)

				if type(controller.Init) == "function" then
					local initOk: boolean, initErr: any = pcall(controller.Init)
					if not initOk then
						warn(("[ClientMain] %s.Init() FAILED: %s"):format(child.Name, tostring(initErr)))
					end
				end
			else
				warn(("[ClientMain] Failed to require %s: %s"):format(child.Name, tostring(controller)))
			end
		end
	end

	-- Phase 2: Execution (Start)
	for _, controller: any in ipairs(startupOrder) do
		if type(controller.Start) == "function" then
			task.spawn(function()
				controller.Start()
			end)
		end
	end

	-- Signal that all core controllers are online
	LoadingController.SignalReady()
end

start()

FrameworkClient.Boot()

return ClientMain
