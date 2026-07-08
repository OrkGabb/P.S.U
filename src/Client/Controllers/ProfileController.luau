--!strict
--@author OrkGabb
--@module ProfileController.luau
--@version 1.0
-- src/Client/Controllers/ProfileController.luau
-- Dynamic metadata-driven Profile UI Controller.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: Folder
local AssetRegistry = require(Shared:WaitForChild("Config"):WaitForChild("AssetRegistry")) :: any
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver")) :: any

local LocalPlayer: Player = Players.LocalPlayer
local ProfileController = {}

local MainPanel: Frame
local PanelScale: UIScale
local BgShield: TextButton
local statsContainer: ScrollingFrame
local isOpen: boolean = false
-- Bumped on every open/close transition; stale animation callbacks compare
-- against it and stand down if a newer transition has taken over.
local animGen: number = 0

local currentLevel: number = 1
local currentRebirths: number = 0

local RebirthButton: TextButton
local RebirthBtnText: TextLabel
local StatLabels: {[string]: TextLabel} = {}
local layoutIndexCounter: number = 4

local function FormatComma(n: number): string
	if not n or n ~= n then return "0" end
	n = math.floor(n)
	if n < 1000 then return tostring(n) end
	if n >= 1e21 then
		local exp = math.floor(math.log10(n))
		return string.format("%.1fe%d", n / (10 ^ exp), exp)
	end
	local tiers: { {any} } = {
		{1e18, "Qi"}, {1e15, "Qa"}, {1e12, "T"},
		{1e9,  "B"},  {1e6,  "M"},  {1e3,  "K"},
	}
	for _, tier in ipairs(tiers) do
		local limit: number = tier[1]
		local suffix: string = tier[2]
		if n >= limit then
			local formatted = string.format("%.1f", n / limit):gsub("%.0$", "")
			return formatted .. suffix
		end
	end
	return tostring(n)
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

local function UpdateRebirthUI(): ()
	if not RebirthButton or not RebirthBtnText then return end

	local REBIRTH_LEVEL_REQ: number = 50 + (currentRebirths * 25)

	if currentLevel >= REBIRTH_LEVEL_REQ then
		RebirthButton.BackgroundColor3 = Color3.fromRGB(120, 50, 200) 
		RebirthBtnText.Text = "REBIRTH (LV " .. REBIRTH_LEVEL_REQ .. ")"
		RebirthBtnText.TextColor3 = Color3.new(1, 1, 1)
		
		local stroke = RebirthButton:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = Color3.fromRGB(80, 20, 140) end
	else
		RebirthButton.BackgroundColor3 = Color3.fromRGB(40, 35, 45) 
		RebirthBtnText.Text = "REQUIRES LEVEL " .. tostring(REBIRTH_LEVEL_REQ)
		RebirthBtnText.TextColor3 = Color3.fromRGB(120, 110, 130)
		
		local stroke = RebirthButton:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = Color3.fromRGB(20, 15, 25) end
	end
end

