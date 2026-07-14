--!strict
--@author OrkGabb
--@module UIController.luau
--@version 1.0
-- src/Client/Controllers/UIController.luau
-- Central UI coordinator that dynamically instantiates the baseline HUD and exposes a dynamic registration API.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: Folder
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver")) :: any
local AssetRegistry = require(Shared:WaitForChild("Config"):WaitForChild("AssetRegistry")) :: any
local UIHelpers = require(script.Parent.Parent.UI.UIHelpers)
local AssetService = require(script.Parent:WaitForChild("AssetService")) :: any

local LocalPlayer: Player = Players.LocalPlayer

local UIController = {}

export type HUDButtonHandle = {
	SetNotificationActive: (active: boolean, text: string?) -> (),
	Destroy: () -> (),
}

export type HUDButtonConfig = {
	Id: string,
	Name: string?,
	IconId: string,
	Type: "Sidebar" | "Floating" | "TopRight",
	OnClick: () -> (),
	LayoutOrder: number?,
}

type ConfigData = {
	[string]: any
}

-- Cached instances
local mainUI: ScreenGui? = nil
local sidebarFrame: Frame? = nil
local floatingFrame: Frame? = nil
local topRightFrame: Frame? = nil
local arrowBtn: TextButton? = nil
local upgradePanel: Frame? = nil
local upgradePanelScale: UIScale? = nil
local upgradePanelShield: TextButton? = nil

-- Open state is tracked here, never derived from Visible: Visible stays true
-- through the whole close animation, so deriving state from it misroutes any
-- toggle that arrives mid-animation. The generation counter invalidates stale
-- Tween.Completed handlers when a newer transition has taken over.
local upgradePanelOpen: boolean = false
local upgradePanelAnimGen: number = 0

local sidebarVisible: boolean = true
local centeredOffsetY: number = 0
local safeUI = AssetRegistry.UI or {}
local buttonSize: number = safeUI.ButtonSize or 45
local bottomButtonSize: number = safeUI.BottomButtonSize or 45
-- Sidebar hugs the left screen edge (10px margin) so a leftward cursor flick
-- lands on the buttons instead of a dead strip.
local SIDEBAR_MARGIN_X: number = 10
local ARROW_OPEN_X: number = SIDEBAR_MARGIN_X + buttonSize + 10
-- Closed-state arrow sits flush against the screen edge so a leftward flick
-- can't overshoot it (Fitts edge target).
local ARROW_CLOSE_X: number = 0
local POS_OPEN: UDim2 = UDim2.new(0, SIDEBAR_MARGIN_X, 0.5, 0)
local POS_CLOSE: UDim2 = UDim2.new(0, -buttonSize - 20, 0.5, 0)
local currentOpenMenuId: string? = nil

local tweenInfo: TweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Local event caching
local function GetLocalEvent(eventName: string): BindableEvent
	local folder: Folder? = ReplicatedStorage:FindFirstChild("LocalEvents") :: Folder?
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "LocalEvents"
		newFolder.Parent = ReplicatedStorage
		folder = newFolder
	end
	local evt: BindableEvent? = (folder :: Folder):FindFirstChild(eventName) :: BindableEvent?
	if not evt then
		local newEvt = Instance.new("BindableEvent")
		newEvt.Name = eventName
		newEvt.Parent = folder :: Folder
		evt = newEvt
	end
	return evt :: BindableEvent
end

local function SetSidebarVisible(open: boolean, instant: boolean?): ()
	if not sidebarFrame or not arrowBtn then return end
	sidebarVisible = open
	arrowBtn.Text = open and "◀" or "▶"

	local targetContainer: UDim2 = open and POS_OPEN or POS_CLOSE
	local targetArrow: UDim2 = UDim2.new(0, open and ARROW_OPEN_X or ARROW_CLOSE_X, 0.5, centeredOffsetY)

	if instant then
		sidebarFrame.Position = targetContainer
		arrowBtn.Position = targetArrow
		return
	end

	TweenService:Create(sidebarFrame, tweenInfo, {Position = targetContainer}):Play()
	TweenService:Create(arrowBtn, tweenInfo, {Position = targetArrow}):Play()
