--!strict
--@author OrkGabb
--@module ClickController.luau
--@version 1.0
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local FeatureResolver: any = require(ReplicatedStorage.Shared.Modules.FeatureResolver)
local AudioController = require(script.Parent.AudioController)
local UpgradeRegistry = require(ReplicatedStorage.Shared.Modules.UpgradeRegistry)

local ClickController = {}

type PoolSlot = {
	Label:    TextLabel,
	Stroke:   UIStroke,
	time:     number,
	startX:   number,
	startY:   number,
	endX:     number,
	endY:     number,
	dead:     boolean,
}

local TEXT_POOL_SIZE = 80 -- Increased to support massive cascades without recycling too early
local pool: {PoolSlot} = {}
local poolIndex = 1
local aliveCount = 0

local lastClick      = 0
local showFloatingText = true
local cachedClickText = "+💰" -- Updated dynamically

local os_clock: () -> number = os.clock
local math_sin: (number) -> number = math.sin
local math_max: (number, number) -> number = math.max
local math_pi: number = math.pi

-- Tuning comes from the genre config (SSoT); these are safe fallbacks only.
local BATCH_INTERVAL: number = FeatureResolver.GetConfigField("Clicker_Farm", "ClickBatchInterval", 0.25)
local CLIENT_CPS_LIMIT: number = FeatureResolver.GetConfigField("Clicker_Farm", "ClientClickCooldown", 0.05)
local pendingClicks: number = 0
local lastSentBatch: number = 0
local lastBatchFire: number = 0
local clickRewardRemote: RemoteEvent

local SUFFIXES: {string} = {"", "k", "M", "B", "T", "Qd"}
local function Format(n: number): string
	if n < 1000 then return tostring(math.floor(n)) end
	local exp = math.floor(math.log10(n) / 3)
	return (string.format("%.1f%s", n / (10 ^ (exp * 3)), SUFFIXES[exp + 1] or "inf"):gsub("%.0", ""))
end

local function GetLocalEvent(eventName: string): BindableEvent
	local folder = ReplicatedStorage:FindFirstChild("LocalEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LocalEvents"
		folder.Parent = ReplicatedStorage
	end
	local event = folder:FindFirstChild(eventName)
	if not event then
		event = Instance.new("BindableEvent")
		event.Name = eventName
		event.Parent = folder
	end
	return event :: BindableEvent
end

local function PlayClickSound(): ()
	AudioController.PlaySFX("Click")
end

local function SpawnParticle(mouseLoc: Vector2): ()
	if not showFloatingText then return end
	
	poolIndex = (poolIndex % TEXT_POOL_SIZE) + 1
	local slot = pool[poolIndex]

	local offsetX: number = math.random(-70, 70)
	local offsetY: number = math.random(-40, 0)

	slot.startX   = mouseLoc.X - 50
	slot.startY   = mouseLoc.Y - 50
	slot.endX     = mouseLoc.X - 50 + offsetX
	slot.endY     = mouseLoc.Y - 150 + offsetY
	slot.time     = 0
	
	if slot.dead then
		aliveCount += 1
		slot.dead = false
	end

	slot.Label.Text             = cachedClickText
	slot.Label.Position         = UDim2.fromOffset(slot.startX, slot.startY)
	slot.Label.TextTransparency = 0
	slot.Label.TextSize         = 34
	slot.Label.Visible          = true
	slot.Stroke.Transparency    = 0
end

local function onHeartbeat(): ()
	if pendingClicks <= 0 then return end
	local now: number = os_clock()
	if now - lastBatchFire < BATCH_INTERVAL then return end
	lastBatchFire = now

	lastSentBatch = pendingClicks
	pendingClicks = 0
	if clickRewardRemote then
		clickRewardRemote:FireServer(lastSentBatch)
	end
end

local function onRenderStepped(dt: number): ()
	if aliveCount == 0 then return end

	local alive: number = 0
	for i = 1, TEXT_POOL_SIZE do
		local slot = pool[i]
		if not slot.dead then
			slot.time += dt
			local alpha: number = slot.time / 0.5

			if alpha >= 1 then
				slot.dead = true
				slot.Label.Visible = false
			else
				alive += 1
				local ease: number = 1 - (1 - alpha) * (1 - alpha)
				local px: number = slot.startX + (slot.endX - slot.startX) * ease
				local py: number = slot.startY + (slot.endY - slot.startY) * ease
				slot.Label.Position = UDim2.fromOffset(px, py)
				slot.Label.TextTransparency = ease
				slot.Stroke.Transparency = ease
				slot.Label.TextSize = 34 + (math_sin(alpha * math_pi) * 8)
			end
		end
	end
	aliveCount = alive
end

function ClickController.Init(): () end

function ClickController.Start(): ()
	if not FeatureResolver.IsCategoryActive("Clicker_Farm") then
		return
	end

	-- Dedicated ScreenGui so particles don't force layout updates on the MainInterface
	local particleGui = Instance.new("ScreenGui")
	particleGui.Name = "ClickParticleGui"
	particleGui.IgnoreGuiInset = true
	particleGui.DisplayOrder = 100
	particleGui.Parent = LocalPlayer.PlayerGui

	for i = 1, TEXT_POOL_SIZE do
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0, 100, 0, 30)
		label.BackgroundTransparency = 1
		label.Visible = false
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromRGB(255, 210, 40)
		label.TextSize = 34
		label.Parent = particleGui

		local stroke = Instance.new("UIStroke", label)
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(120, 60, 0)

		pool[i] = {
			Label    = label,
			Stroke   = stroke,
			time     = 0,
			startX   = 0,
			startY   = 0,
			endX     = 0,
			endY     = 0,
			dead     = true,
		}
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then

			local now: number = os_clock()
			if now - lastClick < CLIENT_CPS_LIMIT then return end
			lastClick = now

			PlayClickSound()
			pendingClicks += 1
			
			SpawnParticle(UserInputService:GetMouseLocation())
		end
	end)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	clickRewardRemote = remotes:WaitForChild(RemoteNames.ClickReward) :: RemoteEvent

	RunService.Heartbeat:Connect(onHeartbeat)

	-- Floating text mirrors the server's click power; both sides derive it
	-- from UpgradeRegistry.ComputeStat, so they agree.
	task.spawn(function()
		local updateData = remotes:WaitForChild(RemoteNames.UpdateProfileData) :: RemoteEvent
		updateData.OnClientEvent:Connect(function(data)
			if data and type(data.Upgrades) == "table" then
				local perClick = 1 + UpgradeRegistry.ComputeStat(data.Upgrades, "PerClick")
				cachedClickText = "+" .. Format(math_max(1, perClick))
			end
		end)
	end)

	GetLocalEvent("ToggleFloatingText").Event:Connect(function(state: boolean)
		showFloatingText = state
		if not state then
			for i = 1, TEXT_POOL_SIZE do
				pool[i].dead = true
				pool[i].Label.Visible = false
			end
			aliveCount = 0
		end
	end)

	RunService.RenderStepped:Connect(onRenderStepped)
end

return ClickController
