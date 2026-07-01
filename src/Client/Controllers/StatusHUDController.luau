--!strict
--@author OrkGabb
--@module StatusHUDController.luau
--@version 1.0
-- src/Client/Controllers/StatusHUDController.lua
-- Flexible, category-aware player HUD controller.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local FeatureResolver = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("FeatureResolver"))

local function FormatSuffix(n: number): string
	if not n or n < 1000 then return tostring(math.floor(n or 0)) end
	local suffixes = {"", "K", "M", "B", "T", "Qa", "Qi", "Sx"}
	local i = math.floor(math.log10(n) / 3)
	local v = n / (10 ^ (i * 3))
	return string.format("%.1f%s", v, suffixes[i + 1] or "e" .. tostring(i * 3))
end

local StatusHUDController = {}

local LevelText: TextLabel?
local XP_Fill: Frame?
local XP_Text: TextLabel?
local HP_Fill: Frame?
local HP_Text: TextLabel?
local BonusText: TextLabel?

local currentIsVIP = false

local function GetMaxExp(level: number): number
	return math.floor(1000 * math.pow(1.3, math.max(0, level - 1)))
end

local function UpdateHUD()
	local ls = LocalPlayer:FindFirstChild("leaderstats")
	if not ls then return end

	if LevelText then
		local level = ls:FindFirstChild("Level") and (ls.Level :: NumberValue).Value or 1
		LevelText.Text = tostring(level)
		
		if BonusText then
			local clickBonus = level * 20
			if currentIsVIP then
				BonusText.Text = " +" .. tostring(clickBonus) .. "% Click Power | +25% VIP"
			else
				BonusText.Text = " +" .. tostring(clickBonus) .. "% Click Power"
			end
		end

		if XP_Fill and XP_Text then
			local exp = ls:FindFirstChild("EXP") and (ls.EXP :: NumberValue).Value or 0
			local maxExp = GetMaxExp(level)
			local progress = math.clamp(exp / maxExp, 0, 1)
			XP_Text.Text = FormatSuffix(exp) .. " / " .. FormatSuffix(maxExp)
			TweenService:Create(XP_Fill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.fromScale(progress, 1)}):Play()
		end
	end

	if HP_Fill and HP_Text then
		local char = LocalPlayer.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				local hpProgress = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
				HP_Text.Text = string.format("%d / %d", math.floor(hum.Health), math.floor(hum.MaxHealth))
				TweenService:Create(HP_Fill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.fromScale(hpProgress, 1)}):Play()
			end
		end
	end
end

