--!strict
--@author OrkGabb
--@module DynamicUIOrchestrator.luau
--@version 1.0
-- src/Client/Controllers/DynamicUIOrchestrator.luau
-- Self-adapting gameplay HUD features based on active configurations.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: Folder
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver")) :: any

local DynamicUIOrchestrator = {}

function DynamicUIOrchestrator.Init(): ()
	print("[DynamicUIOrchestrator] Scanning active gameplay HUD features...")
end

function DynamicUIOrchestrator.Start(): ()
	local player: Player = Players.LocalPlayer
	local playerGui: PlayerGui? = player:WaitForChild("PlayerGui", 10) :: any
	if not playerGui then return end
	
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DynamicHUD"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local fpsActive: boolean = FeatureResolver.IsCategoryActive("FPS_Shooter")
	local clickerActive: boolean = FeatureResolver.IsCategoryActive("Clicker_Farm")

	if fpsActive then
		-- Generate Crosshair HUD
		local crosshair = Instance.new("Frame")
		crosshair.Name = "Crosshair"
		crosshair.Size = UDim2.new(0.01, 0, 0.01, 0)
		crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
		crosshair.Position = UDim2.new(0.5, 0, 0.5, 0)
		crosshair.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
		
		local crosshairAspect = Instance.new("UIAspectRatioConstraint")
		crosshairAspect.AspectRatio = 1
		crosshairAspect.Parent = crosshair
		
		crosshair.Parent = screenGui
		
		-- Generate Ammo Interface
		local ammoLabel = Instance.new("TextLabel")
		ammoLabel.Name = "AmmoInterface"
		ammoLabel.Size = UDim2.new(0.15, 0, 0.05, 0)
		ammoLabel.AnchorPoint = Vector2.new(1, 1)
		ammoLabel.Position = UDim2.new(0.98, 0, 0.95, 0)
		ammoLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		ammoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		ammoLabel.Text = "Ammo: 30/30"
		ammoLabel.Font = Enum.Font.GothamBold
		ammoLabel.TextScaled = true
		
		local ammoAspect = Instance.new("UIAspectRatioConstraint")
		ammoAspect.AspectRatio = 3
		ammoAspect.Parent = ammoLabel
		
		ammoLabel.Parent = screenGui
		
		print("[DynamicUIOrchestrator] FPS HUD initialized.")
	end

	if clickerActive then
		-- Generate Click Input Overlay
		local clickerOverlay = Instance.new("TextButton")
		clickerOverlay.Name = "ClickerOverlay"
		clickerOverlay.Size = UDim2.new(0.2, 0, 0.1, 0)
		clickerOverlay.AnchorPoint = Vector2.new(0.5, 1)
		
		-- Anchor Logic: Prevent HUD Overlap
		if fpsActive then
			clickerOverlay.Position = UDim2.new(0.5, 0, 0.95, 0)
		else
			clickerOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
			clickerOverlay.Position = UDim2.new(0.5, 0, 0.5, 0)
			clickerOverlay.Size = UDim2.new(0.3, 0, 0.15, 0)
		end
		
		local clickerAspect = Instance.new("UIAspectRatioConstraint")
		clickerAspect.AspectRatio = 2
		clickerAspect.Parent = clickerOverlay
		
		clickerOverlay.BackgroundColor3 = Color3.fromRGB(50, 150, 255)
		clickerOverlay.TextColor3 = Color3.fromRGB(255, 255, 255)
		clickerOverlay.Text = "CLICK TO FARM"
		clickerOverlay.Font = Enum.Font.GothamBlack
		clickerOverlay.TextScaled = true
		clickerOverlay.Parent = screenGui
		
		print("[DynamicUIOrchestrator] Clicker Overlay initialized.")
	end
end

return DynamicUIOrchestrator
