--!strict
--@author OrkGabb
--@module SettingsController.luau
--@version 1.0
-- Feature-aware settings controller. Exposes metadata-driven configurations dynamically.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting          = game:GetService("Lighting")
local LocalPlayer       = Players.LocalPlayer

local FeatureResolver   = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("FeatureResolver"))
local SettingsRegistry  = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("SettingsRegistry")) :: any
local UIHelpers         = require(script.Parent.Parent.UI.UIHelpers)
local UITheme           = require(script.Parent.Parent.UI.UITheme)

local SettingsController = {}

local SettingsState: {[string]: any} = {
	MasterVolume    = true,
	PerformanceMode = false,
}

local isOpen     = false
-- Bumped on every open/close transition; stale animation callbacks compare
-- against it and stand down if a newer transition has taken over.
local animGen    = 0
local mainPanel: Frame
local panelScale: UIScale
local BgShield: TextButton
local _cachedEvents: {[string]: BindableEvent} = {}

type ParticleSnap = {
	emitter:       ParticleEmitter?,
	rate:          number,
	lightEmission: number,
	light:         PointLight?,
	lightEnabled:  boolean,
	lightRange:    number,
}

local _particleSnapshots: {ParticleSnap} = {}
local _othersSnapshots: {[number]: {ParticleSnap}} = {}
local _descendantConn: RBXScriptConnection?

local function GetLocalEvent(name: string): BindableEvent
	if _cachedEvents[name] then return _cachedEvents[name] end
	local folder = ReplicatedStorage:FindFirstChild("LocalEvents")
		or Instance.new("Folder", ReplicatedStorage)
	folder.Name = "LocalEvents"
	local evt = folder:FindFirstChild(name) or Instance.new("BindableEvent", folder)
	evt.Name = name
	_cachedEvents[name] = evt :: BindableEvent
	return evt :: BindableEvent
end

local _defaultFog = Lighting.FogEnd
local _lowEndActive    = false
local _particleOriginals: {[ParticleEmitter]: {Rate: number, Size: NumberSequence}} = {}
local _materialOriginals: {[BasePart]: Enum.Material} = {}
local _castShadowOriginals: {[BasePart]: boolean} = {}
local _textureOriginals: {[Texture | Decal]: number} = {}
local _trailBeamOriginals: {[any]: boolean} = {}
local _lightingOriginals: {Diffuse: number?, Specular: number?, Softness: number?} = {}

local EXPENSIVE_MATERIALS = {
	[Enum.Material.Neon] = true,
	[Enum.Material.Glass] = true,
	[Enum.Material.Water] = true,
	[Enum.Material.ForceField] = true,
	[Enum.Material.Foil] = true,
}

-- Suppression Helpers

local function SuppressAttachment(attachment: Attachment, snapList: {ParticleSnap})
	for _, child in ipairs(attachment:GetChildren()) do
		if child:IsA("PointLight") then
			local light = child :: PointLight
			table.insert(snapList, {
				emitter       = nil,
				rate          = 0,
				lightEmission = 0,
				light         = light,
				lightEnabled  = light.Enabled,
				lightRange    = light.Range,
			})
			light.Enabled = false

		elseif child:IsA("ParticleEmitter") then
			local emitter = child :: ParticleEmitter
			table.insert(snapList, {
				emitter       = emitter,
				rate          = emitter.Rate,
				lightEmission = emitter.LightEmission,
				light         = nil,
				lightEnabled  = false,
				lightRange    = 0,
			})
			emitter.Rate          = math.max(math.floor(emitter.Rate * 0.25), 0)
			emitter.LightEmission = 0
		end
	end
end

local function SuppressCharacterVFX(character: Model, snapList: {ParticleSnap})
	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("Attachment") then
			SuppressAttachment(desc :: Attachment, snapList)
		end
	end
end

local function RestoreSnapList(snapList: {ParticleSnap})
	for _, snap in ipairs(snapList) do
		if snap.light and snap.light.Parent then
			snap.light.Enabled = snap.lightEnabled
			snap.light.Range   = snap.lightRange
		elseif snap.emitter and snap.emitter.Parent then
			snap.emitter.Rate          = snap.rate
			snap.emitter.LightEmission = snap.lightEmission
		end
	end
	table.clear(snapList)
