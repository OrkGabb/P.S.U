--!strict
--@author OrkGabb
--@module StoreController.luau
--@version 1.0
-- src/Client/Controllers/StoreController.lua
-- Dynamic, category-aware Premium Store Controller.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local TweenService: TweenService = game:GetService("TweenService")
local Players: Players = game:GetService("Players")
local MarketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local LocalPlayer: Player = Players.LocalPlayer

local FeatureResolver: any = require(ReplicatedStorage.Shared.Modules.FeatureResolver)
local StoreRegistry: any = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("StoreRegistry"))

local StoreController = {}

local MainPanel: Frame
local GridContainer: ScrollingFrame
local PanelScale: UIScale
local BgShield: TextButton
local isOpen: boolean = false
-- Bumped on every open/close transition; stale animation callbacks compare
-- against it and stand down if a newer transition has taken over.
local animGen: number = 0

local FALLBACK_ICON: string = "rbxassetid://15059633013"

type StoreItem = {
	Id: number,
	Type: "Gamepass" | "Product" | "VirtualCurrency",
	Name: string,
	Description: string,
	Price: number,
	Color: Color3,
	Icon: string
}

local StoreCatalog: { [string]: {StoreItem} } = {
	["PASSES"] = {},
	["BOOSTS"] = {}
}

local function InitializeCatalog(): ()
	table.clear(StoreCatalog["PASSES"])
	table.clear(StoreCatalog["BOOSTS"])

	if not FeatureResolver.IsCategoryActive("Monetization") then
		return
	end

	local catalog = StoreRegistry.Catalog
	if not catalog or type(catalog) ~= "table" then
		return
	end

	local activeCats: {string} = FeatureResolver.GetActiveCategories()

	for _, item: any in ipairs(catalog) do
		if not item.Id or not item.Type or not item.Name or not item.Category then
			continue
		end

		local canShow: boolean = true
		if item.Genre then
			canShow = false
			for _, activeCat: string in ipairs(activeCats) do
				if activeCat == item.Genre then
					canShow = true
					break
				end
			end
		end

		if canShow then
			local categoryList: {StoreItem}? = StoreCatalog[item.Category]
			if categoryList then
				table.insert(categoryList, {
					Id = item.Id,
					Type = item.Type,
					Name = item.Name,
					Description = item.Description or "",
					Price = item.Price or 0,
					Color = item.Color or Color3.fromRGB(255, 255, 255),
					Icon = item.Icon or FALLBACK_ICON
				})
			end
		end
	end
end

local function GetLocalEvent(eventName: string): BindableEvent
	local folder: Instance? = ReplicatedStorage:FindFirstChild("LocalEvents")
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "LocalEvents"
		newFolder.Parent = ReplicatedStorage
		folder = newFolder
	end
	local existing = (folder :: Instance):FindFirstChild(eventName)
	if existing and existing:IsA("BindableEvent") then
		return existing
	end
	local evt = Instance.new("BindableEvent")
	evt.Name = eventName
	evt.Parent = folder
	return evt
end

local function PromptPurchase(item: StoreItem)
	if item.Type == "Gamepass" then
		MarketplaceService:PromptGamePassPurchase(LocalPlayer, item.Id)
	elseif item.Type == "Product" then
		MarketplaceService:PromptProductPurchase(LocalPlayer, item.Id)
	elseif item.Type == "VirtualCurrency" then
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local buyRf = remotes and remotes:FindFirstChild(RemoteNames.BuyInGameItem) :: RemoteFunction?
		if buyRf then
			task.spawn(function()
				pcall(function() return buyRf:InvokeServer(item.Id) end)
			end)
		end
	end
end

local function FormatComma(amount: number): string
	local formatted = tostring(math.floor(amount))
	local k
	repeat
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return formatted
end