end

local function ToggleUpgradePanel(reason: string?): ()
	local panel = upgradePanel
	local panelScale = upgradePanelScale
	if not panel or not panelScale then return end

	upgradePanelOpen = not upgradePanelOpen
	upgradePanelAnimGen += 1
	local gen = upgradePanelAnimGen

	if upgradePanelOpen then
		-- Retarget from the current scale (no reset to 0) so reopening during a
		-- close animation continues smoothly instead of snapping shut first.
		panel.Visible = true
		if upgradePanelShield then upgradePanelShield.Visible = true end
		TweenService:Create(panelScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		GetLocalEvent("NotifyMenuOpened"):Fire("Upgrades")
	else
		if upgradePanelShield then upgradePanelShield.Visible = false end
		GetLocalEvent("NotifyMenuClosed"):Fire("Upgrades")
		-- A switch-triggered close (another panel is taking over) uses a fast
		-- start so the outgoing panel gets out of the way quickly; a manual
		-- close keeps the slower, weightier Back/In easing.
		local closeTween: TweenInfo = if reason == "switch"
			then TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			else TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		local tw = TweenService:Create(panelScale, closeTween, {Scale = 0})
		tw:Play()
		tw.Completed:Connect(function(state: Enum.PlaybackState): ()
			-- A reopen cancels this tween (Completed still fires, state=Cancelled)
			-- and bumps the generation; hide only if this close ran to completion
			-- and is still the latest transition.
			if gen ~= upgradePanelAnimGen then return end
			if state ~= Enum.PlaybackState.Completed then return end
			panel.Visible = false
		end)
	end
end

local function BindUpgradePurchase(button: TextButton, categoryId: string): ()
	button.MouseButton1Click:Connect(function(): ()
		UIController.RequestUpgradePurchase(categoryId)
	end)
end

function UIController.Init(): ()
	print("[INFO] UIController Init phase executed")
	UIController.InitializeDynamicHUD()
end

function UIController.Start(): ()
	print("[INFO] UIController Start: Constructing dynamic HUD container.")
	UIController.InitializeDynamicPanels()
end

function UIController.InitializeDynamicHUD(): ()
	-- Instantly create layout structures in memory to avoid lifecycle race conditions
	local dynamicInterface = Instance.new("ScreenGui")
	dynamicInterface.Name = "MainInterface"
	dynamicInterface.ResetOnSpawn = false
	dynamicInterface.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	dynamicInterface.DisplayOrder = 100
	mainUI = dynamicInterface

	-- Sidebar frame baseline container
	local sFrame = Instance.new("Frame")
	sFrame.Name = "SidebarFrame"
	sFrame.AnchorPoint = Vector2.new(0, 0.5)
	sFrame.Size = UDim2.new(0, buttonSize, 0, 0)
	sFrame.AutomaticSize = Enum.AutomaticSize.Y
	sFrame.BackgroundTransparency = 1
	sFrame.Position = POS_OPEN
	sFrame.Parent = dynamicInterface
	sidebarFrame = sFrame

	local sLayout = Instance.new("UIListLayout")
	sLayout.Padding = UDim.new(0, 6)
	sLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sLayout.Parent = sFrame

	-- Toggle Arrow
	local arrow = Instance.new("TextButton")
	arrow.Name = "SidebarToggleArrow"
	arrow.Size = UDim2.new(0, 28, 0, 64)
	arrow.AnchorPoint = Vector2.new(0, 0.5)
	arrow.BackgroundColor3 = Color3.fromRGB(28, 28, 33)
	arrow.BackgroundTransparency = 0.3
	arrow.Text = "◀"
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextSize = 14
	arrow.TextColor3 = Color3.fromRGB(180, 180, 190)
	arrow.AutoButtonColor = false
	arrow.ZIndex = 10
	arrow.Parent = dynamicInterface
	arrowBtn = arrow

	local arrowCorner = Instance.new("UICorner")
	arrowCorner.CornerRadius = UDim.new(0, 5)
	arrowCorner.Parent = arrow

	arrow.MouseEnter:Connect(function(): ()
		TweenService:Create(arrow, TweenInfo.new(0.12),
			{BackgroundTransparency = 0.1, TextColor3 = Color3.fromRGB(230, 230, 240)}):Play()
	end)
	arrow.MouseLeave:Connect(function(): ()
		TweenService:Create(arrow, TweenInfo.new(0.15),
			{BackgroundTransparency = 0.3, TextColor3 = Color3.fromRGB(180, 180, 190)}):Play()
	end)
	arrow.MouseButton1Down:Connect(function(): ()
		TweenService:Create(arrow, TweenInfo.new(0.06), {BackgroundTransparency = 0.0}):Play()
	end)
	arrow.MouseButton1Up:Connect(function(): ()
		TweenService:Create(arrow, TweenInfo.new(0.12), {BackgroundTransparency = 0.3}):Play()
	end)
	arrow.MouseButton1Click:Connect(function(): ()
		SetSidebarVisible(not sidebarVisible)
	end)

	-- Auto-hide arrow if sidebar is empty
	local function checkSidebarArrowVisibility()
		if not arrowBtn or not sidebarFrame then return end
		local count = 0
		for _, child in ipairs(sidebarFrame:GetChildren()) do
			if not child:IsA("UIListLayout") then count += 1 end
		end
		arrowBtn.Visible = (count > 0)
	end
	sFrame.ChildAdded:Connect(checkSidebarArrowVisibility)
	sFrame.ChildRemoved:Connect(checkSidebarArrowVisibility)
	checkSidebarArrowVisibility()

	-- Floating buttons container
	local fFrame = Instance.new("Frame")
	fFrame.Name = "FloatingFrame"
	fFrame.AnchorPoint = Vector2.new(1, 1)
	fFrame.Size = UDim2.new(0, bottomButtonSize, 0, 0)
	fFrame.AutomaticSize = Enum.AutomaticSize.Y
	fFrame.BackgroundTransparency = 1
	fFrame.Position = UDim2.new(1, -20, 1, -30)
	fFrame.Parent = dynamicInterface
	floatingFrame = fFrame

	local fLayout = Instance.new("UIListLayout")
	fLayout.Padding = UDim.new(0, 6)
	fLayout.SortOrder = Enum.SortOrder.LayoutOrder
	fLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	fLayout.Parent = fFrame

	-- Top-right buttons container (for Settings gear icon) — absolute top-right corner
	local trFrame = Instance.new("Frame")
	trFrame.Name = "TopRightFrame"
	trFrame.AnchorPoint = Vector2.new(1, 0)
	trFrame.Size = UDim2.new(0, bottomButtonSize, 0, 0)
	trFrame.AutomaticSize = Enum.AutomaticSize.Y
	trFrame.BackgroundTransparency = 1
	trFrame.Position = UDim2.new(1, -8, 0, 8)
	trFrame.Parent = dynamicInterface
	topRightFrame = trFrame

	local trLayout = Instance.new("UIListLayout")
	trLayout.Padding = UDim.new(0, 6)
	trLayout.SortOrder = Enum.SortOrder.LayoutOrder
	trLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	trLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	trLayout.Parent = trFrame

	-- Coordinate sidebar placement from the interface's own AbsoluteSize.
	-- AbsoluteSize is (0, 0) until the ScreenGui is parented to PlayerGui (done
	-- asynchronously below), and camera ViewportSize does not fire on parenting —
	-- so listen to the AbsoluteSize signal, which covers both parenting and any
	-- later viewport resize.
	local function updateSidebarPosition(): ()
		local screenH: number = dynamicInterface.AbsoluteSize.Y
		if screenH <= 0 then return end
		local freeZoneCenter: number = 56 + (screenH - 56 - 150) / 2
		centeredOffsetY = math.floor(freeZoneCenter - screenH * 0.5)

		POS_OPEN = UDim2.new(0, SIDEBAR_MARGIN_X, 0.5, centeredOffsetY)
		POS_CLOSE = UDim2.new(0, -buttonSize - 20, 0.5, centeredOffsetY)

		SetSidebarVisible(sidebarVisible, true)
	end
	dynamicInterface:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSidebarPosition)
	updateSidebarPosition()

	-- Open/Close coordination matching SidebarController behavior
	GetLocalEvent("NotifyMenuClosed").Event:Connect(function(closedMenuId: string): ()
		if currentOpenMenuId == closedMenuId then
			currentOpenMenuId = nil
			GetLocalEvent("ToggleGachaButton"):Fire(true)
		end
	end)

	GetLocalEvent("NotifyMenuOpened").Event:Connect(function(openedMenuId: string): ()
		if currentOpenMenuId and currentOpenMenuId ~= openedMenuId then
			-- "switch" tells the outgoing panel to use its fast-start close
			-- instead of the slower manual-close easing.
			GetLocalEvent("Toggle" .. currentOpenMenuId):Fire("switch")
		end
		currentOpenMenuId = openedMenuId
		GetLocalEvent("ToggleGachaButton"):Fire(false)
	end)

	-- Parent the ScreenGui asynchronously to prevent yielding during initialization
	task.spawn(function(): ()
		local playerGui: PlayerGui? = LocalPlayer:WaitForChild("PlayerGui", 10) :: any
		if not playerGui then
			warn("[WARN] PlayerGui not found, aborting UI parenting.")
			return
		end

		-- Clear any stale legacy MainInterface or SidebarGui
		local oldMain: Instance? = (playerGui :: PlayerGui):FindFirstChild("MainInterface")
		if oldMain then oldMain:Destroy() end
		local oldSidebar: Instance? = (playerGui :: PlayerGui):FindFirstChild("SidebarGui")
		if oldSidebar then oldSidebar:Destroy() end

		dynamicInterface.Parent = playerGui
	end)
