--!strict
--@author OrkGabb
--@module MainUIController.luau
--@version 1.0
-- src/Client/Controllers/MainUIController.lua
-- Adaptive composition controller that resolves and renders UI based on active features.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local LocalPlayer = Players.LocalPlayer

local LootTableModule = require(ReplicatedStorage.Shared.Modules.LootTable)
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

-- Rarity configuration and feedback settings
local RarityColorMap = {
	COMMON      = Color3.fromRGB(120, 120, 120),
	UNCOMMON    = Color3.fromRGB(80,  200, 120),
	RARE        = Color3.fromRGB(45,  107, 228),
	EPIC        = Color3.fromRGB(180,  50, 255),
	LEGENDARY   = Color3.fromRGB(228, 167,  45),
	MYTHIC      = Color3.fromRGB(228,  45,  45),
	MUTANT      = Color3.fromRGB(255, 100, 220),
	ABYSSAL     = Color3.fromRGB(120,   0, 180),
	COSMIC      = Color3.fromRGB(0,   200, 255),
	SINGULARITY = Color3.fromRGB(255, 255, 255),
	EXOTIC      = Color3.fromRGB(0,   255, 120),
	OMNI        = Color3.fromRGB(255, 255, 255),
}
local FALLBACK_COLOR = Color3.fromRGB(200, 200, 200)

local RarityFeedback = {
	COMMON      = { tier = "none" },
	UNCOMMON    = { tier = "none" },
	RARE        = { tier = "subtle" },
	EPIC        = { tier = "medium" },
	LEGENDARY   = { tier = "impactful" },
	MYTHIC      = { tier = "dramatic" },
	MUTANT      = { tier = "dramatic" },
	ABYSSAL     = { tier = "dramatic" },
	COSMIC      = { tier = "dramatic" },
	SINGULARITY = { tier = "cinematic" },
	EXOTIC      = { tier = "cinematic" },
	OMNI        = { tier = "cinematic" },
}

local SoundTierMap = {
	COMMON      = { tier = "none" },
	UNCOMMON    = { tier = "none" },
	RARE        = { tier = "subtle" },
	EPIC        = { tier = "medium" },
	LEGENDARY   = { tier = "impactful" },
	MYTHIC      = { tier = "dramatic" },
	MUTANT      = { tier = "dramatic" },
	ABYSSAL     = { tier = "dramatic" },
	COSMIC      = { tier = "dramatic" },
	SINGULARITY = { tier = "cinematic" },
	EXOTIC      = { tier = "cinematic" },
	OMNI        = { tier = "cinematic" },
}

local AnticipationDelay = {
	COMMON      = 0,
	UNCOMMON    = 0,
	RARE        = 0,
	EPIC        = 0.1,
	LEGENDARY   = 0.2,
	MYTHIC      = 0.4,
	MUTANT      = 0.4,
	ABYSSAL     = 0.5,
	COSMIC      = 0.5,
	SINGULARITY = 0.8,
	EXOTIC      = 0.8,
	OMNI        = 1.2,
}

local function FormatSuffix(n: number): string
	if not n or n < 1000 then return tostring(math.floor(n or 0)) end
	local suffixes = {"", "K", "M", "B", "T", "Qa"}
	local i = math.floor(math.log10(n) / 3)
	local v = n / (10 ^ (i * 3))
	return string.format("%.1f%s", v, suffixes[i + 1] or "Max")
end

local RollConfig = {
	CurrencyName = "Coins",
	TimeoutDuration = 5.0,
	RevealDuration = 0.25,
	Strings = {
		Idle = "ROLL (%d)",
		Success = " %s ",
		AutoOff = "AUTO: OFF",
		AutoOn = "AUTO: ON"
	},
	Theme = {
		Idle = { Bg = Color3.fromRGB(0, 130, 255), Stroke = Color3.fromRGB(0, 70, 160) },
		Hover = { Bg = Color3.fromRGB(20, 150, 255) },
		Spinning = { Bg = Color3.fromRGB(220, 150, 0), Stroke = Color3.fromRGB(150, 80, 0) },
		Success = { Bg = Color3.fromRGB(0, 180, 50), Stroke = Color3.fromRGB(0, 100, 20) },
		AutoIdle = { Bg = Color3.fromRGB(25, 25, 30), Stroke = Color3.fromRGB(45, 45, 55), Text = Color3.fromRGB(150, 150, 150) },
		AutoActive = { Bg = Color3.fromRGB(90, 20, 200), Stroke = Color3.fromRGB(140, 50, 255), Text = Color3.fromRGB(255, 255, 255) }
	}
}

