--!strict
-- @Author @OrkGabb
-- Dynamic sidebar UI Controller. Automatically gates menus based on active features.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local LocalPlayer       = Players.LocalPlayer

local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local AssetService = require(script.Parent.AssetService)

local SidebarController = {}
local isProcessing      = false
local currentOpenMenuId: string? = nil

local BadgeContainers: {[string]: Frame} = {}

local function GetLocalEvent(eventName: string): BindableEvent
	local folder = ReplicatedStorage:FindFirstChild("LocalEvents")
		or Instance.new("Folder", ReplicatedStorage)
	folder.Name = "LocalEvents"
	local evt = folder:FindFirstChild(eventName)
		or Instance.new("BindableEvent", folder)
	evt.Name = eventName
	return evt :: BindableEvent
end

local function CreateNotifDot(parent: GuiObject): Frame
	local dot = Instance.new("Frame", parent)
	dot.Name = "NotifDot"
	dot.Size = UDim2.new(0, 12, 0, 12)
	dot.AnchorPoint = Vector2.new(1, 0)
	dot.Position = UDim2.new(1, -2, 0, 2)
	dot.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	dot.BorderSizePixel = 0
	dot.Visible = false
	dot.ZIndex = 10
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

	local dotLabel = Instance.new("TextLabel", dot)
	dotLabel.Size               = UDim2.fromScale(1, 1)
	dotLabel.BackgroundTransparency = 1
	dotLabel.Text               = "!"
	dotLabel.Font               = Enum.Font.GothamBlack
	dotLabel.TextSize           = 10
	dotLabel.TextColor3         = Color3.new(1, 1, 1)
	dotLabel.TextXAlignment     = Enum.TextXAlignment.Center
	dotLabel.TextYAlignment     = Enum.TextYAlignment.Center
	dotLabel.ZIndex             = dot.ZIndex + 1

	return dot
end

local dailyNotifDot: Frame? = nil

local function GetMidnightUTC(): number
	local now = os.time()
	return now - (now % 86400)
end

