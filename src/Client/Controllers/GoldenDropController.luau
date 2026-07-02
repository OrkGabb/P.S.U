--!strict
-- @Author @OrkGabb
-- src/Client/Controllers/GoldenDropController.luau
-- Clicker_Farm golden drop client: renders the falling clickable icon when the
-- server issues a GUID, echoes the GUID back on click, and shows the reward.
-- Pure I/O — the reward amount and validity are decided entirely server-side.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local AudioController = require(script.Parent.AudioController)

local LocalPlayer = Players.LocalPlayer

local GENRE_KEY = "Clicker_Farm"
local CLAIM_REMOTE_NAME = "GoldenDropClaim"

local GoldenDropController = {}

local SUFFIXES: {string} = {"", "k", "M", "B", "T", "Qd"}
local function Format(n: number): string
	if n < 1000 then return tostring(math.floor(n)) end
	local exp = math.floor(math.log10(n) / 3)
	return string.format("%.1f%s", n / (10 ^ (exp * 3)), SUFFIXES[exp + 1] or "inf"):gsub("%.0", "")
end

local function showRewardPopup(gui: ScreenGui, position: Vector2, amount: number, tier: string): ()
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 220, 0, 44)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromOffset(position.X, position.Y)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = "+" .. Format(amount)
	label.TextColor3 = Color3.fromRGB(255, 215, 60)
	-- Jackpot/Rare read bigger so the rare tiers feel special
	label.TextSize = if tier == "Jackpot" then 44 elseif tier == "Rare" then 36 else 30
	label.Parent = gui

	local stroke = Instance.new("UIStroke", label)
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(110, 70, 0)

	task.delay(0.8, function()
		local fade = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(label, fade, {
			TextTransparency = 1,
			Position = label.Position - UDim2.fromOffset(0, 60),
		}):Play()
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		task.delay(1.1, function()
			label:Destroy()
		end)
	end)
end

function GoldenDropController.Init(): ()
end

function GoldenDropController.Start(): ()
	if not FeatureResolver.IsCategoryActive(GENRE_KEY) then
		return
	end

	local dropCfg: any = FeatureResolver.GetConfigField(GENRE_KEY, "GoldenDrop", nil)
	if type(dropCfg) ~= "table" or dropCfg.Enabled ~= true then
		return
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local spawnRemote = remotes:WaitForChild(RemoteNames.GoldenDropSpawn) :: RemoteEvent
	local claimRemote = remotes:WaitForChild(CLAIM_REMOTE_NAME) :: RemoteFunction

	local gui = Instance.new("ScreenGui")
	gui.Name = "GoldenDropGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 90
	-- Keep the drop inside device safe areas (mobile notches, TV overscan)
	gui.ClipToDeviceSafeArea = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	-- Only one drop on screen at a time; a new spawn replaces a still-falling one
	local activeDrop: ImageButton? = nil

	spawnRemote.OnClientEvent:Connect(function(guid: string)
		if type(guid) ~= "string" then return end

		if activeDrop then
			activeDrop:Destroy()
			activeDrop = nil
		end

		local lane = math.random(15, 75) / 100

		local btn = Instance.new("ImageButton")
		btn.Name = "GoldenDrop"
		btn.Size = UDim2.fromScale(0.1, 0.1)
		btn.SizeConstraint = Enum.SizeConstraint.RelativeYY
		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Position = UDim2.fromScale(lane, -0.15)
		btn.BackgroundTransparency = 1
		btn.Image = dropCfg.ImageId or ""
		btn.ScaleType = Enum.ScaleType.Fit
		btn.Parent = gui
		activeDrop = btn

		local descent = TweenService:Create(
			btn,
			TweenInfo.new(dropCfg.DescentDuration or 10, Enum.EasingStyle.Linear),
			{ Position = UDim2.fromScale(lane, 1.15) }
		)

		local claimed = false
		btn.MouseButton1Click:Connect(function()
			if claimed then return end
			claimed = true

			local center = btn.AbsolutePosition + btn.AbsoluteSize / 2
			btn:Destroy()
			if activeDrop == btn then activeDrop = nil end

			local result = claimRemote:InvokeServer(guid)
			if type(result) == "table" and type(result.Amount) == "number" then
				AudioController.PlaySFX("GoldenClaim")
				showRewardPopup(gui, center, result.Amount, tostring(result.Tier))
			end
		end)

		descent.Completed:Connect(function()
			if btn.Parent then
				btn:Destroy()
			end
			if activeDrop == btn then activeDrop = nil end
		end)

		descent:Play()
	end)
end

return GoldenDropController