function StatusHUDController.Init(): ()
	for _, child in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
		if child.Name == "StatusHUD" then child:Destroy() end
	end

	local showHP = FeatureResolver.IsCategoryActive("FPS_Shooter") or FeatureResolver.IsCategoryActive("RPG_Adventure")
	local showLevelXP = FeatureResolver.IsCategoryActive("Clicker_Farm") or FeatureResolver.IsCategoryActive("RPG_Adventure")
	local showBonus = FeatureResolver.IsCategoryActive("Clicker_Farm")

	if not (showHP or showLevelXP) then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "StatusHUD"
	gui.ResetOnSpawn = false
	gui.Parent = LocalPlayer.PlayerGui

	local container = Instance.new("Frame")
	container.BackgroundTransparency = 1
	container.Parent = gui

	-- Position and scale adjustments
	if showLevelXP and showHP then
		container.Size = UDim2.new(0, 235, 0, 95)
		container.Position = UDim2.new(0, 20, 1, -115)
	elseif showLevelXP then
		container.Size = UDim2.new(0, 235, 0, 75)
		container.Position = UDim2.new(0, 20, 1, -95)
	elseif showHP then
		container.Size = UDim2.new(0, 200, 0, 45)
		container.Position = UDim2.new(0, 20, 1, -65)
	end

	if showLevelXP then
		local diamond = Instance.new("Frame")
		diamond.Name = "LevelStar"
		diamond.Size = UDim2.new(0, 60, 0, 60)
		diamond.Position = UDim2.new(0, 0, 0.5, -30)
		diamond.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
		diamond.Rotation = 45
		diamond.ZIndex = 3
		Instance.new("UICorner", diamond).CornerRadius = UDim.new(0, 10) 
		
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 2
		stroke.Parent = diamond
		
		LevelText = Instance.new("TextLabel")
		LevelText.Size = UDim2.fromScale(1.4, 1.4) 
		LevelText.AnchorPoint = Vector2.new(0.5, 0.5)
		LevelText.Position = UDim2.fromScale(0.5, 0.5)
		LevelText.Rotation = -45
		LevelText.BackgroundTransparency = 1
		LevelText.TextColor3 = Color3.fromRGB(255, 255, 255)
		LevelText.Font = Enum.Font.FredokaOne 
		LevelText.TextSize = 26 
		LevelText.ZIndex = 4
		LevelText.Parent = diamond
		diamond.Parent = container

		local xpBg = Instance.new("Frame")
		xpBg.Size = UDim2.new(0, 150, 0, 12)
		xpBg.Position = showHP and UDim2.new(0, 46, 0.68, 0) or UDim2.new(0, 46, 0.5, -6)
		xpBg.BackgroundColor3 = Color3.fromRGB(30, 15, 0)
		xpBg.BorderSizePixel = 0
		xpBg.ZIndex = 1
		Instance.new("UICorner", xpBg).CornerRadius = UDim.new(0, 4)
		xpBg.Parent = container

		XP_Fill = Instance.new("Frame")
		XP_Fill.Size = UDim2.fromScale(0, 1)
		XP_Fill.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
		XP_Fill.BorderSizePixel = 0
		XP_Fill.ZIndex = 2
		Instance.new("UICorner", XP_Fill).CornerRadius = UDim.new(0, 4)
		XP_Fill.Parent = xpBg

		XP_Text = Instance.new("TextLabel")
		XP_Text.Size = UDim2.fromScale(1, 1)
		XP_Text.BackgroundTransparency = 1
		XP_Text.TextColor3 = Color3.fromRGB(255, 255, 255)
		XP_Text.Font = Enum.Font.GothamMedium
		XP_Text.TextSize = 9
		XP_Text.ZIndex = 3
		XP_Text.Parent = xpBg
	end

	if showHP then
		local hpBg = Instance.new("Frame")
		hpBg.Size = UDim2.new(0, 170, 0, 16)
		hpBg.Position = showLevelXP and UDim2.new(0, 46, 0.42, 0) or UDim2.new(0, 15, 0.5, -8)
		hpBg.BackgroundColor3 = Color3.fromRGB(10, 30, 10)
		hpBg.BorderSizePixel = 0
		hpBg.ZIndex = 1
		Instance.new("UICorner", hpBg).CornerRadius = UDim.new(0, 4)
		hpBg.Parent = container

		HP_Fill = Instance.new("Frame")
		HP_Fill.Size = UDim2.fromScale(1, 1)
		HP_Fill.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
		HP_Fill.BorderSizePixel = 0
		HP_Fill.ZIndex = 2
		Instance.new("UICorner", HP_Fill).CornerRadius = UDim.new(0, 4)
		HP_Fill.Parent = hpBg

		HP_Text = Instance.new("TextLabel")
		HP_Text.Size = UDim2.fromScale(1, 1)
		HP_Text.BackgroundTransparency = 1
		HP_Text.TextColor3 = Color3.fromRGB(255, 255, 255)
		HP_Text.Font = Enum.Font.GothamMedium
		HP_Text.TextSize = 10
		HP_Text.ZIndex = 3
		HP_Text.Parent = hpBg
	end

	if showBonus then
		BonusText = Instance.new("TextLabel")
		BonusText.Size = UDim2.new(0, 200, 0, 18)
		BonusText.Position = UDim2.new(0, 0, 1, 5) 
		BonusText.BackgroundTransparency = 1
		BonusText.TextColor3 = Color3.fromRGB(255, 215, 0)
		BonusText.Font = Enum.Font.GothamBold
		BonusText.TextSize = 11
		BonusText.TextXAlignment = Enum.TextXAlignment.Left
		BonusText.Parent = container
	end
end

local function WaitForLeaderstats(player: Player, timeout: number?): Folder?
	local deadline = os.clock() + (timeout or 15)
	repeat task.wait(0.1) until player:FindFirstChild("leaderstats") or os.clock() >= deadline
	return player:FindFirstChild("leaderstats") :: Folder?
end

function StatusHUDController.Start(): ()
	local showHP = FeatureResolver.IsCategoryActive("FPS_Shooter") or FeatureResolver.IsCategoryActive("RPG_Adventure")
	local showLevelXP = FeatureResolver.IsCategoryActive("Clicker_Farm") or FeatureResolver.IsCategoryActive("RPG_Adventure")

	if not (showHP or showLevelXP) then return end

	local ls = WaitForLeaderstats(LocalPlayer)
	if not ls then
		warn("[StatusHUDController] leaderstats not found after timeout — HUD change-listeners not connected.")
		UpdateHUD()
		return
	end
	ls.ChildAdded:Connect(UpdateHUD)
	local expVal = ls:WaitForChild("EXP", 10)
	if expVal then expVal.Changed:Connect(UpdateHUD) end
	local levelVal = ls:WaitForChild("Level", 10)
	if levelVal then levelVal.Changed:Connect(UpdateHUD) end

	local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
	local updateData = remotes:WaitForChild("UpdateProfileData") :: RemoteEvent
	updateData.OnClientEvent:Connect(function(data)
		if data.IsVIP ~= nil then
			currentIsVIP = data.IsVIP
			UpdateHUD()
		end
	end)

	LocalPlayer.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid")
		hum.HealthChanged:Connect(UpdateHUD)
		UpdateHUD()
	end)
	if LocalPlayer.Character then
		local hum = LocalPlayer.Character:FindFirstChild("Humanoid")
		if hum then hum.HealthChanged:Connect(UpdateHUD) end
	end
	UpdateHUD()
end

return StatusHUDController
