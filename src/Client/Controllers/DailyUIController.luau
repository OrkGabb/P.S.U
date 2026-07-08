--!strict
--@author OrkGabb
--@module DailyUIController.luau
--@version 2.0
-- src/Client/Controllers/DailyUIController.luau
-- Daily Reward panel: 31-day grid, claim flow, notification-dot sync.
-- Follows the exact structural pattern of QuestsController (panel scale
-- tween, BgShield overlay, NotifyMenuOpened/Closed coordination) so the
-- menu system behaves identically across every core panel.
--
-- v2: previously only registered the HUD button and listened for the
-- notification payload — ToggleDaily fired into the void with no panel to
-- open. This version builds the panel and wires the claim button to the
-- ClaimDailyRequest remote added in Leva 3.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local DailyRegistry = require(ReplicatedStorage.Shared.Modules.DailyRegistry)
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local LocalPlayer = Players.LocalPlayer

local DailyUIController = {}

local PanelGui: ScreenGui
local MainPanel: Frame
local PanelScale: UIScale
local BgShield: TextButton
local ClaimButton: TextButton
local StatusLabel: TextLabel
local DayCells: { [number]: { Cell: Frame, Label: TextLabel, Icon: ImageLabel } } = {}

local isOpen = false
-- Bumped on every open/close transition; stale animation callbacks compare
-- against it and stand down if a newer transition has taken over.
local animGen = 0
local targetScale = 1

local CurrentDailyData: any = { LastClaim = 0, CurrentDay = 0 }

local SECONDS_PER_DAY = 86400

local function GetMidnightUTC(): number
	local now: number = os.time()
	return now - (now % SECONDS_PER_DAY)
end

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

local function GetButtonStroke(btn: TextButton): UIStroke
	local existing = btn:FindFirstChild("UIStroke")
	if existing and existing:IsA("UIStroke") then
		return existing
	end
	local stroke = Instance.new("UIStroke")
	stroke.Parent = btn
	return stroke
end

--------------------------------------------------------------------------------
-- Panel construction
--------------------------------------------------------------------------------

local function BuildDayCell(day: number, layoutOrder: number): Frame
	local cell = Instance.new("Frame")
	cell.Name = "Day" .. tostring(day)
	cell.Size = UDim2.new(0, 56, 0, 56)
	cell.LayoutOrder = layoutOrder
	cell.BackgroundColor3 = Color3.fromRGB(30, 25, 45)
	cell.BackgroundTransparency = 0.1

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = cell

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 60, 120)
	stroke.Thickness = 1.2
	stroke.Transparency = 0.3
	stroke.Parent = cell

	local dayLabel = Instance.new("TextLabel")
	dayLabel.Name = "DayLabel"
	dayLabel.Size = UDim2.new(1, 0, 0, 14)
	dayLabel.Position = UDim2.new(0, 0, 0, 2)
	dayLabel.BackgroundTransparency = 1
	dayLabel.Text = "DAY " .. tostring(day)
	dayLabel.TextColor3 = Color3.fromRGB(180, 170, 200)
	dayLabel.Font = Enum.Font.GothamBold
	dayLabel.TextSize = 8
	dayLabel.Parent = cell

	local icon = Instance.new("ImageLabel")
	icon.Name = "RewardIcon"
	icon.Size = UDim2.new(0, 24, 0, 24)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0.55, 0)
	icon.BackgroundTransparency = 1
	icon.Image = AssetRegistry.UI.DailyIcon
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = cell

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "RewardLabel"
	rewardLabel.Size = UDim2.new(1, 0, 0, 12)
	rewardLabel.Position = UDim2.new(0, 0, 1, -14)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.TextSize = 8
	rewardLabel.Parent = cell

	DayCells[day] = { Cell = cell, Label = rewardLabel, Icon = icon }
	return cell
end