end

function UIController.RegisterHUDButton(config: HUDButtonConfig): HUDButtonHandle
	local targetContainer: Frame? = nil
	if config.Type == "Sidebar" then
		targetContainer = sidebarFrame
	elseif config.Type == "TopRight" then
		targetContainer = topRightFrame
	else
		targetContainer = floatingFrame
	end

	if not targetContainer or not mainUI then
		error("[UIController] Layout containers not initialized.")
	end

	local btnSize: number = buttonSize
	local container = Instance.new("Frame")
	container.Name = config.Id .. "Container"
	container.Size = UDim2.new(0, btnSize, 0, btnSize + 6)
	container.BackgroundTransparency = 1
	container.LayoutOrder = config.LayoutOrder or 10
	container.Parent = targetContainer

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.new(1, 0, 1, -6)
	shadow.Position = UDim2.new(0, 0, 0, 6)
	shadow.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	shadow.BorderSizePixel = 0
	shadow.Parent = container
	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0, 12)
	shadowCorner.Parent = shadow

	local btn = Instance.new("TextButton")
	btn.Name = config.Id
	btn.Size = UDim2.new(1, 0, 1, -6)
	btn.Position = UDim2.new(0, 0, 0, 0)
	btn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.Parent = container
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 12)
	btnCorner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(70, 70, 85)
	stroke.Thickness = 1.5
	stroke.Parent = btn

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, config.Name and 0.38 or 0.5, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Stretch
	icon.Parent = btn

	AssetService.ApplyIcon(icon, config.IconId)

	local iconData = AssetService.GetIconData(config.IconId)
	if iconData then
		icon.Position = UDim2.new(
			0.5, iconData.PixelShift.X,
			config.Name and 0.38 or 0.5, iconData.PixelShift.Y
		)
	end

	if config.Name then
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, 0, 0.3, 0)
		label.Position = UDim2.new(0, 0, 0.65, 0)
		label.Text = config.Name:upper()
		label.TextSize = 9
		label.TextColor3 = Color3.fromRGB(220, 220, 220)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.Parent = btn
	end

	-- Badge Notification Dot
	local dot = Instance.new("Frame")
	dot.Name = "NotifDot"
	dot.Size = UDim2.new(0, 12, 0, 12)
	dot.AnchorPoint = Vector2.new(1, 0)
	dot.Position = UDim2.new(1, -2, 0, 2)
	dot.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	dot.BorderSizePixel = 0
	dot.Visible = false
	dot.ZIndex = 10
	dot.Parent = btn
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	local dotLabel = Instance.new("TextLabel")
	dotLabel.Name = "Label"
	dotLabel.Size = UDim2.fromScale(1, 1)
	dotLabel.BackgroundTransparency = 1
	dotLabel.Text = "!"
	dotLabel.Font = Enum.Font.GothamBlack
	dotLabel.TextSize = 10
	dotLabel.TextColor3 = Color3.new(1, 1, 1)
	dotLabel.TextXAlignment = Enum.TextXAlignment.Center
	dotLabel.TextYAlignment = Enum.TextYAlignment.Center
	dotLabel.ZIndex = dot.ZIndex + 1
	dotLabel.Parent = dot

	btn.MouseEnter:Connect(function(): ()
		TweenService:Create(btn, TweenInfo.new(0.15),
			{BackgroundColor3 = Color3.fromRGB(45, 45, 52)}):Play()
	end)
	btn.MouseLeave:Connect(function(): ()
		TweenService:Create(btn, TweenInfo.new(0.2), {
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundColor3 = Color3.fromRGB(35, 35, 40)
		}):Play()
	end)
	btn.MouseButton1Down:Connect(function(): ()
		TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Position = UDim2.new(0, 0, 0, 4)}):Play()
	end)
	btn.MouseButton1Up:Connect(function(): ()
		TweenService:Create(btn, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Position = UDim2.new(0, 0, 0, 0)}):Play()
	end)
	btn.MouseButton1Click:Connect(config.OnClick)

	local handle: HUDButtonHandle = {
		SetNotificationActive = function(active: boolean, text: string?): ()
			dot.Visible = active
			if text then dotLabel.Text = text end
		end,
		Destroy = function(): ()
			container:Destroy()
		end
	}

	return handle
