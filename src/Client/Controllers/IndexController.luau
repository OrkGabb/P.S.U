--!strict
-- @Author @OrkGabb
-- src/Client/Controllers/IndexController.luau
-- Aura_Collector collection index: every aura in the game shown as a grid of
-- unlocked/silhouetted slots with a details panel (rarity, boosts, real drop
-- odds from the shared roll engine) and equip controls.
--
-- Data flows:
--   • AuraRegistry (shared) — aura defs, rarity styling, drop odds
--   • UpdateCollection (remote) — owned-aura counts after every roll
--   • UpdateEquipped (remote) + "EquippedAura" player attribute — equip state
--   • EquipRequest (remote) — equip/unequip requests, server-validated

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local AuraRegistry = require(ReplicatedStorage.Shared.Modules.AuraRegistry)

local FALLBACK_ICON = "rbxassetid://15059633013"
local BIOME_FALLBACK_COLOR = Color3.fromRGB(80, 80, 100)

-- UI-only styling per rarity tag (colors come from AuraRegistry.Rarities)
local StrokeConfig: {[string]: {Thickness: number, Pulse: boolean}} = {
    EPIC        = { Thickness = 1.8, Pulse = false },
    LEGENDARY   = { Thickness = 2.0, Pulse = false },
    MYTHIC      = { Thickness = 2.5, Pulse = true  },
    MUTANT      = { Thickness = 2.5, Pulse = true  },
    ABYSSAL     = { Thickness = 2.8, Pulse = true  },
    COSMIC      = { Thickness = 2.8, Pulse = true  },
    VIP         = { Thickness = 3.0, Pulse = true  },
    SINGULARITY = { Thickness = 3.2, Pulse = true  },
    EXOTIC      = { Thickness = 3.2, Pulse = true  },
    OMNI        = { Thickness = 3.5, Pulse = true  },
}

local ORNAMENT_TIERS: {[string]: boolean} = {
    LEGENDARY = true, MYTHIC = true, MUTANT = true, ABYSSAL = true,
    COSMIC = true, VIP = true, SINGULARITY = true, EXOTIC = true, OMNI = true,
}

-- Flavor text per aura id
local AURA_LORE: {[string]: string} = {
    Breeze    = "A faint stirring of the air. Everyone starts somewhere.",
    Aqua      = "Cool currents that never quite touch the ground.",
    Ember     = "Sparks that remember an ancient fire.",
    Blood     = "It pulses in time with your heartbeat. Probably yours.",
    Solar     = "Bottled daylight, radiant and warm.",
    Doom      = "A whisper of endings follows you around.",
    Starlight = "Dust from a star that died politely.",
    Nebula    = "A slow bloom of color harvested between worlds.",
    Supernova = "The last breath of a giant, worn as a cloak.",
    Abyssal   = "The deep looked back — and liked what it saw.",
    Cosmic    = "Space bends slightly to keep you company.",
    Astral    = "You flicker between here and somewhere brighter.",
    Ethereal  = "Barely there. Entirely unforgettable.",
    Quantum   = "Simultaneously equipped and unequipped until observed.",
    Oblivion  = "Light declines to comment.",
    Eternal   = "It was here before the servers. It will outlast them.",
    Void      = "A tear in the rift, stitched into your shadow.",
    Eclipse   = "Two lights conspiring to make darkness.",
    VIP       = "Exclusively granted to distinguished collectors.",
}

local OMNI_SPECTRUM = {
    Color3.fromRGB(228,  45,  45),
    Color3.fromRGB(228, 167,  45),
    Color3.fromRGB(228, 228,  45),
    Color3.fromRGB(45,  228, 120),
    Color3.fromRGB(45,  107, 228),
    Color3.fromRGB(123,  47, 190),
}

local IndexController = {}

local MainPanel: Frame
local GridContainer: ScrollingFrame
local DetailsPanel: Frame
local PanelScale: UIScale
local BgShield: TextButton
local isOpen = false
local isAnimating = false
local selectedAuraId: string? = nil
local currentEquippedId: string = "None"
local collectionCache: {[string]: number} = {}
local selectedSlot: TextButton? = nil
local selectedStroke: UIStroke? = nil
local selectedBiomeFilter: string? = nil

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function FormatSuffix(n: number): string
    if n ~= n or n == math.huge then return "?" end
    if n < 1000 then
        return (string.format("%.1f", n):gsub("%.0$", ""))
    end
    local suffixes = {"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"}
    local i = math.floor(math.log10(n) / 3)
    local v = n / (10 ^ (i * 3))
    local suffix = suffixes[i + 1] or ("e" .. tostring(i * 3))
    return (string.format("%.1f%s", v, suffix):gsub("%.0(%a)", "%1"))
end