local function BuildPanel(): ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DailyGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60 -- panel band: 60 resting/closing, 61 while open
	gui.Parent = LocalPlayer.PlayerGui
	PanelGui = gui

	BgShield = Instance.new("TextButton")
	BgShield.Name = "BgShield"
	BgShield.Size = UDim2.fromScale(1, 1)
	BgShield.BackgroundColor3 = Color3.new(0, 0, 0)
	BgShield.BackgroundTransparency = 0.5
	BgShield.Text = ""
	BgShield.AutoButtonColor = false
	BgShield.Visible = false
	BgShield.ZIndex = 1
	BgShield.Parent = gui

	MainPanel = Instance.new("Frame")
	MainPanel.Name = "DailyPanel"
	MainPanel.Size = UDim2.new(0, 480, 0, 380)
	MainPanel.Position = UDim2.fromScale(0.5, 0.5)
	MainPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	MainPanel.BackgroundColor3 = Color3.fromRGB(18, 14, 28)
	MainPanel.BackgroundTransparency = 0.05
	MainPanel.Visible = false
	MainPanel.ZIndex = 2
	MainPanel.Parent = gui

	PanelScale = Instance.new("UIScale")
	PanelScale.Scale = 0
	PanelScale.Parent = MainPanel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = MainPanel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 70, 150)
	stroke.Thickness = 2
	stroke.Parent = MainPanel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 36)
	title.Position = UDim2.new(0, 0, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = "DAILY REWARDS"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 20
	title.Parent = MainPanel

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 28, 0, 28)
	closeBtn.Position = UDim2.new(1, -38, 0, 12)
	closeBtn.BackgroundColor3 = Color3.fromRGB(40, 30, 55)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 14
	closeBtn.Parent = MainPanel
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

	local gridHolder = Instance.new("ScrollingFrame")
	gridHolder.Name = "GridHolder"
	gridHolder.Size = UDim2.new(1, -32, 0, 260)
	gridHolder.Position = UDim2.new(0, 16, 0, 54)
	gridHolder.BackgroundTransparency = 1
	gridHolder.ScrollBarThickness = 4
	gridHolder.CanvasSize = UDim2.new(0, 0, 0, 0)
	gridHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
	gridHolder.Parent = MainPanel

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 56, 0, 56)
	gridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridHolder

	local maxDay = 0
	for day in pairs(DailyRegistry.Days) do
		if day > maxDay then maxDay = day end
	end
	for day = 1, maxDay do
		local cell = BuildDayCell(day, day)
		cell.Parent = gridHolder
	end

	StatusLabel = Instance.new("TextLabel")
	StatusLabel.Name = "StatusLabel"
	StatusLabel.Size = UDim2.new(1, -32, 0, 20)
	StatusLabel.Position = UDim2.new(0, 16, 1, -70)
	StatusLabel.BackgroundTransparency = 1
	StatusLabel.Text = ""
	StatusLabel.TextColor3 = Color3.fromRGB(180, 170, 200)
	StatusLabel.Font = Enum.Font.Gotham
	StatusLabel.TextSize = 12
	StatusLabel.Parent = MainPanel

	ClaimButton = Instance.new("TextButton")
	ClaimButton.Name = "ClaimButton"
	ClaimButton.Size = UDim2.new(1, -32, 0, 40)
	ClaimButton.Position = UDim2.new(0, 16, 1, -48)
	ClaimButton.BackgroundColor3 = Color3.fromRGB(0, 180, 70)
	ClaimButton.Text = "CLAIM"
	ClaimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	ClaimButton.Font = Enum.Font.GothamBold
	ClaimButton.TextSize = 16
	ClaimButton.Parent = MainPanel
	Instance.new("UICorner", ClaimButton).CornerRadius = UDim.new(0, 8)
	GetButtonStroke(ClaimButton).Thickness = 0

	BgShield.MouseButton1Click:Connect(function()
		GetLocalEvent("ToggleDaily"):Fire()
	end)
	closeBtn.MouseButton1Click:Connect(function()
		GetLocalEvent("ToggleDaily"):Fire()
	end)
end

--------------------------------------------------------------------------------
-- Render state
--------------------------------------------------------------------------------

