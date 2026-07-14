--!strict
--@author OrkGabb
--@module StatusHUDController.luau
--@version 1.0
-- src/Client/Controllers/StatusHUDController.lua
-- Flexible, category-aware player HUD controller.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
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

-- HUD element visibility comes from the active genre's config (HUD flags) —
-- the controller itself never names a genre.
local function GetHUDFlags(): (boolean, boolean, boolean)
	local genre: string? = FeatureResolver.GetActiveGenre()
	if not genre then
		return false, false, false
	end
	local hud: any = FeatureResolver.GetConfigField(genre, "HUD", nil)
	if type(hud) ~= "table" then
		return false, false, false
	end
	return hud.ShowHealth == true, hud.ShowLevelXP == true, hud.ShowClickBonus == true
end

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

	local showHP, showLevelXP, showBonus = GetHUDFlags()

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
		
		local levelText = Instance.new("TextLabel")
		levelText.Size = UDim2.fromScale(1.4, 1.4)
		levelText.AnchorPoint = Vector2.new(0.5, 0.5)
		levelText.Position = UDim2.fromScale(0.5, 0.5)
		levelText.Rotation = -45
		levelText.BackgroundTransparency = 1
		levelText.TextColor3 = Color3.fromRGB(255, 255, 255)
		levelText.Font = Enum.Font.FredokaOne
		levelText.TextSize = 26
		levelText.ZIndex = 4
		levelText.Parent = diamond
		LevelText = levelText
		diamond.Parent = container

		local xpBg = Instance.new("Frame")
		xpBg.Size = UDim2.new(0, 150, 0, 12)
		xpBg.Position = showHP and UDim2.new(0, 46, 0.68, 0) or UDim2.new(0, 46, 0.5, -6)
		xpBg.BackgroundColor3 = Color3.fromRGB(30, 15, 0)
		xpBg.BorderSizePixel = 0
		xpBg.ZIndex = 1
		Instance.new("UICorner", xpBg).CornerRadius = UDim.new(0, 4)
		xpBg.Parent = container

		local xpFill = Instance.new("Frame")
		xpFill.Size = UDim2.fromScale(0, 1)
		xpFill.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
		xpFill.BorderSizePixel = 0
		xpFill.ZIndex = 2
		Instance.new("UICorner", xpFill).CornerRadius = UDim.new(0, 4)
		xpFill.Parent = xpBg
		XP_Fill = xpFill

		local xpText = Instance.new("TextLabel")
		xpText.Size = UDim2.fromScale(1, 1)
		xpText.BackgroundTransparency = 1
		xpText.TextColor3 = Color3.fromRGB(255, 255, 255)
		xpText.Font = Enum.Font.GothamMedium
		xpText.TextSize = 9
		xpText.ZIndex = 3
		xpText.Parent = xpBg
		XP_Text = xpText
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

		local hpFill = Instance.new("Frame")
		hpFill.Size = UDim2.fromScale(1, 1)
		hpFill.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
		hpFill.BorderSizePixel = 0
		hpFill.ZIndex = 2
		Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0, 4)
		hpFill.Parent = hpBg
		HP_Fill = hpFill

		local hpText = Instance.new("TextLabel")
		hpText.Size = UDim2.fromScale(1, 1)
		hpText.BackgroundTransparency = 1
		hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
		hpText.Font = Enum.Font.GothamMedium
		hpText.TextSize = 10
		hpText.ZIndex = 3
		hpText.Parent = hpBg
		HP_Text = hpText
	end

	if showBonus then
		local bonusText = Instance.new("TextLabel")
		bonusText.Size = UDim2.new(0, 200, 0, 18)
		bonusText.Position = UDim2.new(0, 0, 1, 5)
		bonusText.BackgroundTransparency = 1
		bonusText.TextColor3 = Color3.fromRGB(255, 215, 0)
		bonusText.Font = Enum.Font.GothamBold
		bonusText.TextSize = 11
		bonusText.TextXAlignment = Enum.TextXAlignment.Left
		bonusText.Parent = container
		BonusText = bonusText
	end
end

local function WaitForLeaderstats(player: Player, timeout: number?): Folder?
	local deadline = os.clock() + (timeout or 15)
	repeat task.wait(0.1) until player:FindFirstChild("leaderstats") or os.clock() >= deadline
	return player:FindFirstChild("leaderstats") :: Folder?
end

function StatusHUDController.Start(): ()
	local showHP, showLevelXP = GetHUDFlags()

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
	local updateData = remotes:WaitForChild(RemoteNames.UpdateProfileData) :: RemoteEvent
	updateData.OnClientEvent:Connect(function(data)
		if data.IsVIP ~= nil then
			currentIsVIP = data.IsVIP
			UpdateHUD()
		end
	end)

	local healthChangedConn: RBXScriptConnection? = nil
	local function ConnectHealthChanged(char: Model): ()
		if healthChangedConn then
			healthChangedConn:Disconnect()
			healthChangedConn = nil
		end
		local hum = char:WaitForChild("Humanoid")
		healthChangedConn = hum.HealthChanged:Connect(UpdateHUD)
	end

	LocalPlayer.CharacterAdded:Connect(function(char)
		ConnectHealthChanged(char)
		UpdateHUD()
	end)
	if LocalPlayer.Character then
		ConnectHealthChanged(LocalPlayer.Character)
	end
	UpdateHUD()
end

return StatusHUDController