function StoreController.PlayPurchaseEffect(rewardType: string, amount: number, displayName: string?, extraData: any?)
	local gui = LocalPlayer.PlayerGui:FindFirstChild("StoreGui")
	if not gui then return end

	local existing = gui:FindFirstChild("PurchasePopup")
	if existing then existing:Destroy() end

	local accentColor: Color3
	local rewardText: string
	local lowerType = string.lower(rewardType)

	if lowerType == "currency" then
		accentColor = Color3.fromRGB(255, 220, 80)
		rewardText  = "+ " .. FormatComma(amount) .. " " .. (displayName or "CURRENCY")
	elseif lowerType == "vip" then
		accentColor = Color3.fromRGB(255, 80, 80)
		rewardText  = displayName or "VIP PASS ACTIVATED"
	elseif lowerType == "gamepass" then
		accentColor = Color3.fromRGB(255, 215, 0)
		rewardText  = displayName or "GAMEPASS UNLOCKED"
	else
		accentColor = Color3.fromRGB(255, 160, 50)
		rewardText  = "+ " .. FormatComma(amount) .. " " .. (displayName or "ITEM")
	end

	local purchaseSound = Instance.new("Sound")
	purchaseSound.SoundId       = "rbxassetid://6895079853"
	purchaseSound.PlaybackSpeed = 0.65
	purchaseSound.Volume        = 0.8
	purchaseSound.Parent        = gui
	purchaseSound:Play()
	game:GetService("Debris"):AddItem(purchaseSound, 3)

	local popup = Instance.new("Frame")
	popup.Name             = "PurchasePopup"
	popup.Size             = UDim2.new(0, 360, 0, 130)
	popup.Position         = UDim2.new(0.5, 0, 0.38, 0)
	popup.AnchorPoint      = Vector2.new(0.5, 0.5)
	popup.BackgroundColor3 = Color3.fromRGB(15, 12, 20)
	popup.ZIndex           = 100
	popup.Parent           = gui
	Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 16)

	local popStroke       = Instance.new("UIStroke", popup)
	popStroke.Color       = accentColor
	popStroke.Thickness   = 2.5

	local popGrad = Instance.new("UIGradient", popup)
	popGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 28, 45)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 10, 18)),
	})
	popGrad.Rotation = 90

	local titleLbl                    = Instance.new("TextLabel", popup)
	titleLbl.Size                     = UDim2.new(1, 0, 0, 30)
	titleLbl.Position                 = UDim2.new(0, 0, 0, 16)
	titleLbl.BackgroundTransparency   = 1
	titleLbl.Text                     = "PURCHASE SUCCESSFUL!"
	titleLbl.Font                     = Enum.Font.GothamBlack
	titleLbl.TextSize                 = 18
	titleLbl.TextColor3               = accentColor
	titleLbl.ZIndex                   = 101

	local rewardLbl                   = Instance.new("TextLabel", popup)
	rewardLbl.Size                    = UDim2.new(1, -20, 0, 36)
	rewardLbl.Position                = UDim2.new(0.5, 0, 0, 50)
	rewardLbl.AnchorPoint             = Vector2.new(0.5, 0)
	rewardLbl.BackgroundTransparency  = 1
	rewardLbl.Font                    = Enum.Font.GothamBlack
	rewardLbl.TextSize                = 22
	rewardLbl.TextColor3              = Color3.fromRGB(255, 255, 255)
	rewardLbl.TextWrapped             = true
	rewardLbl.ZIndex                  = 101
	rewardLbl.Text                    = rewardText

	local subtitleLbl                   = Instance.new("TextLabel", popup)
	subtitleLbl.Size                    = UDim2.new(1, -20, 0, 40)
	subtitleLbl.Position                = UDim2.new(0.5, 0, 0, 85)
	subtitleLbl.AnchorPoint             = Vector2.new(0.5, 0)
	subtitleLbl.BackgroundTransparency  = 1
	subtitleLbl.Font                    = Enum.Font.GothamMedium
	subtitleLbl.TextSize                = 11
	subtitleLbl.TextColor3              = Color3.fromRGB(180, 180, 200)
	subtitleLbl.TextWrapped             = true
	subtitleLbl.TextYAlignment          = Enum.TextYAlignment.Top
	subtitleLbl.ZIndex                  = 101

	if lowerType == "gamepass" then
		subtitleLbl.Text = "Permanently unlocked. Enjoy!"
	elseif lowerType == "vip" then
		if extraData and extraData.benefits and extraData.daysRemaining then
			local benefitsStr = type(extraData.benefits) == "table" and table.concat(extraData.benefits, ", ") or tostring(extraData.benefits)
			popup.Size = UDim2.new(0, 360, 0, 140)
			subtitleLbl.Size = UDim2.new(1, -20, 0, 50)
			subtitleLbl.Text = "Benefits: " .. benefitsStr .. "\nTotal VIP Days Remaining: " .. tostring(extraData.daysRemaining)
		else
			subtitleLbl.Text = "Your VIP status is now active."
		end
	elseif lowerType == "item" then
		subtitleLbl.Text = "Added to your inventory."
	else
		subtitleLbl.Text = "Your balance has been updated."
	end

	local popScale    = Instance.new("UIScale", popup)
	popScale.Scale    = 0
	TweenService:Create(popScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	task.delay(0.3, function()
		if not popup.Parent then return end
		TweenService:Create(popStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Thickness = 5 }):Play()
		task.delay(0.6, function()
			if not popup.Parent then return end
			TweenService:Create(popStroke, TweenInfo.new(0.4), { Thickness = 2.5 }):Play()
		end)
	end)

	task.delay(3.5, function()
		if not popup.Parent then return end
		local fadeOut = TweenService:Create(popScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			if popup.Parent then popup:Destroy() end
		end)
	end)