end

-- Low-End Mode

local function StopDescendantWatcher()
	if _descendantConn then
		_descendantConn:Disconnect()
		_descendantConn = nil
	end
end

local function StartDescendantWatcher(character: Model)
	StopDescendantWatcher()
	_descendantConn = character.DescendantAdded:Connect(function(desc)
		if not SettingsState.PerformanceMode then return end
		task.defer(function()
			if desc:IsA("Attachment") and desc.Parent then
				SuppressAttachment(desc :: Attachment, _particleSnapshots)
			end
		end)
	end)
end

local function ApplyLowEnd(on: boolean)
	if on == _lowEndActive then return end
	_lowEndActive = on

	Lighting.GlobalShadows = not on

	if on then
		_lightingOriginals.Diffuse = Lighting.EnvironmentDiffuseScale
		_lightingOriginals.Specular = Lighting.EnvironmentSpecularScale
		_lightingOriginals.Softness = Lighting.ShadowSoftness
		Lighting.EnvironmentDiffuseScale = 0
		Lighting.EnvironmentSpecularScale = 0
		Lighting.ShadowSoftness = 0
	else
		local diffuse, specular, softness =
			_lightingOriginals.Diffuse, _lightingOriginals.Specular, _lightingOriginals.Softness
		if diffuse and specular and softness then
			Lighting.EnvironmentDiffuseScale = diffuse
			Lighting.EnvironmentSpecularScale = specular
			Lighting.ShadowSoftness = softness
		end
	end

	for _, fx in ipairs(Lighting:GetChildren()) do
		if fx:IsA("BloomEffect")
			or fx:IsA("SunRaysEffect")
			or fx:IsA("DepthOfFieldEffect")
			or fx:IsA("ColorCorrectionEffect")
			or fx:IsA("BlurEffect") then
			fx.Enabled = not on
		end
	end

	if on then
		table.clear(_particleOriginals)
		table.clear(_materialOriginals)
		table.clear(_castShadowOriginals)
		table.clear(_textureOriginals)
		table.clear(_trailBeamOriginals)
		
		task.defer(function()
			for _, obj in ipairs(workspace:GetDescendants()) do
				if obj:IsA("BasePart") then
					if EXPENSIVE_MATERIALS[obj.Material] then
						_materialOriginals[obj] = obj.Material
						obj.Material = Enum.Material.SmoothPlastic
					end
					if obj.CastShadow then
						_castShadowOriginals[obj] = true
						obj.CastShadow = false
					end
				elseif obj:IsA("Texture") or obj:IsA("Decal") then
					if obj.Transparency < 1 then
						_textureOriginals[obj] = obj.Transparency
						obj.Transparency = 1
					end
				elseif obj:IsA("Trail") or obj:IsA("Beam") then
					if obj.Enabled then
						_trailBeamOriginals[obj] = true
						obj.Enabled = false
					end
				end
			end
		end)

		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			if not char then continue end
			for _, obj in ipairs(char:GetDescendants()) do
				if obj:IsA("ParticleEmitter") then
					local pe = obj :: ParticleEmitter
					_particleOriginals[pe] = { Rate = pe.Rate, Size = pe.Size }
					pe.Rate = pe.Rate * 0.15
					local kps = {}
					for _, kp in ipairs(pe.Size.Keypoints) do
						table.insert(kps, NumberSequenceKeypoint.new(
							kp.Time,
							kp.Value * 0.15,
							kp.Envelope * 0.15
						))
					end
					pe.Size = NumberSequence.new(kps)
				elseif obj:IsA("Trail") or obj:IsA("Beam") then
					if obj.Enabled then
						_trailBeamOriginals[obj] = true
						obj.Enabled = false
					end
				end
			end
		end
	else
		for pe, original in pairs(_particleOriginals) do
			if pe and pe.Parent then
				pe.Rate = original.Rate
				pe.Size = original.Size
			end
		end
		table.clear(_particleOriginals)

		for part, mat in pairs(_materialOriginals) do
			if part and part.Parent then
				part.Material = mat
			end
		end
		table.clear(_materialOriginals)

		for part, _ in pairs(_castShadowOriginals) do
			if part and part.Parent then
				part.CastShadow = true
			end
		end
		table.clear(_castShadowOriginals)

		for tex, trans in pairs(_textureOriginals :: {[any]: number}) do
			if tex and tex.Parent then
				tex.Transparency = trans
			end
		end
		table.clear(_textureOriginals)

		for tb, _ in pairs(_trailBeamOriginals) do
			if tb and tb.Parent then
				tb.Enabled = true
			end
		end
		table.clear(_trailBeamOriginals)
	end
