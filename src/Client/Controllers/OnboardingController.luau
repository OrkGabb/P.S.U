--!strict
--@author OrkGabb
--@module OnboardingController.luau
--@version 1.0
-- src/Client/Controllers/OnboardingController.lua
-- Dynamic, category-aware tutorial onboarding system.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local LocalPlayer = Players.LocalPlayer

local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local OnboardingController = {}

local tutorialGui: ScreenGui
local pointerUI: ImageLabel
local textLbl: TextLabel

local currentState: "Idle" | "Clicking" | "Rolling" | "Shooting" | "Attacking" | "Exploring" | "Finished" = "Idle"
local connection: RBXScriptConnection?
local exploreTimer: number = 0

local math_sin: (number) -> number = math.sin

-- Active genre's primary-currency leaderstat value (name is genre config)
local function GetPrimaryCurrencyValue(): number
	local ls = LocalPlayer:FindFirstChild("leaderstats")
	if not ls then return 0 end
	local names = FeatureResolver.GetCurrencyNames()
	local value = ls:FindFirstChild(names.Primary)
	if value and (value:IsA("IntValue") or value:IsA("NumberValue")) then
		return (value :: any).Value
	end
	return 0
end

-- First roll cost for the Aura_Collector tutorial step (Default biome)
local function GetRollCost(): number
	local ok, AuraRegistry = pcall(function()
		return require(ReplicatedStorage.Shared.Modules.AuraRegistry) :: any
	end)
	if ok and AuraRegistry then
		local biome = AuraRegistry.GetBiome("Default")
		if biome then return biome.RollCost end
	end
	return 250
end

local function CreatePointerUI(): ()
	tutorialGui = Instance.new("ScreenGui")
	tutorialGui.Name = "TutorialGui"
	tutorialGui.ResetOnSpawn = false
	tutorialGui.DisplayOrder = 100 
	tutorialGui.Parent = LocalPlayer.PlayerGui

	pointerUI = Instance.new("ImageLabel", tutorialGui)
	pointerUI.Size = UDim2.new(0, 60, 0, 60)
	pointerUI.BackgroundTransparency = 1
	pointerUI.Image = "rbxassetid://15059633013" 
	pointerUI.ImageColor3 = Color3.fromRGB(255, 220, 40)
	pointerUI.AnchorPoint = Vector2.new(0.5, 1)

	textLbl = Instance.new("TextLabel", pointerUI)
	textLbl.Size = UDim2.new(1, 0, 0, 30)
	textLbl.Position = UDim2.new(0, 0, 0, -35)
	textLbl.BackgroundTransparency = 1
	textLbl.Font = Enum.Font.FredokaOne
	textLbl.TextSize = 24
	textLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	
	local stroke = Instance.new("UIStroke", textLbl)
	stroke.Color = Color3.fromRGB(80, 50, 0)
	stroke.Thickness = 3

	task.spawn(function()
		local bounceOffset: number = 0
		local t: number = 0
		while tutorialGui.Parent do
			t += RunService.RenderStepped:Wait()
			bounceOffset = math_sin(t * 8) * 10
			pointerUI:SetAttribute("BounceOffset", bounceOffset)
		end
	end)
end