end

function StoreController.RenderCategory(categoryName: string)
	if not GridContainer then return end

	for _, child in ipairs(GridContainer:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	local items = StoreCatalog[categoryName] or {}

	for _, item in ipairs(items) do
		local card = Instance.new("Frame", GridContainer)
		card.Size = UDim2.new(0, 180, 0, 240)
		card.BackgroundColor3 = Color3.fromRGB(20, 16, 30)
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

		local stroke = Instance.new("UIStroke", card)
		stroke.Color = item.Color
		stroke.Thickness = 2
		stroke.Transparency = 0.3

		local grad = Instance.new("UIGradient", card)
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 24, 45)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 12, 22)),
		})
		grad.Rotation = 90

		local icon = Instance.new("ImageLabel", card)
		icon.Size = UDim2.new(0, 80, 0, 80)
		icon.Position = UDim2.new(0.5, 0, 0, 20)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.BackgroundTransparency = 1
		icon.Image = item.Icon
		icon.ScaleType = Enum.ScaleType.Fit

		local title = Instance.new("TextLabel", card)
		title.Size = UDim2.new(1, 0, 0, 25)
		title.Position = UDim2.new(0, 0, 0, 110)
		title.BackgroundTransparency = 1
		title.Text = item.Name
		title.Font = Enum.Font.GothamBlack
		title.TextSize = 16
		title.TextColor3 = item.Color

		local desc = Instance.new("TextLabel", card)
		desc.Size = UDim2.new(1, -20, 0, 40)
		desc.Position = UDim2.new(0.5, 0, 0, 135)
		desc.AnchorPoint = Vector2.new(0.5, 0)
		desc.BackgroundTransparency = 1
		desc.Text = item.Description
		desc.Font = Enum.Font.GothamBold
		desc.TextSize = 11
		desc.TextColor3 = Color3.fromRGB(180, 180, 190)
		desc.TextWrapped = true

		local buyBtn = Instance.new("TextButton", card)
		buyBtn.Size = UDim2.new(1, -20, 0, 40)
		buyBtn.Position = UDim2.new(0.5, 0, 1, -10)
		buyBtn.AnchorPoint = Vector2.new(0.5, 1)
		buyBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 60)
		buyBtn.Text = ""
		buyBtn.AutoButtonColor = false
		Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 8)

		local btnStroke = Instance.new("UIStroke", buyBtn)
		btnStroke.Color = Color3.fromRGB(0, 80, 30)
		btnStroke.Thickness = 2

		local priceTxt = Instance.new("TextLabel", buyBtn)
		priceTxt.Size = UDim2.new(1, -10, 1, -10)
		priceTxt.Position = UDim2.fromScale(0.5, 0.5)
		priceTxt.AnchorPoint = Vector2.new(0.5, 0.5)
		priceTxt.BackgroundTransparency = 1
		priceTxt.Text = "R$ " .. tostring(item.Price)
		priceTxt.Font = Enum.Font.GothamBlack
		priceTxt.TextScaled = true
		priceTxt.TextColor3 = Color3.new(1, 1, 1)

		local textConstraint = Instance.new("UITextSizeConstraint", priceTxt)
		textConstraint.MaxTextSize = 16

		task.spawn(function()
			if item.Type == "Gamepass" or item.Type == "Product" then
				local success, productInfo = pcall(function()
					local infoType = (item.Type == "Gamepass") and Enum.InfoType.GamePass or Enum.InfoType.Product
					return MarketplaceService:GetProductInfo(item.Id, infoType)
				end)

				if success and productInfo and productInfo.PriceInRobux then
					priceTxt.Text = "R$ " .. tostring(productInfo.PriceInRobux)
				end
			else
				-- Internal virtual currency price
				priceTxt.Text = tostring(item.Price)
			end
			
			if item.Type == "Gamepass" then
				local _ownsSuccess, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, item.Id)
				end)
				
				if not owns then
					local remotes = ReplicatedStorage:FindFirstChild("Remotes")
					local checkRf = remotes and remotes:FindFirstChild(RemoteNames.CheckGamepassOwnership) :: RemoteFunction?
					if checkRf then
						local s, res = pcall(function() return checkRf:InvokeServer(item.Id) end)
						if s and res then owns = true end
					end
				end
				
				if owns then
					priceTxt.Text = "OWNED"
					buyBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
					buyBtn:SetAttribute("Processing", true)
				end
			end
		end)

		local btnScale = Instance.new("UIScale", buyBtn)
		
		buyBtn.MouseEnter:Connect(function()
			TweenService:Create(btnScale, TweenInfo.new(0.1), {Scale = 1.05}):Play()
			TweenService:Create(buyBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(0, 190, 70)}):Play()
		end)
		
		buyBtn.MouseLeave:Connect(function()
			TweenService:Create(btnScale, TweenInfo.new(0.15), {Scale = 1}):Play()
			TweenService:Create(buyBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(0, 160, 60)}):Play()
		end)

		buyBtn.MouseButton1Down:Connect(function()
			TweenService:Create(btnScale, TweenInfo.new(0.05), {Scale = 0.95}):Play()
		end)

		buyBtn.MouseButton1Up:Connect(function()
			TweenService:Create(btnScale, TweenInfo.new(0.1), {Scale = 1.05}):Play()
			
			if buyBtn:GetAttribute("Processing") then return end
			buyBtn:SetAttribute("Processing", true)
			local originalText = priceTxt.Text
			
			task.spawn(function()
				if item.Type == "Gamepass" then
					priceTxt.Text = "..."
					local _success, owns = pcall(function()
						return MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, item.Id)
					end)
					
					if not owns then
						local remotes = ReplicatedStorage:FindFirstChild("Remotes")
						local checkRf = remotes and remotes:FindFirstChild(RemoteNames.CheckGamepassOwnership) :: RemoteFunction?
						if checkRf then
							local s, res = pcall(function() return checkRf:InvokeServer(item.Id) end)
							if s and res then owns = true end
						end
					end
					
					if owns then
						priceTxt.Text = "OWNED"
						TweenService:Create(buyBtn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(80, 80, 90)}):Play()
						return
					end
				end
				
				priceTxt.Text = originalText
				PromptPurchase(item)
				buyBtn:SetAttribute("Processing", nil)
			end)
		end)
	end