local function GetLocalEvent(eventName: string): BindableEvent
    local folder: Instance? = ReplicatedStorage:FindFirstChild("LocalEvents")
    if not folder then
        local newFolder = Instance.new("Folder")
        newFolder.Name = "LocalEvents"
        newFolder.Parent = ReplicatedStorage
        folder = newFolder
    end
    local existing = (folder :: Instance):FindFirstChild(eventName)
    if existing and existing:IsA("BindableEvent") then
        return existing
    end
    local evt = Instance.new("BindableEvent")
    evt.Name = eventName
    evt.Parent = folder
    return evt
end

local function GetRarityColor(rarityTag: string): Color3
    return AuraRegistry.GetRarity(rarityTag).Color
end

-- aura id → home biome id (for the biome filter tabs)
local biomeOfAura: {[string]: string} = {}
for biomeId, biome in pairs(AuraRegistry.Biomes) do
    for _, def in ipairs(biome.Auras) do
        biomeOfAura[def.Id] = biomeId
    end
end

local function ShouldShowAura(auraId: string): boolean
    if selectedBiomeFilter == nil then return true end
    return biomeOfAura[auraId] == selectedBiomeFilter
end

-- "1 in N" drop odds from the shared engine (nil for paid/exclusive auras)
local function GetDropOdds(auraId: string): number?
    local biomeId = biomeOfAura[auraId]
    if not biomeId then return nil end
    local engine = AuraRegistry.GetEngine(biomeId)
    if not engine then return nil end
    for _, entry in ipairs(engine:GetProbabilities()) do
        if entry.Def.Id == auraId and entry.Chance > 0 then
            return 1 / entry.Chance
        end
    end
    return nil
end

local function GetBestAuraId(): string?
    local bestId: string? = nil
    local maxPower = -1
    for auraId, amount in pairs(collectionCache) do
        if amount <= 0 then continue end
        local def = AuraRegistry.GetAuraData(auraId)
        if def.Id == "None" then continue end
        local power = def.CoinMult * def.ExpMult
        if power > maxPower then
            maxPower = power
            bestId = def.Id
        end
    end
    return bestId
end

local function StartOmniAnimation(element: GuiObject | UIStroke, prop: string): ()
    task.spawn(function()
        local idx = 1
        while element and element.Parent do
            local nextIdx = (idx % #OMNI_SPECTRUM) + 1
            local tweenParams = {}
            tweenParams[prop] = OMNI_SPECTRUM[nextIdx]
            local tween = TweenService:Create(element, TweenInfo.new(0.8, Enum.EasingStyle.Sine), tweenParams)
            tween:Play()
            tween.Completed:Wait()
            idx = nextIdx
        end
    end)
end

local function StartStrokePulse(stroke: UIStroke, rarityColor: Color3): ()
    task.spawn(function()
        local shimmer = Color3.fromRGB(255, 255, 220)
        while stroke and stroke.Parent do
            local t1 = TweenService:Create(stroke, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Color = shimmer })
            t1:Play(); t1.Completed:Wait()
            if not (stroke and stroke.Parent) then break end
            local t2 = TweenService:Create(stroke, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Color = rarityColor })
            t2:Play(); t2.Completed:Wait()
        end
    end)
end

-- ─── Grid ─────────────────────────────────────────────────────────────────────

