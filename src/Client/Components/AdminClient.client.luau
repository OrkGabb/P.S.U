--!strict
--@author OrkGabb
--@module AdminClient.client.luau
--@version 1.0
-- src/Client/Components/AdminClient.client.lua
-- Independent Admin Panel — LocalScript (runs autonomously, no bootstrapper dependency).
-- Secure: Only builds UI after server confirms admin status.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local ItemRegistry      = require(ReplicatedStorage.Shared.Modules.ItemRegistry)
local AuraRegistry      = require(ReplicatedStorage.Shared.Modules.AuraRegistry)

-- ========================================================================
-- DESIGN TOKENS
-- ========================================================================
local C = {
	BG          = Color3.fromRGB(10, 8, 18),
	SURFACE     = Color3.fromRGB(18, 14, 28),
	ACCENT      = Color3.fromRGB(200, 160, 50),
	ACCENT_DIM  = Color3.fromRGB(140, 110, 30),
	TEXT        = Color3.fromRGB(240, 240, 240),
	TEXT_DIM    = Color3.fromRGB(130, 120, 150),
	DANGER      = Color3.fromRGB(220, 50, 50),
	DANGER_DIM  = Color3.fromRGB(150, 30, 30),
	SUCCESS     = Color3.fromRGB(0, 180, 80),
	SUCCESS_DIM = Color3.fromRGB(0, 120, 50),
	INPUT_BG    = Color3.fromRGB(22, 17, 35),
	BORDER      = Color3.fromRGB(50, 40, 80),
	SECTION_BG  = Color3.fromRGB(14, 11, 24),
}

local PANEL_WIDTH  = 320
local PANEL_HEIGHT = 520
local ANIM_SPEED   = 0.25

-- ========================================================================
-- BOOT: Wait for Remotes and verify admin status
-- ========================================================================
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
if not Remotes then return end

local AdminRemote    = Remotes:WaitForChild(RemoteNames.SysAdmin, 10) :: RemoteEvent?
local AdminCheckFunc = Remotes:WaitForChild(RemoteNames.SysAdminCheck, 10) :: RemoteFunction?

if not AdminRemote or not AdminCheckFunc then return end

local isAllowed = (AdminCheckFunc :: RemoteFunction):InvokeServer()
if not isAllowed then return end

-- Access granted — build interface

-- ========================================================================
-- SCREEN GUI
-- ========================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "AdminPanel"
gui.DisplayOrder = 200
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = LocalPlayer.PlayerGui

-- ========================================================================
-- TOGGLE BUTTON (Gear icon, top-right)
-- ========================================================================
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "AdminToggle"
toggleBtn.Size = UDim2.new(0, 38, 0, 38)
toggleBtn.Position = UDim2.new(1, -46, 0, 58)
toggleBtn.AnchorPoint = Vector2.new(1, 0)
toggleBtn.Text = "⚙"
toggleBtn.TextSize = 18
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.BackgroundColor3 = C.ACCENT
toggleBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
toggleBtn.AutoButtonColor = false
toggleBtn.ZIndex = 10
toggleBtn.Parent = gui
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 10)
local toggleStroke = Instance.new("UIStroke", toggleBtn)
toggleStroke.Color = C.ACCENT_DIM
toggleStroke.Thickness = 2

-- Hover effects
toggleBtn.MouseEnter:Connect(function()
	TweenService:Create(toggleBtn, TweenInfo.new(0.12), {
		BackgroundColor3 = Color3.fromRGB(230, 190, 60),
		Size = UDim2.new(0, 42, 0, 42)
	}):Play()
end)
toggleBtn.MouseLeave:Connect(function()
	TweenService:Create(toggleBtn, TweenInfo.new(0.12), {
		BackgroundColor3 = C.ACCENT,
		Size = UDim2.new(0, 38, 0, 38)
	}):Play()
end)

-- ========================================================================
-- MAIN PANEL
-- ========================================================================
local panelOpen = false
local offScreenPos = UDim2.new(1, PANEL_WIDTH + 20, 0.5, 0)
local onScreenPos  = UDim2.new(1, -16, 0.5, 0)