local SidebarUIFactory = {}
function SidebarUIFactory.CreateButton(
	parent: Instance, nameText: string?, iconId: string,
	isLocked: boolean, size: number
): (Frame, string, TextButton)

	local originalName = nameText
	if nameText then nameText = nameText:upper() end

	local container = Instance.new("Frame", parent)
	container.Size               = UDim2.new(0, size, 0, size + 6)
	container.BackgroundTransparency = 1

	local shadow = Instance.new("Frame", container)
	shadow.Size             = UDim2.new(1, 0, 1, -6)
	shadow.Position         = UDim2.new(0, 0, 0, 6)
	shadow.BackgroundColor3 = isLocked
		and Color3.fromRGB(120, 90, 0) or Color3.fromRGB(10, 10, 12)
	Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, 12)

	local btn = Instance.new("TextButton", container)
	btn.Size             = UDim2.new(1, 0, 1, -6)
	btn.Position         = UDim2.new(0, 0, 0, 0)
	btn.BackgroundColor3 = isLocked
		and Color3.fromRGB(255, 180, 0) or Color3.fromRGB(35, 35, 40)
	btn.Text             = ""
	btn.AutoButtonColor  = false
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)

	local stroke     = Instance.new("UIStroke", btn)
	stroke.Color     = isLocked
		and Color3.fromRGB(255, 230, 100) or Color3.fromRGB(48, 70, 74)
	stroke.Thickness = 1.5

	local icon       = Instance.new("ImageLabel", btn)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position            = UDim2.new(0.5, 0, nameText and 0.38 or 0.5, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType           = Enum.ScaleType.Stretch
	
	AssetService.ApplyIcon(icon, iconId)

	local iconData = AssetService.GetIconData(iconId)
	if iconData then
		icon.Position = UDim2.new(
			0.5, iconData.PixelShift.X,
			nameText and 0.38 or 0.5, iconData.PixelShift.Y
		)
	end

	if nameText then
		local label              = Instance.new("TextLabel", btn)
		label.Size               = UDim2.new(1, 0, 0.3, 0)
		label.Position           = UDim2.new(0, 0, 0.65, 0)
		label.Text               = nameText
		label.TextSize           = 9
		label.TextColor3         = isLocked
			and Color3.fromRGB(100, 70, 0) or Color3.fromRGB(220, 220, 220)
		label.BackgroundTransparency = 1
		label.Font               = Enum.Font.GothamBlack
	end

	if originalName then
		local bContainer            = Instance.new("Frame", btn)
		bContainer.Size             = UDim2.new(0, 16, 0, 16)
		bContainer.Position         = UDim2.new(1, -6, 0, -6)
		bContainer.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
		bContainer.Visible          = false
		Instance.new("UICorner", bContainer).CornerRadius = UDim.new(1, 0)
		Instance.new("UIStroke", bContainer).Color        = Color3.fromRGB(20, 20, 25)

		local bText                  = Instance.new("TextLabel", bContainer)
		bText.Size                   = UDim2.fromScale(1, 1)
		bText.BackgroundTransparency = 1
		bText.Text                   = "1"
		bText.Font                   = Enum.Font.GothamBlack
		bText.TextSize               = 10
		bText.TextColor3             = Color3.new(1, 1, 1)

		BadgeContainers[originalName] = bContainer
	end

	btn.MouseEnter:Connect(function()
		if not isLocked then
			TweenService:Create(btn, TweenInfo.new(0.15),
				{BackgroundColor3 = Color3.fromRGB(45, 45, 52)}):Play()
		end
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.2), {
			Position         = UDim2.new(0, 0, 0, 0),
			BackgroundColor3 = isLocked
				and Color3.fromRGB(255, 180, 0) or Color3.fromRGB(35, 35, 40)
		}):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Position = UDim2.new(0, 0, 0, 4)}):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Position = UDim2.new(0, 0, 0, 0)}):Play()
	end)

	return container, "Created", btn
end

local function CreateToggleArrow(gui: ScreenGui): TextButton
	local btn                  = Instance.new("TextButton", gui)
	btn.Name                   = "SidebarToggleArrow"
	btn.Size                   = UDim2.new(0, 18, 0, 36)
	btn.AnchorPoint            = Vector2.new(0, 0.5)
	btn.BackgroundColor3       = Color3.fromRGB(28, 28, 33)
	btn.BackgroundTransparency = 0.3
	btn.Text                   = "◀"
	btn.Font                   = Enum.Font.GothamBlack
	btn.TextSize               = 12
	btn.TextColor3             = Color3.fromRGB(180, 180, 190)
	btn.AutoButtonColor        = false
	btn.ZIndex                 = 10
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12),
			{BackgroundTransparency = 0.1, TextColor3 = Color3.fromRGB(230, 230, 240)}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15),
			{BackgroundTransparency = 0.3, TextColor3 = Color3.fromRGB(180, 180, 190)}):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.06), {BackgroundTransparency = 0.0}):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundTransparency = 0.3}):Play()
	end)

	return btn
end

function SidebarController.Init(): ()
	local eventsFolder = ReplicatedStorage:FindFirstChild("LocalEvents")
		or Instance.new("Folder")
	eventsFolder.Name   = "LocalEvents"
	eventsFolder.Parent = ReplicatedStorage

	local allMenus = {}
	for _, menu in ipairs(AssetService.SidebarMenus) do
		table.insert(allMenus, menu.Id)
	end
	for _, config in pairs(AssetService.FloatingButtons) do
		local finalId = config.Id == "Premium" and "Bag" or config.Id
		table.insert(allMenus, finalId)
	end

	for _, id in ipairs(allMenus) do
		local evtName = "Toggle" .. id
		if not eventsFolder:FindFirstChild(evtName) then
			Instance.new("BindableEvent", eventsFolder).Name = evtName
		end
	end

	if not eventsFolder:FindFirstChild("ToggleGachaButton") then
		Instance.new("BindableEvent", eventsFolder).Name = "ToggleGachaButton"
	end
	if not eventsFolder:FindFirstChild("NotifyMenuClosed") then
		Instance.new("BindableEvent", eventsFolder).Name = "NotifyMenuClosed"
	end
	if not eventsFolder:FindFirstChild("ToggleStore") then
		Instance.new("BindableEvent", eventsFolder).Name = "ToggleStore"
	end