local function RefreshUI(): ()
	if not isOpen then return end

	local maxDay = 0
	for day in pairs(DailyRegistry.Days) do
		if day > maxDay then maxDay = day end
	end

	local currentDay: number = CurrentDailyData.CurrentDay or 0
	local canClaim: boolean = (CurrentDailyData.LastClaim or 0) < GetMidnightUTC()
	local nextDay = currentDay + 1
	if nextDay > maxDay then nextDay = 1 end

	for day = 1, maxDay do
		local cellData = DayCells[day]
		if not cellData then continue end

		local entry = DailyRegistry.Days[day]
		local rewardText = entry and (entry.Fragments > 0 and ("+" .. tostring(entry.Fragments) .. " Fragments") or "Coins") or ""
		cellData.Label.Text = rewardText

		if day <= currentDay then
			cellData.Cell.BackgroundColor3 = Color3.fromRGB(20, 60, 35)
			cellData.Icon.ImageColor3 = Color3.fromRGB(120, 255, 160)
		elseif day == nextDay and canClaim then
			cellData.Cell.BackgroundColor3 = Color3.fromRGB(60, 45, 90)
			cellData.Icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
		else
			cellData.Cell.BackgroundColor3 = Color3.fromRGB(30, 25, 45)
			cellData.Icon.ImageColor3 = Color3.fromRGB(90, 80, 110)
		end
	end

	if canClaim then
		ClaimButton.Text = "CLAIM DAY " .. tostring(nextDay)
		ClaimButton.BackgroundColor3 = Color3.fromRGB(0, 180, 70)
		ClaimButton.Active = true
		StatusLabel.Text = "Your reward is ready!"
	else
		ClaimButton.Text = "CLAIMED"
		ClaimButton.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
		ClaimButton.Active = false
		StatusLabel.Text = "Come back after the daily reset."
	end
end

--------------------------------------------------------------------------------
-- Open / close (mirrors QuestsController's panel-scale pattern)
--------------------------------------------------------------------------------

local function closeDailyMenu(reason: string?): ()
	if not isOpen then return end
	isOpen = false
	animGen += 1
	local gen = animGen
	PanelGui.DisplayOrder = 60
	-- Hide the input sink with the logical state, not in Completed — otherwise
	-- the invisible full-screen shield keeps eating clicks while the panel is
	-- still animating shut.
	BgShield.Visible = false
	GetLocalEvent("NotifyMenuClosed"):Fire("Daily")
	-- A switch-triggered close (another panel is taking over) uses a fast
	-- start so the outgoing panel gets out of the way quickly; a manual close
	-- keeps the slower, weightier Quart/In easing.
	local closeTween: TweenInfo = if reason == "switch"
		then TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		else TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
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

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function DailyUIController.Init(): ()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 0.1) :: Folder?
	if not remotes then
		warn("[INFO] DailyUIController Suspension: Remote not found.")
		return
	end

	local updateDaily = remotes:WaitForChild(RemoteNames.UpdateDaily, 0.1) :: RemoteEvent?
	if not updateDaily then
		warn("[INFO] DailyUIController Suspension: Remote not found.")
		return
	end
end

function DailyUIController.Start(): ()
	local UIController: any = require(script.Parent:WaitForChild("UIController"))
	local handle = UIController.RegisterHUDButton({
		Id = "Daily",
		Name = "DAILY",
		IconId = "Daily",
		Type = "Sidebar",
		LayoutOrder = 5,
		OnClick = function(): ()
			GetLocalEvent("ToggleDaily"):Fire()
		end
	})

	BuildPanel()

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 0.1) :: Folder?
	if remotes then
		local updateDaily = remotes:WaitForChild(RemoteNames.UpdateDaily, 0.1) :: RemoteEvent?
		if updateDaily then
			updateDaily.OnClientEvent:Connect(function(data: any): ()
				if data then
					CurrentDailyData = data
					local lastClaim: number = data.LastClaim or 0
					handle.SetNotificationActive(lastClaim < GetMidnightUTC())
					RefreshUI()
				end
			end)
		end

		local claimEvent = remotes:WaitForChild(RemoteNames.ClaimDailyRequest, 0.1) :: RemoteEvent?
		ClaimButton.MouseButton1Click:Connect(function()
			if claimEvent and ClaimButton.Active then
				claimEvent:FireServer()
			end
		end)
	end

	GetLocalEvent("ToggleDaily").Event:Connect(function(reason: string?)
		if isOpen then
			closeDailyMenu(reason)
		else
			isOpen = true
			animGen += 1
			PanelGui.DisplayOrder = 61 -- render above the outgoing panel during a switch
			MainPanel.Visible = true
			BgShield.Visible = true
			RefreshUI()
			-- Retarget from the current scale (no reset to 0) so reopening during
			-- a close animation continues smoothly instead of snapping shut first.
			TweenService:Create(PanelScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = targetScale}):Play()

			GetLocalEvent("NotifyMenuOpened"):Fire("Daily")
		end
	end)

	-- Cross-menu exclusion is owned centrally by UIController's NotifyMenuOpened
	-- handler, which fires ToggleDaily when another menu opens.
end

return DailyUIController
