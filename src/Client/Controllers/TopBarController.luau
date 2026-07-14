--!strict
--@author OrkGabb
--@module TopBarController.luau
--@version 2.0
-- src/Client/Controllers/TopBarController.luau
-- Sleek premium top-right HUD. Generic slot-renderer: draws every resource
-- HUDResourceRegistry tags for the "TopBar" slot, in registry-defined Order.
--
-- v2 REDESIGN: v1 hardcoded exactly two rows (Coins, Secondary currency).
-- Adding CoreFragments (Leva 4/5) the old way meant a third copy-pasted
-- row block per resource — brittle, and it means every future resource
-- needs a controller edit to appear anywhere. v2 reads
-- HUDResourceRegistry.GetResourcesForSlot("TopBar") and draws one row per
-- entry generically. Moving a resource to a different slot, or adding a
-- slot entirely, is now a registry data change — zero edits here.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local LocalPlayer = Players.LocalPlayer

local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local FeatureResolver = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("FeatureResolver"))
local HUDResourceRegistry = require(ReplicatedStorage.Shared.Config.HUDResourceRegistry)

local TopBarController = {}
local Container: Frame

-- Handles all scales. No "inf"/"Max" fallback — very large numbers use scientific notation.
-- NOTE: NumberValue (used for coin tweening) is a 64-bit double — no 2^31 IntValue cap here.
local function FormatNumber(n: number): string
	if not n or n ~= n then return "0" end
	n = math.floor(n)
	if n < 1000 then return tostring(n) end
	if n >= 1e21 then
		local exp = math.floor(math.log10(n))
		return string.format("%.1fe%d", n / (10 ^ exp), exp)
	end
	local tiers: { {Threshold: number, Suffix: string} } = {
		{Threshold = 1e18, Suffix = "Qi"}, {Threshold = 1e15, Suffix = "Qa"}, {Threshold = 1e12, Suffix = "T"},
		{Threshold = 1e9,  Suffix = "B"},  {Threshold = 1e6,  Suffix = "M"},  {Threshold = 1e3,  Suffix = "K"},
	}
	for _, tier in ipairs(tiers) do
		if n >= tier.Threshold then
			local formatted = string.format("%.1f", n / tier.Threshold):gsub("%.0$", "")
			return formatted .. tier.Suffix
		end
	end
	return tostring(n)
end

-- Per-resource render state: label ref + tween bookkeeping, keyed by
-- HUDResourceRegistry resource Id. Replaces the old two hardcoded locals
-- (CoinLabel / SecondaryLabel) with a generic map sized to however many
-- resources the registry currently tags for "TopBar".
type RowState = {
	Label: TextLabel,
	CurrentValue: number,
	ValObj: NumberValue?,
	TweenConn: RBXScriptConnection?,
	Tween: Tween?,
}
local rows: { [string]: RowState } = {}

local function TweenRow(resourceId: string, targetVal: number): ()
	local row = rows[resourceId]
	if not row then return end
	if targetVal == row.CurrentValue and row.ValObj == nil then return end

	local startVal = row.CurrentValue
	if row.ValObj then startVal = row.ValObj.Value end

	if row.Tween then row.Tween:Cancel() end
	if row.TweenConn then row.TweenConn:Disconnect() end
	if row.ValObj then row.ValObj:Destroy() end

	local valObj = Instance.new("NumberValue")
	valObj.Value = startVal
	row.ValObj = valObj
	row.TweenConn = valObj.Changed:Connect(function()
		row.Label.Text = FormatNumber(valObj.Value)
	end)

	local thisTween = TweenService:Create(valObj, TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {Value = targetVal})
	row.Tween = thisTween
	thisTween:Play()
	thisTween.Completed:Connect(function(playbackState)
		if row.Tween == thisTween then
			if row.ValObj then
				row.ValObj:Destroy()
				row.ValObj = nil
			end
			if row.TweenConn then
				row.TweenConn:Disconnect()
				row.TweenConn = nil
			end
			row.Tween = nil
			if playbackState == Enum.PlaybackState.Completed then
				row.Label.Text = FormatNumber(targetVal)
			end
		end
	end)
	row.CurrentValue = targetVal
end

-- Fires on every UpdateProfileData push. Walks the registry's TopBar
-- resources and, for each one whose DataPath resolves on this payload,
-- tweens its row. Resources with no matching data are simply skipped —
-- e.g. a genre that doesn't populate Stats.CoreFragments yet.
local function UpdateProfile(data: any): ()
	if not data then return end
	for _, def in ipairs(HUDResourceRegistry.GetResourcesForSlot("TopBar")) do
		local value = HUDResourceRegistry.ReadValue(def, data)
		if value ~= nil and rows[def.Id] then
			TweenRow(def.Id, value)
		end
	end
end