function IndexController.Refresh(collection: {[string]: number}): ()
    collectionCache = collection
    if not GridContainer then return end

    for _, child in ipairs(GridContainer:GetChildren()) do
        if child:IsA("Frame") or child:IsA("UIListLayout") or child:IsA("UIGridLayout") or child:IsA("UIPadding") then
            child:Destroy()
        end
    end

    local mainListLayout = Instance.new("UIListLayout", GridContainer)
    mainListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    mainListLayout.Padding = UDim.new(0, 15)
    mainListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local mainPadding = Instance.new("UIPadding", GridContainer)
    mainPadding.PaddingTop = UDim.new(0, 10)
    mainPadding.PaddingBottom = UDim.new(0, 20)
    mainPadding.PaddingLeft = UDim.new(0, 10)
    mainPadding.PaddingRight = UDim.new(0, 10)

    -- Every aura in the registry appears — owned slots in full color,
    -- unowned as "?" silhouettes (the collection hook).
    local allAuras: {AuraRegistry.AuraDef} = {}
    for _, biome in pairs(AuraRegistry.Biomes) do
        for _, def in ipairs(biome.Auras) do
            if ShouldShowAura(def.Id) then
                table.insert(allAuras, def)
            end
        end
    end
    if selectedBiomeFilter == nil then
        for _, def in ipairs(AuraRegistry.PaidAuras) do
            table.insert(allAuras, def)
        end
    end

    table.sort(allAuras, function(a, b)
        local orderA = AuraRegistry.GetRarity(a.RarityTag).Order
        local orderB = AuraRegistry.GetRarity(b.RarityTag).Order
        if orderA ~= orderB then return orderA < orderB end
        if a.CoinMult ~= b.CoinMult then return a.CoinMult < b.CoinMult end
        return a.Id < b.Id
    end)

    type Category = { Title: string, MinOrder: number, MaxOrder: number, Exclusive: boolean?, Auras: {AuraRegistry.AuraDef} }
    local categories: {Category} = {
        { Title = "ALL",             MinOrder = 0,  MaxOrder = 6,  Auras = {} },
        { Title = "MUTANTS",         MinOrder = 7,  MaxOrder = 7,  Auras = {} },
        { Title = "THE SINGULARITY", MinOrder = 8,  MaxOrder = 99, Auras = {} },
        { Title = "EXCLUSIVES",      MinOrder = 0,  MaxOrder = 99, Exclusive = true, Auras = {} },
    }

    for _, def in ipairs(allAuras) do
        if def.Paid then
            table.insert(categories[4].Auras, def)
            continue
        end
        local order = AuraRegistry.GetRarity(def.RarityTag).Order
        local placed = false
        for i = 1, 3 do
            local cat = categories[i]
            if order >= cat.MinOrder and order <= cat.MaxOrder then
                table.insert(cat.Auras, def)
                placed = true
                break
            end
        end
        if not placed then
            table.insert(categories[1].Auras, def)
        end
    end

    local layoutOrderCat = 1
    for _, cat in ipairs(categories) do
        if #cat.Auras == 0 then continue end

        local isPremium = (cat.Title == "THE SINGULARITY" or cat.Title == "EXCLUSIVES")

        local catFrame = Instance.new("Frame", GridContainer)
        catFrame.Name = "Cat_" .. cat.Title
        catFrame.BackgroundTransparency = 1
        catFrame.Size = UDim2.new(1, 0, 0, 0)
        catFrame.AutomaticSize = Enum.AutomaticSize.Y
        catFrame.LayoutOrder = layoutOrderCat
        layoutOrderCat += 1

        local header = Instance.new("TextLabel", catFrame)
        header.Size = UDim2.new(1, 0, 0, 25)
        header.BackgroundTransparency = 1
        header.Text = "[ " .. cat.Title .. " ]"
        header.Font = Enum.Font.GothamBlack
        header.TextSize = 16
        header.TextColor3 = Color3.fromRGB(255, 255, 255)
        header.TextTransparency = 0.2
        header.TextXAlignment = Enum.TextXAlignment.Left

        local gridHolder = Instance.new("Frame", catFrame)
        gridHolder.Name = "GridHolder"
        gridHolder.BackgroundTransparency = 1
        gridHolder.Size = UDim2.new(1, 0, 0, 0)
        gridHolder.Position = UDim2.new(0, 0, 0, 30)
        gridHolder.AutomaticSize = Enum.AutomaticSize.Y

        local grid = Instance.new("UIGridLayout", gridHolder)
        grid.SortOrder = Enum.SortOrder.LayoutOrder
        grid.CellPadding = UDim2.new(0, 8, 0, 8)
        grid.CellSize = if isPremium then UDim2.new(1, -20, 0, 95) else UDim2.new(0, 85, 0, 85)

        for _, def in ipairs(cat.Auras) do
            local isUnlocked = (collectionCache[def.Id] or 0) > 0
            local rColor = GetRarityColor(def.RarityTag)
            local strokeCfg = StrokeConfig[def.RarityTag]

            local studBase = Instance.new("Frame", gridHolder)
            studBase.BackgroundTransparency = 1
            studBase.Name = def.Id

            local slot = Instance.new("TextButton", studBase)
            slot.Size = UDim2.new(1, 0, 1, 0)
            slot.BackgroundColor3 = if isUnlocked then Color3.fromRGB(16, 12, 20) else Color3.fromRGB(12, 8, 20)
            slot.BackgroundTransparency = if isUnlocked then 0 else 0.3
            slot.Text = ""
            slot.AutoButtonColor = false
            Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 8)

            local slotGrad = Instance.new("UIGradient", slot)
            slotGrad.Rotation = 90
            if isUnlocked then
                slotGrad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 20, 30)),
                    ColorSequenceKeypoint.new(1, Color3.new(rColor.R * 0.15, rColor.G * 0.15, rColor.B * 0.15)),
                })
            else
                slotGrad.Color = ColorSequence.new(Color3.fromRGB(15, 10, 20))
            end

            local studScale = Instance.new("UIScale", studBase)
            studScale.Scale = 1

            local stroke = Instance.new("UIStroke", slot)
            stroke.Thickness = if isUnlocked and strokeCfg then strokeCfg.Thickness else 1.5
            if isUnlocked then
                stroke.Color = rColor
                if def.RarityTag == "OMNI" then
                    StartOmniAnimation(stroke, "Color")
                elseif strokeCfg and strokeCfg.Pulse then
                    StartStrokePulse(stroke, rColor)
                end
            else
                stroke.Color = Color3.fromRGB(80, 60, 110)
            end

            if isUnlocked and ORNAMENT_TIERS[def.RarityTag] then
                local outerStroke = Instance.new("UIStroke", studBase)
                outerStroke.Thickness = 1.0
                outerStroke.Color = rColor
                outerStroke.Transparency = 0.55
                if def.RarityTag == "OMNI" then
                    StartOmniAnimation(outerStroke, "Color")
                elseif strokeCfg and strokeCfg.Pulse then
                    StartStrokePulse(outerStroke, rColor)
                end
            end

            local watermark = Instance.new("TextLabel", slot)
            watermark.BackgroundTransparency = 1
            watermark.Text = if isUnlocked then string.sub(def.DisplayName, 1, 1):upper() else "?"
            watermark.Font = Enum.Font.GothamBlack
            watermark.TextColor3 = rColor
            watermark.TextTransparency = 0.93
            watermark.ZIndex = slot.ZIndex

            local iconImg = Instance.new("ImageLabel", slot)
            iconImg.Name = "AuraIcon"
            iconImg.BackgroundTransparency = 1
            iconImg.ScaleType = Enum.ScaleType.Fit
            iconImg.Image = def.IconId or FALLBACK_ICON
            iconImg.ZIndex = slot.ZIndex + 1

            local nameLabel = Instance.new("TextLabel", slot)
            nameLabel.BackgroundTransparency = 1
            nameLabel.TextScaled = true
            nameLabel.ZIndex = slot.ZIndex + 2
            local nameConstraint = Instance.new("UITextSizeConstraint", nameLabel)

            if isPremium then
                watermark.Size = UDim2.new(0, 100, 1, 0)
                watermark.Position = UDim2.new(1, -110, 0, 0)
                watermark.TextSize = 80
                watermark.TextXAlignment = Enum.TextXAlignment.Right

                iconImg.SizeConstraint = Enum.SizeConstraint.RelativeYY
                iconImg.Size = UDim2.new(0.7, 0, 0.7, 0)
                iconImg.AnchorPoint = Vector2.new(0, 0.5)
                iconImg.Position = UDim2.new(0, 15, 0.5, 0)

                nameLabel.Size = UDim2.new(1, -110, 0, 20)
                nameLabel.AnchorPoint = Vector2.new(0, 0.5)
                nameLabel.Position = UDim2.new(0, 100, 0.5, -5)
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameConstraint.MaxTextSize = 16
            else
                watermark.Size = UDim2.fromScale(1, 1)
                watermark.TextSize = 65
                watermark.TextXAlignment = Enum.TextXAlignment.Center

                iconImg.Size = UDim2.new(0.55, 0, 0.55, 0)
                iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
                iconImg.Position = UDim2.new(0.5, 0, 0.48, 0)

                nameLabel.Size = UDim2.new(1, -6, 0, 16)
                nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
                nameLabel.Position = UDim2.new(0.5, 0, 0.5, 5)
                nameLabel.TextXAlignment = Enum.TextXAlignment.Center
                nameConstraint.MaxTextSize = 12
            end

            if isUnlocked then
                iconImg.ImageColor3 = Color3.new(1, 1, 1)
                nameLabel.Text = string.upper(def.DisplayName)
                nameLabel.Font = Enum.Font.GothamBlack
                nameLabel.TextColor3 = rColor
                if def.RarityTag == "OMNI" then
                    StartOmniAnimation(watermark, "TextColor3")
                    StartOmniAnimation(nameLabel, "TextColor3")
                end
            else
                iconImg.ImageColor3 = Color3.fromRGB(20, 15, 30)
                iconImg.ImageTransparency = 0.3
                nameLabel.Text = "?"
                nameLabel.Font = Enum.Font.GothamBlack
                nameLabel.TextColor3 = Color3.fromRGB(160, 140, 200)
                nameLabel.TextTransparency = 0.2
                nameConstraint.MaxTextSize = 20
            end

            local nameLabelStroke = Instance.new("UIStroke", nameLabel)
            nameLabelStroke.Color = Color3.fromRGB(0, 0, 0)
            nameLabelStroke.Thickness = 1.2
            nameLabelStroke.Transparency = 0.2

            slot.MouseButton1Click:Connect(function()
                if not isUnlocked then return end

                if selectedSlot and selectedStroke then
                    TweenService:Create(selectedStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Thickness = 1.5 }):Play()
                    local prevStudBase = selectedSlot.Parent
                    local prevScale = prevStudBase and prevStudBase:FindFirstChildOfClass("UIScale")
                    if prevScale then
                        TweenService:Create(prevScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
                    end
                end

                selectedSlot = slot
                selectedStroke = stroke
                selectedAuraId = def.Id

                TweenService:Create(stroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Thickness = 3.5 }):Play()
                TweenService:Create(studScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 0.93 }):Play()

                IndexController.UpdateDetailsPanel()
            end)
        end
    end
