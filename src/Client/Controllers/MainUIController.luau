--!strict
-- @Author @OrkGabb
-- src/Client/Controllers/MainUIController.luau
-- Aura_Collector roll UI: roll button with escalating rarity feedback
-- ("juice"), always-available odds panel, biome selector and the optional
-- auto-roll toggle (Monetization-gated).
--
-- Everything data-driven from the shared registries:
--   • AuraRegistry — biome pools, roll costs, rarity colors/feedback tiers,
--     and the SAME roll engine the server uses (odds shown here can never
--     disagree with server rolls)
--   • AudioRegistry — roll-reveal stingers per feedback tier
--   • FeatureToggles (via FeatureResolver) — roll pacing, currency names
-- Cooldown mirroring: AuraService publishes the effective roll speed as the
-- "RollSpeedMult" player attribute; this controller derives its local input
-- gate from it instead of re-implementing mastery/gamepass math.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local AuraRegistry = require(ReplicatedStorage.Shared.Modules.AuraRegistry)
local AudioRegistry = require(ReplicatedStorage.Shared.Config.AudioRegistry)
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local GENRE_KEY = "Aura_Collector"

-- FeedbackTier → named AudioRegistry stinger
local TIER_SOUNDS: {[string]: string} = {
	subtle    = "RollSubtle",
	medium    = "RollMedium",
	impactful = "RollImpactful",
	dramatic  = "RollDramatic",
	cinematic = "RollCinematic",
}

local RollConfig = {
	TimeoutDuration = 5.0,
	RevealDuration = 0.25,
	Theme = {
		Idle     = { Bg = Color3.fromRGB(0, 130, 255),  Stroke = Color3.fromRGB(0, 70, 160) },
		Hover    = { Bg = Color3.fromRGB(20, 150, 255) },
		Spinning = { Bg = Color3.fromRGB(220, 150, 0),  Stroke = Color3.fromRGB(150, 80, 0) },
		Success  = { Bg = Color3.fromRGB(0, 180, 50),   Stroke = Color3.fromRGB(0, 100, 20) },
	},
}

local MainUIController = {}

local State = {
	IsSpinning = false,
	IsRevealing = false,
	AutoRoll = false,
	CurrentBiome = "Default",
	UnlockedBiomes = { Default = true } :: {[string]: boolean},
	Level = 1,
}

local _rollBtnTweenToken = 0
local currentSpinId = 0

-- ─── Small helpers ────────────────────────────────────────────────────────────

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

local function FormatSuffix(n: number): string
	if not n or n ~= n then return "0" end
	if n < 1000 then
		if n < 10 and n % 1 ~= 0 then
			return string.format("%.1f", n)
		end
		return tostring(math.floor(n))
	end
	local suffixes = {"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp"}
	local i = math.floor(math.log10(n) / 3)
	local v = n / (10 ^ (i * 3))
	local suffix = suffixes[i + 1]
	if not suffix then
		return string.format("%.0e", n)
	end
	return (string.format("%.1f%s", v, suffix):gsub("%.0(%a)", "%1"))
end

local function cfgNum(field: string, default: number): number
	local value = FeatureResolver.GetConfigField(GENRE_KEY, field, default)
	return if type(value) == "number" then value else default
end

local function GetCurrencyValue(): number
	local names = FeatureResolver.GetCurrencyNames()
	local stats = LocalPlayer:FindFirstChild("leaderstats")
	if not stats then return 0 end
	local currency = stats:FindFirstChild(names.Primary)
	if currency and (currency:IsA("IntValue") or currency:IsA("NumberValue")) then
		return (currency :: any).Value
	end
	return 0
end

local function GetCurrentBiome(): AuraRegistry.BiomeDef?
	return AuraRegistry.GetBiome(State.CurrentBiome)
end

local function GetCurrentCost(): number
	local biome = GetCurrentBiome()
	return if biome then biome.RollCost else 0
end

-- Effective roll cooldown, mirrored from the server via RollSpeedMult
local function GetCurrentCooldown(): number
	local base = cfgNum("BaseRollCooldown", 3.5)
	local speed = LocalPlayer:GetAttribute("RollSpeedMult")
	local speedMult = if type(speed) == "number" then math.max(speed, 0.1) else 1
	return base / speedMult
end

local function RollButtonIdleText(): string
	return string.format("ROLL (%s)", FormatSuffix(GetCurrentCost()))
end

-- ─── Controller ───────────────────────────────────────────────────────────────

function MainUIController.Init(): () end