local function PathsMatch(a: {string}, b: {string}): boolean
	if #a ~= #b then return false end
	for i, seg in ipairs(a) do
		if seg ~= b[i] then return false end
	end
	return true
end

-- Fires on every UpdateResourceValue push — a single-resource delta from a
-- high-frequency source (clicks, golden drops, passive income) that doesn't
-- warrant a full UpdateProfileData snapshot. Matches by DataPath so any
-- resource the registry knows about (not just currencies) benefits without a
-- controller change — see HUDResourceRegistry's own "config, not logic" note.
local function UpdateResource(path: {string}, value: number): ()
	if type(value) ~= "number" then return end
	for _, def in ipairs(HUDResourceRegistry.GetResourcesForSlot("TopBar")) do
		if rows[def.Id] and PathsMatch(def.DataPath, path) then
			TweenRow(def.Id, value)
		end
	end
end

local function BuildRow(def: HUDResourceRegistry.ResourceDef, layoutOrder: number): ()
	local row = Instance.new("Frame")
	row.Name = def.Id .. "Row"
	row.Size = UDim2.new(1, 0, 0, 20)
	row.BackgroundTransparency = 1
	row.LayoutOrder = layoutOrder
	row.Parent = Container

	local icon = Instance.new("ImageLabel")
	icon.Name = def.Id .. "Icon"
	icon.Size = UDim2.new(0, 17, 0, 17)
	icon.Position = UDim2.new(0, 0, 0.5, -8)
	icon.BackgroundTransparency = 1
	icon.Image = (AssetRegistry.UI :: any)[def.IconId] or ""
	icon.ImageColor3 = def.Color
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = row

	local label = Instance.new("TextLabel")
	label.Name = def.Id .. "Value"
	label.Size = UDim2.new(1, -21, 1, 0)
	label.Position = UDim2.new(0, 21, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = "0"
	label.TextColor3 = def.Color
	label.Font = Enum.Font.GothamBold
	label.TextSize = 10
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = row

	rows[def.Id] = { Label = label, CurrentValue = 0, ValObj = nil, TweenConn = nil, Tween = nil }
end

function TopBarController.Init(): () end

function TopBarController.Start(): ()
	local activeCats = FeatureResolver.GetActiveCategories()
	local hasActiveGenre = false
	for _, cat in ipairs(activeCats) do
		if cat ~= "Global" then
			hasActiveGenre = true
			break
		end
	end

	local isFPS = FeatureResolver.IsCategoryActive("FPS_Shooter")
	if not hasActiveGenre or isFPS then
		print("[TopBarController] Fallback/FPS mode active: hiding top-right resource display.")
		return
	end

	local slotResources = HUDResourceRegistry.GetResourcesForSlot("TopBar")
	local visibleResources: { HUDResourceRegistry.ResourceDef } = {}
	for _, def in ipairs(slotResources) do
		if not (def.HideOnFPS and isFPS) then
			table.insert(visibleResources, def)
		end
	end
	if #visibleResources == 0 then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "TopBarGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = LocalPlayer.PlayerGui

	Container = Instance.new("Frame")
	Container.Name = "HUDDisplay"
	Container.Size = UDim2.new(0, 126, 0, 20 * #visibleResources + 8 + 4 * (#visibleResources - 1))
	Container.Position = UDim2.new(1, -14, 0, 10)
	Container.AnchorPoint = Vector2.new(1, 0)
	Container.BackgroundColor3 = Color3.fromRGB(15, 10, 25)
	Container.BackgroundTransparency = 0.35
	Container.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = Container

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 60, 120)
	stroke.Thickness = 1.8
	stroke.Transparency = 0.2
	stroke.Parent = Container

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = Container

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = Container

	for i, def in ipairs(visibleResources) do
		BuildRow(def, i)
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local updateData: RemoteEvent? = remotes:WaitForChild(RemoteNames.UpdateProfileData, 5) :: any
	if updateData then
		updateData.OnClientEvent:Connect(UpdateProfile)
	else
		warn("[TopBarController] UpdateProfileData remote not found after 5s timeout.")
	end

	-- High-frequency single-resource deltas (clicks, golden drops, passive
	-- income) — additive to UpdateProfileData, not a replacement. Full syncs
	-- (load, purchases, upgrades) still drive UpdateProfile as before.
	local updateResource: RemoteEvent? = remotes:WaitForChild(RemoteNames.UpdateResourceValue, 5) :: any
	if updateResource then
		updateResource.OnClientEvent:Connect(UpdateResource)
	else
		warn("[TopBarController] UpdateResourceValue remote not found after 5s timeout.")
	end

	-- Initial values arrive on the first UpdateProfileData push (DataService
	-- fires SyncFullState right after load) — no separate leaderstats read
	-- needed now that every TopBar resource goes through the same registry
	-- + payload path.
end

return TopBarController
