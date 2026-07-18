--!strict
--@author OrkGabb
-- Pet_Simulator UI: egg shop (hatch buttons with visible odds — resolved
-- from the SAME engine the server hatches with) and the pet inventory with
-- equip/unequip controls, plus the hatch-reveal popup.
--
-- Data flows:
--   • PetRegistry (shared) — egg defs, pet defs, rarity styling, hatch odds
--   • HatchRequest / HatchResult (remotes) — server-validated hatches
--   • UpdatePetInventory (remote) — owned-pet counts + equipped id
--   • PetEquipRequest (remote) + "EquippedPet" attribute — equip state
--   • AudioRegistry — hatch-reveal stinger

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local PetRegistry = require(ReplicatedStorage.Shared.Modules.PetRegistry)
local AudioRegistry = require(ReplicatedStorage.Shared.Config.AudioRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)
local PSUTypes = require(ReplicatedStorage.Shared.Types.PSUTypes)
local UIHelpers = require(script.Parent.Parent.UI.UIHelpers)

local GENRE_KEY = "Pet_Simulator"

local PetsUIController = {}

local MainPanel: Frame
local EggList: ScrollingFrame
local InventoryGrid: ScrollingFrame
local PanelScale: UIScale
local BgShield: TextButton
local isOpen = false
-- Bumped on every open/close transition; stale animation callbacks compare
-- against it and stand down if a newer transition has taken over.
local animGen = 0
local inventoryCache: {[string]: number} = {}
local currentEquippedId = "None"
local playerLevel = 1

-- Helpers

local GetLocalEvent = require(script.Parent.Parent.UI.UIEvents).Get

local function FormatNumber(n: number): string
	if n ~= n then return "0" end
	if n < 1000 then return tostring(math.floor(n)) end
	local suffixes = {"", "K", "M", "B", "T"}
	local i = math.floor(math.log10(n) / 3)
	local suffix = suffixes[i + 1] or ("e" .. tostring(i * 3))
	return (string.format("%.1f%s", n / (10 ^ (i * 3)), suffix):gsub("%.0(%a)", "%1"))
end

local function FormatChance(chance: number): string
	if chance <= 0 then return "—" end
	local pct = chance * 100
	if pct >= 1 then
		return (string.format("%.1f%%", pct):gsub("%.0%%", "%%"))
	end
	return "1 in " .. FormatNumber(1 / chance)
end

-- Panel scaffolding

local function makePanelFrame(gui: ScreenGui): ()
	MainPanel = Instance.new("Frame")
	MainPanel.Size = UDim2.new(0, 620, 0, 420)
	MainPanel.Position = UDim2.new(0.5, -310, 0.5, -210)
	MainPanel.BackgroundColor3 = Color3.fromRGB(16, 20, 14)
	MainPanel.Active = true
	MainPanel.Visible = false
	MainPanel.Parent = gui
	Instance.new("UICorner", MainPanel).CornerRadius = UDim.new(0, 16)

	local grad = Instance.new("UIGradient", MainPanel)
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 32, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 16, 10)),
	})
	grad.Rotation = 135

	local stroke = Instance.new("UIStroke", MainPanel)
	stroke.Color = Color3.fromRGB(90, 150, 60)
	stroke.Thickness = 2

	PanelScale = Instance.new("UIScale", MainPanel)
	UIHelpers.PrimeSpiral(MainPanel, PanelScale)
end

-- Egg shop (left column)