local function onRenderStepped(dt: number): ()
	if currentState == "Finished" then
		if tutorialGui then tutorialGui:Destroy() end
		if connection then connection:Disconnect() end
		return
	end

	if currentState == "Idle" or not pointerUI then return end

	local bounceAttr = pointerUI:GetAttribute("BounceOffset")
	local bounceY: number = if type(bounceAttr) == "number" then bounceAttr else 0

	if currentState == "Clicking" then
		textLbl.Text = "TAP SCREEN TO GET COINS!"
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local vector, onScreen = workspace.CurrentCamera:WorldToScreenPoint(hrp.Position + Vector3.new(0, 4, 0))
			if onScreen then
				pointerUI.Visible = true
				pointerUI.Position = UDim2.new(0, vector.X, 0, vector.Y + bounceY)
			else
				pointerUI.Visible = false
			end
		end
		
		-- First earnings arrived → tutorial done for tap-to-earn genres
		if GetPrimaryCurrencyValue() > 0 then
			currentState = "Finished"
		end

	elseif currentState == "Rolling" then
		if GetPrimaryCurrencyValue() < GetRollCost() then
			textLbl.Text = "EARN COINS TO ROLL!"
		else
			textLbl.Text = "ROLL FOR AN AURA!"
		end
		pointerUI.Visible = true

		local rngGui = LocalPlayer.PlayerGui:FindFirstChild("GachaInterface") :: ScreenGui?
		if rngGui then
			local rollBtn = rngGui:FindFirstChild("RollButton") :: TextButton?
			if rollBtn then
				local absolutePos = rollBtn.AbsolutePosition
				local absoluteSize = rollBtn.AbsoluteSize
				local targetX: number = absolutePos.X + (absoluteSize.X / 2)
				local targetY: number = absolutePos.Y - 20
				pointerUI.Position = UDim2.new(0, targetX, 0, targetY + bounceY)
			end
		end

	elseif currentState == "Shooting" then
		textLbl.Text = "TAP SCREEN TO FIRE WEAPON!"
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local vector, onScreen = workspace.CurrentCamera:WorldToScreenPoint(hrp.Position + Vector3.new(0, 4, 0))
			if onScreen then
				pointerUI.Visible = true
				pointerUI.Position = UDim2.new(0, vector.X, 0, vector.Y + bounceY)
			else
				pointerUI.Visible = false
			end
		end

		-- Complete onboarding once they get first level/EXP or shoot
		local ls = LocalPlayer:FindFirstChild("leaderstats")
		if ls then
			local exp = ls:FindFirstChild("EXP") :: IntValue?
			if exp and exp.Value > 0 then
				currentState = "Finished"
			end
		end

	elseif currentState == "Attacking" then
		textLbl.Text = "ATTACK ENEMIES TO LEVEL UP!"
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local vector, onScreen = workspace.CurrentCamera:WorldToScreenPoint(hrp.Position + Vector3.new(0, 4, 0))
			if onScreen then
				pointerUI.Visible = true
				pointerUI.Position = UDim2.new(0, vector.X, 0, vector.Y + bounceY)
			else
				pointerUI.Visible = false
			end
		end

		local ls = LocalPlayer:FindFirstChild("leaderstats")
		if ls then
			local exp = ls:FindFirstChild("EXP") :: IntValue?
			if exp and exp.Value > 0 then
				currentState = "Finished"
			end
		end

	elseif currentState == "Exploring" then
		textLbl.Text = "EXPLORE THE WORLD!"
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local vector, onScreen = workspace.CurrentCamera:WorldToScreenPoint(hrp.Position + Vector3.new(0, 4, 0))
			if onScreen then
				pointerUI.Visible = true
				pointerUI.Position = UDim2.new(0, vector.X, 0, vector.Y + bounceY)
			else
				pointerUI.Visible = false
			end
		end

		exploreTimer += dt
		if exploreTimer >= 5.0 then
			currentState = "Finished"
		end
	end
end

function OnboardingController.Init(): () end

function OnboardingController.Start(): ()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local updateData = remotes:WaitForChild(RemoteNames.UpdateProfileData) :: RemoteEvent

	local hasLoaded = false

	local initConn; initConn = updateData.OnClientEvent:Connect(function(data)
		if not hasLoaded then
			hasLoaded = true
			-- Newcomer condition: fresh abstract profile (no primary currency)
			local currencyVal = 0
			if type(data) == "table" and type(data.Currencies) == "table" then
				currencyVal = data.Currencies.Primary or 0
			end
			if currencyVal == 0 then
				CreatePointerUI()

				if FeatureResolver.IsCategoryActive("Clicker_Farm") then
					currentState = "Clicking"
				elseif FeatureResolver.IsCategoryActive("Aura_Collector") then
					currentState = "Rolling"
				elseif FeatureResolver.IsCategoryActive("FPS_Shooter") then
					currentState = "Shooting"
				elseif FeatureResolver.IsCategoryActive("RPG_Adventure") then
					currentState = "Attacking"
				else
					currentState = "Exploring"
				end
			else
				currentState = "Finished"
			end
			initConn:Disconnect()
		end
	end)

	connection = RunService.RenderStepped:Connect(onRenderStepped)

	local localEvents = ReplicatedStorage:FindFirstChild("LocalEvents")
	if localEvents then
		local auraRolled = localEvents:WaitForChild("EffectRolled", 5) :: BindableEvent?
		if auraRolled then
			auraRolled.Event:Connect(function()
				if currentState == "Rolling" then
					currentState = "Finished"
				end
			end)
		end
	end
end

return OnboardingController