end

function UIController.InitializeDynamicPanels(): ()
	local upgradeConfigs: ConfigData = FeatureResolver.GetConfigField("Upgrades", "Configs", {}) :: ConfigData
	
	if not FeatureResolver.IsCategoryActive("Upgrades") and not FeatureResolver.IsCategoryActive("RPG_Adventure") then
		return
	end

	-- Procedurally build the UpgradePanel UI hierarchy
	local dynamicInterface = mainUI
	if not dynamicInterface then return end

	-- Click-outside-to-close shield, matching the BgShield every other panel has.
	-- Created before the panel so sibling paint order keeps the panel on top.
	local shield = Instance.new("TextButton")
	shield.Name = "InputSink"
	shield.Size = UDim2.fromScale(1, 1)
	shield.BackgroundColor3 = Color3.new(0, 0, 0)
	shield.BackgroundTransparency = 0.5
	shield.Text = ""
	shield.AutoButtonColor = false
	shield.Visible = false
	shield.Active = true
	shield.Parent = dynamicInterface
	upgradePanelShield = shield
	shield.MouseButton1Up:Connect(function(): ()
		if upgradePanelOpen then ToggleUpgradePanel() end
	end)

	local panel = Instance.new("Frame")
	panel.Name = "UpgradePanel"
	panel.Size = UDim2.new(0, 620, 0, 420)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = Color3.fromRGB(15, 14, 22)
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = false
	panel.Parent = dynamicInterface
	upgradePanel = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(90, 60, 150)
	panelStroke.Thickness = 2.5
	panelStroke.Parent = panel

	local panelGrad = Instance.new("UIGradient")
	panelGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 16, 38)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 8, 16)),
	})
	panelGrad.Rotation = 135
	panelGrad.Parent = panel

	local panelScale = Instance.new("UIScale")
	panelScale.Scale = 0
	panelScale.Parent = panel
	upgradePanelScale = panelScale

	-- Close Button
	UIHelpers.CreateCloseButton(panel, ToggleUpgradePanel)

	local panelTitle = Instance.new("TextLabel")
	panelTitle.Size = UDim2.new(1, 0, 0, 50)
	panelTitle.BackgroundTransparency = 1
	panelTitle.Text = "UPGRADES"
	panelTitle.Font = Enum.Font.FredokaOne
	panelTitle.TextSize = 22
	panelTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	panelTitle.Parent = panel

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(130, 90, 230)
	titleStroke.Thickness = 1.5
	titleStroke.Parent = panelTitle

	-- Scrolling frame container
	local container = Instance.new("ScrollingFrame")
	container.Name = "Container"
	container.Size = UDim2.new(1, -24, 1, -70)
	container.Position = UDim2.new(0, 12, 0, 55)
	container.BackgroundTransparency = 1
	container.ScrollBarThickness = 4
	container.ScrollBarImageColor3 = Color3.fromRGB(130, 90, 230)
	container.BorderSizePixel = 0
	container.CanvasSize = UDim2.new(0, 0, 0, 0)
	container.AutomaticCanvasSize = Enum.AutomaticSize.Y
	container.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = container

	-- Template Upgrade Node
	local template = Instance.new("Frame")
	template.Name = "Template"
	template.Size = UDim2.new(1, 0, 0, 60)
	template.BackgroundColor3 = Color3.fromRGB(22, 17, 32)
	template.BorderSizePixel = 0
	template.Visible = false
	template.Parent = container
	local templateCorner = Instance.new("UICorner")
	templateCorner.CornerRadius = UDim.new(0, 10)
	templateCorner.Parent = template
	local templateStroke = Instance.new("UIStroke")
	templateStroke.Color = Color3.fromRGB(60, 48, 85)
	templateStroke.Thickness = 1.5
	templateStroke.Parent = template

	local tTitle = Instance.new("TextLabel")
	tTitle.Name = "TitleLabel"
	tTitle.Size = UDim2.new(0.6, 0, 1, 0)
	tTitle.Position = UDim2.new(0, 15, 0, 0)
	tTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	tTitle.Font = Enum.Font.GothamBold
	tTitle.TextSize = 14
	tTitle.TextXAlignment = Enum.TextXAlignment.Left
	tTitle.BackgroundTransparency = 1
	tTitle.Parent = template

	local buyBtn = Instance.new("TextButton")
	buyBtn.Name = "PurchaseButton"
	buyBtn.Size = UDim2.new(0, 140, 0, 40)
	buyBtn.Position = UDim2.new(1, -155, 0.5, -20)
	buyBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 50)
	buyBtn.Text = "UPGRADE"
	buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyBtn.Font = Enum.Font.GothamBlack
	buyBtn.TextSize = 11
	buyBtn.AutoButtonColor = false
	buyBtn.Parent = template
	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 8)
	buyCorner.Parent = buyBtn
	local buyStroke = Instance.new("UIStroke")
	buyStroke.Color = Color3.fromRGB(0, 80, 25)
	buyStroke.Thickness = 1.5
	buyStroke.Parent = buyBtn

	-- Build upgrade list
	for categoryId: string, _ in pairs(upgradeConfigs) do
		local newNode = template:Clone()
		newNode.Name = categoryId
		newNode.Visible = true
		
		local label = newNode:FindFirstChild("TitleLabel") :: TextLabel
		label.Text = tostring(categoryId):upper()
		
		local button = newNode:FindFirstChild("PurchaseButton") :: TextButton
		BindUpgradePurchase(button, categoryId)
		
		newNode.Parent = container
	end

	-- Connect keyboard shortcut & events
	local toggleEvent: BindableEvent = GetLocalEvent("ToggleUpgradePanel")
	toggleEvent.Event:Connect(ToggleUpgradePanel)

	local toggleEvent2: BindableEvent = GetLocalEvent("ToggleUpgrades")
	toggleEvent2.Event:Connect(ToggleUpgradePanel)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean): ()
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.U then
			ToggleUpgradePanel()
		end
	end)
end

function UIController.RequestUpgradePurchase(categoryId: string): ()
	print("[INFO] Dispatching upgrade purchase request for category: " .. categoryId)
	local networkBridge = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
	local purchaseEvent = networkBridge and networkBridge:FindFirstChild("RequestUpgradePurchase") :: RemoteEvent?
	if purchaseEvent then
		purchaseEvent:FireServer(categoryId)
	else
		warn("[UIController] RequestUpgradePurchase failed: Remote not found.")
	end
end

return UIController
