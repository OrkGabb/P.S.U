--!strict
--@author OrkGabb
--@module SkillsController.luau
--@version 1.0
-- src/Client/Controllers/SkillsController.lua
-- Skills/Mastery UI Controller. Overhauled with premium glassmorphism styling to match Quests UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local UpgradeRegistry = require(ReplicatedStorage.Shared.Modules.UpgradeRegistry)
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local SkillsController = {}

local MainPanel: Frame
local PanelScale: UIScale
local BgShield: TextButton
local isOpen = false
-- Generation counter: bumped on every open/close transition so a stale
-- Tween.Completed handler from an interrupted animation can detect it lost
-- ownership and must not touch panel state.
local animGen = 0
local UI_Cache: {[string]: {CostLabel: TextLabel, CostBadge: Frame, Lvl: TextLabel, Bar: Frame, Btn: TextButton, BtnStroke: UIStroke}} = {}
local CurrentUpgrades = {}

local SUFFIXES = {"", "k", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"}

local function Format(n: number): string
	if n < 1000 then return tostring(math.floor(n)) end
	local exp = math.floor(math.log10(n) / 3)
	local suffix = SUFFIXES[exp + 1] or "e" .. tostring(exp * 3)
	return (string.format("%.2f%s", n / (10 ^ (exp * 3)), suffix):gsub("%.00", ""):gsub("(%.%d)0", "%1"))
end

local function GetLocalEvent(name: string): BindableEvent
	local folder = ReplicatedStorage:FindFirstChild("LocalEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LocalEvents"
		folder.Parent = ReplicatedStorage
	end
	
	local event = folder:FindFirstChild(name)
	if not event then
		event = Instance.new("BindableEvent")
		event.Name = name
		event.Parent = folder
	end
	return event :: BindableEvent
end

local function RefreshUI()
	if not isOpen then return end

	local currencyNames = FeatureResolver.GetCurrencyNames()
	local ls = LocalPlayer:FindFirstChild("leaderstats")
	local primaryStat = ls and (ls:FindFirstChild(currencyNames.Primary) or ls:FindFirstChild("Coins"))
	local currentCoins = if primaryStat and (primaryStat:IsA("IntValue") or primaryStat:IsA("NumberValue"))
		then (primaryStat :: IntValue).Value
		else 0

	for id, elements in pairs(UI_Cache) do
		local level = CurrentUpgrades[id] or 0
		local def = UpgradeRegistry.Defs[id]
		if not def then continue end
		local cost = UpgradeRegistry.GetCost(id, level)
		local milestoneCost = UpgradeRegistry.GetMilestoneCost(id, level + 1)

		elements.Lvl.Text = string.format("%d / %d", level, def.MaxLevel)

		TweenService:Create(elements.Bar, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(level / def.MaxLevel, 1)
		}):Play()

		if level >= def.MaxLevel or cost == nil then
			elements.CostLabel.Text = "MAX LEVEL"
			elements.CostLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
			elements.Btn.BackgroundColor3 = Color3.fromRGB(40, 35, 45)
			elements.Btn.Text = "MAXED"
			if elements.BtnStroke then elements.BtnStroke.Color = Color3.fromRGB(60, 55, 65) end
		else
			if milestoneCost > 0 then
				-- Milestone purchase: show the secondary-currency gate alongside the base cost
				elements.CostLabel.Text = string.format("%s + %d %s", Format(cost), milestoneCost, currencyNames.Secondary)
			else
				elements.CostLabel.Text = Format(cost)
			end
			elements.CostLabel.TextColor3 = Color3.fromRGB(255, 215, 0)

			if currentCoins >= cost then
				elements.Btn.BackgroundColor3 = Color3.fromRGB(0, 160, 50)
				elements.Btn.Text = "UPGRADE"
				if elements.BtnStroke then elements.BtnStroke.Color = Color3.fromRGB(0, 80, 25) end
			else
				elements.Btn.BackgroundColor3 = Color3.fromRGB(130, 30, 30)
				elements.Btn.Text = "LOCKED"
				if elements.BtnStroke then elements.BtnStroke.Color = Color3.fromRGB(70, 15, 15) end
			end
		end
	end
end

function SkillsController.Init(): ()
	-- Guarantee local events and folder exist programmatically during Init phase to prevent stalls
	local folder = ReplicatedStorage:FindFirstChild("LocalEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LocalEvents"
		folder.Parent = ReplicatedStorage
	end

	local toggleSkills = folder:FindFirstChild("ToggleSkills")
	if not toggleSkills then
		toggleSkills = Instance.new("BindableEvent")
		toggleSkills.Name = "ToggleSkills"
		toggleSkills.Parent = folder
	end

	local notifyMenuOpened = folder:FindFirstChild("NotifyMenuOpened")
	if not notifyMenuOpened then
		notifyMenuOpened = Instance.new("BindableEvent")
		notifyMenuOpened.Name = "NotifyMenuOpened"
		notifyMenuOpened.Parent = folder
	end

	local notifyMenuClosed = folder:FindFirstChild("NotifyMenuClosed")
	if not notifyMenuClosed then
		notifyMenuClosed = Instance.new("BindableEvent")
		notifyMenuClosed.Name = "NotifyMenuClosed"
		notifyMenuClosed.Parent = folder
	end
end

function SkillsController.Start(): ()
	-- Gate: Skills/Mastery UI is only relevant for genres that have upgrade trees.
	-- In FPS_Shooter mode this panel is out of scope and must not appear.
	-- IsCategoryActive is the single check — if no upgrade-bearing genre is active,
	-- return immediately without registering the HUD button or building any UI.
	if not (FeatureResolver.IsCategoryActive("RPG_Adventure")
		or FeatureResolver.IsCategoryActive("Clicker_Farm")
		or FeatureResolver.IsCategoryActive("Pet_Simulator")) then
		return
	end

	local UIController: any = require(script.Parent:WaitForChild("UIController"))
	UIController.RegisterHUDButton({
		Id = "Skills",
		Name = "SKILLS",
		IconId = "Skills",
		Type = "Sidebar",
		LayoutOrder = 2,
		OnClick = function(): ()
			GetLocalEvent("ToggleSkills"):Fire()
		end
	})

	local gui = Instance.new("ScreenGui")
	gui.Name = "SkillsGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60 -- panel band: 60 resting/closing, 61 while open
	gui.Parent = LocalPlayer.PlayerGui

	BgShield = Instance.new("TextButton", gui)
	BgShield.Name = "InputSink"
	BgShield.Size = UDim2.fromScale(1, 1)
	BgShield.BackgroundTransparency = 1
	BgShield.Text = ""
	BgShield.AutoButtonColor = false
	BgShield.Visible = false
	BgShield.Active = true
	-- (click-to-close is connected below, once closeSkillsMenu exists)

	MainPanel = Instance.new("Frame")
	MainPanel.Size = UDim2.new(0, 460, 0, 420)
	-- Left side, vertically below center
	MainPanel.AnchorPoint = Vector2.new(0, 0.5)
	MainPanel.Position = UDim2.new(0, 12, 0.62, 0)
	MainPanel.BackgroundColor3 = Color3.fromRGB(15, 14, 22)
	MainPanel.BorderSizePixel = 0
	MainPanel.Visible = false
	MainPanel.ClipsDescendants = true
	MainPanel.Parent = gui
	Instance.new("UICorner", MainPanel).CornerRadius = UDim.new(0, 16)

	PanelScale = Instance.new("UIScale", MainPanel)
	PanelScale.Scale = 0

	local closeBtn = Instance.new("TextButton", MainPanel)
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -46, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(0, 0)
	closeBtn.AutoButtonColor = false
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	closeBtn.BackgroundTransparency = 0
	
	local corner = Instance.new("UICorner", closeBtn)
	corner.CornerRadius = UDim.new(0, 8)
	
	local stroke = Instance.new("UIStroke", closeBtn)
	stroke.Color = Color3.fromRGB(120, 20, 20)
	stroke.Thickness = 2
	
	local cIcon = closeBtn:FindFirstChild("HD_Icon")
	if cIcon then cIcon:Destroy() end

	local clickTw = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	closeBtn.MouseEnter:Connect(function() TweenService:Create(closeBtn, clickTw, {Size = UDim2.new(0, 38, 0, 38), BackgroundColor3 = Color3.fromRGB(255, 70, 70)}):Play() end)
	closeBtn.MouseLeave:Connect(function() TweenService:Create(closeBtn, clickTw, {Size = UDim2.new(0, 36, 0, 36), BackgroundColor3 = Color3.fromRGB(220, 50, 50)}):Play() end)
	closeBtn.MouseButton1Down:Connect(function() TweenService:Create(closeBtn, clickTw, {Size = UDim2.new(0, 32, 0, 32)}):Play() end)
	closeBtn.MouseButton1Up:Connect(function() TweenService:Create(closeBtn, clickTw, {Size = UDim2.new(0, 38, 0, 38)}):Play() end)

	local camera = workspace.CurrentCamera
	local targetScale = 1
	
	local function updateUIScale()
		if not camera then return end
		local size = camera.ViewportSize
		local scaleX = size.X / 480
		local scaleY = size.Y / 440
		targetScale = math.clamp(math.min(scaleX, scaleY, 1), 0.5, 1.2)
		if isOpen then
			-- Retarget with a tween: a direct Scale set while another tween is
			-- animating the property gets overwritten every frame.
			TweenService:Create(PanelScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = targetScale}):Play()
		end
	end
	
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateUIScale)
	updateUIScale()

	local function closeSkillsMenu(reason: string?)
		if isOpen then
			isOpen = false
			animGen += 1
			local gen = animGen
			gui.DisplayOrder = 60
			BgShield.Visible = false
			GetLocalEvent("NotifyMenuClosed"):Fire("Skills")
			-- A switch-triggered close (another panel is taking over) uses a
			-- fast start so the outgoing panel gets out of the way quickly; a
			-- manual close keeps the slower, weightier Back/In easing.
			local closeTween: TweenInfo = if reason == "switch"
				then TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				else TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			local tw = TweenService:Create(PanelScale, closeTween, {Scale = 0})
			tw:Play()
			tw.Completed:Connect(function(state: Enum.PlaybackState)
				-- A reopen cancels this tween (Completed still fires, state=Cancelled)
				-- and bumps the generation; hide only if this close ran to completion
				-- and is still the latest transition.
				if gen ~= animGen then return end
				if state ~= Enum.PlaybackState.Completed then return end
				MainPanel.Visible = false
			end)
		end
	end

	closeBtn.MouseButton1Up:Connect(function() closeSkillsMenu() end)
	BgShield.MouseButton1Up:Connect(function() closeSkillsMenu() end)

	-- Header Title
	local title = Instance.new("TextLabel", MainPanel)
	title.Text = "MASTERY UPGRADES"
	title.Size = UDim2.new(1, 0, 0, 50)
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 22
	title.BackgroundTransparency = 1

	-- List layout container
	local list = Instance.new("ScrollingFrame", MainPanel)
	list.Size = UDim2.new(1, -24, 1, -70)
	list.Position = UDim2.new(0, 12, 0, 55)
	list.BackgroundTransparency = 1
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = Color3.fromRGB(130, 90, 230)
	list.BorderSizePixel = 0
	list.CanvasSize          = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	
	local layout = Instance.new("UIListLayout", list)
	layout.Padding = UDim.new(0, 10)

	local listPad = Instance.new("UIPadding", list)
	listPad.PaddingLeft = UDim.new(0, 4)
	listPad.PaddingRight = UDim.new(0, 4)
	listPad.PaddingTop = UDim.new(0, 4)
	listPad.PaddingBottom = UDim.new(0, 4)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local req = remotes:WaitForChild(RemoteNames.UpgradeRequest) :: RemoteEvent

	-- Build skill upgrade cards
	for id, def in pairs(UpgradeRegistry.Defs) do
		if not FeatureResolver.IsCategoryActive(def.Category) then continue end
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 100)
		card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		card.BackgroundTransparency = 0.94
		card.BorderSizePixel = 0
		card.Parent = list
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
		
		local cardStroke = Instance.new("UIStroke", card)
		cardStroke.Color = Color3.fromRGB(255, 255, 255)
		cardStroke.Thickness = 1
		cardStroke.Transparency = 0.92
		
		-- Title
		local n = Instance.new("TextLabel", card)
		n.Text = def.Name:upper()
		n.Size = UDim2.new(0.6, 0, 0, 26)
		n.Position = UDim2.new(0, 15, 0, 8)
		n.TextColor3 = Color3.fromRGB(255, 255, 255)
		n.Font = Enum.Font.GothamBlack
		n.TextSize = 14
		n.TextXAlignment = Enum.TextXAlignment.Left
		n.BackgroundTransparency = 1

		-- Level progress details
		local lvl = Instance.new("TextLabel", card)
		lvl.Size = UDim2.new(0, 90, 0, 26)
		lvl.Position = UDim2.new(1, -105, 0, 8)
		lvl.TextColor3 = Color3.fromRGB(180, 170, 200)
		lvl.Font = Enum.Font.GothamBold
		lvl.TextSize = 13
		lvl.TextXAlignment = Enum.TextXAlignment.Right
		lvl.BackgroundTransparency = 1

		-- Premium progress bar track
		local barBg = Instance.new("Frame", card)
		barBg.Size = UDim2.new(1, -30, 0, 7)
		barBg.Position = UDim2.new(0, 15, 0, 40)
		barBg.BackgroundColor3 = Color3.fromRGB(10, 8, 16)
		barBg.BorderSizePixel = 0
		Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 3)
		
		local barFill = Instance.new("Frame", barBg)
		barFill.Size = UDim2.fromScale(0, 1)
		barFill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
		barFill.BorderSizePixel = 0
		Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 3)

		local barFillGrad = Instance.new("UIGradient", barFill)
		barFillGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 120, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 240, 255)),
		})

		-- Cost Capsule (Matches Quests UI horizontal reward style)
		local costBadge = Instance.new("Frame", card)
		costBadge.Size = UDim2.new(0, 115, 0, 26)
		costBadge.Position = UDim2.new(0, 15, 0, 56)
		costBadge.BackgroundColor3 = Color3.fromRGB(36, 28, 12)
		costBadge.BorderSizePixel = 0
		Instance.new("UICorner", costBadge).CornerRadius = UDim.new(0, 6)
		
		local costBadgeStroke = Instance.new("UIStroke", costBadge)
		costBadgeStroke.Color = Color3.fromRGB(140, 95, 20)
		costBadgeStroke.Thickness = 1
		
		local costBadgeGrad = Instance.new("UIGradient", costBadge)
		costBadgeGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(48, 36, 12)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 18, 8)),
		})

		local coinIcon = Instance.new("ImageLabel", costBadge)
		coinIcon.Size = UDim2.new(0, 14, 0, 14)
		coinIcon.Position = UDim2.new(0, 6, 0.5, 0)
		coinIcon.AnchorPoint = Vector2.new(0, 0.5)
		coinIcon.BackgroundTransparency = 1
		coinIcon.Image = AssetRegistry.UI.CoinIcon
		coinIcon.ScaleType = Enum.ScaleType.Fit

		local cost = Instance.new("TextLabel", costBadge)
		cost.Name = "CostLabel"
		cost.Size = UDim2.new(1, -26, 1, 0)
		cost.Position = UDim2.new(0, 22, 0, 0)
		cost.TextColor3 = Color3.fromRGB(255, 215, 0)
		cost.Font = Enum.Font.GothamBold
		cost.TextSize = 11
		cost.TextXAlignment = Enum.TextXAlignment.Left
		cost.BackgroundTransparency = 1

		-- Upgrade purchase button
		local buy = Instance.new("TextButton", card)
		buy.Size = UDim2.new(0, 130, 0, 40)
		buy.Position = UDim2.new(1, -145, 0, 52)
		buy.Text = "UPGRADE"
		buy.TextColor3 = Color3.fromRGB(255, 255, 255)
		buy.Font = Enum.Font.GothamBlack
		buy.TextSize = 11
		buy.AutoButtonColor = false
		Instance.new("UICorner", buy).CornerRadius = UDim.new(0, 8)
		
		local buyStroke = Instance.new("UIStroke", buy)
		buyStroke.Thickness = 1.5
		
		local btnScale = Instance.new("UIScale", buy)
		buy.MouseEnter:Connect(function() TweenService:Create(btnScale, TweenInfo.new(0.1), {Scale = 1.05}):Play() end)
		buy.MouseLeave:Connect(function() TweenService:Create(btnScale, TweenInfo.new(0.1), {Scale = 1}):Play() end)
		buy.MouseButton1Down:Connect(function() TweenService:Create(btnScale, TweenInfo.new(0.05), {Scale = 0.95}):Play() end)
		buy.MouseButton1Up:Connect(function() TweenService:Create(btnScale, TweenInfo.new(0.1), {Scale = 1.05}):Play() end)

		UI_Cache[id] = {CostLabel = cost, CostBadge = costBadge, Lvl = lvl, Bar = barFill, Btn = buy, BtnStroke = buyStroke}
		
		buy.MouseButton1Click:Connect(function() req:FireServer(id) end)
	end

	remotes:WaitForChild(RemoteNames.UpdateUpgrades).OnClientEvent:Connect(function(upgrades)
		CurrentUpgrades = upgrades
		RefreshUI()
	end)
	
	task.spawn(function()
		local currencyNames = FeatureResolver.GetCurrencyNames()
		local ls = LocalPlayer:WaitForChild("leaderstats", 5)
		if ls then
			local coins = ls:WaitForChild(currencyNames.Primary, 5) or ls:FindFirstChild("Coins")
			if coins and (coins:IsA("IntValue") or coins:IsA("NumberValue")) then
				(coins :: IntValue).Changed:Connect(RefreshUI)
			end
		end
	end)

	GetLocalEvent("ToggleSkills").Event:Connect(function(reason: string?)
		if isOpen then
			closeSkillsMenu(reason)
		else
			isOpen = true
			animGen += 1
			gui.DisplayOrder = 61 -- render above the outgoing panel during a switch
			MainPanel.Visible = true
			BgShield.Visible = true
			RefreshUI()
			-- Retarget from the current scale (no reset to 0) so reopening during
			-- a close animation continues smoothly instead of snapping shut first.
			-- targetScale is kept fresh by the ViewportSize connection above.
			TweenService:Create(PanelScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = targetScale}):Play()

			GetLocalEvent("NotifyMenuOpened"):Fire("Skills")
		end
	end)

	-- Cross-menu exclusion is owned centrally by UIController's NotifyMenuOpened
	-- handler, which fires ToggleSkills when another menu opens.

	isOpen = false
	MainPanel.Visible = false
	PanelScale.Scale = 0
end

return SkillsController