end

-- ─── Details panel ────────────────────────────────────────────────────────────

function IndexController.UpdateDetailsPanel(): ()
    if not selectedAuraId or not DetailsPanel then return end

    local def = AuraRegistry.GetAuraData(selectedAuraId :: string)
    if def.Id == "None" then return end

    local rColor = GetRarityColor(def.RarityTag)

    local equipC = DetailsPanel:FindFirstChild("EquipBtnContainer") :: Frame?
    local rarityTxt = DetailsPanel:FindFirstChild("Rarity") :: TextLabel?
    local yieldTxt = DetailsPanel:FindFirstChild("Power") :: TextLabel?
    local loreTxt = DetailsPanel:FindFirstChild("Lore") :: TextLabel?
    local chanceTxt = DetailsPanel:FindFirstChild("Chance") :: TextLabel?
    local dIcon = DetailsPanel:FindFirstChild("SelectedIcon") :: ImageLabel?
    local title = DetailsPanel:FindFirstChild("Title") :: TextLabel?

    for _, element in ipairs({equipC :: Instance?, rarityTxt :: Instance?, yieldTxt :: Instance?, loreTxt :: Instance?, chanceTxt :: Instance?, dIcon :: Instance?}) do
        if element and (element:IsA("Frame") or element:IsA("TextLabel") or element:IsA("ImageLabel")) then
            (element :: GuiObject).Visible = true
        end
    end

    local equipBtn = equipC and equipC:FindFirstChild("EquipBtn") :: TextButton?
    if equipBtn then
        local isEquipped = (selectedAuraId == currentEquippedId)
        equipBtn.Text = if isEquipped then "UNEQUIP" else "EQUIP"
        equipBtn.BackgroundColor3 = if isEquipped
            then Color3.fromRGB(60, 60, 65)
            else Color3.fromRGB(0, 140, 50)
    end

    if dIcon then
        dIcon.Image = def.IconId or FALLBACK_ICON
    end

    if title then
        title.Text = string.upper(def.DisplayName)
        title.TextColor3 = rColor
        if def.RarityTag == "OMNI" then StartOmniAnimation(title, "TextColor3") end
    end

    if rarityTxt then
        rarityTxt.Text = def.RarityTag
        rarityTxt.TextColor3 = rColor
        if def.RarityTag == "OMNI" then StartOmniAnimation(rarityTxt, "TextColor3") end
    end

    if chanceTxt then
        local odds = GetDropOdds(def.Id)
        chanceTxt.Text = if odds
            then "DROP CHANCE: 1 in " .. FormatSuffix(odds)
            else "NOT OBTAINABLE BY ROLLING"
    end

    if yieldTxt then
        yieldTxt.Text = string.format("BOOSTS: Coins x%s | EXP x%s", FormatSuffix(def.CoinMult), FormatSuffix(def.ExpMult))
    end

    if loreTxt then
        local lore = AURA_LORE[def.Id]
        loreTxt.Text = if lore then "\"" .. lore .. "\"" else ""
    end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function IndexController.Init(): () end