end

-- Others' VFX

local _otherCharConns: {[number]: RBXScriptConnection} = {}

local function SuppressOtherCharacter(player: Player)
	local uid = player.UserId
	if _othersSnapshots[uid] then return end 

	local character = player.Character
	if not character then return end

	local snapList: {ParticleSnap} = {}
	SuppressCharacterVFX(character, snapList)
	_othersSnapshots[uid] = snapList
end

local function RestoreOtherCharacter(player: Player)
	local uid = player.UserId
	local snapList = _othersSnapshots[uid]
	if not snapList then return end
	RestoreSnapList(snapList)
	_othersSnapshots[uid] = nil
end

local ApplyOthersVFX: (boolean) -> ()

function ApplyOthersVFX(show: boolean)
	if not show then
		for _, player in ipairs(Players:GetPlayers()) do
			if player == LocalPlayer then continue end
			SuppressOtherCharacter(player)
		end

		for _, player in ipairs(Players:GetPlayers()) do
			if player == LocalPlayer then continue end
			local uid = player.UserId
			if _otherCharConns[uid] then continue end
			_otherCharConns[uid] = player.CharacterAdded:Connect(function(char)
				if SettingsState.OthersVFX then return end
				task.wait(1) 
				SuppressOtherCharacter(player)
			end)
		end

		if not _cachedEvents["_othersPlayerAdded"] then
			Players.PlayerAdded:Connect(function(player)
				if player == LocalPlayer then return end
				local uid = player.UserId
				_otherCharConns[uid] = player.CharacterAdded:Connect(function()
					if SettingsState.OthersVFX then return end
					task.wait(1)
					SuppressOtherCharacter(player)
				end)
			end)
			Players.PlayerRemoving:Connect(function(player)
				local uid = player.UserId
				_othersSnapshots[uid] = nil
				if _otherCharConns[uid] then
					_otherCharConns[uid]:Disconnect()
					_otherCharConns[uid] = nil
				end
			end)
			_cachedEvents["_othersPlayerAdded"] = Instance.new("BindableEvent")
		end
	else
		for _, player in ipairs(Players:GetPlayers()) do
			if player == LocalPlayer then continue end
			RestoreOtherCharacter(player)
		end
	end
end

function SettingsController.Init(): ()
	GetLocalEvent("ToggleSettings")
	GetLocalEvent("ToggleFloatingText")

	pcall(function()
		local level = UserSettings():GetService("UserGameSettings").SavedQualityLevel
		if level.Value > 0 and level.Value <= 3 then
			SettingsState.PerformanceMode = true
		end
	end)
end