local panel = Instance.new("Frame")
panel.Name = "MainPanel"
panel.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
panel.Position = offScreenPos
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.BackgroundColor3 = C.BG
panel.Visible = false
panel.ClipsDescendants = true
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color = C.ACCENT_DIM
panelStroke.Thickness = 1.5

-- ── Header ──
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 42)
header.BackgroundColor3 = C.ACCENT
header.Parent = panel
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)
-- Bottom filler to square off bottom corners of header
local hFill = Instance.new("Frame", header)
hFill.Size = UDim2.new(1, 0, 0.5, 0)
hFill.Position = UDim2.new(0, 0, 0.5, 0)
hFill.BackgroundColor3 = C.ACCENT
hFill.BorderSizePixel = 0

local headerLabel = Instance.new("TextLabel")
headerLabel.Size = UDim2.new(1, -40, 1, 0)
headerLabel.Position = UDim2.new(0, 14, 0, 0)
headerLabel.BackgroundTransparency = 1
headerLabel.Text = "⚡ CONTROL PANEL"
headerLabel.Font = Enum.Font.GothamBlack
headerLabel.TextSize = 13
headerLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
headerLabel.TextXAlignment = Enum.TextXAlignment.Left
headerLabel.Parent = header

-- ── Status Console (bottom) ──
local console = Instance.new("TextLabel")
console.Name = "StatusConsole"
console.Size = UDim2.new(1, -16, 0, 36)
console.Position = UDim2.new(0, 8, 1, -44)
console.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
console.TextColor3 = C.TEXT_DIM
console.Text = " READY"
console.Font = Enum.Font.Code
console.TextSize = 11
console.TextXAlignment = Enum.TextXAlignment.Left
console.TextTruncate = Enum.TextTruncate.AtEnd
console.Parent = panel
Instance.new("UICorner", console).CornerRadius = UDim.new(0, 6)

-- ── Scrolling Content ──
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 1, -95)
scroll.Position = UDim2.new(0, 0, 0, 44)
scroll.BackgroundTransparency = 1
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = C.ACCENT_DIM
scroll.CanvasSize = UDim2.new(0, 0, 0, 0) -- Auto-sized
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel

local layout = Instance.new("UIListLayout", scroll)
layout.Padding = UDim.new(0, 6)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
Instance.new("UIPadding", scroll).PaddingTop = UDim.new(0, 8)

-- ========================================================================
-- UI FACTORY FUNCTIONS
-- ========================================================================
local orderCounter = 0

local function NextOrder(): number
	orderCounter += 1
	return orderCounter
end

local function MakeInput(placeholder: string): TextBox
	local box = Instance.new("TextBox")
	box.Text = ""
	box.Size = UDim2.new(1, -24, 0, 32)
	box.BackgroundColor3 = C.INPUT_BG
	box.TextColor3 = C.TEXT
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = C.TEXT_DIM
	box.Font = Enum.Font.GothamBold
	box.TextSize = 12
	box.ClearTextOnFocus = false
	box.LayoutOrder = NextOrder()
	box.Parent = scroll
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
	local s = Instance.new("UIStroke", box)
	s.Color = C.BORDER
	s.Thickness = 1
	return box
end

local function MakeButton(text: string, color: Color3, dimColor: Color3): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -24, 0, 34)
	btn.BackgroundColor3 = color
	btn.TextColor3 = C.TEXT
	btn.Text = text
	btn.Font = Enum.Font.GothamBlack
	btn.TextSize = 12
	btn.AutoButtonColor = false
	btn.LayoutOrder = NextOrder()
	btn.Parent = scroll
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
	local s = Instance.new("UIStroke", btn)
	s.Color = dimColor
	s.Thickness = 1.5

	-- Micro-interactions
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.1), {Size = UDim2.new(1, -20, 0, 36)}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.1), {Size = UDim2.new(1, -24, 0, 34)}):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.05), {Size = UDim2.new(1, -28, 0, 32)}):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.1, Enum.EasingStyle.Back), {Size = UDim2.new(1, -24, 0, 34)}):Play()
	end)

	return btn
end