function IndexController.Start(): ()
    local UIController: any = require(script.Parent:WaitForChild("UIController"))
    UIController.RegisterHUDButton({
        Id = "Index",
        Name = "Index",
        IconId = "Index",
        Type = "Sidebar",
        LayoutOrder = 3,
        OnClick = function(): ()
            GetLocalEvent("ToggleIndex"):Fire()
        end,
    })

    local gui = Instance.new("ScreenGui")
    gui.Name = "IndexGui"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 20
    gui.Parent = LocalPlayer.PlayerGui

    MainPanel = Instance.new("Frame")
    MainPanel.Size = UDim2.new(0, 620, 0, 420)
    MainPanel.Position = UDim2.new(0.5, -310, 0.5, -210)
    MainPanel.BackgroundColor3 = Color3.fromRGB(14, 11, 22)
    MainPanel.Active = true
    MainPanel.Visible = false
    Instance.new("UICorner", MainPanel).CornerRadius = UDim.new(0, 16)

    local mpGrad = Instance.new("UIGradient", MainPanel)
    mpGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 15, 35)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 8, 18)),
    })
    mpGrad.Rotation = 135

    local mpStroke = Instance.new("UIStroke", MainPanel)
    mpStroke.Color = Color3.fromRGB(90, 60, 150)
    mpStroke.Thickness = 2

    PanelScale = Instance.new("UIScale", MainPanel)
    PanelScale.Scale = 0

    local function closePanel(): ()
        if not isOpen or isAnimating then return end
        isOpen = false
        isAnimating = true
        BgShield.Visible = false
        GetLocalEvent("NotifyMenuClosed"):Fire("Index")
        local tw = TweenService:Create(PanelScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
        tw:Play()
        tw.Completed:Connect(function()
            isAnimating = false
            if not isOpen then MainPanel.Visible = false end
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
    BgShield.MouseButton1Up:Connect(closePanel)

    MainPanel.Parent = gui

    local closeBtn = Instance.new("TextButton", MainPanel)
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -15, 0, 15)
    closeBtn.AnchorPoint = Vector2.new(1, 0)
    closeBtn.AutoButtonColor = false
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextScaled = true
    closeBtn.Font = Enum.Font.GothamBlack
    closeBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
    local closeStroke = Instance.new("UIStroke", closeBtn)
    closeStroke.Color = Color3.fromRGB(120, 20, 20)
    closeStroke.Thickness = 2

    local clickTw = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    closeBtn.MouseEnter:Connect(function() TweenService:Create(closeBtn, clickTw, {Size = UDim2.new(0, 32, 0, 32), BackgroundColor3 = Color3.fromRGB(255, 70, 70)}):Play() end)
    closeBtn.MouseLeave:Connect(function() TweenService:Create(closeBtn, clickTw, {Size = UDim2.new(0, 30, 0, 30), BackgroundColor3 = Color3.fromRGB(220, 50, 50)}):Play() end)
    closeBtn.MouseButton1Up:Connect(closePanel)

    local remotes = ReplicatedStorage:WaitForChild("Remotes")

    local equipBestBtn = Instance.new("TextButton", MainPanel)
    equipBestBtn.Size = UDim2.new(0, 100, 0, 30)
    equipBestBtn.Position = UDim2.new(1, -55, 0, 15)
    equipBestBtn.AnchorPoint = Vector2.new(1, 0)
    equipBestBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 50)
    equipBestBtn.Text = "EQUIP BEST"
    equipBestBtn.Font = Enum.Font.GothamBlack
    equipBestBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    equipBestBtn.TextSize = 12
    equipBestBtn.AutoButtonColor = false
    Instance.new("UICorner", equipBestBtn).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", equipBestBtn).Color = Color3.fromRGB(0, 80, 30)

    local panelTitle = Instance.new("TextLabel", MainPanel)
    panelTitle.Size = UDim2.new(1, 0, 0, 50)
    panelTitle.BackgroundTransparency = 1
    panelTitle.Text = "COLLECTION"
    panelTitle.Font = Enum.Font.GothamBlack
    panelTitle.TextSize = 22
    panelTitle.TextColor3 = Color3.fromRGB(255, 255, 255)

    -- Biome filter tabs
    local tabBar = Instance.new("Frame", MainPanel)
    tabBar.Name = "BiomeTabBar"
    tabBar.Size = UDim2.new(0.6, -20, 0, 36)
    tabBar.Position = UDim2.new(0, 15, 0, 50)
    tabBar.BackgroundTransparency = 1

    local tabLayout = Instance.new("UIListLayout", tabBar)
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 6)
    tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local function MakeTab(label: string, biomeId: string?, accentColor: Color3): (TextButton, Frame)
        local btn = Instance.new("TextButton", tabBar)
        btn.Size = UDim2.new(0, 0, 1, 0)
        btn.AutomaticSize = Enum.AutomaticSize.X
        btn.BackgroundColor3 = Color3.fromRGB(25, 20, 35)
        btn.TextColor3 = accentColor
        btn.Text = label
        btn.Font = Enum.Font.GothamBlack
        btn.TextSize = 13
        btn.AutoButtonColor = false
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
        local pad = Instance.new("UIPadding", btn)
        pad.PaddingLeft = UDim.new(0, 10)
        pad.PaddingRight = UDim.new(0, 10)

        local underline = Instance.new("Frame", btn)
        underline.Name = "Underline"
        underline.Size = UDim2.new(1, 0, 0, 3)
        underline.Position = UDim2.new(0, 0, 1, -3)
        underline.BackgroundColor3 = accentColor
        underline.BackgroundTransparency = 1
        underline.BorderSizePixel = 0

        btn.MouseButton1Click:Connect(function()
            selectedBiomeFilter = biomeId
            IndexController.Refresh(collectionCache)
            for _, t in ipairs(tabBar:GetChildren()) do
                if t:IsA("TextButton") then
                    local ul = t:FindFirstChild("Underline") :: Frame?
                    if ul then ul.BackgroundTransparency = 1 end
                    t.BackgroundColor3 = Color3.fromRGB(25, 20, 35)
                end
            end
            underline.BackgroundTransparency = 0
            btn.BackgroundColor3 = Color3.fromRGB(35, 28, 50)
        end)
        return btn, underline
    end

    local allBtn, allUl = MakeTab("ALL", nil, Color3.fromRGB(200, 180, 255))
    allUl.BackgroundTransparency = 0
    allBtn.BackgroundColor3 = Color3.fromRGB(35, 28, 50)

    for biomeId, biomeDef in pairs(AuraRegistry.Biomes) do
        MakeTab(string.upper(biomeDef.DisplayName), biomeId, biomeDef.Color or BIOME_FALLBACK_COLOR)
    end

    GridContainer = Instance.new("ScrollingFrame", MainPanel)
    GridContainer.Size = UDim2.new(0.6, -20, 1, -100)
    GridContainer.Position = UDim2.new(0, 15, 0, 90)
    GridContainer.BackgroundTransparency = 1
    GridContainer.ScrollBarThickness = 4
    GridContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    GridContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y

    DetailsPanel = Instance.new("Frame", MainPanel)
    DetailsPanel.Size = UDim2.new(0.4, -20, 1, -70)
    DetailsPanel.Position = UDim2.new(0.6, 5, 0, 55)
    DetailsPanel.BackgroundColor3 = Color3.fromRGB(18, 13, 30)
    Instance.new("UICorner", DetailsPanel).CornerRadius = UDim.new(0, 12)
    Instance.new("UIStroke", DetailsPanel).Color = Color3.fromRGB(80, 50, 130)

    local dpGrad = Instance.new("UIGradient", DetailsPanel)
    dpGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 18, 44)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 10, 22)),
    })
    dpGrad.Rotation = 160

    local selectedIcon = Instance.new("ImageLabel", DetailsPanel)
    selectedIcon.Name = "SelectedIcon"
    selectedIcon.Size = UDim2.new(0, 60, 0, 60)
    selectedIcon.Position = UDim2.new(1, -68, 0, 8)
    selectedIcon.BackgroundTransparency = 1
    selectedIcon.ScaleType = Enum.ScaleType.Fit
    selectedIcon.Image = FALLBACK_ICON
    selectedIcon.Visible = false

    local dTitle = Instance.new("TextLabel", DetailsPanel)
    dTitle.Name = "Title"
    dTitle.Size = UDim2.new(1, -75, 0, 60)
    dTitle.Position = UDim2.new(0, 10, 0, 0)
    dTitle.BackgroundTransparency = 1
    dTitle.Text = "SELECT AURA"
    dTitle.Font = Enum.Font.GothamBlack
    dTitle.TextSize = 18
    dTitle.TextColor3 = Color3.fromRGB(120, 120, 130)
    dTitle.TextXAlignment = Enum.TextXAlignment.Left

    local dRarity = Instance.new("TextLabel", DetailsPanel)
    dRarity.Name = "Rarity"
    dRarity.Size = UDim2.new(1, 0, 0, 25)
    dRarity.Position = UDim2.new(0, 10, 0, 60)
    dRarity.BackgroundTransparency = 1
    dRarity.Font = Enum.Font.GothamBlack
    dRarity.TextSize = 14
    dRarity.Text = ""
    dRarity.Visible = false
    dRarity.TextXAlignment = Enum.TextXAlignment.Left
    local rarityStroke = Instance.new("UIStroke", dRarity)
    rarityStroke.Color = Color3.fromRGB(0, 0, 0)
    rarityStroke.Thickness = 1.5
    rarityStroke.Transparency = 0.2

    local dPower = Instance.new("TextLabel", DetailsPanel)
    dPower.Name = "Power"
    dPower.Size = UDim2.new(1, -20, 0, 30)
    dPower.Position = UDim2.new(0, 10, 0, 85)
    dPower.BackgroundTransparency = 1
    dPower.Font = Enum.Font.GothamBold
    dPower.TextColor3 = Color3.fromRGB(200, 200, 200)
    dPower.Text = ""
    dPower.Visible = false
    dPower.TextXAlignment = Enum.TextXAlignment.Left
    dPower.TextScaled = true
    Instance.new("UITextSizeConstraint", dPower).MaxTextSize = 13

    local dLore = Instance.new("TextLabel", DetailsPanel)
    dLore.Name = "Lore"
    dLore.Size = UDim2.new(1, -20, 0, 50)
    dLore.Position = UDim2.new(0, 10, 0, 115)
    dLore.BackgroundTransparency = 1
    dLore.Font = Enum.Font.GothamBold
    dLore.TextWrapped = true
    dLore.TextScaled = true
    dLore.Text = ""
    dLore.Visible = false
    dLore.TextColor3 = Color3.fromRGB(180, 180, 200)
    dLore.TextXAlignment = Enum.TextXAlignment.Left
    Instance.new("UITextSizeConstraint", dLore).MaxTextSize = 12

    local dChance = Instance.new("TextLabel", DetailsPanel)
    dChance.Name = "Chance"
    dChance.Size = UDim2.new(1, -20, 0, 30)
    dChance.Position = UDim2.new(0, 10, 0, 165)
    dChance.BackgroundTransparency = 1
    dChance.Font = Enum.Font.GothamBlack
    dChance.TextColor3 = Color3.fromRGB(255, 215, 0)
    dChance.Text = ""
    dChance.Visible = false
    dChance.TextXAlignment = Enum.TextXAlignment.Left
    dChance.TextScaled = true
    Instance.new("UITextSizeConstraint", dChance).MaxTextSize = 14
    local cStroke = Instance.new("UIStroke", dChance)
    cStroke.Color = Color3.fromRGB(0, 0, 0)
    cStroke.Thickness = 1.5

    local equipBtnC = Instance.new("Frame", DetailsPanel)
    equipBtnC.Name = "EquipBtnContainer"
    equipBtnC.Size = UDim2.new(0, 160, 0, 45)
    equipBtnC.Position = UDim2.new(0.5, -80, 1, -65)
    equipBtnC.BackgroundTransparency = 1
    equipBtnC.Visible = false

    local equipBtn = Instance.new("TextButton", equipBtnC)
    equipBtn.Name = "EquipBtn"
    equipBtn.Size = UDim2.new(1, 0, 1, -4)
    equipBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 50)
    equipBtn.Text = "EQUIP"
    equipBtn.Font = Enum.Font.GothamBlack
    equipBtn.TextColor3 = Color3.new(1, 1, 1)
    Instance.new("UICorner", equipBtn).CornerRadius = UDim.new(0, 8)

    -- ── Open/close wiring ─────────────────────────────────────────────────────
    GetLocalEvent("ToggleIndex").Event:Connect(function()
        if isAnimating then return end
        if isOpen then
            closePanel()
        else
            isOpen = true
            isAnimating = true
            MainPanel.Visible = true
            BgShield.Visible = true
            PanelScale.Scale = 0
            local tw = TweenService:Create(PanelScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
            tw:Play()
            tw.Completed:Connect(function()
                isAnimating = false
            end)
            IndexController.UpdateDetailsPanel()
            GetLocalEvent("NotifyMenuOpened"):Fire("Index")
        end
    end)

    GetLocalEvent("NotifyMenuOpened").Event:Connect(function(openedMenuId: string)
        if isOpen and openedMenuId ~= "Index" then closePanel() end
    end)

    -- ── Equip wiring ──────────────────────────────────────────────────────────
    equipBtn.MouseButton1Click:Connect(function()
        if not selectedAuraId then return end
        equipBtn.Text = "WAITING..."
        local target = if selectedAuraId == currentEquippedId then "None" else selectedAuraId
        ;(remotes:WaitForChild("EquipRequest") :: RemoteEvent):FireServer(target)
    end)

    equipBestBtn.MouseButton1Click:Connect(function()
        local bestAuraId = GetBestAuraId()
        if bestAuraId then
            if bestAuraId == currentEquippedId then
                equipBestBtn.Text = "ALREADY BEST"
                task.delay(1.5, function() equipBestBtn.Text = "EQUIP BEST" end)
            else
                equipBestBtn.Text = "EQUIPPING..."
                ;(remotes:WaitForChild("EquipRequest") :: RemoteEvent):FireServer(bestAuraId)
            end
        else
            equipBestBtn.Text = "NO AURAS"
            task.delay(1.5, function() equipBestBtn.Text = "EQUIP BEST" end)
        end
    end)

    local function onEquippedChanged(auraId: string): ()
        currentEquippedId = auraId
        if equipBestBtn.Text == "EQUIPPING..." then
            equipBestBtn.Text = "BEST EQUIPPED!"
            task.delay(1.5, function() equipBestBtn.Text = "EQUIP BEST" end)
        end
        IndexController.UpdateDetailsPanel()
    end

    ;(remotes:WaitForChild("UpdateEquipped") :: RemoteEvent).OnClientEvent:Connect(function(auraId: any)
        if type(auraId) == "string" then
            onEquippedChanged(auraId)
        end
    end)

    -- Attribute covers late joins / initial state (AuraService publishes it)
    LocalPlayer:GetAttributeChangedSignal("EquippedAura"):Connect(function()
        local auraId = LocalPlayer:GetAttribute("EquippedAura")
        if type(auraId) == "string" then
            onEquippedChanged(auraId)
        end
    end)
    local initialEquipped = LocalPlayer:GetAttribute("EquippedAura")
    if type(initialEquipped) == "string" then
        currentEquippedId = initialEquipped
    end

    ;(remotes:WaitForChild("UpdateCollection") :: RemoteEvent).OnClientEvent:Connect(function(collection: any)
        if type(collection) ~= "table" then return end
        IndexController.Refresh(collection)
        IndexController.UpdateDetailsPanel()
    end)

    -- Seed owned auras from the full-state sync (rolls only send deltas after)
    local updateProfileRemote = remotes:WaitForChild("UpdateProfileData", 5) :: RemoteEvent?
    if updateProfileRemote then
        updateProfileRemote.OnClientEvent:Connect(function(data: any)
            if type(data) ~= "table" or type(data.GenreData) ~= "table" then return end
            local genreData = data.GenreData.Aura_Collector
            if type(genreData) == "table" and type(genreData.Collection) == "table" then
                IndexController.Refresh(genreData.Collection)
            end
        end)
    end

    IndexController.Refresh({})
end

return IndexController
