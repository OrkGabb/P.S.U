--!strict
--@author OrkGabb
--@module LoadingController.luau
--@version 1.0
--[[
========================================================================
MODULARFRAMEWORK CORE - DYNAMIC ASSET BOOTSTRAPPER & LOADING CONTROLLER
========================================================================
Preloads prioritized visual, physical, and audio assets efficiently using
asynchronous pipelines to optimize memory streaming on join.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LoadingController = {}
LoadingController.Name = "LoadingController"

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Configuration constants
local MAX_PRELOAD_TIMEOUT = 10 -- Safety timeout limit to prevent infinite menu lockups

-- Active states
local loadingActive = true
local screenGui: ScreenGui? = nil
local background: Frame? = nil
local controls: any = nil
local clientMainReady = false

-- Signal from ClientMain
function LoadingController.SignalReady()
	clientMainReady = true
end

function LoadingController.Init(): ()
	-- Load DebugUtility dynamically
	local DebugUtility = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("DebugUtility")) :: any
	DebugUtility.Log("LoadingController", "Initializing dynamic loading bootstrapper...")

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

	-- Synchronously create ScreenGui and Background Cover to block the viewport instantly
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

	-- Dynamically load FeatureResolver and VFXRegistry
	local FeatureResolver = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("FeatureResolver")) :: any
	local VFXRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("VFXRegistry")) :: any

	local branding = FeatureResolver.GetCategoryConfig("Branding") or { GameName = "YOUR PROJECT", Subtitle = "FRAMEWORK CORE ACTIVE" }

	-- Game Title Label (Replaces legacy title with professional placeholder)
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

	-- Dynamic Subtitle for Active Configurations
	local genreLabel = Instance.new("TextLabel")
	genreLabel.Size = UDim2.new(0.8, 0, 0.05, 0)
	genreLabel.Position = UDim2.new(0.1, 0, 0.52, 0)
	genreLabel.BackgroundTransparency = 1
	genreLabel.TextColor3 = Color3.fromRGB(0, 255, 120) -- Neon green accent color
	genreLabel.Font = Enum.Font.GothamSemibold
	genreLabel.TextSize = 16
	genreLabel.TextXAlignment = Enum.TextXAlignment.Center
	genreLabel.Parent = background

	-- Match active modules with dynamic tags
	local activeTemplates: {string} = {}
	if FeatureResolver.IsCategoryActive("FPS_Shooter") then table.insert(activeTemplates, "FPS SHOOTER") end
	if FeatureResolver.IsCategoryActive("Clicker_Farm") then table.insert(activeTemplates, "CLICKER FARM") end
	if FeatureResolver.IsCategoryActive("Pet_Simulator") then table.insert(activeTemplates, "PET SIMULATOR") end
	if FeatureResolver.IsCategoryActive("RPG_Adventure") then table.insert(activeTemplates, "RPG ADVENTURE") end

	if #activeTemplates > 0 then
		genreLabel.Text = string.upper(branding.Subtitle) .. " + " .. table.concat(activeTemplates, " + ")
	else
		genreLabel.Text = string.upper(branding.Subtitle)
	end

	-- Status Loader Text
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

	-- Outer Bar
	local progressBackground = Instance.new("Frame")
	progressBackground.Size = UDim2.new(0.4, 0, 0.008, 0) -- Sleek, minimalistic thin loading bar
	progressBackground.Position = UDim2.new(0.3, 0, 0.72, 0)
	progressBackground.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	progressBackground.BorderSizePixel = 0
	progressBackground.Parent = background

	local uiCornerBg = Instance.new("UICorner")
	uiCornerBg.CornerRadius = UDim.new(0.5, 0)
	uiCornerBg.Parent = progressBackground

	-- Inner Progress Bar
	local progressBar = Instance.new("Frame")
	progressBar.Size = UDim2.new(0, 0, 1, 0)
	progressBar.BackgroundColor3 = Color3.fromRGB(0, 255, 120) -- Neon green progress
	progressBar.BorderSizePixel = 0
	progressBar.Parent = progressBackground

	local uiCornerBar = Instance.new("UICorner")
	uiCornerBar.CornerRadius = UDim.new(0.5, 0)
	uiCornerBar.Parent = progressBar

	-- Parse and gather specific assets to preload from registries (avoiding blind GetDescendants calls)
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

	-- Modern 2026 Batch Preloading pipeline
	if totalAssets > 0 then
		for _, assetId in ipairs(assetQueue) do
			if not loadingActive then break end
			
			-- Prepare temporary structural instance to resolve the Asset ID properly
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
					local success, _ = pcall(function()
						ContentProvider:PreloadAsync({tempInstance :: Instance})
					end)
					
					completedAssets += 1
					local progressRatio = math.clamp(completedAssets / totalAssets, 0, 1)
					
					-- Smoothly interpolate loading bar width
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
		-- Complete instantly if registries contain no assets
		TweenService:Create(progressBar, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
			Size = UDim2.new(1, 0, 1, 0)
		}):Play()
		statusLabel.Text = "PRE-LOAD SYSTEM COMPLETED"
	end

	-- Timeout safety loop ensuring slow networks don't freeze the boot sequence
	local elapsed = 0
	while (completedAssets < totalAssets or not clientMainReady) and elapsed < MAX_PRELOAD_TIMEOUT do
		elapsed += task.wait()
	end

	statusLabel.Text = "PRE-LOADING COMPLETED! LAUNCHING ENGINE..."

	-- Play smooth fade-out closing sequence
	local fadeTween = TweenService:Create(background, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1
	})

	-- Smoothly fade individual text elements
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
		
		-- Require DebugUtility dynamically for log
		local DebugUtility = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("DebugUtility")) :: any
		DebugUtility.Log("LoadingController", "Bootstrapper closed cleanly. Gameplay loop active.")
	end)
end

return LoadingController