local function MakeSectionHeader(text: string): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -24, 0, 24)
	lbl.BackgroundColor3 = C.SECTION_BG
	lbl.TextColor3 = C.ACCENT
	lbl.Text = "  ─── " .. text .. " ───"
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 10
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.LayoutOrder = NextOrder()
	lbl.Parent = scroll
	Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 4)
	return lbl
end

local function MakeDualButton(textL: string, colorL: Color3, dimL: Color3, textR: string, colorR: Color3, dimR: Color3): (TextButton, TextButton)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -24, 0, 34)
	row.BackgroundTransparency = 1
	row.LayoutOrder = NextOrder()
	row.Parent = scroll

	local btnL = Instance.new("TextButton")
	btnL.Size = UDim2.new(0.48, 0, 1, 0)
	btnL.Position = UDim2.new(0, 0, 0, 0)
	btnL.BackgroundColor3 = colorL
	btnL.TextColor3 = C.TEXT
	btnL.Text = textL
	btnL.Font = Enum.Font.GothamBlack
	btnL.TextSize = 11
	btnL.AutoButtonColor = false
	btnL.Parent = row
	Instance.new("UICorner", btnL).CornerRadius = UDim.new(0, 8)
	local sL = Instance.new("UIStroke", btnL)
	sL.Color = dimL; sL.Thickness = 1.5

	local btnR = Instance.new("TextButton")
	btnR.Size = UDim2.new(0.48, 0, 1, 0)
	btnR.Position = UDim2.new(0.52, 0, 0, 0)
	btnR.BackgroundColor3 = colorR
	btnR.TextColor3 = C.TEXT
	btnR.Text = textR
	btnR.Font = Enum.Font.GothamBlack
	btnR.TextSize = 11
	btnR.AutoButtonColor = false
	btnR.Parent = row
	Instance.new("UICorner", btnR).CornerRadius = UDim.new(0, 8)
	local sR = Instance.new("UIStroke", btnR)
	sR.Color = dimR; sR.Thickness = 1.5

	return btnL, btnR
end

-- ========================================================================
-- PANEL ELEMENTS
-- ========================================================================

-- ─── TARGET ───
MakeSectionHeader("TARGET")
local inTarget = MakeInput("Player name (empty = self)")

-- ─── ECONOMY ───
MakeSectionHeader("ECONOMY")
local inCoins = MakeInput("Currency amount")
local btnCoinsAdd, btnCoinsRem = MakeDualButton(
	"＋ GIVE", C.SUCCESS, C.SUCCESS_DIM,
	"－ REMOVE", C.DANGER, C.DANGER_DIM
)
local inExp = MakeInput("EXP amount")
local btnExp = MakeButton("⚡ GIVE EXP", C.ACCENT, C.ACCENT_DIM)

-- ─── PROGRESSION ───
MakeSectionHeader("PROGRESSION")
local inLevel = MakeInput("Level (integer)")
local btnLevel = MakeButton("📊 SET LEVEL", C.ACCENT, C.ACCENT_DIM)
local inRebirth = MakeInput("Rebirth level")
local btnRebirth = MakeButton("⚡ SET REBIRTH", C.ACCENT, C.ACCENT_DIM)

-- ─── ITEMS & EFFECTS ───
MakeSectionHeader("ITEMS & EFFECTS")
local inItem = MakeInput("Item / Potion ID")
local inItemQty = MakeInput("Quantity (default 1)")
local btnItem = MakeButton("🎁 GIVE ITEM", C.ACCENT, C.ACCENT_DIM)
local inAura = MakeInput("Effect ID")
local btnAura = MakeButton("✨ GIVE EFFECT", C.ACCENT, C.ACCENT_DIM)

-- ─── WORLD ───
MakeSectionHeader("WORLD")
local inSpeed = MakeInput("WalkSpeed (16 = default)")
local btnSpeed = MakeButton("🏃 SET SPEED", C.ACCENT, C.ACCENT_DIM)

-- ─── DANGER ZONE ───
MakeSectionHeader("DANGER ZONE")
local btnReset = MakeButton("💀 RESET (KEEP PAID)", C.DANGER, C.DANGER_DIM)

