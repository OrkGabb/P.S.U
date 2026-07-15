--!strict
-- @Author @OrkGabb

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LoadingController = {}
LoadingController.Name = "LoadingController"

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local MAX_PRELOAD_TIMEOUT = 10 -- safety timeout to prevent infinite menu lockups
-- Per-instance WaitForChild timeout used below and by ClientMain.client.luau's own
-- boot resolution. Must stay comfortably under MAX_PRELOAD_TIMEOUT so a boot
-- failure is signaled (via SignalFailure) while this file's safety loop is
-- still running, instead of racing it independently.
local BOOT_WAIT_TIMEOUT = 8

local loadingActive = true
local screenGui: ScreenGui? = nil
local background: Frame? = nil
local controls: any = nil
local clientMainReady = false
local clientMainFailed = false
local failureReason: string? = nil

-- Waits for a chain of instances, each bounded by BOOT_WAIT_TIMEOUT. Returns
-- nil (instead of hanging or erroring) if any link in the chain is missing.
local function waitChain(root: Instance, ...: string): Instance?
	local current = root
	for _, name in ipairs({...}) do
		local nextChild = current:WaitForChild(name, BOOT_WAIT_TIMEOUT)
		if not nextChild then
			return nil
		end
		current = nextChild
	end
	return current
end

-- Same as waitChain, but requires the resolved ModuleScript. Returns nil on
-- either a missing instance or a require() error — callers treat both as
-- "dependency unavailable" and fall back accordingly.
local function tryRequireChain(root: Instance, ...: string): any?
	local moduleScript = waitChain(root, ...)
	if not moduleScript then
		return nil
	end
	local ok, result = pcall(require, moduleScript)
	if not ok then
		return nil
	end
	return result
end

function LoadingController.SignalReady()
	clientMainReady = true
end

-- Signal from ClientMain that boot failed unrecoverably. The safety loop below
-- observes this and hard-locks on an error screen instead of fading out and
-- releasing controls into a client with no controllers initialized.
function LoadingController.SignalFailure(reason: string): ()
	clientMainFailed = true
	failureReason = reason
end

function LoadingController.Init(): ()
	-- non-fatal: logging only
	local DebugUtility = tryRequireChain(ReplicatedStorage, "Shared", "Modules", "DebugUtility")
	if DebugUtility then
		DebugUtility.Log("LoadingController", "Initializing dynamic loading bootstrapper...")
	end

	-- Lock controls immediately to prevent player movement during load
	pcall(function()
		local playerScripts = LocalPlayer:WaitForChild("PlayerScripts", 10)
		if playerScripts then
			local playerModule = require(playerScripts:WaitForChild("PlayerModule", 10) :: ModuleScript) :: any
			if playerModule and playerModule.GetControls then
				controls = playerModule:GetControls()
				if controls and controls.Disable then
					controls:Disable()
				end
			end
		end
	end)

	-- Created synchronously so the viewport is blocked instantly
	local newScreenGui = Instance.new("ScreenGui")
	newScreenGui.Name = "FrameworkLoadingScreen"
	newScreenGui.IgnoreGuiInset = true
	newScreenGui.ResetOnSpawn = false
	newScreenGui.DisplayOrder = 9999
	newScreenGui.Parent = PlayerGui
	screenGui = newScreenGui

	local newBg = Instance.new("Frame")
	newBg.Size = UDim2.new(1, 0, 1, 0)
	newBg.BackgroundColor3 = Color3.fromRGB(15, 15, 17)
	newBg.BorderSizePixel = 0
	newBg.Parent = newScreenGui
	background = newBg
end

function LoadingController.Start(): ()
	task.spawn(function()
		LoadingController.CreateAndAnimateHUD()
	end)
end

