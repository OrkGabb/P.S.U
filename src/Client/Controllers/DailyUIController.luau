--!strict
--@author OrkGabb
--@module DailyUIController.luau
--@version 2.0
-- Daily Reward panel: 31-day grid, claim flow, notification-dot sync.
-- Follows the exact structural pattern of QuestsController (panel scale
-- tween, BgShield overlay, NotifyMenuOpened/Closed coordination) so the
-- menu system behaves identically across every core panel.
--
-- v2: previously only registered the HUD button and listened for the
-- notification payload — ToggleDaily fired into the void with no panel to
-- open. This version builds the panel and wires the claim button to the
-- ClaimDailyRequest remote added in Leva 3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local DailyRegistry = require(ReplicatedStorage.Shared.Modules.DailyRegistry)
local MenuPanel = require(script.Parent.Parent.UI.MenuPanel)

local DailyUIController = {}

local menu: MenuPanel.MenuPanelHandle? = nil
local ClaimButton: TextButton
local StatusLabel: TextLabel
local DayCells: { [number]: { Cell: Frame, Label: TextLabel, Icon: ImageLabel } } = {}

local CurrentDailyData: any = { LastClaim = 0, CurrentDay = 0 }

local SECONDS_PER_DAY = 86400

local function GetMidnightUTC(): number
	local now: number = os.time()
	return now - (now % SECONDS_PER_DAY)
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

-- Panel construction

local function BuildDayCell(m: MenuPanel.MenuPanelHandle, day: number, layoutOrder: number): Frame
	local cell = Instance.new("Frame")
	cell.Name = "Day" .. tostring(day)
	cell.Size = UDim2.new(0, 56, 0, 56)
	cell.LayoutOrder = layoutOrder
	cell.BackgroundColor3 = Color3.fromRGB(28, 34, 43)
	cell.BackgroundTransparency = 0.1

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = cell

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(34, 86, 88)
	stroke.Thickness = 1.2
	stroke.Transparency = 0.3
	stroke.Parent = cell

	local dayLabel = Instance.new("TextLabel")
	dayLabel.Name = "DayLabel"
	dayLabel.Size = UDim2.new(1, 0, 0, 14)
	dayLabel.Position = UDim2.new(0, 0, 0, 2)
	dayLabel.BackgroundTransparency = 1
	dayLabel.Text = "DAY " .. tostring(day)
	dayLabel.TextColor3 = Color3.fromRGB(165, 192, 196)
	dayLabel.Font = Enum.Font.GothamBold
	dayLabel.TextSize = 8
	dayLabel.Parent = cell

	local icon = Instance.new("ImageLabel")
	icon.Name = "RewardIcon"
	icon.Size = UDim2.new(0, 24, 0, 24)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0.55, 0)
	icon.BackgroundTransparency = 1
	icon.Image = m.Assets.DailyIcon
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

local function BuildPanel(m: MenuPanel.MenuPanelHandle): ()
	local MainPanel = m.Panel

	-- Daily-exclusive chrome on top of the shared scaffold
	m.Gui.IgnoreGuiInset = true
	MainPanel.BackgroundColor3 = Color3.fromRGB(19, 23, 30)
	MainPanel.BackgroundTransparency = 0.05

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(27, 140, 130)
	stroke.Thickness = 2
	stroke.Parent = MainPanel

	local title = MainPanel:FindFirstChild("Title") :: TextLabel
	title.Size = UDim2.new(1, 0, 0, 36)
	title.Position = UDim2.new(0, 0, 0, 10)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 20

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
		local cell = BuildDayCell(m, day, day)
		cell.Parent = gridHolder
	end

	StatusLabel = Instance.new("TextLabel")
	StatusLabel.Name = "StatusLabel"
	StatusLabel.Size = UDim2.new(1, -32, 0, 20)
	StatusLabel.Position = UDim2.new(0, 16, 1, -70)
	StatusLabel.BackgroundTransparency = 1
	StatusLabel.Text = ""
	StatusLabel.TextColor3 = Color3.fromRGB(165, 192, 196)
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
end

-- Render state

local function RefreshUI(): ()
	if not (menu and menu.IsOpen()) then return end

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
			cellData.Cell.BackgroundColor3 = Color3.fromRGB(28, 72, 74)
			cellData.Icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
		else
			cellData.Cell.BackgroundColor3 = Color3.fromRGB(28, 34, 43)
			cellData.Icon.ImageColor3 = Color3.fromRGB(62, 88, 92)
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

-- Lifecycle

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
	local dailyMenu = MenuPanel.Create({
		Id = "Daily",
		Title = "DAILY REWARDS",
		Size = Vector2.new(480, 380),
		OnOpen = RefreshUI,
		Button = { Name = "DAILY", IconId = "Daily", Type = "Sidebar", LayoutOrder = 5 },
	})
	menu = dailyMenu

	BuildPanel(dailyMenu)

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 0.1) :: Folder?
	if remotes then
		local updateDaily = remotes:WaitForChild(RemoteNames.UpdateDaily, 0.1) :: RemoteEvent?
		if updateDaily then
			updateDaily.OnClientEvent:Connect(function(data: any): ()
				if data then
					CurrentDailyData = data
					local lastClaim: number = data.LastClaim or 0
					dailyMenu.SetButtonNotification(lastClaim < GetMidnightUTC())
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
end

return DailyUIController