end

function SidebarController.Start(): ()
	local gui       = LocalPlayer.PlayerGui:FindFirstChild("SidebarGui")
		or Instance.new("ScreenGui", LocalPlayer.PlayerGui)
	gui.Name         = "SidebarGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui:ClearAllChildren()

	local HUD_TOP = 56
	local HUD_BOT = 150

	local container             = Instance.new("Frame", gui)
	container.AnchorPoint       = Vector2.new(0, 0.5)
	container.Size              = UDim2.new(0, AssetRegistry.UI.ButtonSize, 0, 0)
	container.AutomaticSize     = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.Position          = UDim2.new(0, 15, 0.5, 0)
	Instance.new("UIListLayout", container).Padding = UDim.new(0, 4)

	local ARROW_OPEN_X  = 15 + AssetRegistry.UI.ButtonSize + 10
	local ARROW_CLOSE_X = 6

	local arrowBtn = CreateToggleArrow(gui)
	arrowBtn.Position = UDim2.new(0, ARROW_OPEN_X, 0.5, 0)

	local sidebarVisible = true
	local centeredOffsetY = 0

	local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	local POS_OPEN: UDim2
	local POS_CLOSE: UDim2

	local function SetSidebarVisible(open: boolean, instant: boolean?)
		sidebarVisible = open
		arrowBtn.Text  = open and "◀" or "▶"

		local targetContainer = open and POS_OPEN or POS_CLOSE
		local targetArrow     = UDim2.new(0, open and ARROW_OPEN_X or ARROW_CLOSE_X, 0.5, centeredOffsetY)

		if instant then
			container.Position = targetContainer
			arrowBtn.Position  = targetArrow
			return
		end

		TweenService:Create(container, tweenInfo, {Position = targetContainer}):Play()
		TweenService:Create(arrowBtn,  tweenInfo, {Position = targetArrow}):Play()
	end

	arrowBtn.MouseButton1Click:Connect(function()
		SetSidebarVisible(not sidebarVisible)
	end)

	local gachaToggle = GetLocalEvent("ToggleGachaButton")

	local function HandleMenuClick(targetMenuId: string, isLocked: boolean)
		if isProcessing or isLocked then return end
		isProcessing = true

		if BadgeContainers[targetMenuId] then
			BadgeContainers[targetMenuId].Visible = false
		end

		if targetMenuId == "Daily" and dailyNotifDot then
			dailyNotifDot.Visible = false
		end

		if currentOpenMenuId == targetMenuId then
			GetLocalEvent("Toggle" .. targetMenuId):Fire()
			currentOpenMenuId = nil
			gachaToggle:Fire(true)
		else
			if currentOpenMenuId then
				GetLocalEvent("Toggle" .. currentOpenMenuId):Fire()
			end
			currentOpenMenuId = targetMenuId
			GetLocalEvent("Toggle" .. targetMenuId):Fire()
			GetLocalEvent("NotifyMenuOpened"):Fire(targetMenuId)
			gachaToggle:Fire(false)
		end

		task.wait(0.25)
		isProcessing = false
	end

	local activeMenus = {}
	for _, menu in ipairs(AssetService.SidebarMenus) do
		local isEnabled = true
		if menu.Id == "Skills" then
			isEnabled = FeatureResolver.IsCategoryActive("Clicker_Farm") 
				or FeatureResolver.IsCategoryActive("FPS_Shooter") 
				or FeatureResolver.IsCategoryActive("RPG_Adventure") 
				or FeatureResolver.IsCategoryActive("Pet_Simulator")
		elseif menu.Id == "Index" then
			isEnabled = FeatureResolver.IsCategoryActive("Clicker_Farm")
		elseif menu.Id == "Quests" then
			isEnabled = FeatureResolver.IsCategoryActive("RPG_Adventure")
		elseif menu.Id == "Upgrades" then
			isEnabled = FeatureResolver.IsCategoryActive("Upgrades") or FeatureResolver.IsCategoryActive("RPG_Adventure")
		elseif menu.Id == "Inventory" then
			isEnabled = FeatureResolver.IsCategoryActive("RPG_Adventure") or FeatureResolver.IsCategoryActive("Pet_Simulator")
		end
		if isEnabled then
			table.insert(activeMenus, menu)
		end
	end

	local menuBtns = {}
	for _, menu in ipairs(activeMenus) do
		local _, _, btn = SidebarUIFactory.CreateButton(
			container, menu.Name, menu.Id,
			menu.LevelLocked, AssetRegistry.UI.ButtonSize)
		btn.Name = menu.Id
		table.insert(menuBtns, btn)
	end

	local menuHDIcons = {
		Profile = AssetRegistry.UI.ProfileIcon,
		Skills  = AssetRegistry.UI.SkillsIcon,
		Quests  = AssetRegistry.UI.QuestsIcon,
		Daily   = AssetRegistry.UI.DailyIcon
	}

	for _, btn in ipairs(menuBtns) do
		local hdIconId = menuHDIcons[btn.Name]
		if hdIconId then
			local existingIcon = btn:FindFirstChildOfClass("ImageLabel")
			if existingIcon then
				existingIcon.Image = hdIconId
				existingIcon.ImageRectSize = Vector2.new(0, 0)
				existingIcon.ImageRectOffset = Vector2.new(0, 0)
			end
		end
		
		btn.MouseButton1Click:Connect(function()
			HandleMenuClick(btn.Name, false)
		end)
	end

	for _, btn in ipairs(menuBtns) do
		if btn.Name == "Daily" then
			dailyNotifDot = CreateNotifDot(btn)
		elseif btn.Name == "Quests" then
			local questDot = Instance.new("Frame", btn)
			questDot.Name                  = "QuestDot"
			questDot.Size                  = UDim2.new(0, 16, 0, 16)
			questDot.Position              = UDim2.new(1, -4, 0, -4)
			questDot.AnchorPoint           = Vector2.new(1, 0)
			questDot.BackgroundColor3      = Color3.fromRGB(220, 50, 50)
			questDot.BorderSizePixel       = 0
			questDot.Visible               = false
			questDot.ZIndex                = btn.ZIndex + 3
			Instance.new("UICorner", questDot).CornerRadius = UDim.new(1, 0)

			local questDotLabel = Instance.new("TextLabel", questDot)
			questDotLabel.Size                  = UDim2.fromScale(1, 1)
			questDotLabel.BackgroundTransparency = 1
			questDotLabel.Text                  = "!"
			questDotLabel.Font                  = Enum.Font.GothamBlack
			questDotLabel.TextSize              = 10
			questDotLabel.TextColor3            = Color3.new(1, 1, 1)
			questDotLabel.TextXAlignment        = Enum.TextXAlignment.Center
			questDotLabel.TextYAlignment        = Enum.TextYAlignment.Center
			questDotLabel.ZIndex                = questDot.ZIndex + 1

			task.spawn(function()
				while questDot and questDot.Parent do
					if questDot.Visible then
						TweenService:Create(questDot,
							TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
							{ BackgroundTransparency = 0.45 }):Play()
						task.wait(0.55)
						if not (questDot and questDot.Parent) then break end
						TweenService:Create(questDot,
							TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
							{ BackgroundTransparency = 0.0 }):Play()
						task.wait(0.55)
					else
						task.wait(0.5)
					end
				end
			end)
		end
	end

	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
		if not remotes then return end
		local updateDaily = remotes:WaitForChild("UpdateDaily", 10) :: RemoteEvent?
		if updateDaily then
			updateDaily.OnClientEvent:Connect(function(data: any)
				if dailyNotifDot and data then
					local lastClaim = data.LastClaim or 0
					dailyNotifDot.Visible = (lastClaim < GetMidnightUTC())
				end
			end)
		end
	end)

	local floatingHDIcons = {
		Settings = AssetRegistry.UI.SettingsIcon,
		Premium  = AssetRegistry.UI.BagIcon
	}

	local floatingIndex = 0
	local floatingKeys  = {"Settings", "Premium"}

	if FeatureResolver.IsCategoryActive("Monetization") then
		local storeContainer, _, storeBtn = SidebarUIFactory.CreateButton(
			gui, "STORE", "Store", false, AssetRegistry.UI.BottomButtonSize)
		storeContainer.AnchorPoint = Vector2.new(1, 1)
		storeContainer.Position = UDim2.new(1, -20, 1, -30 - (2 * 70))

		storeBtn.MouseButton1Click:Connect(function()
			local storeIsOpen = storeContainer:GetAttribute("IsOpen") == true
			if storeIsOpen then
				GetLocalEvent("ToggleStore"):Fire()
				storeContainer:SetAttribute("IsOpen", false)
			else
				if currentOpenMenuId then
					GetLocalEvent("Toggle" .. currentOpenMenuId):Fire()
					currentOpenMenuId = nil
				end
				GetLocalEvent("ToggleStore"):Fire()
				GetLocalEvent("NotifyMenuOpened"):Fire("Store")
				gachaToggle:Fire(false)
				storeContainer:SetAttribute("IsOpen", true)
			end
		end)
	end

	for _, key in ipairs(floatingKeys) do
		local config = AssetService.FloatingButtons[key]
		if not config then continue end

		local targetId  = config.Id == "Premium" and "Bag" or config.Id
		local nameLabel = config.Id == "Premium" and "BAG"
			or (key == "Settings" and "CONFIG" or key:upper())

		local containerNode, _, btn = SidebarUIFactory.CreateButton(
			gui, nameLabel, config.Id,
			false, AssetRegistry.UI.BottomButtonSize)
		containerNode.AnchorPoint = Vector2.new(1, 1)
		containerNode.Position    = UDim2.new(1, -20, 1, -30 - (floatingIndex * 70))
		btn.MouseButton1Click:Connect(function()
			HandleMenuClick(targetId, false)
		end)

		local hdIconId = floatingHDIcons[key]
		if hdIconId then
			local existingIcon = btn:FindFirstChildOfClass("ImageLabel")
			if existingIcon then
				existingIcon.Image = hdIconId
				existingIcon.ImageRectSize = Vector2.new(0, 0)
				existingIcon.ImageRectOffset = Vector2.new(0, 0)
			end
		end

		floatingIndex += 1
	end

	GetLocalEvent("NotifyMenuClosed").Event:Connect(function(closedMenuId: string)
		if currentOpenMenuId == closedMenuId then
			currentOpenMenuId = nil
			gachaToggle:Fire(true)
		end
	end)

	GetLocalEvent("NotifyMenuOpened").Event:Connect(function(openedMenuId: string)
		if currentOpenMenuId and currentOpenMenuId ~= openedMenuId then
			GetLocalEvent("Toggle" .. currentOpenMenuId):Fire()
			currentOpenMenuId = nil
		end
	end)

	task.defer(function()
		local screenH   = gui.AbsoluteSize.Y
		local freeZoneCenter = HUD_TOP + (screenH - HUD_TOP - HUD_BOT) / 2
		centeredOffsetY = math.floor(freeZoneCenter - screenH * 0.5)

		POS_OPEN  = UDim2.new(0, 15, 0.5, centeredOffsetY)
		POS_CLOSE = UDim2.new(0, -AssetRegistry.UI.ButtonSize - 20, 0.5, centeredOffsetY)

		SetSidebarVisible(true, true)
	end)
end

return SidebarController