function LoadingController.CreateAndAnimateHUD()
	if not screenGui or not background then return end

	-- Dynamically load FeatureResolver and VFXRegistry. Neither is fatal to the
	-- loading screen itself if missing — ClientMain's own dependency resolution
	-- is the authoritative fatal-failure channel (via SignalFailure); here we
	-- just fall back to sane defaults so the HUD still renders.
	local FeatureResolver = tryRequireChain(ReplicatedStorage, "Shared", "Modules", "FeatureResolver")
	local VFXRegistry = tryRequireChain(ReplicatedStorage, "Shared", "Config", "VFXRegistry") or {}

	local branding = (FeatureResolver and FeatureResolver.GetCategoryConfig("Branding"))
		or { GameName = "YOUR PROJECT", Subtitle = "FRAMEWORK CORE ACTIVE" }

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(0.8, 0, 0.2, 0)
	titleLabel.Position = UDim2.new(0.1, 0, 0.35, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 42
	titleLabel.Text = string.upper(branding.GameName)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.Parent = background

	local genreLabel = Instance.new("TextLabel")
	genreLabel.Size = UDim2.new(0.8, 0, 0.05, 0)
	genreLabel.Position = UDim2.new(0.1, 0, 0.52, 0)
	genreLabel.BackgroundTransparency = 1
	genreLabel.TextColor3 = Color3.fromRGB(0, 255, 120)
	genreLabel.Font = Enum.Font.GothamMedium
	genreLabel.TextSize = 16
	genreLabel.TextXAlignment = Enum.TextXAlignment.Center
	genreLabel.Parent = background

	local activeTemplates: {string} = {}
	if FeatureResolver and FeatureResolver.IsCategoryActive("FPS_Shooter") then table.insert(activeTemplates, "FPS SHOOTER") end
	if FeatureResolver and FeatureResolver.IsCategoryActive("Clicker_Farm") then table.insert(activeTemplates, "CLICKER FARM") end
	if FeatureResolver and FeatureResolver.IsCategoryActive("Pet_Simulator") then table.insert(activeTemplates, "PET SIMULATOR") end
	if FeatureResolver and FeatureResolver.IsCategoryActive("RPG_Adventure") then table.insert(activeTemplates, "RPG ADVENTURE") end

	if #activeTemplates > 0 then
		genreLabel.Text = string.upper(branding.Subtitle) .. " + " .. table.concat(activeTemplates, " + ")
	else
		genreLabel.Text = string.upper(branding.Subtitle)
	end

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(0.8, 0, 0.05, 0)
	statusLabel.Position = UDim2.new(0.1, 0, 0.65, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 14
	statusLabel.Text = "PRE-LOADING ASSET PIPELINES..."
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center
	statusLabel.Parent = background

	local progressBackground = Instance.new("Frame")
	progressBackground.Size = UDim2.new(0.4, 0, 0.008, 0)
	progressBackground.Position = UDim2.new(0.3, 0, 0.72, 0)
	progressBackground.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	progressBackground.BorderSizePixel = 0
	progressBackground.Parent = background

	local uiCornerBg = Instance.new("UICorner")
	uiCornerBg.CornerRadius = UDim.new(0.5, 0)
	uiCornerBg.Parent = progressBackground

	local progressBar = Instance.new("Frame")
	progressBar.Size = UDim2.new(0, 0, 1, 0)
	progressBar.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
	progressBar.BorderSizePixel = 0
	progressBar.Parent = progressBackground

	local uiCornerBar = Instance.new("UICorner")
	uiCornerBar.CornerRadius = UDim.new(0.5, 0)
	uiCornerBar.Parent = progressBar

	-- Only queue what the registries reference, instead of a blind GetDescendants scan
	local assetQueue: {string} = {}

	for _, effectConfig in pairs(VFXRegistry) do
		if effectConfig.AudioId then
			table.insert(assetQueue, effectConfig.AudioId)
		end
		if effectConfig.AssetId then
			table.insert(assetQueue, effectConfig.AssetId)
		end
	end

	local totalAssets = #assetQueue
	local completedAssets = 0

	if totalAssets > 0 then
		for _, assetId in ipairs(assetQueue) do
			if not loadingActive then break end
			
			local tempInstance: Instance? = nil
			if string.match(assetId, "audio") or string.match(assetId, "911422") then
				local sound = Instance.new("Sound")
				sound.SoundId = assetId
				tempInstance = sound
			else
				local decal = Instance.new("Decal")
				decal.Texture = assetId
				tempInstance = decal
			end

			if tempInstance then
				task.spawn(function()
					local _success, _ = pcall(function()
						ContentProvider:PreloadAsync({tempInstance :: Instance})
					end)
					
					completedAssets += 1
					local progressRatio = math.clamp(completedAssets / totalAssets, 0, 1)
					
					TweenService:Create(progressBar, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
						Size = UDim2.new(progressRatio, 0, 1, 0)
					}):Play()

					statusLabel.Text = string.format("PRE-LOADING ASSETS: %d/%d (%d%%)", completedAssets, totalAssets, math.round(progressRatio * 100))
					
					tempInstance:Destroy()
				end)
			end
			
			-- Micro-delay to avoid throttling the frame rate during boot
			task.wait(0.01)
		end
	else
		TweenService:Create(progressBar, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
			Size = UDim2.new(1, 0, 1, 0)
		}):Play()
		statusLabel.Text = "PRE-LOAD SYSTEM COMPLETED"
	end

	-- Timeout safety loop ensuring slow networks don't freeze the boot sequence.
	-- Also breaks early on a signaled boot failure, so that branch (below) runs
	-- while there's still timeout budget left rather than only at the 10s cap.
	local elapsed = 0
	while (completedAssets < totalAssets or (not clientMainReady and not clientMainFailed)) and elapsed < MAX_PRELOAD_TIMEOUT do
		elapsed += task.wait()
	end

	if clientMainFailed then
		-- Hard lock: boot failed unrecoverably (see ClientMain.client.luau).
		-- Leave the loading screen up and controls disabled rather than
		-- releasing the player into a client with no controllers initialized —
		-- a stuck loading screen with a clear error is preferable to a
		-- silently broken, player-controllable game world.
		statusLabel.Text = "FAILED TO LOAD — PLEASE REJOIN"
		statusLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
		progressBar.BackgroundColor3 = Color3.fromRGB(255, 90, 90)
		warn(("[LoadingController] Boot failed, holding on error screen: %s"):format(tostring(failureReason)))
		return
	end

	statusLabel.Text = "PRE-LOADING COMPLETED! LAUNCHING ENGINE..."

	local fadeTween = TweenService:Create(background, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1
	})

	TweenService:Create(titleLabel, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {TextTransparency = 1}):Play()
	TweenService:Create(genreLabel, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {TextTransparency = 1}):Play()
	TweenService:Create(statusLabel, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {TextTransparency = 1}):Play()
	TweenService:Create(progressBackground, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {BackgroundTransparency = 1}):Play()
	TweenService:Create(progressBar, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {BackgroundTransparency = 1}):Play()

	fadeTween:Play()
	fadeTween.Completed:Connect(function()
		loadingActive = false
		if screenGui then screenGui:Destroy() end
		if controls and controls.Enable then
			pcall(function()
				controls:Enable()
			end)
		end
		
		-- non-fatal: logging only
		local DebugUtility = tryRequireChain(ReplicatedStorage, "Shared", "Modules", "DebugUtility")
		if DebugUtility then
			DebugUtility.Log("LoadingController", "Bootstrapper closed cleanly. Gameplay loop active.")
		end
	end)
end

return LoadingController
