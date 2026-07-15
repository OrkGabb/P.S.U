--!strict
-- @Author @OrkGabb

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui: StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

local LoadingController = require(script.Parent:WaitForChild("LoadingController")) :: any
LoadingController.Init()
LoadingController.Start()

local ClientMain = {}

-- Must stay comfortably under LoadingController's MAX_PRELOAD_TIMEOUT (10s) so
-- a boot failure here is signaled while its safety loop is still running,
-- instead of racing it as a second, independent timeout.
local WAIT_TIMEOUT = 8

-- Waits for a chain of instances, each bounded by WAIT_TIMEOUT. Returns nil
-- (instead of hanging or erroring) if any link in the chain is missing.
local function waitChain(root: Instance, ...: string): Instance?
	local current = root
	for _, name in ipairs({...}) do
		local nextChild = current:WaitForChild(name, WAIT_TIMEOUT)
		if not nextChild then
			return nil
		end
		current = nextChild
	end
	return current
end

local ClientFolder: any = nil
local FrameworkClient: any = nil
local FeatureResolver: any = nil

local bootOk: boolean, bootErr: any = pcall(function()
	local clientFolder = waitChain(StarterPlayer, "StarterPlayerScripts", "Client")
	if not clientFolder then
		error("timed out waiting for StarterPlayerScripts.Client")
	end
	ClientFolder = clientFolder

	local frameworkClientModule = waitChain(clientFolder, "Core", "FrameworkClient")
	if not frameworkClientModule then
		error("timed out waiting for Client.Core.FrameworkClient")
	end
	FrameworkClient = require(frameworkClientModule)

	local featureResolverModule = waitChain(ReplicatedStorage, "Shared", "Modules", "FeatureResolver")
	if not featureResolverModule then
		error("timed out waiting for Shared.Modules.FeatureResolver")
	end
	FeatureResolver = require(featureResolverModule)
end)

if not bootOk then
	warn(("[ClientMain] Boot dependency resolution failed: %s"):format(tostring(bootErr)))
	LoadingController.SignalFailure(tostring(bootErr))
	return ClientMain
end

local function start(): ()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)


	-- Genres are mutually exclusive — abort boot naming the exact flags on conflict.
	FeatureResolver.AssertGenreExclusivity("ClientMain")
	print(("[ClientMain] Active genre: %s"):format(FeatureResolver.GetActiveGenre() or "Global"))

	local controllersFolder: Folder = ClientFolder:WaitForChild("Controllers") :: Folder
	local startupOrder: { any } = {}

	local SKIP_CONTROLLERS: { [string]: boolean } = {
		SidebarController = true, -- Consolidated into UIController
	}

	local isClickerActive: boolean = FeatureResolver.IsCategoryActive("Clicker_Farm")
	local isAuraActive: boolean = FeatureResolver.IsCategoryActive("Aura_Collector")
	local isRPGActive: boolean = FeatureResolver.IsCategoryActive("RPG_Adventure")
	local isPetActive: boolean = FeatureResolver.IsCategoryActive("Pet_Simulator")
	local isFPSActive: boolean = FeatureResolver.IsCategoryActive("FPS_Shooter")
	local isMonetizationActive: boolean = FeatureResolver.IsCategoryActive("Monetization")
	local isDailyActive: boolean = FeatureResolver.IsCategoryActive("Retention") or FeatureResolver.IsCategoryActive("Daily")
	local isDashActive: boolean = FeatureResolver.IsCategoryActive("Dash") or FeatureResolver.IsCategoryActive("DashConfig")

	if not isClickerActive then
		SKIP_CONTROLLERS["ClickController"] = true
		SKIP_CONTROLLERS["GoldenDropController"] = true
	end

	-- Roll UI, collection index and aura VFX are Aura_Collector systems
	if not isAuraActive then
		SKIP_CONTROLLERS["IndexController"] = true
		SKIP_CONTROLLERS["MainUIController"] = true
		SKIP_CONTROLLERS["AuraVFXController"] = true
	end

	-- Companion rendering + egg shop/inventory UI
	if not isPetActive then
		SKIP_CONTROLLERS["PetController"] = true
		SKIP_CONTROLLERS["PetsUIController"] = true
	end

	if not isRPGActive then
		SKIP_CONTROLLERS["QuestsController"] = true
	end

	if not (isRPGActive or isFPSActive) then
		SKIP_CONTROLLERS["WeaponController"] = true
		SKIP_CONTROLLERS["StatusHUDController"] = true
		SKIP_CONTROLLERS["ViewmodelController"] = true
		SKIP_CONTROLLERS["MatchStatsController"] = true
	end

	if not isDailyActive then
		SKIP_CONTROLLERS["DailyUIController"] = true
	end

	if not isMonetizationActive then
		SKIP_CONTROLLERS["StoreController"] = true
	end

	if not isDashActive then
		SKIP_CONTROLLERS["DashController"] = true
	end

	if not (isClickerActive or isRPGActive or isAuraActive) then
		SKIP_CONTROLLERS["OnboardingController"] = true
	end

	-- SkillsController and BagController are deliberately NOT genre-gated: they
	-- are the genre-neutral player chrome (masteries + inventory), and gating
	-- them meant a core-only boot left the sidebar with one lone button. They
	-- now always load and render whatever the registries hold for the active
	-- categories — an empty list when no genre is enabled.

	-- Phase 1: require + Init (pcall-protected)
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

	-- Phase 2: Start
	for _, controller: any in ipairs(startupOrder) do
		if type(controller.Start) == "function" then
			task.spawn(function()
				controller.Start()
			end)
		end
	end

	LoadingController.SignalReady()
end

start()

FrameworkClient.Boot()

return ClientMain