function SettingsController.Start(): ()
	local UIController: any = require(script.Parent:WaitForChild("UIController"))
	UIController.RegisterHUDButton({
		Id = "Settings",
		Name = "CONFIG",
		IconId = "Settings",
		Type = "TopRight",
		LayoutOrder = 1,
		OnClick = function(): ()
			GetLocalEvent("ToggleSettings"):Fire()
		end
	})

	for _, child in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
		if child.Name == "SettingsGui" then child:Destroy() end
	end

	local gui        = Instance.new("ScreenGui")
	gui.Name         = "SettingsGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60 -- panel band: 60 resting/closing, 61 while open
	gui.Parent       = LocalPlayer.PlayerGui
	
	if SettingsState.PerformanceMode then
		ApplyLowEnd(true)
	end

	BgShield = Instance.new("TextButton", gui)
	BgShield.Name = "InputSink"
	BgShield.Size = UDim2.fromScale(1, 1)
	BgShield.BackgroundTransparency = 1
	BgShield.Text = ""
	BgShield.AutoButtonColor = false
	BgShield.Visible = false
	BgShield.Active = true
	-- (click-to-close is connected below, once ClosePanel exists)

	mainPanel                        = Instance.new("Frame")
	mainPanel.Visible                = false
	mainPanel.Parent                 = gui
	mainPanel.Size                   = UDim2.new(0, 380, 0, 370)
	mainPanel.AnchorPoint            = Vector2.new(0.5, 0.5)
	mainPanel.Position               = UDim2.new(0.5, 0, 0.5, 0)
	mainPanel.BackgroundColor3       = UITheme.PanelBackground
	mainPanel.BackgroundTransparency = 0.05
	mainPanel.BorderSizePixel        = 0
	Instance.new("UICorner", mainPanel).CornerRadius = UDim.new(0, 16)

	local panelGrad = Instance.new("UIGradient", mainPanel)
	panelGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UITheme.PanelGradientTop),
		ColorSequenceKeypoint.new(1, UITheme.PanelGradientBottom),
	})
	panelGrad.Rotation = 135

	local stroke     = Instance.new("UIStroke", mainPanel)
	stroke.Color     = UITheme.Accent
	stroke.Thickness = 2

	panelScale       = Instance.new("UIScale", mainPanel)
	UIHelpers.PrimeSpiral(mainPanel, panelScale)

	local title                  = Instance.new("TextLabel", mainPanel)
	title.Size                   = UDim2.new(1, 0, 0, 50)
	title.BackgroundTransparency = 1
	title.Text                   = "SETTINGS"
	title.Font                   = Enum.Font.GothamBlack
	title.TextSize               = 24
	title.TextColor3             = Color3.fromRGB(255, 255, 255)

	local function ClosePanel(reason: string?)
		if not isOpen then return end
		isOpen = false
		animGen += 1
		local gen = animGen
		gui.DisplayOrder = 60
		BgShield.Visible = false
		GetLocalEvent("NotifyMenuClosed"):Fire("Settings")
		local tw = UIHelpers.SpiralClose(mainPanel, panelScale, reason)
		tw.Completed:Connect(function(state: Enum.PlaybackState)
			-- A reopen cancels this tween (Completed still fires, state=Cancelled)
			-- and bumps the generation; hide only if this close ran to completion
			-- and is still the latest transition.
			if gen ~= animGen then return end
			if state ~= Enum.PlaybackState.Completed then return end
			mainPanel.Visible = false
		end)
	end

	UIHelpers.CreateCloseButton(mainPanel, ClosePanel)
	BgShield.MouseButton1Up:Connect(function() ClosePanel() end)

	local listFrame                       = Instance.new("ScrollingFrame", mainPanel)
	listFrame.Size                        = UDim2.new(1, -30, 1, -70)
	listFrame.Position                    = UDim2.new(0, 15, 0, 60)
	listFrame.BackgroundTransparency      = 1
	listFrame.BorderSizePixel             = 0
	listFrame.ScrollBarThickness          = 4
	listFrame.ScrollBarImageColor3        = Color3.fromRGB(48, 70, 74)
	listFrame.CanvasSize                  = UDim2.new(0, 0, 0, 0) 
	listFrame.AutomaticCanvasSize         = Enum.AutomaticSize.Y
	listFrame.ScrollingDirection          = Enum.ScrollingDirection.Y

	local layout       = Instance.new("UIListLayout", listFrame)
	layout.Padding     = UDim.new(0, 8)
	layout.SortOrder   = Enum.SortOrder.LayoutOrder

	local rowLayoutIndex = 1

	for _, setting in ipairs(SettingsRegistry) do
		-- Genre-gated rows only appear when their category is active
		if setting.RequiresCategory and not FeatureResolver.IsCategoryActive(setting.RequiresCategory) then
			continue
		end
		if SettingsState[setting.Id] == nil then
			SettingsState[setting.Id] = setting.Default
		end

		local row                  = Instance.new("Frame", listFrame)
		row.Size                   = UDim2.new(1, 0, 0, 40)
		row.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
		row.BackgroundTransparency = 0.94
		row.LayoutOrder            = rowLayoutIndex
		rowLayoutIndex += 1
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
		local rStroke = Instance.new("UIStroke",  row)
		rStroke.Color        = Color3.fromRGB(255, 255, 255)
		rStroke.Thickness    = 1
		rStroke.Transparency = 0.92

		local lbl                  = Instance.new("TextLabel", row)
		lbl.Size                   = UDim2.new(0.5, 0, 1, 0)
		lbl.Position               = UDim2.new(0, 15, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text                   = setting.Title
		lbl.Font                   = Enum.Font.GothamBold
		lbl.TextSize               = 12
		lbl.TextColor3             = Color3.fromRGB(150, 150, 160)
		lbl.TextXAlignment         = Enum.TextXAlignment.Left

		if setting.Type == "Toggle" then
			local btn                  = Instance.new("TextButton", row)
			btn.Size                   = UDim2.new(0, 90, 0, 30)
			btn.Position               = UDim2.new(1, -104, 0.5, -15)
			btn.AutoButtonColor        = false
			btn.Font                   = Enum.Font.GothamBlack
			btn.TextSize               = 13
			btn.TextColor3             = Color3.new(1, 1, 1)
			Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

			local state = SettingsState[setting.Id]
			local function Refresh()
				btn.BackgroundColor3 = state
					and Color3.fromRGB(0, 170, 50)
					or  Color3.fromRGB(150, 30, 30)
				btn.Text = state and "ON" or "OFF"
			end
			Refresh()

			btn.MouseButton1Click:Connect(function()
				state = not state
				SettingsState[setting.Id] = state
				Refresh()
				if setting.Id == "PerformanceMode" then
					ApplyLowEnd(state)
				end
				setting.Callback(state)
			end)
		elseif setting.Type == "Cycle" then
			local cyclBtn = Instance.new("TextButton", row)
			cyclBtn.Size             = UDim2.new(0, 128, 0, 28)
			cyclBtn.Position         = UDim2.new(1, -140, 0.5, -14)
			cyclBtn.AutoButtonColor  = false
			cyclBtn.Font             = Enum.Font.GothamBlack
			cyclBtn.TextSize         = 11
			cyclBtn.TextColor3       = Color3.new(1, 1, 1)
			Instance.new("UICorner", cyclBtn).CornerRadius = UDim.new(0, 8)

			local options = setting.CycleOptions or {}
			local labels = setting.CycleLabels or {}
			local colors = setting.CycleColors or {}

			local function RefreshCycle()
				local cur = SettingsState[setting.Id]
				cyclBtn.Text             = labels[cur] or cur
				cyclBtn.BackgroundColor3 = colors[cur] or Color3.fromRGB(100, 100, 100)
				setting.Callback(cur)
			end
			RefreshCycle()

			cyclBtn.MouseButton1Click:Connect(function()
				local cur = SettingsState[setting.Id]
				local idx = table.find(options, cur) or 1
				local nextIdx = (idx % #options) + 1
				SettingsState[setting.Id] = options[nextIdx]
				RefreshCycle()
			end)
		end
	end

	LocalPlayer.CharacterAdded:Connect(function(character)
		if SettingsState.PerformanceMode then
			task.wait(1)
			table.clear(_particleSnapshots)
			SuppressCharacterVFX(character, _particleSnapshots)
			StartDescendantWatcher(character)
		end
	end)

	GetLocalEvent("ToggleSettings").Event:Connect(function(reason: string?)
		if isOpen then
			ClosePanel(reason)
		else
			isOpen            = true
			animGen += 1
			gui.DisplayOrder = 61 -- render above the outgoing panel during a switch
			mainPanel.Visible = true
			BgShield.Visible  = true
			-- Retarget from the current scale/rotation (no reset to the resting
			-- pose) so reopening during a close animation continues smoothly
			-- instead of snapping shut first.
			UIHelpers.SpiralOpen(mainPanel, panelScale, 1)
			GetLocalEvent("NotifyMenuOpened"):Fire("Settings")
		end
	end)

	-- Cross-menu exclusion is owned centrally by UIController's NotifyMenuOpened
	-- handler, which fires ToggleSettings when another menu opens.
end

return SettingsController