function MainUIController.Start(): ()
	if not FeatureResolver.IsCategoryActive(GENRE_KEY) then
		return
	end
	local showAutoRoll = FeatureResolver.IsCategoryActive("Monetization")

	for _, child in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
		if child.Name == "GachaInterface" or child.Name == "ScreenshotGui" then
			child:Destroy()
		end
	end

	local mainInterface = Instance.new("ScreenGui")
	mainInterface.Name = "GachaInterface"
	mainInterface.ResetOnSpawn = false
	mainInterface.DisplayOrder = 10
	mainInterface.Parent = LocalPlayer.PlayerGui

	-- ── HUD-hide (screenshot) toggle ──────────────────────────────────────────
	local screenshotGui = Instance.new("ScreenGui")
	screenshotGui.Name = "ScreenshotGui"
	screenshotGui.ResetOnSpawn = false
	screenshotGui.DisplayOrder = 1000
	screenshotGui.IgnoreGuiInset = true
	screenshotGui.Parent = LocalPlayer.PlayerGui

	local eyeBtn = Instance.new("ImageButton")
	eyeBtn.Name = "ToggleHUD"
	eyeBtn.Size = UDim2.new(0, 32, 0, 32)
	eyeBtn.Position = UDim2.new(0, 180, 0, 12)
	eyeBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	eyeBtn.Image = AssetRegistry.UI.HideUI
	eyeBtn.AutoButtonColor = false
	eyeBtn.Parent = screenshotGui
	Instance.new("UICorner", eyeBtn).CornerRadius = UDim.new(0, 8)

	local eyeStroke = Instance.new("UIStroke", eyeBtn)
	eyeStroke.Color = Color3.fromRGB(60, 60, 75)
	eyeStroke.Thickness = 2

	local isHudHidden = false
	local hiddenGuisCache: {[ScreenGui]: boolean} = {}

	eyeBtn.MouseEnter:Connect(function()
		if not isHudHidden then TweenService:Create(eyeBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(40, 40, 45)}):Play() end
	end)
	eyeBtn.MouseLeave:Connect(function()
		if not isHudHidden then TweenService:Create(eyeBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(25, 25, 30)}):Play() end
	end)
	eyeBtn.MouseButton1Click:Connect(function()
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

	-- ── Roll vignette ─────────────────────────────────────────────────────────
	local vignetteGui = Instance.new("ScreenGui")
	vignetteGui.Name = "JuiceVignetteGui"
	vignetteGui.ResetOnSpawn = false
	vignetteGui.DisplayOrder = 9
	vignetteGui.IgnoreGuiInset = true
	vignetteGui.Parent = LocalPlayer.PlayerGui

	local vignetteFrame = Instance.new("Frame")
	vignetteFrame.Name = "RollVignette"
	vignetteFrame.Size = UDim2.fromScale(1, 1)
	vignetteFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	vignetteFrame.BackgroundTransparency = 1.0
	vignetteFrame.ZIndex = 10
	vignetteFrame.Active = false
	vignetteFrame.BorderSizePixel = 0
	vignetteFrame.Parent = vignetteGui

	-- ── Roll-reveal stingers (AudioRegistry-driven) ───────────────────────────
	local stale = SoundService:FindFirstChild("JuiceSounds")
	if stale then stale:Destroy() end
	local juiceSoundsFolder = Instance.new("Folder")
	juiceSoundsFolder.Name = "JuiceSounds"
	juiceSoundsFolder.Parent = SoundService

	local JuiceSounds: {[string]: Sound} = {}
	local function buildSound(name: string): ()
		local def = AudioRegistry.GetSFX(name)
		if not def then return end
		local snd = Instance.new("Sound")
		snd.Name = name
		snd.SoundId = def.SoundId
		snd.Volume = def.Volume or 0.5
		snd.PlaybackSpeed = def.PlaybackSpeed or 1
		snd.Parent = juiceSoundsFolder
		JuiceSounds[name] = snd
	end
	for _, sfxName in pairs(TIER_SOUNDS) do
		buildSound(sfxName)
	end
	buildSound("RollOmniSwell")

	-- ── Roll button ───────────────────────────────────────────────────────────
	local rollButton = Instance.new("TextButton")
	rollButton.Name = "RollButton"
	rollButton.Text = RollButtonIdleText()
	rollButton.Size = UDim2.new(0, 240, 0, 65)
	rollButton.AnchorPoint = Vector2.new(0.5, 1)
	rollButton.Position = if showAutoRoll then UDim2.new(0.5, 30, 1, -30) else UDim2.new(0.5, 0, 1, -30)
	rollButton.BackgroundColor3 = RollConfig.Theme.Idle.Bg
	rollButton.Font = Enum.Font.GothamBlack
	rollButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	rollButton.TextSize = 24
	rollButton.AutoButtonColor = false
	rollButton.Parent = mainInterface
	Instance.new("UICorner", rollButton).CornerRadius = UDim.new(0, 12)

	local stroke = Instance.new("UIStroke", rollButton)
	stroke.Color = RollConfig.Theme.Idle.Stroke
	stroke.Thickness = 4.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local shadow = Instance.new("Frame", rollButton)
	shadow.Size = UDim2.new(1, 0, 0.15, 0)
	shadow.Position = UDim2.new(0, 0, 0.85, 0)
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.75
	shadow.BorderSizePixel = 0
	Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, 10)

	local scale = Instance.new("UIScale", rollButton)
	local rollButtonDefaultPos = rollButton.Position

	-- ── Odds panel (visible odds — same engine the server rolls with) ────────
	local oddsToggle = Instance.new("TextButton")
	oddsToggle.Name = "OddsToggle"
	oddsToggle.Size = UDim2.new(0, 70, 0, 30)
	oddsToggle.AnchorPoint = Vector2.new(0.5, 1)
	oddsToggle.Position = UDim2.new(0.5, 190, 1, -47)
	oddsToggle.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	oddsToggle.Font = Enum.Font.GothamBlack
	oddsToggle.TextSize = 13
	oddsToggle.TextColor3 = Color3.fromRGB(255, 215, 0)
	oddsToggle.Text = "ODDS"
	oddsToggle.AutoButtonColor = false
	oddsToggle.Parent = mainInterface
	Instance.new("UICorner", oddsToggle).CornerRadius = UDim.new(0, 8)
	Instance.new("UIStroke", oddsToggle).Color = Color3.fromRGB(80, 70, 30)

	local oddsPanel = Instance.new("Frame")
	oddsPanel.Name = "OddsPanel"
	oddsPanel.Size = UDim2.new(0, 250, 0, 320)
	oddsPanel.AnchorPoint = Vector2.new(0.5, 1)
	oddsPanel.Position = UDim2.new(0.5, 190, 1, -85)
	oddsPanel.BackgroundColor3 = Color3.fromRGB(14, 11, 22)
	oddsPanel.Visible = false
	oddsPanel.Parent = mainInterface
	Instance.new("UICorner", oddsPanel).CornerRadius = UDim.new(0, 12)
	Instance.new("UIStroke", oddsPanel).Color = Color3.fromRGB(90, 60, 150)

	local oddsTitle = Instance.new("TextLabel", oddsPanel)
	oddsTitle.Size = UDim2.new(1, 0, 0, 30)
	oddsTitle.BackgroundTransparency = 1
	oddsTitle.Font = Enum.Font.GothamBlack
	oddsTitle.TextSize = 14
	oddsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	oddsTitle.Text = "DROP ODDS"

	local oddsList = Instance.new("ScrollingFrame", oddsPanel)
	oddsList.Size = UDim2.new(1, -16, 1, -38)
	oddsList.Position = UDim2.new(0, 8, 0, 32)
	oddsList.BackgroundTransparency = 1
	oddsList.ScrollBarThickness = 4
	oddsList.CanvasSize = UDim2.new(0, 0, 0, 0)
	oddsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	oddsList.BorderSizePixel = 0

	local oddsLayout = Instance.new("UIListLayout", oddsList)
	oddsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	oddsLayout.Padding = UDim.new(0, 2)

	local function RefreshOddsPanel(): ()
		for _, child in ipairs(oddsList:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end
		local biome = GetCurrentBiome()
		local engine = AuraRegistry.GetEngine(State.CurrentBiome)
		if not biome or not engine then return end

		oddsTitle.Text = string.upper(biome.DisplayName) .. " — ODDS"

		-- GetProbabilities is rarest-first; show commons on top
		local probabilities = engine:GetProbabilities()
		local order = 1
		for i = #probabilities, 1, -1 do
			local entry = probabilities[i]
			local rarity = AuraRegistry.GetRarity(entry.Def.RarityTag)

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 22)
			row.BackgroundTransparency = 1
			row.LayoutOrder = order
			order += 1

			local nameLabel = Instance.new("TextLabel", row)
			nameLabel.Size = UDim2.new(0.55, 0, 1, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextSize = 12
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextColor3 = rarity.Color
			nameLabel.Text = entry.Def.DisplayName

			local chanceLabel = Instance.new("TextLabel", row)
			chanceLabel.Size = UDim2.new(0.45, 0, 1, 0)
			chanceLabel.Position = UDim2.new(0.55, 0, 0, 0)
			chanceLabel.BackgroundTransparency = 1
			chanceLabel.Font = Enum.Font.Gotham
			chanceLabel.TextSize = 12
			chanceLabel.TextXAlignment = Enum.TextXAlignment.Right
			chanceLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
			chanceLabel.Text = if entry.Chance > 0
				then "1 in " .. FormatSuffix(1 / entry.Chance)
				else "—"

			row.Parent = oddsList
		end
	end

	oddsToggle.MouseButton1Click:Connect(function()
		oddsPanel.Visible = not oddsPanel.Visible
		if oddsPanel.Visible then
			RefreshOddsPanel()
		end
	end)

	-- ── Biome selector ────────────────────────────────────────────────────────
	local biomeBar = Instance.new("Frame")
	biomeBar.Name = "BiomeBar"
	biomeBar.Size = UDim2.new(0, 0, 0, 30)
	biomeBar.AutomaticSize = Enum.AutomaticSize.X
	biomeBar.AnchorPoint = Vector2.new(0.5, 1)
	biomeBar.Position = UDim2.new(0.5, 0, 1, -105)
	biomeBar.BackgroundTransparency = 1
	biomeBar.Parent = mainInterface

	local biomeLayout = Instance.new("UIListLayout", biomeBar)
	biomeLayout.FillDirection = Enum.FillDirection.Horizontal
	biomeLayout.Padding = UDim.new(0, 6)
	biomeLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local biomeButtons: {[string]: TextButton} = {}

	local function BiomeButtonText(biome: AuraRegistry.BiomeDef): string
		if State.UnlockedBiomes[biome.Id] then
			return string.upper(biome.DisplayName)
		end
		if State.Level < biome.LevelReq then
			return string.format("%s (LV %d)", string.upper(biome.DisplayName), biome.LevelReq)
		end
		return string.format("%s (%s)", string.upper(biome.DisplayName), FormatSuffix(biome.UnlockCost or 0))
	end

	local function RefreshBiomeBar(): ()
		for biomeId, btn in pairs(biomeButtons) do
			local biome = AuraRegistry.GetBiome(biomeId)
			if not biome then continue end
			btn.Text = BiomeButtonText(biome)
			local isActive = (biomeId == State.CurrentBiome)
			local unlocked = State.UnlockedBiomes[biomeId] == true
			btn.BackgroundColor3 = if isActive
				then Color3.fromRGB(35, 28, 50)
				elseif unlocked then Color3.fromRGB(25, 20, 35)
				else Color3.fromRGB(18, 14, 24)
			btn.TextColor3 = if unlocked
				then (biome.Color or Color3.fromRGB(200, 180, 255))
				else Color3.fromRGB(130, 120, 150)
		end
	end

	do
		-- Sort biomes by level requirement for a stable progression order
		local sorted: {AuraRegistry.BiomeDef} = {}
		for _, biome in pairs(AuraRegistry.Biomes) do
			table.insert(sorted, biome)
		end
		table.sort(sorted, function(a, b)
			if a.LevelReq ~= b.LevelReq then return a.LevelReq < b.LevelReq end
			return a.Id < b.Id
		end)

		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		for i, biome in ipairs(sorted) do
			local btn = Instance.new("TextButton")
			btn.Name = "Biome_" .. biome.Id
			btn.Size = UDim2.new(0, 0, 1, 0)
			btn.AutomaticSize = Enum.AutomaticSize.X
			btn.LayoutOrder = i
			btn.Font = Enum.Font.GothamBlack
			btn.TextSize = 12
			btn.AutoButtonColor = false
			btn.Parent = biomeBar
			Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
			local pad = Instance.new("UIPadding", btn)
			pad.PaddingLeft = UDim.new(0, 10)
			pad.PaddingRight = UDim.new(0, 10)

			btn.MouseButton1Click:Connect(function()
				if biome.Id == State.CurrentBiome then return end
				if State.IsSpinning or State.IsRevealing or State.AutoRoll then return end
				-- Server validates level/cost; locked clicks are a purchase attempt
				;(remotes:WaitForChild("SetBiomeRequest") :: RemoteEvent):FireServer(biome.Id)
			end)

			biomeButtons[biome.Id] = btn
		end
	end

	-- ── Juice (rarity feedback) ───────────────────────────────────────────────
	local juiceActive = false

	local function TweenButtonColor(color: Color3, duration: number): ()
		rollButton.BackgroundColor3 = color
		local revert = TweenService:Create(rollButton, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = RollConfig.Theme.Success.Bg,
		})
		revert:Play()
		revert.Completed:Wait()
	end

	local function TweenVignette(targetAlpha: number, duration: number, hold: number): ()
		local fadeIn = TweenService:Create(vignetteFrame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = targetAlpha,
		})
		fadeIn:Play()
		fadeIn.Completed:Wait()
		if hold > 0 then task.wait(hold) end
		local fadeOut = TweenService:Create(vignetteFrame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1.0,
		})
		fadeOut:Play()
		fadeOut.Completed:Wait()
	end

	local function TweenButtonBounce(duration: number): ()
		task.wait(0.1)
		local half = duration / 2
		local up = TweenService:Create(scale, TweenInfo.new(half, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.23 })
		up:Play()
		up.Completed:Wait()
		local down = TweenService:Create(scale, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.15 })
		down:Play()
		down.Completed:Wait()
	end

	local function ShakeRollButton(offset: number, duration: number): ()
		local origPos = rollButtonDefaultPos
		local shakeCount = 6
		local interval = duration / shakeCount
		for i = 1, shakeCount do
			local dx = if (i % 2 == 0) then offset else -offset
			local dy = if (i % 3 == 0) then offset else -offset
			local t = TweenService:Create(rollButton, TweenInfo.new(interval, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(origPos.X.Scale, origPos.X.Offset + dx, origPos.Y.Scale, origPos.Y.Offset + dy),
			})
			t:Play()
			t.Completed:Wait()
		end
		rollButton.Position = origPos
	end

	local function PlayJuice(rarityTag: string): ()
		local rarity = AuraRegistry.GetRarity(rarityTag)
		local tier = rarity.FeedbackTier
		local reduceEffects = LocalPlayer:GetAttribute("ReduceEffects") == true

		if reduceEffects then
			if tier ~= "none" then
				TweenService:Create(rollButton, TweenInfo.new(0.15), { BackgroundColor3 = rarity.Color }):Play()
			end
			return
		end

		if tier == "none" or juiceActive then return end
		juiceActive = true

		task.spawn(function()
			local ok, err = pcall((function()
				TweenButtonColor(rarity.Color, 0.1)
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
				if rarityTag == "OMNI" then
					rollButton.Active = false
					task.wait(1.0)
					rollButton.Active = true
				end
			end) :: any)
			if not ok then warn("[MainUIController] Juice error:", err) end
			task.wait(0.1)
			juiceActive = false
		end)
	end

	local function PlayJuiceSound(rarityTag: string): ()
		if LocalPlayer:GetAttribute("ReduceEffects") == true then return end
		local tier = AuraRegistry.GetRarity(rarityTag).FeedbackTier
		local soundName = TIER_SOUNDS[tier]
		if not soundName then return end

		local snd = JuiceSounds[soundName]
		if snd then snd:Play() end

		if rarityTag == "OMNI" then
			task.delay(0.6, function()
				local swell = JuiceSounds["RollOmniSwell"]
				if swell then swell:Play() end
			end)
		end
	end

	local function PlayRollingAnimation(duration: number): () -> ()
		if duration <= 0 then
			return function() end
		end
		local running = true
		task.spawn(function()
			local dots = { "ROLLING.", "ROLLING..", "ROLLING..." }
			local idx = 1
			while running do
				rollButton.Text = dots[idx]
				idx = (idx % #dots) + 1
				task.wait(0.1)
			end
		end)
		return function()
			running = false
		end
	end

	-- ── Auto-roll toggle (Monetization-gated) ─────────────────────────────────
	local autoToggle: TextButton? = nil

	local function SetAutoRoll(isActive: boolean): ()
		State.AutoRoll = isActive
		_rollBtnTweenToken += 1
		local token = _rollBtnTweenToken
		if isActive then
			rollButton.Text = "AUTO-ROLLING..."
			rollButton.TextColor3 = Color3.fromRGB(150, 150, 160)
			rollButton.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
			stroke.Color = Color3.fromRGB(20, 20, 25)
			rollButton:SetAttribute("IsLocked", true)
		else
			rollButton:SetAttribute("IsLocked", false)
			if not State.IsSpinning and not State.IsRevealing then
				task.defer(function()
					if _rollBtnTweenToken ~= token then return end
					rollButton.Text = RollButtonIdleText()
					rollButton.TextColor3 = Color3.new(1, 1, 1)
					rollButton.BackgroundColor3 = RollConfig.Theme.Idle.Bg
					stroke.Color = RollConfig.Theme.Idle.Stroke
				end)
			end
		end
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local rollReq = remotes:WaitForChild("RollRequest") :: RemoteEvent
	local toggleAutoReq = remotes:WaitForChild("ToggleAutoRoll") :: RemoteEvent
	local updateClient = remotes:WaitForChild("UpdateClient") :: RemoteEvent
	local updateBiome = remotes:WaitForChild("UpdateBiome") :: RemoteEvent

	if showAutoRoll then
		local toggleBtn = Instance.new("TextButton")
		toggleBtn.Name = "AutoRollToggle"
		toggleBtn.Size = UDim2.new(0, 50, 0, 50)
		toggleBtn.Position = UDim2.new(0.5, -100, 1, -30)
		toggleBtn.AnchorPoint = Vector2.new(1, 0.5)
		toggleBtn.BackgroundTransparency = 1
		toggleBtn.Text = ""
		toggleBtn.AutoButtonColor = false
		toggleBtn.Parent = mainInterface
		autoToggle = toggleBtn

		local aIcon = Instance.new("ImageLabel", toggleBtn)
		aIcon.Name = "AutoIcon"
		aIcon.Size = UDim2.fromScale(1, 1)
		aIcon.BackgroundTransparency = 1
		aIcon.Image = AssetRegistry.UI.AutoRollOffIcon
		aIcon.ScaleType = Enum.ScaleType.Fit

		toggleBtn.MouseButton1Click:Connect(function()
			local now = os.clock()
			local lastClick = toggleBtn:GetAttribute("LastClick")
			if now - (if type(lastClick) == "number" then lastClick else 0) < 1.0 then return end
			toggleBtn:SetAttribute("LastClick", now)

			local isAuto = not (toggleBtn:GetAttribute("IsAuto") == true)
			toggleBtn:SetAttribute("IsAuto", isAuto)
			aIcon.Image = if isAuto then AssetRegistry.UI.AutoRollOnIcon else AssetRegistry.UI.AutoRollOffIcon
			SetAutoRoll(isAuto)

			TweenService:Create(toggleBtn, TweenInfo.new(0.1, Enum.EasingStyle.Bounce), {Size = UDim2.new(0, 55, 0, 55)}):Play()
			task.delay(0.1, function()
				TweenService:Create(toggleBtn, TweenInfo.new(0.1), {Size = UDim2.new(0, 50, 0, 50)}):Play()
			end)

			toggleAutoReq:FireServer(isAuto)
		end)
	end

	local function ForceAutoOff(): ()
		SetAutoRoll(false)
		local toggleBtn = autoToggle
		if toggleBtn then
			toggleBtn:SetAttribute("IsAuto", false)
			local aIcon = toggleBtn:FindFirstChild("AutoIcon") :: ImageLabel?
			if aIcon then aIcon.Image = AssetRegistry.UI.AutoRollOffIcon end
		end
	end

	local forceDisableRemote = remotes:WaitForChild("ForceDisableAutoRoll", 5) :: RemoteEvent?
	if forceDisableRemote then
		forceDisableRemote.OnClientEvent:Connect(function()
			ForceAutoOff()
			toggleAutoReq:FireServer(false)

			-- "Requires premium" toast
			local alertGui = Instance.new("ScreenGui")
			alertGui.Name = "AlertGui"
			alertGui.DisplayOrder = 1000
			alertGui.Parent = LocalPlayer.PlayerGui

			local popup = Instance.new("TextLabel", alertGui)
			popup.Size = UDim2.new(0, 350, 0, 40)
			popup.AnchorPoint = Vector2.new(0.5, 0)
			popup.Position = UDim2.new(0.5, 0, 0, 0)
			popup.BackgroundTransparency = 1
			popup.Font = Enum.Font.GothamBlack
			popup.Text = "AUTO-ROLL REQUIRES THE AUTO-ROLL PASS"
			popup.TextColor3 = Color3.fromRGB(255, 100, 100)
			popup.TextSize = 14

			local popStroke = Instance.new("UIStroke", popup)
			popStroke.Color = Color3.fromRGB(80, 20, 20)
			popStroke.Thickness = 2

			TweenService:Create(popup, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, 0, 0, 120)}):Play()
			task.delay(3.5, function()
				local fade = TweenService:Create(popup, TweenInfo.new(0.4), {TextTransparency = 1, Position = UDim2.new(0.5, 0, 0, 80)})
				TweenService:Create(popStroke, TweenInfo.new(0.4), {Transparency = 1}):Play()
				fade:Play()
				fade.Completed:Connect(function() alertGui:Destroy() end)
			end)
		end)
	end

	toggleAutoReq.OnClientEvent:Connect(function(serverState: boolean)
		if serverState == false then
			ForceAutoOff()
		else
			SetAutoRoll(serverState == true)
		end
	end)

	-- ── Roll input ────────────────────────────────────────────────────────────
	rollButton.MouseEnter:Connect(function()
		if not State.IsSpinning and not State.IsRevealing and not State.AutoRoll then
			TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 1.05}):Play()
			TweenService:Create(rollButton, TweenInfo.new(0.1), {BackgroundColor3 = RollConfig.Theme.Hover.Bg}):Play()
		end
	end)
	rollButton.MouseLeave:Connect(function()
		if not State.IsRevealing and not State.AutoRoll then
			TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play()
			if not State.IsSpinning then
				TweenService:Create(rollButton, TweenInfo.new(0.15), {BackgroundColor3 = RollConfig.Theme.Idle.Bg}):Play()
			end
		end
	end)
	rollButton.MouseButton1Down:Connect(function()
		if not State.IsRevealing and not State.AutoRoll then
			TweenService:Create(scale, TweenInfo.new(0.05), {Scale = 0.92}):Play()
		end
	end)
	rollButton.MouseButton1Up:Connect(function()
		if not State.IsRevealing and not State.AutoRoll then
			TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 1.05}):Play()
		end
	end)

	rollButton.MouseButton1Click:Connect(function()
		if rollButton:GetAttribute("IsLocked") == true then return end
		if State.AutoRoll or State.IsSpinning or State.IsRevealing then return end
		if GetCurrencyValue() < GetCurrentCost() then return end

		local currentCooldown = GetCurrentCooldown()
		local now = os.clock()
		local lastReq = rollButton:GetAttribute("LastRollReq")
		if now - (if type(lastReq) == "number" then lastReq else 0) < currentCooldown then return end
		rollButton:SetAttribute("LastRollReq", now)

		currentSpinId += 1
		local mySpinId = currentSpinId

		State.IsSpinning = true
		rollReq:FireServer(State.CurrentBiome, mySpinId)

		rollButton.BackgroundColor3 = RollConfig.Theme.Spinning.Bg
		stroke.Color = RollConfig.Theme.Spinning.Stroke
		rollButton.TextTransparency = 0.5

		-- Failsafe: unstick the button if the server rejects the roll
		task.delay(RollConfig.TimeoutDuration, function()
			if State.IsSpinning and currentSpinId == mySpinId then
				State.IsSpinning = false
				rollButton.BackgroundColor3 = RollConfig.Theme.Idle.Bg
				stroke.Color = RollConfig.Theme.Idle.Stroke
				rollButton.TextTransparency = 0
				rollButton.Text = RollButtonIdleText()
			end
		end)

		-- Name flicker while spinning
		task.spawn(function()
			local biome = GetCurrentBiome()
			local pool = if biome then biome.Auras else nil
			while State.IsSpinning and pool and #pool > 0 do
				rollButton.Text = pool[math.random(1, #pool)].DisplayName
				task.wait(0.1)
			end
		end)
	end)

	-- ── External toggles / server events ──────────────────────────────────────
	GetLocalEvent("ToggleGachaButton").Event:Connect(function(isVisible: boolean)
		if isHudHidden then
			hiddenGuisCache[mainInterface] = isVisible
			return
		end
		mainInterface.Enabled = isVisible
	end)

	updateBiome.OnClientEvent:Connect(function(biomeId: any)
		if type(biomeId) ~= "string" then return end
		State.CurrentBiome = biomeId
		State.UnlockedBiomes[biomeId] = true
		if not State.IsSpinning and not State.IsRevealing and not State.AutoRoll then
			rollButton.Text = RollButtonIdleText()
		end
		RefreshBiomeBar()
		if oddsPanel.Visible then RefreshOddsPanel() end
	end)

	-- Full-state sync seeds biome/level state on join and after purchases
	local updateProfileRemote = remotes:WaitForChild("UpdateProfileData", 5) :: RemoteEvent?
	if updateProfileRemote then
		updateProfileRemote.OnClientEvent:Connect(function(data: any)
			if type(data) ~= "table" then return end
			if type(data.Progression) == "table" and type(data.Progression.Level) == "number" then
				State.Level = data.Progression.Level
			end
			local genreData = if type(data.GenreData) == "table" then data.GenreData[GENRE_KEY] else nil
			if type(genreData) == "table" then
				if type(genreData.CurrentBiome) == "string" then
					State.CurrentBiome = genreData.CurrentBiome
				end
				if type(genreData.UnlockedBiomes) == "table" then
					for biomeId, unlocked in pairs(genreData.UnlockedBiomes) do
						if unlocked == true and type(biomeId) == "string" then
							State.UnlockedBiomes[biomeId] = true
						end
					end
				end
			end
			if not State.IsSpinning and not State.IsRevealing and not State.AutoRoll then
				rollButton.Text = RollButtonIdleText()
			end
			RefreshBiomeBar()
		end)
	end

	-- Auto-roll pause tiers, keyed off rarity Order (SettingsController sets
	-- the AutoRollStopTier attribute)
	local function ShouldPauseAutoRoll(rarityTag: string): boolean
		local key = LocalPlayer:GetAttribute("AutoRollStopTier")
		local mode = if type(key) == "string" then key else "MYTHIC+"
		if mode == "NEVER" then return false end
		local order = AuraRegistry.GetRarity(rarityTag).Order
		if mode == "RAREST" then return order >= 10 end
		return order >= 6 -- "MYTHIC+"
	end

	-- ── Roll result / reveal ──────────────────────────────────────────────────
	updateClient.OnClientEvent:Connect(function(rolledId: any, _equippedId: any, rolledBiomeId: any, spinId: any)
		if type(rolledId) ~= "string" then return end
		if rolledBiomeId ~= State.CurrentBiome then return end
		if not State.AutoRoll and type(spinId) == "number" and spinId ~= currentSpinId then return end

		local def = AuraRegistry.GetAuraData(rolledId)
		local rarity = AuraRegistry.GetRarity(def.RarityTag)

		-- Hold the spin long enough to feel like a roll, even on low ping
		local timeSinceClick = 0
		if not State.AutoRoll then
			local lastReq = rollButton:GetAttribute("LastRollReq")
			local reqAt = if type(lastReq) == "number" then lastReq else 0
			timeSinceClick = os.clock() - reqAt
			local currentCooldown = GetCurrentCooldown()
			local minSpin = math.min(1.8, math.max(0.8, currentCooldown - 0.7))
			if timeSinceClick < minSpin then
				task.wait(minSpin - timeSinceClick)
				timeSinceClick = os.clock() - reqAt
			end
		end

		State.IsSpinning = false
		State.IsRevealing = true
		rollButton.TextTransparency = 0

		GetLocalEvent("EffectRolled"):Fire(rolledId)

		if not (LocalPlayer:GetAttribute("ReduceEffects") == true) and rarity.AnticipationSecs > 0 then
			local stopRolling = PlayRollingAnimation(rarity.AnticipationSecs)
			task.wait(rarity.AnticipationSecs)
			stopRolling()
		end

		rollButton.BackgroundColor3 = RollConfig.Theme.Success.Bg
		stroke.Color = RollConfig.Theme.Success.Stroke
		rollButton.Text = string.format(" %s \n[%s]", string.upper(def.DisplayName), def.RarityTag)
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.15}):Play()

		PlayJuice(def.RarityTag)
		task.spawn(function()
			local ok, err = pcall(PlayJuiceSound :: any, def.RarityTag)
			if not ok then warn("[MainUIController] Sound error:", err) end
		end)

		local dynamicRevealDuration = RollConfig.RevealDuration
		if not State.AutoRoll then
			dynamicRevealDuration = math.max(0.5, GetCurrentCooldown() - timeSinceClick)
		end

		local mySpinId = if type(spinId) == "number" then spinId else currentSpinId
		rollButton:SetAttribute("CurrentRevealId", mySpinId)

		if State.AutoRoll and ShouldPauseAutoRoll(def.RarityTag) then
			ForceAutoOff()
			toggleAutoReq:FireServer(false)

			local frozenText = rollButton.Text
			task.delay(dynamicRevealDuration, function()
				if rollButton:GetAttribute("CurrentRevealId") ~= mySpinId then return end
				TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
				rollButton.Text = frozenText .. "\n⚠ AUTO-ROLL PAUSED"
				State.IsRevealing = false
			end)
			task.delay(dynamicRevealDuration + 3.0, function()
				if rollButton:GetAttribute("CurrentRevealId") ~= mySpinId then return end
				if not State.AutoRoll and not State.IsSpinning then
					TweenService:Create(rollButton, TweenInfo.new(0.4), {BackgroundColor3 = RollConfig.Theme.Idle.Bg}):Play()
					stroke.Color = RollConfig.Theme.Idle.Stroke
					rollButton.Text = RollButtonIdleText()
				end
			end)
			return
		end

		task.delay(dynamicRevealDuration, function()
			if rollButton:GetAttribute("CurrentRevealId") ~= mySpinId then return end
			TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
			if not State.AutoRoll then
				TweenService:Create(rollButton, TweenInfo.new(0.3), {BackgroundColor3 = RollConfig.Theme.Idle.Bg}):Play()
				stroke.Color = RollConfig.Theme.Idle.Stroke
				rollButton.Text = RollButtonIdleText()
			else
				SetAutoRoll(true)
			end
			State.IsRevealing = false
		end)
	end)

	RefreshBiomeBar()
end

return MainUIController