local function RefreshEggList(): ()
	if not EggList then return end
	for _, child in ipairs(EggList:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	local sorted: {PetRegistry.EggDef} = {}
	for _, egg in pairs(PetRegistry.Eggs) do
		table.insert(sorted, egg)
	end
	table.sort(sorted, function(a, b)
		if a.LevelReq ~= b.LevelReq then return a.LevelReq < b.LevelReq end
		return a.HatchCost < b.HatchCost
	end)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local hatchReq = remotes:WaitForChild(RemoteNames.HatchRequest) :: RemoteEvent

	for order, egg in ipairs(sorted) do
		local engine = PetRegistry.GetEngine(egg.Id)
		if not engine then continue end
		local probabilities = engine:GetProbabilities()
		local locked = playerLevel < egg.LevelReq

		local card = Instance.new("Frame")
		card.Name = "Egg_" .. egg.Id
		card.Size = UDim2.new(1, 0, 0, 96 + #probabilities * 18)
		card.BackgroundColor3 = Color3.fromRGB(22, 28, 18)
		card.LayoutOrder = order
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
		local cardStroke = Instance.new("UIStroke", card)
		cardStroke.Color = if locked then Color3.fromRGB(60, 60, 60) else egg.Color
		cardStroke.Thickness = 1.5

		local title = Instance.new("TextLabel", card)
		title.Size = UDim2.new(1, -16, 0, 26)
		title.Position = UDim2.new(0, 8, 0, 6)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.TextSize = 16
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = if locked then Color3.fromRGB(130, 130, 130) else egg.Color
		title.Text = string.upper(egg.DisplayName)

		local hatchBtn = Instance.new("TextButton", card)
		hatchBtn.Name = "HatchBtn"
		hatchBtn.Size = UDim2.new(0, 150, 0, 40)
		hatchBtn.Position = UDim2.new(1, -160, 0, 30)
		hatchBtn.Font = Enum.Font.GothamBlack
		hatchBtn.TextSize = 13
		hatchBtn.TextColor3 = Color3.new(1, 1, 1)
		hatchBtn.AutoButtonColor = false
		hatchBtn.BackgroundColor3 = if locked then Color3.fromRGB(60, 60, 65) else Color3.fromRGB(0, 140, 50)
		hatchBtn.Text = if locked
			then string.format("LEVEL %d", egg.LevelReq)
			else string.format("HATCH (%s)", FormatNumber(egg.HatchCost))
		Instance.new("UICorner", hatchBtn).CornerRadius = UDim.new(0, 8)

		if not locked then
			hatchBtn.MouseButton1Click:Connect(function()
				local now = os.clock()
				local lastReq = hatchBtn:GetAttribute("LastHatchReq")
				if now - (if type(lastReq) == "number" then lastReq else 0) < 1.0 then return end
				hatchBtn:SetAttribute("LastHatchReq", now)
				hatchReq:FireServer(egg.Id)
			end)
		end

		local oddsHeader = Instance.new("TextLabel", card)
		oddsHeader.Size = UDim2.new(0.6, 0, 0, 18)
		oddsHeader.Position = UDim2.new(0, 8, 0, 36)
		oddsHeader.BackgroundTransparency = 1
		oddsHeader.Font = Enum.Font.GothamBold
		oddsHeader.TextSize = 11
		oddsHeader.TextXAlignment = Enum.TextXAlignment.Left
		oddsHeader.TextColor3 = Color3.fromRGB(160, 170, 150)
		oddsHeader.Text = "DROP ODDS:"

		-- GetProbabilities is rarest-first; list commons on top
		local rowY = 56
		for i = #probabilities, 1, -1 do
			local entry = probabilities[i]
			local rarity = PetRegistry.GetRarity(entry.Def.RarityTag)

			local nameLabel = Instance.new("TextLabel", card)
			nameLabel.Size = UDim2.new(0.55, -8, 0, 16)
			nameLabel.Position = UDim2.new(0, 16, 0, rowY)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextSize = 12
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextColor3 = rarity.Color
			nameLabel.Text = entry.Def.DisplayName

			local chanceLabel = Instance.new("TextLabel", card)
			chanceLabel.Size = UDim2.new(0.4, -16, 0, 16)
			chanceLabel.Position = UDim2.new(0.55, 8, 0, rowY)
			chanceLabel.BackgroundTransparency = 1
			chanceLabel.Font = Enum.Font.Gotham
			chanceLabel.TextSize = 12
			chanceLabel.TextXAlignment = Enum.TextXAlignment.Right
			chanceLabel.TextColor3 = Color3.fromRGB(200, 210, 195)
			chanceLabel.Text = FormatChance(entry.Chance)

			rowY += 18
		end

		card.Parent = EggList
	end
end

-- Inventory (right column)

local function RefreshInventory(): ()
	if not InventoryGrid then return end
	for _, child in ipairs(InventoryGrid:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	local owned: {PetRegistry.PetDef} = {}
	for petId, count in pairs(inventoryCache) do
		if count > 0 then
			local def = PetRegistry.GetPetData(petId)
			if def.Id ~= "None" then
				table.insert(owned, def)
			end
		end
	end
	table.sort(owned, function(a, b)
		local orderA = PetRegistry.GetRarity(a.RarityTag).Order
		local orderB = PetRegistry.GetRarity(b.RarityTag).Order
		if orderA ~= orderB then return orderA > orderB end
		return a.Id < b.Id
	end)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local equipReq = remotes:WaitForChild(RemoteNames.PetEquipRequest) :: RemoteEvent

	if #owned == 0 then
		local empty = Instance.new("Frame", InventoryGrid)
		empty.Size = UDim2.new(1, 0, 0, 60)
		empty.BackgroundTransparency = 1
		local lbl = Instance.new("TextLabel", empty)
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 13
		lbl.TextColor3 = Color3.fromRGB(150, 160, 145)
		lbl.TextWrapped = true
		lbl.Text = "No pets yet — hatch an egg!"
		return
	end

	for order, def in ipairs(owned) do
		local rarity = PetRegistry.GetRarity(def.RarityTag)
		local isEquipped = (def.Id == currentEquippedId)

		local slot = Instance.new("Frame", InventoryGrid)
		slot.Name = def.Id
		slot.LayoutOrder = order
		slot.BackgroundColor3 = if isEquipped then Color3.fromRGB(30, 42, 24) else Color3.fromRGB(20, 26, 16)
		Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 8)
		local stroke = Instance.new("UIStroke", slot)
		stroke.Color = if isEquipped then Color3.fromRGB(120, 220, 80) else rarity.Color
		stroke.Thickness = if isEquipped then 2.5 else 1.5

		local swatch = Instance.new("Frame", slot)
		swatch.Size = UDim2.new(0, 26, 0, 26)
		swatch.Position = UDim2.new(0.5, -13, 0, 8)
		swatch.BackgroundColor3 = def.Build.BodyColor
		Instance.new("UICorner", swatch).CornerRadius = UDim.new(1, 0)
		local swatchStroke = Instance.new("UIStroke", swatch)
		swatchStroke.Color = def.Build.AccentColor
		swatchStroke.Thickness = 2

		local nameLabel = Instance.new("TextLabel", slot)
		nameLabel.Size = UDim2.new(1, -8, 0, 14)
		nameLabel.Position = UDim2.new(0, 4, 0, 38)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.TextColor3 = rarity.Color
		nameLabel.Text = def.DisplayName
		Instance.new("UITextSizeConstraint", nameLabel).MaxTextSize = 11

		local countLabel = Instance.new("TextLabel", slot)
		countLabel.Size = UDim2.new(1, -8, 0, 12)
		countLabel.Position = UDim2.new(0, 4, 0, 54)
		countLabel.BackgroundTransparency = 1
		countLabel.Font = Enum.Font.Gotham
		countLabel.TextSize = 10
		countLabel.TextColor3 = Color3.fromRGB(170, 180, 165)
		countLabel.Text = if isEquipped then "EQUIPPED" else "x" .. tostring(inventoryCache[def.Id] or 0)

		local btn = Instance.new("TextButton", slot)
		btn.Size = UDim2.fromScale(1, 1)
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.MouseButton1Click:Connect(function()
			equipReq:FireServer(if def.Id == currentEquippedId then "None" else def.Id)
		end)
	end
end

-- Hatch reveal popup

local revealSound: Sound? = nil

local function ShowHatchReveal(petId: string, isNew: boolean): ()
	local def = PetRegistry.GetPetData(petId)
	if def.Id == "None" then return end
	local rarity = PetRegistry.GetRarity(def.RarityTag)

	if revealSound then revealSound:Play() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchRevealGui"
	gui.DisplayOrder = 200
	gui.Parent = LocalPlayer.PlayerGui

	local popup = Instance.new("Frame", gui)
	popup.Size = UDim2.new(0, 260, 0, 90)
	popup.AnchorPoint = Vector2.new(0.5, 0)
	popup.Position = UDim2.new(0.5, 0, 0, 60)
	popup.BackgroundColor3 = Color3.fromRGB(14, 18, 12)
	Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 12)
	local stroke = Instance.new("UIStroke", popup)
	stroke.Color = rarity.Color
	stroke.Thickness = 2.5

	local scale = Instance.new("UIScale", popup)
	scale.Scale = 0

	local nameLabel = Instance.new("TextLabel", popup)
	nameLabel.Size = UDim2.new(1, -16, 0, 34)
	nameLabel.Position = UDim2.new(0, 8, 0, 12)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextSize = 20
	nameLabel.TextColor3 = rarity.Color
	nameLabel.Text = string.upper(def.DisplayName)

	local subLabel = Instance.new("TextLabel", popup)
	subLabel.Size = UDim2.new(1, -16, 0, 20)
	subLabel.Position = UDim2.new(0, 8, 0, 48)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.GothamBold
	subLabel.TextSize = 13
	subLabel.TextColor3 = Color3.fromRGB(210, 220, 205)
	subLabel.Text = def.RarityTag .. (if isNew then "  •  NEW!" else "  •  DUPLICATE")

	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(2.5, function()
		local out = TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		out:Play()
		out.Completed:Connect(function() gui:Destroy() end)
	end)
end

-- Lifecycle

function PetsUIController.Init(): () end

function PetsUIController.Start(): ()
	if not FeatureResolver.IsCategoryActive(GENRE_KEY) then
		return
	end

	local UIController: any = require(script.Parent:WaitForChild("UIController"))
	UIController.RegisterHUDButton({
		Id = "Pets",
		Name = "Pets",
		IconId = "Pets",
		Type = "Sidebar",
		LayoutOrder = 3,
		OnClick = function(): ()
			GetLocalEvent("TogglePets"):Fire()
		end,
	})

	-- Hatch-reveal stinger (AudioRegistry-driven, Global fallback)
	local sfx = AudioRegistry.GetSFX("HatchReveal") or AudioRegistry.GetSFX("Purchase")
	if sfx then
		local snd = Instance.new("Sound")
		snd.Name = "HatchReveal"
		snd.SoundId = sfx.SoundId
		snd.Volume = sfx.Volume or 0.5
		snd.PlaybackSpeed = sfx.PlaybackSpeed or 1
		snd.Parent = SoundService
		revealSound = snd
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "PetsGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60 -- panel band: 60 resting/closing, 61 while open
	gui.Parent = LocalPlayer.PlayerGui

	makePanelFrame(gui)

	local function closePanel(reason: string?): ()
		-- Guard only on logical state: dropping a close request during an
		-- animation is how panels get stuck open during cross-menu switches.
		if not isOpen then return end
		isOpen = false
		animGen += 1
		local gen = animGen
		gui.DisplayOrder = 60
		BgShield.Visible = false
		GetLocalEvent("NotifyMenuClosed"):Fire("Pets")
		local tw = UIHelpers.SpiralClose(MainPanel, PanelScale, reason)
		tw.Completed:Connect(function(state: Enum.PlaybackState)
			-- A reopen cancels this tween (Completed still fires, state=Cancelled)
			-- and bumps the generation; hide only if this close ran to completion
			-- and is still the latest transition.
			if gen ~= animGen then return end
			if state ~= Enum.PlaybackState.Completed then return end
			MainPanel.Visible = false
		end)
	end

	BgShield = Instance.new("TextButton")
	BgShield.Name = "InputSink"
	BgShield.Size = UDim2.fromScale(1, 1)
	BgShield.BackgroundTransparency = 1
	BgShield.Text = ""
	BgShield.AutoButtonColor = false
	BgShield.Visible = false
	BgShield.Active = true
	BgShield.Parent = gui
	BgShield.MouseButton1Up:Connect(function() closePanel() end)

	UIHelpers.CreateCloseButton(MainPanel, closePanel)

	local panelTitle = Instance.new("TextLabel", MainPanel)
	panelTitle.Size = UDim2.new(1, 0, 0, 50)
	panelTitle.BackgroundTransparency = 1
	panelTitle.Text = "PETS"
	panelTitle.Font = Enum.Font.GothamBlack
	panelTitle.TextSize = 22
	panelTitle.TextColor3 = Color3.fromRGB(255, 255, 255)

	local eggHeader = Instance.new("TextLabel", MainPanel)
	eggHeader.Size = UDim2.new(0.5, -30, 0, 20)
	eggHeader.Position = UDim2.new(0, 15, 0, 50)
	eggHeader.BackgroundTransparency = 1
	eggHeader.Font = Enum.Font.GothamBlack
	eggHeader.TextSize = 13
	eggHeader.TextXAlignment = Enum.TextXAlignment.Left
	eggHeader.TextColor3 = Color3.fromRGB(180, 200, 160)
	eggHeader.Text = "[ EGG SHOP ]"

	EggList = Instance.new("ScrollingFrame", MainPanel)
	EggList.Size = UDim2.new(0.5, -25, 1, -90)
	EggList.Position = UDim2.new(0, 15, 0, 75)
	EggList.BackgroundTransparency = 1
	EggList.ScrollBarThickness = 4
	EggList.CanvasSize = UDim2.new(0, 0, 0, 0)
	EggList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	EggList.BorderSizePixel = 0
	local eggLayout = Instance.new("UIListLayout", EggList)
	eggLayout.SortOrder = Enum.SortOrder.LayoutOrder
	eggLayout.Padding = UDim.new(0, 10)

	local invHeader = Instance.new("TextLabel", MainPanel)
	invHeader.Size = UDim2.new(0.5, -30, 0, 20)
	invHeader.Position = UDim2.new(0.5, 10, 0, 50)
	invHeader.BackgroundTransparency = 1
	invHeader.Font = Enum.Font.GothamBlack
	invHeader.TextSize = 13
	invHeader.TextXAlignment = Enum.TextXAlignment.Left
	invHeader.TextColor3 = Color3.fromRGB(180, 200, 160)
	invHeader.Text = "[ MY PETS — CLICK TO EQUIP ]"

	InventoryGrid = Instance.new("ScrollingFrame", MainPanel)
	InventoryGrid.Size = UDim2.new(0.5, -25, 1, -90)
	InventoryGrid.Position = UDim2.new(0.5, 10, 0, 75)
	InventoryGrid.BackgroundTransparency = 1
	InventoryGrid.ScrollBarThickness = 4
	InventoryGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
	InventoryGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	InventoryGrid.BorderSizePixel = 0
	local grid = Instance.new("UIGridLayout", InventoryGrid)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellPadding = UDim2.new(0, 8, 0, 8)
	grid.CellSize = UDim2.new(0, 82, 0, 72)

	GetLocalEvent("TogglePets").Event:Connect(function(reason: string?)
		if isOpen then
			closePanel(reason)
		else
			isOpen = true
			animGen += 1
			gui.DisplayOrder = 61 -- render above the outgoing panel during a switch
			MainPanel.Visible = true
			BgShield.Visible = true
			RefreshEggList()
			RefreshInventory()
			-- Retarget from the current scale/rotation (no reset to the resting
			-- pose) so reopening during a close animation continues smoothly
			-- instead of snapping shut first.
			UIHelpers.SpiralOpen(MainPanel, PanelScale, 1)
			GetLocalEvent("NotifyMenuOpened"):Fire("Pets")
		end
	end)

	-- Cross-menu exclusion is owned centrally by UIController's NotifyMenuOpened
	-- handler, which fires TogglePets when another menu opens.

	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	;(remotes:WaitForChild(RemoteNames.UpdatePetInventory) :: RemoteEvent).OnClientEvent:Connect(function(inventory: any, equipped: any)
		if type(inventory) == "table" then
			inventoryCache = inventory
		end
		if type(equipped) == "string" then
			currentEquippedId = equipped
		end
		if isOpen then RefreshInventory() end
	end)

	;(remotes:WaitForChild(RemoteNames.HatchResult) :: RemoteEvent).OnClientEvent:Connect(function(petId: any, _eggId: any, isNew: any)
		if type(petId) ~= "string" then return end
		ShowHatchReveal(petId, isNew == true)
	end)

	-- Equip attribute covers late joins and out-of-band equips
	LocalPlayer:GetAttributeChangedSignal("EquippedPet"):Connect(function()
		local petId = LocalPlayer:GetAttribute("EquippedPet")
		if type(petId) == "string" then
			currentEquippedId = petId
			if isOpen then RefreshInventory() end
		end
	end)
	local initialEquipped = LocalPlayer:GetAttribute("EquippedPet")
	if type(initialEquipped) == "string" then
		currentEquippedId = initialEquipped
	end

	-- Seed level (egg locks) + inventory from the full-state sync
	local updateProfileRemote = remotes:WaitForChild(RemoteNames.UpdateProfileData, 5) :: RemoteEvent?
	if updateProfileRemote then
		updateProfileRemote.OnClientEvent:Connect(function(data: any)
			if type(data) ~= "table" then return end
			local progression = if type(data.Progression) == "table" then data.Progression :: PSUTypes.ProgressionData else nil
			if progression and type(progression.Level) == "number" then
				if progression.Level ~= playerLevel then
					playerLevel = progression.Level
					if isOpen then RefreshEggList() end
				end
			end
			local genreDataRaw = if type(data.GenreData) == "table" then (data.GenreData :: PSUTypes.GenreDataMap)[GENRE_KEY] else nil
			if type(genreDataRaw) == "table" then
				local genreData = genreDataRaw :: PSUTypes.PetSimulatorData
				if type(genreData.Inventory) == "table" then
					inventoryCache = genreData.Inventory
				end
				if type(genreData.Equipped) == "string" then
					currentEquippedId = genreData.Equipped
				end
				if isOpen then RefreshInventory() end
			end
		end)
	end
end

return PetsUIController