-- ========================================================================
-- TOGGLE LOGIC
-- ========================================================================
local function TogglePanel()
	panelOpen = not panelOpen
	if panelOpen then
		panel.Visible = true
		TweenService:Create(panel, TweenInfo.new(ANIM_SPEED, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = onScreenPos
		}):Play()
	else
		local tween = TweenService:Create(panel, TweenInfo.new(ANIM_SPEED, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
			Position = offScreenPos
		})
		tween:Play()
		tween.Completed:Connect(function()
			if not panelOpen then panel.Visible = false end
		end)
	end
end

toggleBtn.MouseButton1Click:Connect(TogglePanel)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F2 then
		TogglePanel()
	end
end)

-- ========================================================================
-- REMOTE INTERACTION
-- ========================================================================
local remote = AdminRemote :: RemoteEvent

local function Send(action: string, ...)
	remote:FireServer(action, ...)
end

-- Feedback from server
remote.OnClientEvent:Connect(function(action: string, success: boolean, message: string)
	local prefix = success and "✓ " or "✗ "
	console.Text = " " .. prefix .. string.upper(tostring(message))
	console.TextColor3 = success and C.SUCCESS or C.DANGER

	-- Flash animation
	local origBg = console.BackgroundColor3
	console.BackgroundColor3 = success and Color3.fromRGB(0, 30, 15) or Color3.fromRGB(40, 5, 5)
	TweenService:Create(console, TweenInfo.new(0.6), { BackgroundColor3 = origBg }):Play()

	-- Auto-reset after 4s
	task.delay(4, function()
		if console.Text == " " .. prefix .. string.upper(tostring(message)) then
			TweenService:Create(console, TweenInfo.new(0.3), { TextColor3 = C.TEXT_DIM }):Play()
		end
	end)
end)

