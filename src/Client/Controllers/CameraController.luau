--!strict
--@author OrkGabb
--@module CameraController.luau
--@version 1.0
-- src/Client/Controllers/CameraController.luau
-- Handles security camera monitoring seats (CCTV) with panning and UI overlays.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: Folder
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver")) :: any

local LocalPlayer = Players.LocalPlayer :: Player
local CameraController = {}

local isActive = false
local isInCams = false
local currentCamIndex = 1
local cameraZoneChildren: {Instance} = {}
local rotatedCFrame = CFrame.new()

local cameraGui: ScreenGui? = nil
local spotlightPart: Part? = nil
local spotlightInstance: SpotLight? = nil
local renderConnection: RBXScriptConnection? = nil
local seatedConnection: RBXScriptConnection? = nil
local charConnection: RBXScriptConnection? = nil

-- UI buttons connections
local nextConn: RBXScriptConnection? = nil
local prevConn: RBXScriptConnection? = nil

local function playCamAnimation(): ()
	if not cameraGui then return end
	local staticFrame = cameraGui:FindFirstChild("staticframe") :: Frame?
	if not staticFrame then return end

	staticFrame.BackgroundTransparency = 0
	TweenService:Create(
		staticFrame,
		TweenInfo.new(1),
		{ BackgroundTransparency = 0.8 }
	):Play()
end

local function setCharacterTransparency(char: Model, amount: number): ()
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = amount
		end
	end
end

local function cleanCams(): ()
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end

	if cameraGui then
		cameraGui.Enabled = false
	end

	local char = LocalPlayer.Character
	if char then
		setCharacterTransparency(char, 0)
	end

	if spotlightPart then
		spotlightPart.CFrame = CFrame.new(0, -1000, 0)
	end

	isInCams = false
	table.clear(cameraZoneChildren)
end

local function onSeated(seated: boolean, seat: Instance?): ()
	local camera = workspace.CurrentCamera
	local char = LocalPlayer.Character
	if not char or not camera then return end

	if seated and seat and seat.Parent and seat.Parent:HasTag("CameraSeat") then
		local zoneValue = seat.Parent:FindFirstChild("CameraZone") :: ObjectValue?
		local zone = zoneValue and zoneValue.Value :: Instance?
		if not zone then return end

		cameraZoneChildren = zone:GetChildren()
		if #cameraZoneChildren == 0 then return end

		currentCamIndex = 1
		camera.CameraType = Enum.CameraType.Scriptable
		
		if cameraGui then
			cameraGui.Enabled = true
			local openCamSound = cameraGui:FindFirstChild("OpenCam") :: Sound?
			if openCamSound then
				openCamSound:Play()
			end
			playCamAnimation()
		end

		setCharacterTransparency(char, 1)
		isInCams = true
	else
		cleanCams()
	end
end

local function setupCharacter(char: Model): ()
	if seatedConnection then
		seatedConnection:Disconnect()
		seatedConnection = nil
	end

	local humanoid = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		seatedConnection = humanoid.Seated:Connect(onSeated)
	end
end

function CameraController.Init(): ()
	local config = FeatureResolver.GetCategoryConfig("FPS_Shooter")
	if config and config.Enabled then
		isActive = true
	end
end

function CameraController.Start(): ()
	if not isActive then return end

	-- Find/wait for CameraGui in PlayerGui
	task.spawn(function(): ()
		local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
		cameraGui = playerGui:WaitForChild("CameraGui", 10) :: ScreenGui?
		if not cameraGui then return end

		-- Hook Next button
		local nextBtn = cameraGui:FindFirstChild("Next") :: ImageButton?
		if nextBtn then
			nextConn = nextBtn.MouseButton1Down:Connect(function(): ()
				if not isInCams or #cameraZoneChildren == 0 then return end
				local camSwitchSound = cameraGui and cameraGui:FindFirstChild("CameraSwitch") :: Sound?
				if camSwitchSound then camSwitchSound:Play() end
				playCamAnimation()

				currentCamIndex = if currentCamIndex < #cameraZoneChildren then currentCamIndex + 1 else 1
			end)
		end

		-- Hook Prev button
		local prevBtn = cameraGui:FindFirstChild("Prev") :: ImageButton?
		if prevBtn then
			prevConn = prevBtn.MouseButton1Down:Connect(function(): ()
				if not isInCams or #cameraZoneChildren == 0 then return end
				local camSwitchSound = cameraGui and cameraGui:FindFirstChild("CameraSwitch") :: Sound?
				if camSwitchSound then camSwitchSound:Play() end
				playCamAnimation()

				currentCamIndex = if currentCamIndex > 1 then currentCamIndex - 1 else #cameraZoneChildren
			end)
		end
	end)

	-- Create spotlight part in workspace
	local part = Instance.new("Part")
	part.Name = "CCTV_SpotlightPart"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 1
	part.CFrame = CFrame.new(0, -1000, 0)
	part.Parent = workspace
	spotlightPart = part

	local sl = Instance.new("SpotLight")
	sl.Angle = 65
	sl.Brightness = 0.5
	sl.Range = 60
	sl.Enabled = true
	sl.Parent = part
	spotlightInstance = sl

	-- Listen for characters
	charConnection = LocalPlayer.CharacterAdded:Connect(setupCharacter)
	if LocalPlayer.Character then
		setupCharacter(LocalPlayer.Character)
	end

	-- RenderStepped camera update
	renderConnection = RunService.RenderStepped:Connect(function(dt: number): ()
		if not isInCams or #cameraZoneChildren == 0 then return end
		local activeCamPart = cameraZoneChildren[currentCamIndex] :: BasePart?
		if not activeCamPart or not activeCamPart:IsA("BasePart") then return end

		local camera = workspace.CurrentCamera
		if not camera then return end

		local baseCFrame = activeCamPart.CFrame
		local mousePos = UserInputService:GetMouseLocation()
		local viewportSize = camera.ViewportSize
		local center = viewportSize / 2
		local offset = (mousePos - center) / center

		local maxAngle = math.rad(15)
		local yaw = math.clamp(-offset.X, -1, 1) * maxAngle
		local pitch = math.clamp(offset.Y, -1, 1) * maxAngle

		rotatedCFrame = rotatedCFrame:Lerp(CFrame.Angles(-pitch, yaw, 0), 0.065)
		camera.CFrame = baseCFrame * rotatedCFrame

		if cameraGui then
			local camNameLabel = cameraGui:FindFirstChild("CameraName") :: TextLabel?
			if camNameLabel then
				camNameLabel.Text = activeCamPart.Name
			end
		end

		local isFlashlightKey = UserInputService:IsKeyDown(Enum.KeyCode.F)
		local flashBtn = cameraGui and cameraGui:FindFirstChild("FlashLight") :: ImageButton?
		-- Check if mobile button is active (we can just assume keybind for safety)
		if isFlashlightKey then
			part.CFrame = camera.CFrame
		else
			part.CFrame = CFrame.new(0, -1000, 0)
		end
	end)
end

function CameraController.Destroy(): ()
	if renderConnection then renderConnection:Disconnect() end
	if seatedConnection then seatedConnection:Disconnect() end
	if charConnection then charConnection:Disconnect() end
	if nextConn then nextConn:Disconnect() end
	if prevConn then prevConn:Disconnect() end

	if spotlightPart then
		pcall(function(): () spotlightPart:Destroy() end)
	end
end

return CameraController
