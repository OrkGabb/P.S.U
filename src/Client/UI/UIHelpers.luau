--!strict
--@author OrkGabb
--@module UIHelpers.luau
--@version 1.0
-- src/Client/UI/UIHelpers.luau
-- Shared UI chrome factories for panel controllers.
--
-- BagController's close button is intentionally NOT covered here: it uses a
-- transparent background + ImageLabel icon + color-only hover tween, a
-- different visual pattern from the other nine panels' red X button. Not
-- yet consolidated -- needs its own design decision if unification is wanted.

local TweenService = game:GetService("TweenService")

local UIHelpers = {}

local SIZE = UDim2.new(0, 36, 0, 36)
local HOVER_SIZE = UDim2.new(0, 38, 0, 38)
local PRESS_SIZE = UDim2.new(0, 32, 0, 32)
local INSET = 10

local IDLE_COLOR = Color3.fromRGB(220, 50, 50)
local HOVER_COLOR = Color3.fromRGB(255, 70, 70)
local STROKE_COLOR = Color3.fromRGB(120, 20, 20)

local CLICK_TWEEN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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
	closeBtn.BackgroundColor3 = IDLE_COLOR
	closeBtn.BackgroundTransparency = 0
	closeBtn.Parent = parent

	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

	local stroke = Instance.new("UIStroke", closeBtn)
	stroke.Color = STROKE_COLOR
	stroke.Thickness = 2

	local cIcon = closeBtn:FindFirstChild("HD_Icon")
	if cIcon then cIcon:Destroy() end

	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, CLICK_TWEEN_INFO, {Size = HOVER_SIZE, BackgroundColor3 = HOVER_COLOR}):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, CLICK_TWEEN_INFO, {Size = SIZE, BackgroundColor3 = IDLE_COLOR}):Play()
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