end

function StoreController.Init(): () end

function StoreController.Start(): ()
	local UIController: any = require(script.Parent:WaitForChild("UIController"))
	UIController.RegisterHUDButton({
		Id = "Store",
		Name = "STORE",
		IconId = "Store",
		Type = "Floating",
		LayoutOrder = 3,
		OnClick = function(): ()
			GetLocalEvent("ToggleStore"):Fire()
		end
	})

	InitializeCatalog()

	local gui = Instance.new("ScreenGui", LocalPlayer.PlayerGui)
	gui.Name         = "StoreGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60 -- panel band: 60 resting/closing, 61 while open

	BgShield = Instance.new("TextButton", gui) :: any
	BgShield.Name                   = "InputSink"
	BgShield.Size                   = UDim2.fromScale(1, 1)
	BgShield.BackgroundTransparency = 0.5
	BgShield.BackgroundColor3       = Color3.new(0, 0, 0)
	BgShield.Text                   = ""
	BgShield.AutoButtonColor        = false
	BgShield.Visible                = false
	BgShield.Active                 = true
	-- (click-to-close is connected below, once closePanel exists)

	MainPanel = Instance.new("Frame", gui)
	MainPanel.Size             = UDim2.new(0, 620, 0, 420)
	MainPanel.Position         = UDim2.new(0.5, -310, 0.5, -210)
	MainPanel.BackgroundColor3 = Color3.fromRGB(14, 11, 22)
	MainPanel.Active           = true
	MainPanel.Visible          = false
	Instance.new("UICorner", MainPanel).CornerRadius = UDim.new(0, 16)

	local clickAbsorber              = Instance.new("TextButton", MainPanel)
	clickAbsorber.Size               = UDim2.fromScale(1, 1)
	clickAbsorber.BackgroundTransparency = 1
	clickAbsorber.Text               = ""
	clickAbsorber.AutoButtonColor    = false
	clickAbsorber.ZIndex             = 1
	clickAbsorber.Active             = true

	local mpGrad = Instance.new("UIGradient", MainPanel)
	mpGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 15, 35)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10,  8, 18)),
	})
	mpGrad.Rotation = 135
	
	local mpStroke = Instance.new("UIStroke", MainPanel)
	mpStroke.Color = Color3.fromRGB(90, 60, 150)
	mpStroke.Thickness = 2.5

	PanelScale       = Instance.new("UIScale", MainPanel)
	PanelScale.Scale = 0

	local function closePanel()
		if not isOpen then return end
		isOpen            = false
		animGen += 1
		local gen = animGen
		gui.DisplayOrder  = 60
		BgShield.Visible  = false
		GetLocalEvent("NotifyMenuClosed"):Fire("Store")
		local tw = TweenService:Create(PanelScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
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
	BgShield.MouseButton1Up:Connect(closePanel)

	local closeBtn = Instance.new("TextButton", MainPanel)
	closeBtn.Size             = UDim2.new(0, 30, 0, 30)
	closeBtn.Position         = UDim2.new(1, -15, 0, 15)
	closeBtn.AnchorPoint      = Vector2.new(1, 0)
	closeBtn.AutoButtonColor  = false
	closeBtn.Text = "X" 
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	closeBtn.BackgroundTransparency = 0 
	closeBtn.ZIndex = 2
	
	local corner = Instance.new("UICorner", closeBtn)
	corner.CornerRadius = UDim.new(0, 8)
	
	local stroke = Instance.new("UIStroke", closeBtn)
	stroke.Color = Color3.fromRGB(120, 20, 20)
	stroke.Thickness = 2
	
	local cIcon = closeBtn:FindFirstChild("HD_Icon")
	if cIcon then cIcon:Destroy() end
	
	local TweenService = game:GetService("TweenService")
	local clickTw = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	closeBtn.MouseEnter:Connect(function() TweenService:Create(closeBtn, clickTw, {Size = UDim2.new(0, 32, 0, 32), BackgroundColor3 = Color3.fromRGB(255, 70, 70)}):Play() end)
	closeBtn.MouseLeave:Connect(function() TweenService:Create(closeBtn, clickTw, {Size = UDim2.new(0, 30, 0, 30), BackgroundColor3 = Color3.fromRGB(220, 50, 50)}):Play() end)
	closeBtn.MouseButton1Down:Connect(function() TweenService:Create(closeBtn, clickTw, {Size = UDim2.new(0, 26, 0, 26)}):Play() end)
	closeBtn.MouseButton1Up:Connect(function() TweenService:Create(closeBtn, clickTw, {Size = UDim2.new(0, 32, 0, 32)}):Play() end)
	
	closeBtn.MouseButton1Up:Connect(closePanel)

	local panelTitle = Instance.new("TextLabel", MainPanel)
	panelTitle.Size                   = UDim2.new(1, 0, 0, 50)
	panelTitle.BackgroundTransparency = 1
	panelTitle.Text                   = "PREMIUM STORE"
	panelTitle.Font                   = Enum.Font.GothamBlack
	panelTitle.TextSize               = 22
	panelTitle.TextColor3             = Color3.fromRGB(255, 215, 0)
	panelTitle.ZIndex                 = 2

	local tabBar = Instance.new("Frame", MainPanel)
	tabBar.Size = UDim2.new(1, -30, 0, 36)
	tabBar.Position = UDim2.new(0, 15, 0, 50)
	tabBar.BackgroundTransparency = 1
	tabBar.ZIndex = 2

	local tabLayout = Instance.new("UIListLayout", tabBar)
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local function MakeTab(label: string, categoryId: string)
		local btn = Instance.new("TextButton", tabBar)
		btn.Size = UDim2.new(0, 150, 1, 0)
		btn.BackgroundColor3 = Color3.fromRGB(25, 20, 35)
		btn.TextColor3 = Color3.fromRGB(200, 200, 210)
		btn.Text = label
		btn.Font = Enum.Font.GothamBlack
		btn.TextSize = 14
		btn.AutoButtonColor = false
		btn.ZIndex = 2
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

		local underline = Instance.new("Frame", btn)
		underline.Size = UDim2.new(1, 0, 0, 3)
		underline.Position = UDim2.new(0, 0, 1, -3)
		underline.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
		underline.BackgroundTransparency = 1
		underline.BorderSizePixel = 0

		btn.MouseButton1Click:Connect(function()
			for _, t in ipairs(tabBar:GetChildren()) do
				if t:IsA("TextButton") then
					t.BackgroundColor3 = Color3.fromRGB(25, 20, 35)
					t.TextColor3 = Color3.fromRGB(150, 150, 160)
					local ul = t:FindFirstChildOfClass("Frame")
					if ul then ul.BackgroundTransparency = 1 end
				end
			end
			
			btn.BackgroundColor3 = Color3.fromRGB(35, 28, 50)
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			underline.BackgroundTransparency = 0
			
			StoreController.RenderCategory(categoryId)
		end)
		
		return btn, underline
	end

	local passBtn, passUl = MakeTab("GAMEPASSES", "PASSES")
	local boostBtn, boostUl = MakeTab("BOOSTS & COINS", "BOOSTS")

	GridContainer = Instance.new("ScrollingFrame", MainPanel)
	GridContainer.Size                = UDim2.new(1, -30, 1, -110)
	GridContainer.Position            = UDim2.new(0, 15, 0, 95)
	GridContainer.BackgroundTransparency = 1
	GridContainer.ScrollBarThickness  = 4
	GridContainer.CanvasSize          = UDim2.new(0, 0, 0, 0)
	GridContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
	GridContainer.ZIndex              = 2

	local grid = Instance.new("UIGridLayout", GridContainer)
	grid.CellSize    = UDim2.new(0, 180, 0, 220)
	grid.CellPadding = UDim2.new(0, 15, 0, 15)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local gridPad = Instance.new("UIPadding", GridContainer)
	gridPad.PaddingTop    = UDim.new(0, 5)
	gridPad.PaddingBottom = UDim.new(0, 15)

	task.spawn(function()
		local remotes       = ReplicatedStorage:WaitForChild("Remotes", 10)
		if not remotes then return end
		local notifyEvt     = remotes:WaitForChild(RemoteNames.NotifyPurchase, 10) :: RemoteEvent?
		if not notifyEvt then return end
		notifyEvt.OnClientEvent:Connect(function(rewardType: string, amount: number, displayName: string?, extraData: any?)
			StoreController.PlayPurchaseEffect(rewardType, amount, displayName, extraData)
		end)
	end)

	GetLocalEvent("ToggleStore").Event:Connect(function()
		if isOpen then
			closePanel()
		else
			InitializeCatalog()
			isOpen            = true
			animGen += 1
			gui.DisplayOrder  = 61 -- render above the outgoing panel during a switch
			MainPanel.Visible = true
			BgShield.Visible  = true
			-- Retarget from the current scale (no reset to 0) so reopening during
			-- a close animation continues smoothly instead of snapping shut first.
			TweenService:Create(PanelScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

			GetLocalEvent("NotifyMenuOpened"):Fire("Store")

			passBtn.BackgroundColor3        = Color3.fromRGB(35, 28, 50)
			passBtn.TextColor3              = Color3.fromRGB(255, 255, 255)
			passUl.BackgroundTransparency   = 0
			boostBtn.BackgroundColor3       = Color3.fromRGB(25, 20, 35)
			boostBtn.TextColor3             = Color3.fromRGB(150, 150, 160)
			boostUl.BackgroundTransparency  = 1

			StoreController.RenderCategory("PASSES")
		end
	end)

	-- Cross-menu exclusion is owned centrally by UIController's NotifyMenuOpened
	-- handler, which fires ToggleStore when another menu opens.
end

return StoreController