local MainUIController = {}

local State = {
	IsSpinning = false,
	IsRevealing = false,
	AutoRoll = false,
	CurrentBiome = "Default",
	RollSpeed = 1
}

local _rollBtnTweenToken = 0
local currentSpinId = 0

local function GetLocalEvent(eventName: string): BindableEvent
	local folder = ReplicatedStorage:FindFirstChild("LocalEvents") or Instance.new("Folder", ReplicatedStorage)
	folder.Name = "LocalEvents"
	
	local evt = folder:FindFirstChild(eventName) or Instance.new("BindableEvent", folder)
	evt.Name = eventName
	
	return evt :: BindableEvent
end

local function GetCurrencyValue(): number
	local stats = LocalPlayer:FindFirstChild("leaderstats")
	if not stats then return 0 end
	local currency = stats:FindFirstChild(RollConfig.CurrencyName) :: IntValue | NumberValue
	return currency and currency.Value or 0
end

local function GetCurrentCost(): number
	local biomeDef = LootTableModule.Biomes[State.CurrentBiome]
	return biomeDef and biomeDef.Cost or 250
end

function MainUIController.Init(): () end

function MainUIController.Start(): ()
	local showRoll = FeatureResolver.IsCategoryActive("Clicker_Farm")
	local showAutoRoll = showRoll and FeatureResolver.IsCategoryActive("Monetization")

	for _, child in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
		if child.Name == "GachaInterface" or child.Name == "ScreenshotGui" then 
			child:Destroy() 
		end
	end

	local mainInterface = Instance.new("ScreenGui")
	mainInterface.Name = "GachaInterface"
	mainInterface.ResetOnSpawn = false
	mainInterface.Enabled = true
	mainInterface.DisplayOrder = 10 
	mainInterface.Parent = LocalPlayer.PlayerGui

	-- Screenshot UI Eye button setup
	local screenshotGui = Instance.new("ScreenGui", LocalPlayer.PlayerGui)
	screenshotGui.Name = "ScreenshotGui"
	screenshotGui.ResetOnSpawn = false
	screenshotGui.DisplayOrder = 1000 
	screenshotGui.IgnoreGuiInset = true

	local eyeBtn = Instance.new("ImageButton", screenshotGui)
	eyeBtn.Name = "ToggleHUD"
	eyeBtn.Size = UDim2.new(0, 32, 0, 32)
	eyeBtn.Position = UDim2.new(0, 180, 0, 12)
	eyeBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	eyeBtn.Image = AssetRegistry.UI.HideUI
	eyeBtn.BackgroundTransparency = 0
	eyeBtn.AutoButtonColor = false
	Instance.new("UICorner", eyeBtn).CornerRadius = UDim.new(0, 8)
	
	local eyeStroke = Instance.new("UIStroke", eyeBtn)
	eyeStroke.Color = Color3.fromRGB(60, 60, 75)
	eyeStroke.Thickness = 2

	local isHudHidden = false
	local hiddenGuisCache = {}

	eyeBtn.MouseEnter:Connect(function()
		if not isHudHidden then TweenService:Create(eyeBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(40, 40, 45)}):Play() end
	end)
	eyeBtn.MouseLeave:Connect(function()
		if not isHudHidden then TweenService:Create(eyeBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(25, 25, 30)}):Play() end
	end)
	eyeBtn.MouseButton1Down:Connect(function()
		TweenService:Create(eyeBtn, TweenInfo.new(0.05), {Size = UDim2.new(0, 28, 0, 28), Position = UDim2.new(0, 182, 0, 14)}):Play()
	end)

	eyeBtn.MouseButton1Up:Connect(function()
		TweenService:Create(eyeBtn, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 32, 0, 32), Position = UDim2.new(0, 180, 0, 12)}):Play()
		
		isHudHidden = not isHudHidden
		
		if isHudHidden then
			eyeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
			eyeStroke.Color = Color3.fromRGB(100, 20, 20)
			
			table.clear(hiddenGuisCache)
			for _, child in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
				if child:IsA("ScreenGui") and child ~= screenshotGui then
					hiddenGuisCache[child] = child.Enabled
					child.Enabled = false
				end
			end
			
			pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
		else
			eyeBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
			eyeStroke.Color = Color3.fromRGB(60, 60, 75)
			
			for gui, wasEnabled in pairs(hiddenGuisCache) do
				if gui and gui.Parent then
					gui.Enabled = wasEnabled
				end
			end
			table.clear(hiddenGuisCache)
			
			pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true) end)
		end
	end)

	-- Vignetting for rolls
	local vignetteGui = Instance.new("ScreenGui")
	vignetteGui.Name = "JuiceVignetteGui"
	vignetteGui.ResetOnSpawn = false
	vignetteGui.DisplayOrder = 9
	vignetteGui.IgnoreGuiInset = true
	vignetteGui.Parent = LocalPlayer.PlayerGui

	local vignetteFrame = Instance.new("Frame", vignetteGui)
	vignetteFrame.Name = "RollVignette"
	vignetteFrame.Size = UDim2.fromScale(1, 1)
	vignetteFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	vignetteFrame.BackgroundTransparency = 1.0
	vignetteFrame.ZIndex = 10
	vignetteFrame.Active = false
	vignetteFrame.BorderSizePixel = 0

	-- Juice Sounds Setup
	local stale = SoundService:FindFirstChild("JuiceSounds")
	if stale then stale:Destroy() end
	local stale2 = LocalPlayer.PlayerGui:FindFirstChild("JuiceSounds")
	if stale2 then stale2:Destroy() end
	local juiceSoundsFolder = Instance.new("Folder")
	juiceSoundsFolder.Name = "JuiceSounds"
	juiceSoundsFolder.Parent = LocalPlayer.PlayerGui

	local SoundDefs = {
		subtle      = { Id = "rbxassetid://95154184427705",  Volume = 0.4, Pitch = 1.1  },
		medium      = { Id = "rbxassetid://122136024332497", Volume = 0.6, Pitch = 1.0  },
		impactful   = { Id = "rbxassetid://115447313733239", Volume = 0.8, Pitch = 0.95 },
		dramatic    = { Id = "rbxassetid://79552398776329",  Volume = 0.9, Pitch = 0.85 },
		cinematic   = { Id = "rbxassetid://95851961981936",  Volume = 1.0, Pitch = 0.8  },
		omni_swell  = { Id = "rbxassetid://134160561050962", Volume = 0.8, Pitch = 0.8  },
	}

	local JuiceSounds = {}
	for tierName, def in pairs(SoundDefs) do
		local snd = Instance.new("Sound")
		snd.Name = tierName
		snd.SoundId = def.Id
		snd.Volume = def.Volume
		snd.PlaybackSpeed = def.Pitch
		snd.RollOffMode = Enum.RollOffMode.InverseTapered
		snd.RollOffMinDistance = 0
		snd.RollOffMaxDistance = 10000
		snd.Parent = juiceSoundsFolder
		JuiceSounds[tierName] = snd
	end

	-- Setup conditionally active clicker buttons
	local rollButton: TextButton? = nil
	local autoToggle: TextButton? = nil
	local stroke: UIStroke? = nil
	local scale: UIScale? = nil
	local shadow: Frame? = nil

	if showRoll then
		rollButton = Instance.new("TextButton")
		rollButton.Name = "RollButton"
		rollButton.Text = string.format(RollConfig.Strings.Idle, GetCurrentCost())
		rollButton.Size = UDim2.new(0, 240, 0, 65)
		rollButton.AnchorPoint = Vector2.new(0.5, 1)
		
		if showAutoRoll then
			rollButton.Position = UDim2.new(0.5, 30, 1, -30)
		else
			rollButton.Position = UDim2.new(0.5, 0, 1, -30)
		end
		
		rollButton.BackgroundColor3 = RollConfig.Theme.Idle.Bg
		rollButton.Font = Enum.Font.GothamBlack
		rollButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		rollButton.TextSize = 24
		rollButton.AutoButtonColor = false 
		
		Instance.new("UICorner", rollButton).CornerRadius = UDim.new(0, 12)
		
		stroke = Instance.new("UIStroke", rollButton)
		stroke.Color = RollConfig.Theme.Idle.Stroke
		stroke.Thickness = 4.5
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

		shadow = Instance.new("Frame", rollButton)
		shadow.Size = UDim2.new(1, 0, 0.15, 0)
		shadow.Position = UDim2.new(0, 0, 0.85, 0)
		shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		shadow.BackgroundTransparency = 0.75
		shadow.BorderSizePixel = 0
		Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, 10)

		scale = Instance.new("UIScale", rollButton)
		rollButton.Parent = mainInterface
	end

	local juiceActive = false
	local rollButtonDefaultPos = rollButton and rollButton.Position or UDim2.new(0.5, 0, 1, -30)

	local function TweenButtonColor(color: Color3, duration: number)
		if not rollButton then return end
		rollButton.BackgroundColor3 = color
		local revert = TweenService:Create(rollButton, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = RollConfig.Theme.Success.Bg
		})
		revert:Play()
		revert.Completed:Wait()
	end

	local function TweenVignette(targetAlpha: number, duration: number, hold: number)
		local fadeIn = TweenService:Create(vignetteFrame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = targetAlpha
		})
		fadeIn:Play()
		fadeIn.Completed:Wait()
		if hold > 0 then task.wait(hold) end
		local fadeOut = TweenService:Create(vignetteFrame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1.0
		})
		fadeOut:Play()
		fadeOut.Completed:Wait()
	end

	local function TweenButtonBounce(duration: number)
		if not scale then return end
		task.wait(0.1)
		local half = duration / 2
		local up = TweenService:Create(scale, TweenInfo.new(half, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.23 })
		up:Play()
		up.Completed:Wait()
		local down = TweenService:Create(scale, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.15 })
		down:Play()
		down.Completed:Wait()
	end

	local function ShakeRollButton(offset: number, duration: number)
		if not rollButton then return end
		local origPos = rollButtonDefaultPos
		local shakeCount = 6
		local interval = duration / shakeCount
		for i = 1, shakeCount do
			local dx = (i % 2 == 0) and offset or -offset
			local dy = (i % 3 == 0) and offset or -offset
			local t = TweenService:Create(rollButton, TweenInfo.new(interval, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(origPos.X.Scale, origPos.X.Offset + dx, origPos.Y.Scale, origPos.Y.Offset + dy)
			})
			t:Play()
			t.Completed:Wait()
		end
		rollButton.Position = origPos
	end

	local function PlayJuice(rarityTag: string)
		local reduceEffects = LocalPlayer:GetAttribute("ReduceEffects") == true
		local entry = RarityFeedback[rarityTag]
		local tier = entry and entry.tier or "none"
		local color = RarityColorMap[rarityTag] or FALLBACK_COLOR

		if reduceEffects then
			if tier ~= "none" and rollButton then
				TweenService:Create(rollButton, TweenInfo.new(0.15), { BackgroundColor3 = color }):Play()
			end
			return
		end

		if tier == "none" then return end
		if juiceActive then return end
		juiceActive = true

		task.spawn(function()
			local ok, err = pcall(function()
				TweenButtonColor(color, 0.1)

				if tier == "subtle" then return end

				task.spawn(function() TweenVignette(0.7, 0.2, 0) end)

				if tier == "medium" then return end

				task.spawn(function() TweenButtonBounce(0.3) end)

				if tier == "impactful" then return end

				task.spawn(function() ShakeRollButton(3, 0.2) end)

				if rarityTag == "ABYSSAL" or rarityTag == "COSMIC" then
					task.spawn(function() TweenVignette(0.7, 0.2, 0.3) end)
				end

				if tier == "dramatic" then return end

				task.spawn(function() TweenVignette(0.6, 0.3, 0.5) end)

				if rarityTag == "OMNI" and rollButton then
					rollButton.Active = false
					rollButton.AutoButtonColor = false
					task.wait(1.0)
					rollButton.Active = true
				end
			end)

			if not ok then warn("[JuiceSystem] Error:", err) end
			task.wait(0.1)
			juiceActive = false
		end)
	end

	local function PlayJuiceSound(rarityTag: string)
		if LocalPlayer:GetAttribute("ReduceEffects") == true then return end
		local entry = SoundTierMap[rarityTag]
		local tier = entry and entry.tier or "none"
		if tier == "none" then return end

		task.spawn(function()
			local snd = JuiceSounds[tier]
			if snd then snd:Play() end
		end)

		if rarityTag == "OMNI" then
			task.delay(0.6, function()
				local swell = JuiceSounds["omni_swell"]
				if swell then swell:Play() end
			end)
		end
	end

	local function PlayRollingAnimation(duration: number)
		if not rollButton or duration <= 0 then
			return function() end
		end
		local running = true
		task.spawn(function()
			local dots = { "ROLLING.", "ROLLING..", "ROLLING..." }
			local idx = 1
			while running and rollButton do
				rollButton.Text = dots[idx]
				idx = (idx % #dots) + 1
				task.wait(0.1)
			end
		end)
		return function()
			running = false
		end
	end

	local function SetAutoRoll(isActive: boolean)
		if not rollButton or not stroke then return end
		State.AutoRoll = isActive
		_rollBtnTweenToken += 1
		local token = _rollBtnTweenToken
		if isActive then
			rollButton.Text             = "AUTO-ROLLING..."
			rollButton.TextColor3       = Color3.fromRGB(150, 150, 160)
			rollButton.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
			stroke.Color                = Color3.fromRGB(20, 20, 25)
			rollButton:SetAttribute("IsLocked", true)
		else
			rollButton:SetAttribute("IsLocked", false)

			if not State.IsSpinning and not State.IsRevealing then
				task.delay(0, function()
					if _rollBtnTweenToken ~= token or not rollButton or not stroke then return end
					rollButton.Text             = string.format(RollConfig.Strings.Idle, GetCurrentCost())
					rollButton.TextColor3       = Color3.new(1, 1, 1)
					rollButton.BackgroundColor3 = RollConfig.Theme.Idle.Bg
					stroke.Color               = RollConfig.Theme.Idle.Stroke
				end)
			end
		end
	end

	if showRoll and showAutoRoll then
		autoToggle = Instance.new("TextButton")
		autoToggle.Name = "AutoRollToggle"
		autoToggle.Size = UDim2.new(0, 50, 0, 50)
		autoToggle.Position = UDim2.new(0.5, -100, 1, -30) 
		autoToggle.AnchorPoint = Vector2.new(1, 0.5)
		autoToggle.BackgroundTransparency = 1
		autoToggle.Text = ""
		autoToggle.AutoButtonColor = false
		autoToggle.Parent = mainInterface

		autoToggle:GetPropertyChangedSignal("Text"):Connect(function()
			if autoToggle.Text ~= "" then autoToggle.Text = "" end
		end)

		local aIcon = Instance.new("ImageLabel", autoToggle)
		aIcon.Name = "AutoIcon"
		aIcon.Size = UDim2.fromScale(1, 1)
		aIcon.Position = UDim2.fromScale(0, 0)
		aIcon.BackgroundTransparency = 1
		aIcon.Image = AssetRegistry.UI.AutoRollOffIcon
		aIcon.ScaleType = Enum.ScaleType.Fit

		autoToggle.MouseButton1Click:Connect(function()
			local now = os.clock()
			if now - (autoToggle:GetAttribute("LastClick") or 0) < 1.0 then return end
			autoToggle:SetAttribute("LastClick", now)

			local isAuto = (autoToggle:GetAttribute("IsAuto") == true)
			isAuto = not isAuto
			autoToggle:SetAttribute("IsAuto", isAuto)
			
			aIcon.Image = isAuto and AssetRegistry.UI.AutoRollOnIcon or AssetRegistry.UI.AutoRollOffIcon
			
			SetAutoRoll(isAuto)
			
			TweenService:Create(autoToggle, TweenInfo.new(0.1, Enum.EasingStyle.Bounce), {Size = UDim2.new(0, 55, 0, 55)}):Play()
			task.delay(0.1, function()
				if autoToggle then
					TweenService:Create(autoToggle, TweenInfo.new(0.1), {Size = UDim2.new(0, 50, 0, 50)}):Play()
				end
			end)
			
			local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
			if remotes and remotes:FindFirstChild("ToggleAutoRoll") then
				remotes.ToggleAutoRoll:FireServer(isAuto)
			end
		end)
	end

	GetLocalEvent("ToggleGachaButton").Event:Connect(function(isVisible: boolean)
		if isHudHidden then
			hiddenGuisCache[mainInterface] = isVisible
			return
		end
		mainInterface.Enabled = isVisible
	end)

	if rollButton and scale and stroke then
		rollButton.MouseEnter:Connect(function()
			if not State.IsSpinning and not State.IsRevealing and not State.AutoRoll and rollButton and scale then
				TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 1.05}):Play()
				TweenService:Create(rollButton, TweenInfo.new(0.1), {BackgroundColor3 = RollConfig.Theme.Hover.Bg}):Play()
			end
		end)
		
		rollButton.MouseLeave:Connect(function()
			if not State.IsRevealing and not State.AutoRoll and scale and rollButton then
				TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play()
				if not State.IsSpinning then
					TweenService:Create(rollButton, TweenInfo.new(0.15), {BackgroundColor3 = RollConfig.Theme.Idle.Bg}):Play()
				end
			end
		end)
		
		rollButton.MouseButton1Down:Connect(function() 
			if not State.IsRevealing and not State.AutoRoll and scale then TweenService:Create(scale, TweenInfo.new(0.05), {Scale = 0.92}):Play() end
		end)
		
		rollButton.MouseButton1Up:Connect(function() 
			if not State.IsRevealing and not State.AutoRoll and scale then TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 1.05}):Play() end
		end)
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local rollReq = remotes:WaitForChild("RollRequest") :: RemoteEvent
	local toggleAutoReq = remotes:WaitForChild("ToggleAutoRoll") :: RemoteEvent
	local updateClient = remotes:WaitForChild("UpdateClient") :: RemoteEvent
	
	local maxedRecycleReq = remotes:WaitForChild("MaxedRecycle") :: RemoteEvent
	maxedRecycleReq.OnClientEvent:Connect(function(rolledName: string, expValue: number, coinValue: number, essenceName: string)
		if State.AutoRoll then return end

		local popup = Instance.new("TextLabel")
		popup.Size = UDim2.new(0, 400, 0, 30)
		popup.AnchorPoint = Vector2.new(0.5, 0.5)
		popup.Position = UDim2.new(0.5, 0, 0.85, 0)
		popup.BackgroundTransparency = 1
		popup.Font = Enum.Font.GothamBlack

		local essStr = essenceName and string.upper(essenceName) or "ESSENCE"
		popup.Text = string.format(" TRANSMUTED! +1 %s", essStr)
		popup.TextColor3 = Color3.fromRGB(200, 150, 255)
		popup.TextSize = 14

		local popStroke = Instance.new("UIStroke", popup)
		popStroke.Color = Color3.fromRGB(30, 10, 40)
		popStroke.Thickness = 2.5

		popup.Parent = mainInterface

		TweenService:Create(popup, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0.8, 0),
			TextSize = 16
		}):Play()

		task.delay(1.0, function()
			local fade = TweenService:Create(popup, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
				Position = UDim2.new(0.5, 0, 0.82, 0)
			})
			TweenService:Create(popStroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
			fade:Play()
			fade.Completed:Connect(function() popup:Destroy() end)
		end)
	end)

	local forceDisableRemote = remotes:WaitForChild("ForceDisableAutoRoll", 5) :: RemoteEvent?
	if forceDisableRemote and showAutoRoll and autoToggle then
		forceDisableRemote.OnClientEvent:Connect(function()
			local aIcon = autoToggle and autoToggle:FindFirstChild("AutoIcon") :: ImageLabel?
			if autoToggle then autoToggle:SetAttribute("IsAuto", false) end
			if aIcon then aIcon.Image = AssetRegistry.UI.AutoRollOffIcon end
			SetAutoRoll(false)
			toggleAutoReq:FireServer(false)
			
			local popup = Instance.new("TextLabel")
			popup.Size = UDim2.new(0, 350, 0, 40)
			popup.AnchorPoint = Vector2.new(0.5, 0)
			popup.Position = UDim2.new(0.5, 0, 0, 0)
			popup.BackgroundTransparency = 1
			popup.Font = Enum.Font.GothamBlack
			popup.Text = "️ AUTO-ROLL REQUIRES PREMIUM"
			popup.TextColor3 = Color3.fromRGB(255, 100, 100)
			popup.TextSize = 14
			
			local popStroke = Instance.new("UIStroke", popup)
			popStroke.Color = Color3.fromRGB(80, 20, 20)
			popStroke.Thickness = 2
			
			local alertGui = Instance.new("ScreenGui", LocalPlayer.PlayerGui)
			alertGui.Name = "AlertGui"
			alertGui.DisplayOrder = 1000
			popup.Parent = alertGui

			TweenService:Create(popup, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, 0, 0, 120)}):Play()

			task.delay(3.5, function()
				local fade = TweenService:Create(popup, TweenInfo.new(0.4), {TextTransparency = 1, Position = UDim2.new(0.5, 0, 0, 80)})
				TweenService:Create(popStroke, TweenInfo.new(0.4), {Transparency = 1}):Play()
				fade:Play()
				fade.Completed:Connect(function() 
					popup:Destroy() 
					alertGui:Destroy()
				end)
			end)
		end)
	end

	toggleAutoReq.OnClientEvent:Connect(function(serverState: boolean)
		SetAutoRoll(serverState)
	end)

	if rollButton then
		rollButton.MouseButton1Click:Connect(function()
			if not rollButton then return end
			if rollButton:GetAttribute("IsLocked") == true then return end
			if State.AutoRoll then return end 
			if State.IsSpinning or State.IsRevealing then return end
			if GetCurrencyValue() < GetCurrentCost() then return end

			local speedMult = math.max(State.RollSpeed or 1, 0.1)
			local currentCooldown = math.max(3.5 / speedMult, 1.75)
			local now = os.clock()
			
			if now - (rollButton:GetAttribute("LastRollReq") or 0) < currentCooldown then return end
			rollButton:SetAttribute("LastRollReq", now)

			currentSpinId += 1
			local mySpinId = currentSpinId

			State.IsSpinning = true
			rollReq:FireServer(State.CurrentBiome, mySpinId)
			
			if rollButton and stroke then
				rollButton.BackgroundColor3 = RollConfig.Theme.Spinning.Bg
				stroke.Color = RollConfig.Theme.Spinning.Stroke
				rollButton.AutoButtonColor = false
				rollButton.TextTransparency = 0.5
			end

			task.delay(RollConfig.TimeoutDuration, function()
				if State.IsSpinning and currentSpinId == mySpinId and rollButton and stroke then
					State.IsSpinning = false
					rollButton.BackgroundColor3 = RollConfig.Theme.Idle.Bg
					stroke.Color = RollConfig.Theme.Idle.Stroke
					rollButton.Text = string.format(RollConfig.Strings.Idle, GetCurrentCost())
				end
			end)

			task.spawn(function()
				local biomeDef = LootTableModule.Biomes[State.CurrentBiome]
				local biomeAuras = biomeDef and biomeDef.Items or {}
				while State.IsSpinning and #biomeAuras > 0 and rollButton do
					rollButton.Text = biomeAuras[math.random(1, #biomeAuras)].name
					task.wait(0.1)
				end
			end)
		end)
	end

	local STOP_TIERS = {
		["RAREST"]  = { MUTANT=true, SINGULARITY=true, EXOTIC=true, OMNI=true },
		["MYTHIC+"] = { MYTHIC=true, MUTANT=true, ABYSSAL=true, COSMIC=true, SINGULARITY=true, EXOTIC=true, OMNI=true },
		["NEVER"]   = {},
	}
	local function GetBreakTiers(): {[string]: boolean}
		local key = LocalPlayer:GetAttribute("AutoRollStopTier") or "MYTHIC+"
		return STOP_TIERS[key] or STOP_TIERS["MYTHIC+"]
	end

	updateClient.OnClientEvent:Connect(function(rolledName: string, equippedName: string, rolledBiomeId: string, spinId: number?)
		if rolledBiomeId ~= State.CurrentBiome then return end
		if not rollButton or not stroke or not scale then return end
		
		if not State.AutoRoll and spinId ~= nil and spinId ~= currentSpinId then return end
		
		local timeSinceClick = 0
		if not State.AutoRoll then
			timeSinceClick = os.clock() - (rollButton:GetAttribute("LastRollReq") or 0)
			
			local speedMult = math.max(State.RollSpeed or 1, 0.1)
			local currentCooldown = math.max(3.5 / speedMult, 1.75)
			
			local minSpin = math.min(1.8, math.max(0.8, currentCooldown - 0.7))
			
			if timeSinceClick < minSpin then
				task.wait(minSpin - timeSinceClick)
				timeSinceClick = os.clock() - (rollButton:GetAttribute("LastRollReq") or 0)
			end
		end
		
		State.IsSpinning = false
		State.IsRevealing = true

		if rollButton then
			rollButton.AutoButtonColor = true
			rollButton.TextTransparency = 0
		end

		GetLocalEvent("EffectRolled"):Fire(rolledName)

		local itemData = LootTableModule.GetItemData(rolledName)

		local anticipationDelay = AnticipationDelay[itemData.rarityTag] or 0
		if not (LocalPlayer:GetAttribute("ReduceEffects") == true) and anticipationDelay > 0 and rollButton then
			local stopRolling = PlayRollingAnimation(anticipationDelay)
			task.wait(anticipationDelay)
			stopRolling()
		end

		if rollButton and stroke and scale then
			rollButton.BackgroundColor3 = RollConfig.Theme.Success.Bg
			stroke.Color = RollConfig.Theme.Success.Stroke
			local rarityLabel = itemData.rarityTag and ("[" .. itemData.rarityTag:upper() .. "]") or ""
			rollButton.Text = string.format(RollConfig.Strings.Success, rolledName:upper())
				.. "\n" .. rarityLabel
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.15}):Play()
		end

		PlayJuice(itemData.rarityTag)

		task.spawn(function()
			local ok, err = pcall(PlayJuiceSound, itemData.rarityTag)
			if not ok then warn("[SoundSystem] Error:", err) end
		end)
		
		local speedMult = math.max(State.RollSpeed or 1, 0.1)
		local currentCooldown = math.max(3.5 / speedMult, 1.75)
		
		local dynamicRevealDuration = RollConfig.RevealDuration
		if not State.AutoRoll then
			dynamicRevealDuration = math.max(0.5, currentCooldown - timeSinceClick)
		end
		
		local mySpinId = spinId or currentSpinId
		if rollButton then
			rollButton:SetAttribute("CurrentRevealId", mySpinId)
		end
		
		if State.AutoRoll and GetBreakTiers()[itemData.rarityTag] then
			SetAutoRoll(false)
			toggleAutoReq:FireServer(false)
			if showAutoRoll and autoToggle then
				local aIcon = autoToggle:FindFirstChild("AutoIcon") :: ImageLabel?
				autoToggle:SetAttribute("IsAuto", false)
				if aIcon then aIcon.Image = AssetRegistry.UI.AutoRollOffIcon end
			end

			local frozenText  = rollButton and rollButton.Text or ""

			task.delay(dynamicRevealDuration, function()
				if not rollButton or not scale then return end
				if rollButton:GetAttribute("CurrentRevealId") ~= mySpinId then return end
				TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
				rollButton.Text = frozenText .. "\n⚠ AUTO-ROLL PAUSED"
				State.IsRevealing = false
			end)

			task.delay(dynamicRevealDuration + 3.0, function()
				if not rollButton or not stroke then return end
				if rollButton:GetAttribute("CurrentRevealId") ~= mySpinId then return end
				if not State.AutoRoll and not State.IsSpinning then
					TweenService:Create(rollButton, TweenInfo.new(0.4), {BackgroundColor3 = RollConfig.Theme.Idle.Bg}):Play()
					stroke.Color = RollConfig.Theme.Idle.Stroke
					rollButton.Text = string.format(RollConfig.Strings.Idle, GetCurrentCost())
				end
			end)

			return
		end

		task.delay(dynamicRevealDuration, function()
			if not rollButton or not scale or not stroke then return end
			if rollButton:GetAttribute("CurrentRevealId") ~= mySpinId then return end
			TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
			if not State.AutoRoll then
				TweenService:Create(rollButton, TweenInfo.new(0.3), {BackgroundColor3 = RollConfig.Theme.Idle.Bg}):Play()
				stroke.Color = RollConfig.Theme.Idle.Stroke
				rollButton.Text = string.format(RollConfig.Strings.Idle, GetCurrentCost())
			else
				SetAutoRoll(true)
			end
			State.IsRevealing = false
		end)
	end)

	local updateProfileRemote = remotes:FindFirstChild("UpdateProfileData") or remotes:WaitForChild("UpdateProfileData", 5)
	if updateProfileRemote then
		(updateProfileRemote :: RemoteEvent).OnClientEvent:Connect(function(data)
			if data.RollSpeed then State.RollSpeed = data.RollSpeed end
			if data.EXP and data.TotalEXP then
				local expLabel = mainInterface:FindFirstChild("ExpTextLabel") :: TextLabel?
				if expLabel then
					expLabel.Text = FormatSuffix(data.EXP) .. " / " .. FormatSuffix(data.TotalEXP)
				end
			end
		end)
	end
end

return MainUIController