function ProfileController.PlayCinematicEffect(): ()
	local gui: ScreenGui? = LocalPlayer.PlayerGui:FindFirstChild("ProfileGui") :: ScreenGui?
	if not gui then return end

	local flash = Instance.new("Frame", gui)
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	flash.BackgroundTransparency = 0
	flash.ZIndex = 1000
	flash.BorderSizePixel = 0

	local boomSnd = Instance.new("Sound", gui)
	boomSnd.SoundId = "rbxassetid://6895079853"
	boomSnd.PlaybackSpeed = 0.35 
	boomSnd.Volume = 0.8
	boomSnd:Play()
	game:GetService("Debris"):AddItem(boomSnd, 4)

	local popup = Instance.new("TextLabel", flash)
	popup.Size = UDim2.new(1, 0, 0, 100)
	popup.Position = UDim2.new(0, 0, 0.5, -50)
	popup.BackgroundTransparency = 1
	popup.Text = "REBIRTH SUCCESSFUL"
	popup.Font = Enum.Font.GothamBlack
	popup.TextSize = 32
	popup.TextColor3 = Color3.fromRGB(200, 150, 255)
	
	local stroke = Instance.new("UIStroke", popup)
	stroke.Color = Color3.fromRGB(50, 20, 100)
	stroke.Thickness = 3

	local scale = Instance.new("UIScale", popup)
	scale.Scale = 0
	TweenService:Create(scale, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Scale = 1}):Play()

	task.delay(1.5, function(): ()
		local fadeOut = TweenService:Create(flash, TweenInfo.new(1.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {BackgroundTransparency = 1})
		fadeOut:Play()
		fadeOut.Completed:Connect(function(state: Enum.PlaybackState): ()
			flash:Destroy()
		end)
	end)
end

local function CreateStatRow(parent: Instance, label: string, valueColor: Color3, layoutOrder: number): TextLabel
	local row = Instance.new("Frame", parent)
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	row.BackgroundTransparency = 0.94
	row.LayoutOrder = layoutOrder
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
	local rStroke = Instance.new("UIStroke", row)
	rStroke.Color = Color3.fromRGB(255, 255, 255)
	rStroke.Thickness = 1
	rStroke.Transparency = 0.92

	local titleLbl = Instance.new("TextLabel", row)
	titleLbl.Size = UDim2.new(0.5, 0, 1, 0)
	titleLbl.Position = UDim2.new(0, 15, 0, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = label
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextSize = 13
	titleLbl.TextColor3 = Color3.fromRGB(150, 140, 160)
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left

	local valLbl = Instance.new("TextLabel", row)
	valLbl.Size = UDim2.new(0.5, -15, 1, 0)
	valLbl.Position = UDim2.new(0.5, 0, 0, 0)
	valLbl.BackgroundTransparency = 1
	valLbl.Text = "0"
	valLbl.Font = Enum.Font.GothamBlack
	valLbl.TextSize = 15
	valLbl.TextColor3 = valueColor
	valLbl.TextXAlignment = Enum.TextXAlignment.Right

	local constraint = Instance.new("UITextSizeConstraint", valLbl)
	constraint.MaxTextSize = 15
	valLbl.TextScaled = true

	return valLbl
end

local function GetDisplayName(key: string): string
	local keyUpper = key:upper()
	if keyUpper == "PRIMARY" or keyUpper == "COINS" or keyUpper == "GOLD" or keyUpper == "CASH" then
		local primaryName = "Coins"
		local activeCategories = FeatureResolver.GetActiveCategories()
		for _, category in ipairs(activeCategories) do
			if category == "Clicker_Farm" then
				primaryName = "Coins"
				break
			elseif category == "FPS_Shooter" then
				primaryName = "Cash"
				break
			elseif category == "Pet_Simulator" then
				primaryName = "Coins"
				break
			elseif category == "RPG_Adventure" then
				primaryName = "Gold"
				break
			end
		end
		local configPrimary = FeatureResolver.GetConfigField("Currencies", "PrimaryName", nil)
		if configPrimary then
			primaryName = configPrimary
		end
		return primaryName:upper()
	elseif keyUpper == "SECONDARY" or keyUpper == "AURACOINS" or keyUpper == "DIAMONDS" or keyUpper == "GEMS" or keyUpper == "KILLS" then
		local secondaryName = "Secondary"
		local activeCategories = FeatureResolver.GetActiveCategories()
		for _, category in ipairs(activeCategories) do
			if category == "Clicker_Farm" then
				secondaryName = "AuraCoins"
				break
			elseif category == "FPS_Shooter" then
				secondaryName = "Kills"
				break
			elseif category == "Pet_Simulator" then
				secondaryName = "Diamonds"
				break
			elseif category == "RPG_Adventure" then
				secondaryName = "Gems"
				break
			end
		end
		local configSecondary = FeatureResolver.GetConfigField("Currencies", "SecondaryName", nil)
		if configSecondary then
			secondaryName = configSecondary
		end
		return secondaryName:upper()
	elseif keyUpper == "EXPERIENCE" or keyUpper == "EXP" then
		return "EXP"
	end
	return keyUpper
end

local function GetStatColor(key: string): Color3
	local keyUpper = key:upper()
	if keyUpper == "PRIMARY" or keyUpper == "COINS" or keyUpper == "GOLD" or keyUpper == "CASH" or keyUpper == "SECONDARY" or keyUpper == "AURACOINS" or keyUpper == "DIAMONDS" or keyUpper == "GEMS" or keyUpper == "KILLS" or keyUpper == "PREMIUM" then
		return Color3.fromRGB(255, 215, 0)
	elseif keyUpper == "LEVEL" or keyUpper == "EXPERIENCE" or keyUpper == "EXP" or keyUpper == "REBIRTHS" then
		return Color3.fromRGB(130, 80, 255)
	end
	return Color3.fromRGB(220, 220, 220)
end

local function ShowRebirthConfirmation(): ()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then return end
	
	local infoRF = remotes:FindFirstChild("RequestRebirthInfo") :: RemoteFunction?
	if not infoRF then return end

	local info = infoRF:InvokeServer()
	if not info then return end

	local confirmGui = Instance.new("ScreenGui")
	confirmGui.Name = "ConfirmRebirthGui"
	confirmGui.DisplayOrder = 99
	confirmGui.ResetOnSpawn = false
	confirmGui.Parent = LocalPlayer.PlayerGui

	local overlay = Instance.new("TextButton")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.55
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.Parent = confirmGui

	local modal = Instance.new("Frame")
	modal.Size = UDim2.fromOffset(360, 370)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = Color3.fromRGB(14, 10, 26)
	modal.BorderSizePixel = 0
	modal.Parent = overlay
	Instance.new("UICorner", modal).CornerRadius = UDim.new(0, 18)

	local modalGrad = Instance.new("UIGradient", modal)
	modalGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 14, 44)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 8, 20)),
	})
	modalGrad.Rotation = 135

	local stroke = Instance.new("UIStroke", modal)
	stroke.Color = Color3.fromRGB(140, 80, 255)
	stroke.Thickness = 2.5

	local modalScale = Instance.new("UIScale", modal)
	modalScale.Scale = 0

	local accentBar = Instance.new("Frame", modal)
	accentBar.Size = UDim2.new(1, 0, 0, 4)
	accentBar.BackgroundColor3 = Color3.fromRGB(160, 90, 255)
	accentBar.BorderSizePixel = 0
	Instance.new("UICorner", accentBar).CornerRadius = UDim.new(0, 18)

	local title = Instance.new("TextLabel", modal)
	title.Size = UDim2.new(1, -20, 0, 52)
	title.Position = UDim2.new(0, 10, 0, 8)
	title.Text = "REBIRTH"
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 26
	title.TextColor3 = Color3.fromRGB(220, 180, 255)
	title.BackgroundTransparency = 1
	local titleStroke = Instance.new("UIStroke", title)
	titleStroke.Color = Color3.fromRGB(80, 30, 130)
	titleStroke.Thickness = 2

	local reqBadge = Instance.new("Frame", modal)
	reqBadge.Size = UDim2.new(1, -28, 0, 34)
	reqBadge.Position = UDim2.new(0, 14, 0, 58)
	reqBadge.BackgroundColor3 = Color3.fromRGB(36, 26, 10)
	reqBadge.BorderSizePixel = 0
	Instance.new("UICorner", reqBadge).CornerRadius = UDim.new(0, 8)
	local reqStroke = Instance.new("UIStroke", reqBadge)
	reqStroke.Color = Color3.fromRGB(180, 130, 0)
	reqStroke.Thickness = 1.5

	local reqLabel = Instance.new("TextLabel", reqBadge)
	reqLabel.Size = UDim2.new(1, -12, 1, 0)
	reqLabel.Position = UDim2.new(0, 6, 0, 0)
	reqLabel.Text = string.format("⚡  Requires Level %d", info.LevelReq)
	reqLabel.Font = Enum.Font.GothamBold
	reqLabel.TextSize = 13
	reqLabel.TextColor3 = Color3.fromRGB(255, 210, 60)
	reqLabel.TextXAlignment = Enum.TextXAlignment.Left
	reqLabel.BackgroundTransparency = 1

	local gainsHeader = Instance.new("TextLabel", modal)
	gainsHeader.Size = UDim2.new(1, -28, 0, 22)
	gainsHeader.Position = UDim2.new(0, 14, 0, 102)
	gainsHeader.Text = "✦  PERMANENT GAINS"
	gainsHeader.Font = Enum.Font.FredokaOne
	gainsHeader.TextSize = 15
	gainsHeader.TextColor3 = Color3.fromRGB(100, 255, 150)
	gainsHeader.TextXAlignment = Enum.TextXAlignment.Left
	gainsHeader.BackgroundTransparency = 1

	local gainsBox = Instance.new("Frame", modal)
	gainsBox.Size = UDim2.new(1, -28, 0, 72)
	gainsBox.Position = UDim2.new(0, 14, 0, 126)
	gainsBox.BackgroundColor3 = Color3.fromRGB(10, 30, 15)
	gainsBox.BorderSizePixel = 0
	Instance.new("UICorner", gainsBox).CornerRadius = UDim.new(0, 8)
	local gainsStroke = Instance.new("UIStroke", gainsBox)
	gainsStroke.Color = Color3.fromRGB(40, 140, 60)
	gainsStroke.Thickness = 1.5

	local gainsText = Instance.new("TextLabel", gainsBox)
	gainsText.Size = UDim2.new(1, -16, 1, -8)
	gainsText.Position = UDim2.new(0, 8, 0, 4)
	gainsText.Text = info.Gains
	gainsText.Font = Enum.Font.GothamMedium
	gainsText.TextSize = 13
	gainsText.TextColor3 = Color3.fromRGB(130, 255, 160)
	gainsText.TextXAlignment = Enum.TextXAlignment.Left
	gainsText.TextYAlignment = Enum.TextYAlignment.Top
	gainsText.BackgroundTransparency = 1
	gainsText.TextWrapped = true

	local resetsHeader = Instance.new("TextLabel", modal)
	resetsHeader.Size = UDim2.new(1, -28, 0, 22)
	resetsHeader.Position = UDim2.new(0, 14, 0, 208)
	resetsHeader.Text = "✕  WILL BE RESET"
	resetsHeader.Font = Enum.Font.FredokaOne
	resetsHeader.TextSize = 15
	resetsHeader.TextColor3 = Color3.fromRGB(255, 100, 100)
	resetsHeader.TextXAlignment = Enum.TextXAlignment.Left
	resetsHeader.BackgroundTransparency = 1

	local resetsBox = Instance.new("Frame", modal)
	resetsBox.Size = UDim2.new(1, -28, 0, 72)
	resetsBox.Position = UDim2.new(0, 14, 0, 232)
	resetsBox.BackgroundColor3 = Color3.fromRGB(28, 10, 10)
	resetsBox.BorderSizePixel = 0
	Instance.new("UICorner", resetsBox).CornerRadius = UDim.new(0, 8)
	local resetsStroke = Instance.new("UIStroke", resetsBox)
	resetsStroke.Color = Color3.fromRGB(140, 40, 40)
	resetsStroke.Thickness = 1.5

	local resetsText = Instance.new("TextLabel", resetsBox)
	resetsText.Size = UDim2.new(1, -16, 1, -8)
	resetsText.Position = UDim2.new(0, 8, 0, 4)
	resetsText.Text = info.Losses
	resetsText.Font = Enum.Font.GothamMedium
	resetsText.TextSize = 13
	resetsText.TextColor3 = Color3.fromRGB(255, 130, 130)
	resetsText.TextXAlignment = Enum.TextXAlignment.Left
	resetsText.TextYAlignment = Enum.TextYAlignment.Top
	resetsText.BackgroundTransparency = 1
	resetsText.TextWrapped = true

	local cancel = Instance.new("TextButton", modal)
	cancel.Size = UDim2.new(0.42, 0, 0, 38)
	cancel.Position = UDim2.new(0, 14, 1, -52)
	cancel.BackgroundColor3 = Color3.fromRGB(40, 36, 50)
	cancel.Text = "CANCEL"
	cancel.Font = Enum.Font.GothamBold
	cancel.TextSize = 13
	cancel.TextColor3 = Color3.fromRGB(180, 170, 200)
	cancel.AutoButtonColor = false
	cancel.BorderSizePixel = 0
	Instance.new("UICorner", cancel).CornerRadius = UDim.new(0, 9)

	local proceed = Instance.new("TextButton", modal)
	proceed.Size = UDim2.new(0.48, 0, 0, 38)
	proceed.Position = UDim2.new(1, -14, 1, -52)
	proceed.AnchorPoint = Vector2.new(1, 0)
	proceed.BackgroundColor3 = Color3.fromRGB(120, 50, 210)
	proceed.Text = "REBIRTH NOW"
	proceed.Font = Enum.Font.FredokaOne
	proceed.TextSize = 16
	proceed.TextColor3 = Color3.fromRGB(255, 255, 255)
	proceed.AutoButtonColor = false
	proceed.BorderSizePixel = 0
	Instance.new("UICorner", proceed).CornerRadius = UDim.new(0, 9)
	local proceedStroke = Instance.new("UIStroke", proceed)
	proceedStroke.Color = Color3.fromRGB(180, 100, 255)
	proceedStroke.Thickness = 2

	local proceedScale = Instance.new("UIScale", proceed)
	proceed.MouseEnter:Connect(function(): ()
		TweenService:Create(proceedScale, TweenInfo.new(0.1), {Scale = 1.04}):Play()
		TweenService:Create(proceed, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(145, 70, 235)}):Play()
	end)
	proceed.MouseLeave:Connect(function(): ()
		TweenService:Create(proceedScale, TweenInfo.new(0.12), {Scale = 1}):Play()
		TweenService:Create(proceed, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(120, 50, 210)}):Play()
	end)
	proceed.MouseButton1Down:Connect(function(): ()
		TweenService:Create(proceedScale, TweenInfo.new(0.06), {Scale = 0.95}):Play()
	end)

	local isClosing = false
	local function CloseConfirmation(): ()
		if isClosing then return end
		isClosing = true
		TweenService:Create(modalScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0}):Play()
		task.wait(0.2)
		confirmGui:Destroy()
	end

	cancel.MouseButton1Up:Connect(CloseConfirmation)
	overlay.MouseButton1Up:Connect(CloseConfirmation)

	proceed.MouseButton1Up:Connect(function(): ()
		if proceed:GetAttribute("Processing") then return end
		proceed:SetAttribute("Processing", true)
		proceed.Text = "WAITING..."
		
		local requestRebirth = remotes:FindFirstChild("RequestRebirth") :: RemoteEvent?
		if requestRebirth then
			requestRebirth:FireServer()
			
			local errEvt = remotes:WaitForChild("RebirthError", 2) :: RemoteEvent?
			local notifyEvt = remotes:WaitForChild("NotifyRebirth", 2) :: RemoteEvent?
			
			local errConn: RBXScriptConnection? = nil
			local notConn: RBXScriptConnection? = nil
			
			if errEvt then
				errConn = errEvt.OnClientEvent:Connect(function(errMsg): ()
					if errConn then errConn:Disconnect() end
					if notConn then notConn:Disconnect() end
					if proceed and proceed.Parent then
						proceed.Text = errMsg or "FAILED"
						proceed.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
						task.delay(2.5, function(): ()
							if proceed and proceed.Parent then
								proceed.Text = "REBIRTH NOW"
								proceed.BackgroundColor3 = Color3.fromRGB(120, 50, 210)
								proceed:SetAttribute("Processing", nil)
							end
						end)
					end
				end)
			end
			
			if notifyEvt then
				notConn = notifyEvt.OnClientEvent:Connect(function(): ()
					if errConn then errConn:Disconnect() end
					if notConn then notConn:Disconnect() end
					CloseConfirmation()
				end)
			end
			
			task.delay(6, function(): ()
				if errConn then errConn:Disconnect() end
				if notConn then notConn:Disconnect() end
				if proceed and proceed.Parent and proceed:GetAttribute("Processing") then
					proceed.Text = "TIMEOUT"
					proceed.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
					task.delay(2, function(): ()
						if proceed and proceed.Parent then
							proceed.Text = "REBIRTH NOW"
							proceed.BackgroundColor3 = Color3.fromRGB(120, 50, 210)
							proceed:SetAttribute("Processing", nil)
						end
					end)
				end
			end)
		end
	end)

	TweenService:Create(modalScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
end

function ProfileController.Init(): () end

function ProfileController.Start(): ()
	local UIController: any = require(script.Parent:WaitForChild("UIController"))
	UIController.RegisterHUDButton({
		Id = "Profile",
		Name = "PROFILE",
		IconId = "Profile",
		Type = "Sidebar",
		LayoutOrder = 1,
		OnClick = function(): ()
			GetLocalEvent("ToggleProfile"):Fire()
		end
	})

	local gui = Instance.new("ScreenGui", LocalPlayer.PlayerGui)
	gui.Name         = "ProfileGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60 -- panel band: 60 resting/closing, 61 while open

	BgShield = Instance.new("TextButton", gui)
	BgShield.Size                   = UDim2.fromScale(1, 1)
	BgShield.BackgroundTransparency = 0.5
	BgShield.BackgroundColor3       = Color3.new(0, 0, 0)
	BgShield.Text                   = ""
	BgShield.AutoButtonColor        = false
	BgShield.Visible                = false
	BgShield.Active                 = true
	-- (click-to-close is connected below, once closePanel exists — the old
	-- guarded global reference was always nil, so clicking the shield
	-- silently did nothing)

	MainPanel = Instance.new("Frame")
	MainPanel.Visible          = false
	MainPanel.Parent           = gui
	MainPanel.Size             = UDim2.new(0, 360, 0, 520)
	-- Left side, vertically below center (AnchorPoint = (0, 0.5), X = 0 + margin, Y = 0.62)
	MainPanel.AnchorPoint      = Vector2.new(0, 0.5)
	MainPanel.Position         = UDim2.new(0, 12, 0.62, 0)
	MainPanel.BackgroundColor3 = Color3.fromRGB(14, 11, 22)
	MainPanel.Active           = true
	Instance.new("UICorner", MainPanel).CornerRadius = UDim.new(0, 16)

	PanelScale       = Instance.new("UIScale", MainPanel)
	PanelScale.Scale = 0

	local camera: Camera? = workspace.CurrentCamera
	local targetScale: number = 1
	
	local function updateUIScale(): ()
		if not camera then return end
		local size = camera.ViewportSize
		local scaleX = size.X / 380
		local scaleY = size.Y / 540
		targetScale = math.clamp(math.min(scaleX, scaleY, 1), 0.5, 1.2)
		if isOpen then
			-- Retarget with a tween: a direct Scale set while another tween is
			-- animating the property gets overwritten every frame.
			TweenService:Create(PanelScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = targetScale}):Play()
		end
	end
	
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateUIScale)
	end
	updateUIScale()

	local function closePanel(reason: string?): ()
		if not isOpen then return end
		isOpen            = false
		animGen += 1
		local gen = animGen
		gui.DisplayOrder  = 60
		BgShield.Visible  = false
		GetLocalEvent("NotifyMenuClosed"):Fire("Profile")
		-- A switch-triggered close (another panel is taking over) uses a fast
		-- start so the outgoing panel gets out of the way quickly; a manual
		-- close keeps the slower, weightier Back/In easing.
		local closeTween: TweenInfo = if reason == "switch"
			then TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			else TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		local tw = TweenService:Create(PanelScale, closeTween, { Scale = 0 })
		tw:Play()
		tw.Completed:Connect(function(state: Enum.PlaybackState): ()
			-- A reopen cancels this tween (Completed still fires, state=Cancelled)
			-- and bumps the generation; hide only if this close ran to completion
			-- and is still the latest transition.
			if gen ~= animGen then return end
			if state ~= Enum.PlaybackState.Completed then return end
			MainPanel.Visible = false
		end)
	end

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
	
	closeBtn.MouseButton1Up:Connect(function() closePanel() end)
	BgShield.MouseButton1Up:Connect(function() closePanel() end)

	local panelTitle = Instance.new("TextLabel", MainPanel)
	panelTitle.Size                   = UDim2.new(1, 0, 0, 50)
	panelTitle.BackgroundTransparency = 1
	panelTitle.Text                   = "PROFILE"
	panelTitle.Font                   = Enum.Font.GothamBlack
	panelTitle.TextSize               = 22
	panelTitle.TextColor3             = Color3.new(1, 1, 1)
	panelTitle.Parent = MainPanel

	-- Declare isRPGActive before using it in the scrolling frame size
	local isRPGActive: boolean = FeatureResolver.IsCategoryActive("RPG_Adventure")

	statsContainer = Instance.new("ScrollingFrame", MainPanel)
	statsContainer.Size = UDim2.new(1, -40, 1, isRPGActive and -140 or -80)
	statsContainer.Position = UDim2.new(0, 20, 0, 60)
	statsContainer.BackgroundTransparency = 1
	statsContainer.ScrollBarThickness = 0
	statsContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
	statsContainer.CanvasSize = UDim2.new(0, 0, 0, 0)

	local listLayout = Instance.new("UIListLayout", statsContainer)
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder

	-- Instantiate Baseline Profile Rows (Username, UserId, Account Age)
	CreateStatRow(statsContainer, "USERNAME", Color3.fromRGB(220, 220, 220), 1).Text = LocalPlayer.Name
	CreateStatRow(statsContainer, "USER ID", Color3.fromRGB(150, 150, 160), 2).Text = tostring(LocalPlayer.UserId)
	CreateStatRow(statsContainer, "ACCOUNT AGE", Color3.fromRGB(100, 200, 255), 3).Text = tostring(LocalPlayer.AccountAge) .. " days"

	-- Optional Rebirth UI Creation if RPG Adventure is active (isRPGActive declared above)
	if isRPGActive then
		RebirthButton = Instance.new("TextButton", MainPanel)
		RebirthButton.Size             = UDim2.new(1, -40, 0, 50)
		RebirthButton.Position         = UDim2.new(0.5, 0, 1, -15)
		RebirthButton.AnchorPoint      = Vector2.new(0.5, 1)
		RebirthButton.BackgroundColor3 = Color3.fromRGB(40, 35, 45)
		RebirthButton.Text             = ""
		RebirthButton.AutoButtonColor  = false
		Instance.new("UICorner", RebirthButton).CornerRadius = UDim.new(0, 10)
		
		local rbStroke = Instance.new("UIStroke", RebirthButton)
		rbStroke.Color = Color3.fromRGB(20, 15, 25)
		rbStroke.Thickness = 2.5

		local rbIcon = Instance.new("ImageLabel", RebirthButton)
		rbIcon.Size = UDim2.new(0, 30, 0, 30)
		rbIcon.Position = UDim2.new(0, 15, 0.5, -15)
		rbIcon.BackgroundTransparency = 1
		rbIcon.Image = AssetRegistry.UI.RebirthIcon or "rbxassetid://15059633013"
		rbIcon.ScaleType = Enum.ScaleType.Fit

		RebirthBtnText = Instance.new("TextLabel", RebirthButton)
		RebirthBtnText.Size = UDim2.new(1, -60, 1, 0)
		RebirthBtnText.Position = UDim2.new(0, 60, 0, 0)
		RebirthBtnText.BackgroundTransparency = 1
		RebirthBtnText.Text = "LOADING..."
		RebirthBtnText.Font = Enum.Font.GothamBlack
		RebirthBtnText.TextSize = 16
		RebirthBtnText.TextColor3 = Color3.fromRGB(120, 110, 130)
		RebirthBtnText.TextXAlignment = Enum.TextXAlignment.Left

		local btnScale = Instance.new("UIScale", RebirthButton)
		RebirthButton.MouseEnter:Connect(function(): ()
			local REBIRTH_LEVEL_REQ = 50 + (currentRebirths * 25)
			if currentLevel >= REBIRTH_LEVEL_REQ then
				TweenService:Create(btnScale, TweenInfo.new(0.1), {Scale = 1.03}):Play()
				TweenService:Create(RebirthButton, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(140, 70, 220)}):Play()
			end
		end)
		
		RebirthButton.MouseLeave:Connect(function(): ()
			local REBIRTH_LEVEL_REQ = 50 + (currentRebirths * 25)
			if currentLevel >= REBIRTH_LEVEL_REQ then
				TweenService:Create(btnScale, TweenInfo.new(0.15), {Scale = 1}):Play()
				TweenService:Create(RebirthButton, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(120, 50, 200)}):Play()
			end
		end)

		RebirthButton.MouseButton1Down:Connect(function(): ()
			local REBIRTH_LEVEL_REQ = 50 + (currentRebirths * 25)
			if currentLevel >= REBIRTH_LEVEL_REQ then
				TweenService:Create(btnScale, TweenInfo.new(0.05), {Scale = 0.96}):Play()
			end
		end)

		RebirthButton.MouseButton1Up:Connect(function(): ()
			local REBIRTH_LEVEL_REQ = 50 + (currentRebirths * 25)
			if currentLevel >= REBIRTH_LEVEL_REQ then
				TweenService:Create(btnScale, TweenInfo.new(0.1), {Scale = 1.03}):Play()
				ShowRebirthConfirmation()
			end
		end)
	end

	GetLocalEvent("ToggleProfile").Event:Connect(function(reason: string?): ()
		if isOpen then
			closePanel(reason)
		else
			isOpen            = true
			animGen += 1
			gui.DisplayOrder  = 61 -- render above the outgoing panel during a switch
			MainPanel.Visible = true
			BgShield.Visible  = true
			-- Retarget from the current scale (no reset to 0) so reopening during
			-- a close animation continues smoothly instead of snapping shut first.
			-- targetScale is kept fresh by the ViewportSize connection above.
			TweenService:Create(PanelScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = targetScale }):Play()

			GetLocalEvent("NotifyMenuOpened"):Fire("Profile")

			if isRPGActive then UpdateRebirthUI() end
		end
	end)

	-- Cross-menu exclusion is owned centrally by UIController's NotifyMenuOpened
	-- handler, which fires ToggleProfile when another menu opens.

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local updateData: RemoteEvent? = remotes:WaitForChild(RemoteNames.UpdateProfileData, 5) :: any
	
	if updateData then
		updateData.OnClientEvent:Connect(function(data: any): ()
			if not data then return end
			
			-- Cache currentLevel & currentRebirths
			if data.Level then
				currentLevel = data.Level
			elseif data.Progression and data.Progression.Level then
				currentLevel = data.Progression.Level
			end
			
			if data.Rebirths then
				currentRebirths = data.Rebirths
			elseif data.Progression and data.Progression.Rebirths then
				currentRebirths = data.Progression.Rebirths
			end

			-- Dynamic Metadata-Driven row generation for active sub-genres
			local activeCats = FeatureResolver.GetActiveCategories()
			local hasActiveGenre = false
			for _, cat in ipairs(activeCats) do
				if cat ~= "Global" then
					hasActiveGenre = true
					break
				end
			end
			
			local isFPSActive = FeatureResolver.IsCategoryActive("FPS_Shooter")

			if hasActiveGenre then
				-- Process Currencies dictionary
				if data.Currencies and type(data.Currencies) == "table" then
					for key, val in pairs(data.Currencies) do
						if type(val) == "number" or type(val) == "string" then
							local valNum = tonumber(val) or 0
							local displayName = GetDisplayName(key)
							if not isFPSActive and (displayName == "KILLS" or displayName == "LEVEL" or displayName == "EXP") then
								local row = StatLabels[displayName]
								if row then
									local rowParent = row.Parent
									if rowParent then rowParent:Destroy() end
									StatLabels[displayName] = nil
								end
								continue
							end
							if not StatLabels[displayName] then
								local statColor = GetStatColor(key)
								StatLabels[displayName] = CreateStatRow(statsContainer, displayName, statColor, layoutIndexCounter)
								layoutIndexCounter += 1
							end
							StatLabels[displayName].Text = FormatComma(valNum)
						end
					end
				end

				-- Process Progression dictionary
				if data.Progression and type(data.Progression) == "table" then
					for key, val in pairs(data.Progression) do
						if type(val) == "number" or type(val) == "string" then
							local valNum = tonumber(val) or 0
							local displayName = GetDisplayName(key)
							if not isFPSActive and (displayName == "KILLS" or displayName == "LEVEL" or displayName == "EXP") then
								local row = StatLabels[displayName]
								if row then
									local rowParent = row.Parent
									if rowParent then rowParent:Destroy() end
									StatLabels[displayName] = nil
								end
								continue
							end
							if not StatLabels[displayName] then
								local statColor = GetStatColor(key)
								StatLabels[displayName] = CreateStatRow(statsContainer, displayName, statColor, layoutIndexCounter)
								layoutIndexCounter += 1
							end
							StatLabels[displayName].Text = FormatComma(valNum)
						end
					end
				end

				-- Direct mapping of top-level currencies/progression keys if present
				for key, val in pairs(data) do
					if key ~= "Currencies" and key ~= "Progression" and (type(val) == "number" or type(val) == "string") then
						local valNum = tonumber(val) or 0
						local displayName = GetDisplayName(key)
						if not isFPSActive and (displayName == "KILLS" or displayName == "LEVEL" or displayName == "EXP") then
							local row = StatLabels[displayName]
							if row then
								local rowParent = row.Parent
								if rowParent then rowParent:Destroy() end
								StatLabels[displayName] = nil
							end
							continue
						end
						if displayName ~= "USERNAME" and displayName ~= "USER ID" and displayName ~= "ACCOUNT AGE" and displayName ~= "LEVEL" and displayName ~= "REBIRTHS" then
							if not StatLabels[displayName] then
								local statColor = GetStatColor(key)
								StatLabels[displayName] = CreateStatRow(statsContainer, displayName, statColor, layoutIndexCounter)
								layoutIndexCounter += 1
							end
							StatLabels[displayName].Text = FormatComma(valNum)
						end
					end
				end
			end

			if isOpen and isRPGActive then UpdateRebirthUI() end
		end)
	else
		warn("[ProfileController] UpdateProfileData remote not found after 5s timeout.")
	end

	if isRPGActive then
		local notifyRebirth: RemoteEvent? = remotes:WaitForChild("NotifyRebirth", 5) :: any
		if notifyRebirth then
			notifyRebirth.OnClientEvent:Connect(function(): ()
				closePanel()
				ProfileController.PlayCinematicEffect()
			end)
		else
			warn("[ProfileController] NotifyRebirth remote not found after 5s timeout.")
		end
	end
end

return ProfileController
