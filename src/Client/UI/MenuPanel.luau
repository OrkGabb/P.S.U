--!strict
--@author OrkGabb
--@module MenuPanel.luau
--@version 1.0
-- Single factory for the standard menu panel scaffold. Owns everything every
-- panel used to copy-paste: ScreenGui + click-outside shield, centered frame
-- with UIScale, spiral open/close with the animGen race guard, viewport
-- autoscale, the shared close button, the Toggle<Id> event wiring, the
-- NotifyMenuOpened/Closed handshake, and (optionally) the sidebar/floating
-- HUD button.
--
-- A menu controller builds only its content, into handle.Panel:
--
--   local menu = MenuPanel.Create({
--       Id = "Skills",
--       Title = "MASTERY UPGRADES",
--       Size = Vector2.new(460, 420),
--       OnOpen = RefreshUI,
--       Button = { Name = "SKILLS", IconId = "Skills", Type = "Sidebar", LayoutOrder = 2 },
--   })
--   buildCards(menu.Panel)
--
-- Resilience contract: the panel works even when UIController is missing
-- (the HUD button is skipped with a warning; the Toggle<Id> event and any
-- hotkey still open the menu). Deleting a menu controller only leaves its
-- Toggle event without a listener — no other module breaks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UIHelpers = require(script.Parent.UIHelpers)
local UITheme = require(script.Parent.UITheme)
local UIEvents = require(script.Parent.UIEvents)
local UIAssetPacks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("UIAssetPacks"))

local LocalPlayer = Players.LocalPlayer

-- Panel band: resting/closing panels render at REST, the opening panel jumps
-- to OPEN so it paints above the outgoing panel during a switch.
local DISPLAY_ORDER_REST = 60
local DISPLAY_ORDER_OPEN = 61

export type MenuButtonConfig = {
	Name: string?,
	IconId: string,
	Type: "Sidebar" | "Floating" | "TopRight",
	LayoutOrder: number?,
}

export type MenuPanelConfig = {
	Id: string,
	Title: string?,
	Size: Vector2?,             -- design size in px (default 460x420); autoscaled to fit the viewport
	ClipsDescendants: boolean?,
	Hotkey: Enum.KeyCode?,
	OnOpen: (() -> ())?,        -- runs right before the open animation (refresh hooks)
	OnClose: (() -> ())?,
	Button: MenuButtonConfig?,  -- omit for panels without their own HUD button
}

export type MenuPanelHandle = {
	Gui: ScreenGui,
	Panel: Frame,
	Assets: UIAssetPacks.UIAssetPack,
	IsOpen: () -> boolean,
	Open: () -> (),
	Close: (reason: string?) -> (),
	Toggle: (reason: string?) -> (),
	SetButtonNotification: (active: boolean, text: string?) -> (),
}

local MenuPanel = {}

--- Registers the HUD button through UIController when it is available.
--- Degrades to nil (menu still reachable via Toggle event / hotkey) when it
--- is not — a deleted UIController must never hang or break a menu.
local function registerHUDButton(config: MenuPanelConfig, onClick: () -> ()): any?
	local button = config.Button
	if not button then
		return nil
	end

	local ok, handle = pcall(function(): any
		local FrameworkClient = require(script.Parent.Parent.Core.FrameworkClient) :: any
		local ui = FrameworkClient.GetController("UIController")
		return ui.RegisterHUDButton({
			Id = config.Id,
			Name = button.Name,
			IconId = button.IconId,
			Type = button.Type,
			LayoutOrder = button.LayoutOrder,
			OnClick = onClick,
		})
	end)

	if ok and type(handle) == "table" then
		return handle
	end
	warn(("[MenuPanel] HUD button for %q unavailable (%s) — menu still opens via Toggle%s event.")
		:format(config.Id, tostring(handle), config.Id))
	return nil
end

