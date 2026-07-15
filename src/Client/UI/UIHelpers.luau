--!strict
--@author OrkGabb
--@module UIHelpers.luau
--@version 1.0
-- Shared UI chrome factories for panel controllers.
--
-- BagController's close button is intentionally NOT covered here: it uses a
-- transparent background + ImageLabel icon + color-only hover tween, a
-- different visual pattern from the other nine panels' red X button. Not
-- yet consolidated -- needs its own design decision if unification is wanted.

local TweenService = game:GetService("TweenService")

local UITheme = require(script.Parent.UITheme)

local UIHelpers = {}

local SIZE = UDim2.new(0, 36, 0, 36)
local HOVER_SIZE = UDim2.new(0, 38, 0, 38)
local PRESS_SIZE = UDim2.new(0, 32, 0, 32)
local INSET = 10

local CLICK_TWEEN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Spiral open/close: panels rest at SPIRAL_REST_ROTATION with Scale 0 and unwind to (0deg, target)
-- on open. Rest rotation is the same angle for open and close, so a toggle that
-- interrupts a running transition just retargets from wherever the panel
-- currently is instead of snapping.

local SPIRAL_REST_ROTATION: number = -140

local SPIRAL_OPEN_INFO = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SPIRAL_CLOSE_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In)
-- A switch-triggered close (another panel is taking over) uses a fast, flat
-- easing so the outgoing panel gets out of the way quickly.
local SPIRAL_SWITCH_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--- Puts `panel` in its closed resting pose. Call once at construction, after
--- the panel's UIScale exists.
function UIHelpers.PrimeSpiral(panel: GuiObject, scale: UIScale): ()
	panel.Rotation = SPIRAL_REST_ROTATION
	scale.Scale = 0
end

--- Spirals `panel` open to `targetScale` (the viewport-fit scale the caller
--- already computes). Does not touch Visible — the caller owns that.
function UIHelpers.SpiralOpen(panel: GuiObject, scale: UIScale, targetScale: number): ()
	TweenService:Create(panel, SPIRAL_OPEN_INFO, {Rotation = 0}):Play()
	TweenService:Create(scale, SPIRAL_OPEN_INFO, {Scale = targetScale}):Play()
end

--- Spirals `panel` shut. Returns the scale tween so the caller can hook
--- Completed for its own generation-guarded Visible = false.
function UIHelpers.SpiralClose(panel: GuiObject, scale: UIScale, reason: string?): Tween
	local info: TweenInfo = if reason == "switch" then SPIRAL_SWITCH_INFO else SPIRAL_CLOSE_INFO
	TweenService:Create(panel, info, {Rotation = SPIRAL_REST_ROTATION}):Play()
	local scaleTween = TweenService:Create(scale, info, {Scale = 0})
	scaleTween:Play()
	return scaleTween
end

--- Builds the standardized 36x36 panel close button (10px inset, top-right
--- anchored) with the hover/press/release tween from the Fitts's Law pass,
--- and wires MouseButton1Up to `onClose`. `onClose` is invoked with a nil
--- reason for a direct click; callers still invoke it themselves with an
--- explicit reason (e.g. "switch") from other close paths.
function UIHelpers.CreateCloseButton(parent: Instance, onClose: (reason: string?) -> ()): TextButton
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = SIZE
	closeBtn.Position = UDim2.new(1, -INSET, 0, INSET)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.AutoButtonColor = false
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.BackgroundColor3 = UITheme.DangerIdle
	closeBtn.BackgroundTransparency = 0
	closeBtn.Parent = parent

	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

	local stroke = Instance.new("UIStroke", closeBtn)
	stroke.Color = UITheme.DangerStroke
	stroke.Thickness = 2

	local cIcon = closeBtn:FindFirstChild("HD_Icon")
	if cIcon then cIcon:Destroy() end

	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, CLICK_TWEEN_INFO, {Size = HOVER_SIZE, BackgroundColor3 = UITheme.DangerHover}):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, CLICK_TWEEN_INFO, {Size = SIZE, BackgroundColor3 = UITheme.DangerIdle}):Play()
	end)
	closeBtn.MouseButton1Down:Connect(function()
		TweenService:Create(closeBtn, CLICK_TWEEN_INFO, {Size = PRESS_SIZE}):Play()
	end)
	closeBtn.MouseButton1Up:Connect(function()
		TweenService:Create(closeBtn, CLICK_TWEEN_INFO, {Size = HOVER_SIZE}):Play()
	end)
	closeBtn.MouseButton1Up:Connect(function()
		onClose(nil)
	end)

	return closeBtn
end

return UIHelpers