-- ========================================================================
-- AUTOCOMPLETE SYSTEM
-- ========================================================================
local function SetupAutocomplete(textBox: TextBox, getSuggestions: () -> {string})
	local overlay: ScrollingFrame? = nil

	local function clearOverlay()
		if overlay then
			overlay:Destroy()
			overlay = nil
		end
	end

	local function showSuggestions(filterText: string)
		clearOverlay()

		local allSuggestions = getSuggestions()
		local matches = {}
		local filterLower = string.lower(filterText)

		for _, s in ipairs(allSuggestions) do
			if string.find(string.lower(s), filterLower, 1, true) then
				table.insert(matches, s)
			end
		end

		if #matches == 0 then
			return
		end

		local displayedMatches = {}
		for i = 1, math.min(#matches, 6) do
			table.insert(displayedMatches, matches[i])
		end

		overlay = Instance.new("ScrollingFrame")
		local currentOverlay = overlay :: ScrollingFrame
		currentOverlay.Name = "AutocompleteOverlay"
		currentOverlay.Size = UDim2.new(1, 0, 0, math.min(120, #displayedMatches * 26))
		currentOverlay.Position = UDim2.new(0, 0, 1, 4)
		currentOverlay.BackgroundColor3 = C.SURFACE
		currentOverlay.BorderSizePixel = 0
		currentOverlay.ZIndex = 100
		currentOverlay.ScrollBarThickness = 3
		currentOverlay.ScrollBarImageColor3 = C.ACCENT_DIM
		currentOverlay.CanvasSize = UDim2.new(0, 0, 0, #displayedMatches * 26)
		currentOverlay.Parent = textBox

		Instance.new("UICorner", currentOverlay).CornerRadius = UDim.new(0, 6)
		local stroke = Instance.new("UIStroke", currentOverlay)
		stroke.Color = C.BORDER
		stroke.Thickness = 1

		local list = Instance.new("UIListLayout", currentOverlay)
		list.SortOrder = Enum.SortOrder.LayoutOrder

		for i, name in ipairs(displayedMatches) do
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, 0, 0, 26)
			btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			btn.BackgroundTransparency = 1
			btn.Text = name
			btn.TextColor3 = C.TEXT
			btn.Font = Enum.Font.GothamMedium
			btn.TextSize = 11
			btn.TextXAlignment = Enum.TextXAlignment.Left
			btn.AutoButtonColor = false
			btn.ZIndex = 101
			btn.LayoutOrder = i
			btn.Parent = currentOverlay

			local padding = Instance.new("UIPadding", btn)
			padding.PaddingLeft = UDim.new(0, 8)

			btn.MouseEnter:Connect(function()
				btn.BackgroundTransparency = 0.8
				btn.BackgroundColor3 = C.ACCENT
				btn.TextColor3 = Color3.fromRGB(0, 0, 0)
			end)
			btn.MouseLeave:Connect(function()
				btn.BackgroundTransparency = 1
				btn.TextColor3 = C.TEXT
			end)

			btn.MouseButton1Down:Connect(function()
				textBox.Text = name
				clearOverlay()
				textBox:ReleaseFocus()
			end)
		end
	end

	textBox.Focused:Connect(function()
		textBox.ZIndex = 50
		showSuggestions(textBox.Text)
	end)

	textBox.FocusLost:Connect(function()
		task.delay(0.15, function()
			clearOverlay()
			textBox.ZIndex = 1
		end)
	end)

	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		if textBox:IsFocused() then
			showSuggestions(textBox.Text)
		end
	end)
end

local function getPlayerSuggestions(): {string}
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(list, p.Name)
	end
	return list
end

local function getItemSuggestions(): {string}
	local list = {}
	for id, _ in pairs(ItemRegistry.Potions) do
		table.insert(list, id)
	end
	table.sort(list)
	return list
end

local function getEffectSuggestions(): {string}
	local list = {}
	local seen: {[string]: boolean} = {}
	for _, biome in pairs(AuraRegistry.Biomes) do
		for _, aura in ipairs(biome.Auras) do
			if not seen[aura.Id] then
				seen[aura.Id] = true
				table.insert(list, aura.Id)
			end
		end
	end
	table.sort(list)
	return list
end

SetupAutocomplete(inTarget, getPlayerSuggestions)
SetupAutocomplete(inItem, getItemSuggestions)
SetupAutocomplete(inAura, getEffectSuggestions)

-- ── Button Handlers ──
local target = function(): string return inTarget.Text end

btnCoinsAdd.MouseButton1Click:Connect(function()
	Send("give_currency", "Primary", inCoins.Text, target())
end)

btnCoinsRem.MouseButton1Click:Connect(function()
	local val = tonumber(inCoins.Text)
	if val then Send("give_currency", "Primary", -val, target()) end
end)



btnExp.MouseButton1Click:Connect(function()
	Send("give_exp", inExp.Text, target())
end)

btnLevel.MouseButton1Click:Connect(function()
	Send("set_level", inLevel.Text, target())
end)

btnRebirth.MouseButton1Click:Connect(function()
    Send("set_rebirth", inRebirth.Text, target())
end)

btnItem.MouseButton1Click:Connect(function()
	local qty = tonumber(inItemQty.Text) or 1
	Send("give_item", inItem.Text, qty, target())
end)

btnAura.MouseButton1Click:Connect(function()
	Send("give_effect", inAura.Text, target())
end)

btnSpeed.MouseButton1Click:Connect(function()
	Send("set_speed", inSpeed.Text, target())
end)

-- Reset requires double-click confirmation within 2 seconds
local resetPendingConfirm = false
btnReset.MouseButton1Click:Connect(function()
	if not resetPendingConfirm then
		resetPendingConfirm = true
		btnReset.Text = "⚠ CONFIRM RESET?"
		btnReset.BackgroundColor3 = Color3.fromRGB(200, 120, 0)
		task.delay(2.5, function()
			if resetPendingConfirm then
				resetPendingConfirm = false
				btnReset.Text = "💀 RESET (KEEP PAID)"
				btnReset.BackgroundColor3 = C.DANGER
			end
		end)
	else
		resetPendingConfirm = false
		btnReset.Text = "💀 RESET (KEEP PAID)"
		btnReset.BackgroundColor3 = C.DANGER
		Send("reset_player", target())
	end
end)