function MenuPanel.Create(config: MenuPanelConfig): MenuPanelHandle
	local designSize: Vector2 = config.Size or Vector2.new(460, 420)
	local assets = UIAssetPacks.For(config.Id)
	local theme: { [string]: any } = (assets :: any).Theme or {}

	local isOpen = false
	-- Generation counter: bumped on every open/close transition so a stale
	-- Tween.Completed handler from an interrupted animation can detect it lost
	-- ownership and must not touch panel state.
	local animGen = 0
	local targetScale = 1

	local gui = Instance.new("ScreenGui")
	gui.Name = config.Id .. "Gui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = DISPLAY_ORDER_REST
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local shield = Instance.new("TextButton")
	shield.Name = "InputSink"
	shield.Size = UDim2.fromScale(1, 1)
	shield.BackgroundTransparency = 1
	shield.Text = ""
	shield.AutoButtonColor = false
	shield.Visible = false
	shield.Active = true
	shield.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "MainPanel"
	panel.Size = UDim2.new(0, designSize.X, 0, designSize.Y)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = theme.PanelBackground or UITheme.PanelBackground
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ClipsDescendants = config.ClipsDescendants == true
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = panel

	local panelScale = Instance.new("UIScale")
	panelScale.Parent = panel
	UIHelpers.PrimeSpiral(panel, panelScale)

	if config.Title then
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0, 50)
		title.BackgroundTransparency = 1
		title.Text = config.Title
		title.Font = Enum.Font.FredokaOne
		title.TextSize = 22
		title.TextColor3 = theme.TitleText or UITheme.TitleText
		title.Parent = panel
	end

	-- Fit the design size to the viewport; retarget live while open so a
	-- window resize doesn't leave a mid-animation scale behind.
	local camera = workspace.CurrentCamera
	local function updateUIScale()
		if not camera then return end
		local view = camera.ViewportSize
		local scaleX = view.X / (designSize.X + 20)
		local scaleY = view.Y / (designSize.Y + 20)
		targetScale = math.clamp(math.min(scaleX, scaleY, 1), 0.5, 1.2)
		if isOpen then
			TweenService:Create(panelScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = targetScale}):Play()
		end
	end
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateUIScale)
	end
	updateUIScale()

	local function close(reason: string?)
		if not isOpen then return end
		isOpen = false
		animGen += 1
		local gen = animGen
		gui.DisplayOrder = DISPLAY_ORDER_REST
		shield.Visible = false
		if config.OnClose then
			config.OnClose()
		end
		UIEvents.Get("NotifyMenuClosed"):Fire(config.Id)
		local tw = UIHelpers.SpiralClose(panel, panelScale, reason)
		tw.Completed:Connect(function(state: Enum.PlaybackState)
			-- A reopen cancels this tween (Completed still fires, state=Cancelled)
			-- and bumps the generation; hide only if this close ran to completion
			-- and is still the latest transition.
			if gen ~= animGen then return end
			if state ~= Enum.PlaybackState.Completed then return end
			panel.Visible = false
		end)
	end

	local function open()
		if isOpen then return end
		isOpen = true
		animGen += 1
		gui.DisplayOrder = DISPLAY_ORDER_OPEN
		panel.Visible = true
		shield.Visible = true
		if config.OnOpen then
			config.OnOpen()
		end
		-- Retarget from the current scale/rotation (no reset to the resting
		-- pose) so reopening during a close animation continues smoothly
		-- instead of snapping shut first.
		UIHelpers.SpiralOpen(panel, panelScale, targetScale)
		UIEvents.Get("NotifyMenuOpened"):Fire(config.Id)
	end

	local function toggle(reason: string?)
		if isOpen then
			close(reason)
		else
			open()
		end
	end

	UIHelpers.CreateCloseButton(panel, close)
	shield.MouseButton1Up:Connect(function() close(nil) end)
	UIEvents.Get("Toggle" .. config.Id).Event:Connect(toggle)
	-- Cross-menu exclusion is owned centrally by UIController's
	-- NotifyMenuOpened handler, which fires Toggle<Id>("switch") at the
	-- currently open menu when another one opens.

	if config.Hotkey then
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then return end
			if input.KeyCode == config.Hotkey then
				toggle(nil)
			end
		end)
	end

	local buttonHandle = registerHUDButton(config, function() toggle(nil) end)

	return {
		Gui = gui,
		Panel = panel,
		Assets = assets,
		IsOpen = function() return isOpen end,
		Open = open,
		Close = close,
		Toggle = toggle,
		SetButtonNotification = function(active: boolean, text: string?)
			if buttonHandle then
				buttonHandle.SetNotificationActive(active, text)
			end
		end,
	}
end

return MenuPanel
