--!strict
--@author OrkGabb
--@module IndexController.luau
--@version 1.0
-- src/Client/Controllers/IndexController.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Players           = game:GetService("Players")
local LocalPlayer       = Players.LocalPlayer

local LootTableModule   = require(ReplicatedStorage.Shared.Modules.LootTable)
local AssetRegistry     = require(ReplicatedStorage.Shared.Config.AssetRegistry)

local FALLBACK_ICON = "rbxassetid://15059633013"

-- RarityConfig (SSoT)
local RarityConfig: {[string]: {Color: Color3, FontSize: number?, GlowAlpha: number?}} = {
    COMMON      = { Color = Color3.fromRGB(120, 120, 120), FontSize = 11, GlowAlpha = 0   },
    UNCOMMON    = { Color = Color3.fromRGB(80,  200, 120), FontSize = 11, GlowAlpha = 0   },
    RARE        = { Color = Color3.fromRGB(45,  107, 228), FontSize = 11, GlowAlpha = 0   },
    EPIC        = { Color = Color3.fromRGB(180,  50, 255), FontSize = 12, GlowAlpha = 0.3 },
    LEGENDARY   = { Color = Color3.fromRGB(228, 167,  45), FontSize = 12, GlowAlpha = 0.5 },
    MYTHIC      = { Color = Color3.fromRGB(228,  45,  45), FontSize = 13, GlowAlpha = 0.5 },
    MUTANT      = { Color = Color3.fromRGB(255, 100, 220), FontSize = 13, GlowAlpha = 0.5 },
    ABYSSAL     = { Color = Color3.fromRGB(120,   0, 180), FontSize = 13, GlowAlpha = 0.6 },
    COSMIC      = { Color = Color3.fromRGB(0,   200, 255), FontSize = 14, GlowAlpha = 0.6 },
    VIP         = { Color = Color3.fromRGB(255, 215,   0), FontSize = 14, GlowAlpha = 0.7 },
    SINGULARITY = { Color = Color3.fromRGB(255, 255, 255), FontSize = 14, GlowAlpha = 0.7 },
    EXOTIC      = { Color = Color3.fromRGB(0,   255, 120), FontSize = 15, GlowAlpha = 0.7 },
    OMNI        = { Color = Color3.fromRGB(255, 255, 255), FontSize = 16, GlowAlpha = 0.8 },
}

local RarityHierarchy: {[string]: number} = {
    COMMON      = 1,
    UNCOMMON    = 2,
    RARE        = 3,
    EPIC        = 4,
    LEGENDARY   = 5,
    MYTHIC      = 6,
    MUTANT      = 7,
    ABYSSAL     = 8,
    COSMIC      = 9,
    VIP         = 9,
    SINGULARITY = 10,
    EXOTIC      = 11,
    OMNI        = 12,
}

local RARITY_FALLBACK_COLOR = Color3.fromRGB(120, 120, 120)
local BIOME_FALLBACK_COLOR  = Color3.fromRGB(80, 80, 100)
local selectedBiomeFilter: string? = nil

-- Unified Item Lore
local ITEM_LORE: {[string]: string} = {
    -- Global items
    ["Starter Badge"]   = "Given to every adventurer starting their journey.",
    ["Bronze Medal"]    = "A symbol of basic achievement and focus.",
    ["Silver Medal"]    = "Recognizes those who push beyond initial limits.",
    ["Gold Medal"]      = "The standard of excellence for dedicated champions.",
    ["Star Trophy"]     = "Shines brightly with the hope of future accomplishments.",
    ["Crown Jewel"]     = "A precious artifact from royal lineages.",
    ["Forest Token"]    = "Acquired in the heart of the forest sanctuary.",
    ["Woodland Crest"]  = "A leaf-covered emblem of natural harmony.",
    ["Ancient Bark"]    = "Durable bark harvested from millennial trees.",
    ["Nature Core"]     = "Pulses with the raw, green energy of nature.",
    ["Rift Pearl"]      = "A mysterious gem found floating near the abyss.",
    ["Cosmic Core"]     = "The superdense center of a collapsed nebula.",
    ["Infinity Relic"]  = "Transcends the bounds of time and space.",
    ["VIP Tag"]         = "Exclusively granted to distinguished premium users.",

    -- Clicker Farm items
    ["Speed Booster I"] = "Increases roll speeds to quicken progress.",
    ["Coin Booster I"]  = "Generates higher coin yields on click actions.",
    ["Coin Booster II"] = "Doubles click coin outcomes for fast expansion.",
    ["Luck Booster I"]  = "Slightly raises chances of higher-tier item rolls.",
    ["Super Booster I"] = "A potent booster for high-speed clicking.",
    ["Hyper Booster I"] = "Unleashes maximum booster capacities.",

    -- FPS Shooter items
    ["Rusty Pistol"]    = "A discarded handgun, reliable in emergencies.",
    ["Standard Pistol"] = "Standard issue sidearm with balanced stats.",
    ["Tactical Pistol"] = "Equipped with custom attachments for accuracy.",
    ["Light SMG"]       = "High rate of fire, ideal for close-quarter combat.",
    ["Heavy Shotgun"]   = "Close-range power that commands respect.",
    ["Golden Pistol"]   = "A sidearm decorated with pure gold accents.",

    -- RPG Adventure items
    ["Wooden Club"]     = "A basic, heavy wooden bludgeon.",
    ["Stone Sword"]     = "Carved out of hard granite with a sharp edge.",
    ["Iron Dagger"]     = "Quick, silent, and deadly in the right hands.",
    ["Steel Greatsword"]= "Requires two hands to wield. Deals devastating blows.",
    ["Champion Blade"]  = "Forged for the arena's most valorous warriors.",
    ["Relic Sword"]     = "Infused with standard runic glyphs of power.",

    -- Pet Simulator items
    ["Common Cat"]      = "A friendly feline companion that boosts progression.",
    ["Common Dog"]      = "A loyal puppy ready to accompany you anywhere.",
    ["Spotted Bunny"]   = "Hops around and gathers loose resources.",
    ["Red Fox"]         = "Quick and cunning, finding hidden items.",
    ["Royal Pegasus"]   = "A majestic winged horse of legend.",
    ["Phoenix Pet"]     = "A pet reborn from ashes, offering ultimate luck.",
}

local MOD_LORE: {[string]: string} = {
    Cursed = "Tainted by an ancient malice, its power comes with a heavy price.",
    Glitch = "A fragmented anomaly, breaking the very rules of its existence.",
}

-- O(1) membership cache: itemName -> biomeId
local _biomeMembershipCache: {[string]: string} = {}
local function RebuildMembershipCache()
    table.clear(_biomeMembershipCache)
    for biomeId, biomeDef in pairs(LootTableModule.Biomes) do
        local idToMatch = biomeDef.Id or biomeId
        for _, a in ipairs(biomeDef.Items) do
            _biomeMembershipCache[a.name] = idToMatch
        end
    end
end

RebuildMembershipCache()

local function ShouldShowItem(itemName: string): boolean
    if selectedBiomeFilter == nil then return true end
    return _biomeMembershipCache[itemName] == selectedBiomeFilter
end

local function GetRarityColor(rarityTag: string): Color3
    local entry = RarityConfig[rarityTag]
    return entry and entry.Color or RARITY_FALLBACK_COLOR
end

local OMNI_SPECTRUM = {
    Color3.fromRGB(228,  45,  45),
    Color3.fromRGB(228, 167,  45),
    Color3.fromRGB(228, 228,  45),
    Color3.fromRGB(45,  228, 120),
    Color3.fromRGB(45,  107, 228),
    Color3.fromRGB(123,  47, 190),
}

local StrokeConfig: {[string]: {thickness: number, pulse: boolean}} = {
    EPIC        = { thickness = 1.8, pulse = false },
    LEGENDARY   = { thickness = 2.0, pulse = false },
    MYTHIC      = { thickness = 2.5, pulse = true  },
    MUTANT      = { thickness = 2.5, pulse = true  },
    ABYSSAL     = { thickness = 2.8, pulse = true  },
    COSMIC      = { thickness = 2.8, pulse = true  },
    VIP         = { thickness = 3.0, pulse = true  },
    SINGULARITY = { thickness = 3.2, pulse = true  },
    EXOTIC      = { thickness = 3.2, pulse = true  },
    OMNI        = { thickness = 3.5, pulse = true  },
}

local function StartOmniAnimation(element: GuiObject, prop: string)
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

local function StartStrokePulse(stroke: UIStroke, rarityColor: Color3)
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

local IndexController = {}
local MainPanel: Frame
local GridContainer: ScrollingFrame
local DetailsPanel: Frame
local PanelScale: UIScale
local BgShield: TextButton
local isOpen             = false
local selectedItemId: string? = nil
local currentEquippedId: string? = nil
local collectionCache    = {}
local ascensionsCache    = {}
local selectedSlot: TextButton? = nil
local selectedStroke: UIStroke? = nil

local function FormatSuffix(n: number): string
    if n < 1000 then return string.format("%.1f", n):gsub("%.0", "") end
    local suffixes = {"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"}
    local i = math.floor(math.log10(n) / 3)
    local v = n / (10 ^ (i * 3))
    local suffix = suffixes[i + 1] or "e" .. tostring(i * 3)
    local formatted = string.format("%.1f%s", v, suffix)
    return formatted:gsub("%.0", "")
end

local function GetLocalEvent(eventName: string): BindableEvent
    local folder = ReplicatedStorage:FindFirstChild("LocalEvents") or Instance.new("Folder")
    folder.Name   = "LocalEvents"
    folder.Parent = ReplicatedStorage

    local evt = folder:FindFirstChild(eventName) or Instance.new("BindableEvent")
    evt.Name   = eventName
    evt.Parent = folder

    return evt :: BindableEvent
end

local function GetBestItemId(): string?
    local bestId   = nil
    local maxPower = -1

    for itemId, amount in pairs(collectionCache) do
        if not amount or amount <= 0 then continue end
        local itemData = LootTableModule.GetItemData(itemId)
        if not itemData or itemData.name == "None" or itemData.name == "" then continue end

        local power = (itemData.coinMult or 1) * (itemData.expMult or 1)
        if power > maxPower then
            maxPower = power
            bestId   = itemId
        end
    end

    return bestId
end

function IndexController.Refresh(collection: {[string]: number}, ascensions: {[string]: number}?)
    collectionCache = collection
    if ascensions then ascensionsCache = ascensions end
    if not GridContainer then return end

    RebuildMembershipCache()

    for _, child in ipairs(GridContainer:GetChildren()) do
        if child:IsA("Frame") or child:IsA("UILayout") or child:IsA("UIListLayout") or child:IsA("UIGridLayout") or child:IsA("UIPadding") then
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

    local allItems  = {}
    local seenBases = {}

    for _, biome in pairs(LootTableModule.Biomes) do
        for _, item in ipairs(biome.Items) do
            local owned = collectionCache[item.name] ~= nil and collectionCache[item.name] > 0
            if owned and not seenBases[item.name] then
                seenBases[item.name] = true
                table.insert(allItems, { id = item.name, weight = item.weight, biomeId = biome.Id or "Default" })
            end
        end
    end

    if LootTableModule.PaidAuras then
        for _, item in ipairs(LootTableModule.PaidAuras) do
            local owned = collectionCache[item.name] ~= nil and collectionCache[item.name] > 0
            if owned and not seenBases[item.name] then
                seenBases[item.name] = true
                table.insert(allItems, { id = item.name, weight = item.weight, biomeId = "Exclusive" })
            end
        end
    end

    table.sort(allItems, function(a, b)
        local baseA = string.split(a.id, ":")[1]
        local baseB = string.split(b.id, ":")[1]
        local dataA = LootTableModule.GetItemData(baseA)
        local dataB = LootTableModule.GetItemData(baseB)

        local tagA = dataA and dataA.rarityTag or "COMMON"
        local tagB = dataB and dataB.rarityTag or "COMMON"

        local powerA = RarityHierarchy[tagA] or 0
        local powerB = RarityHierarchy[tagB] or 0

        if powerA ~= powerB then
            return powerA < powerB
        end

        local multA = dataA and dataA.coinMult or 0
        local multB = dataB and dataB.coinMult or 0
        if multA ~= multB then
            return multA < multB
        end

        return a.id < b.id
    end)

    local CategoriesConfig = {
        { Title = "ALL",             Tiers = {COMMON=true, UNCOMMON=true, RARE=true, EPIC=true, LEGENDARY=true, MYTHIC=true}, Items = {} },
        { Title = "MUTANTS",         Tiers = {MUTANT=true}, Items = {} },
        { Title = "THE SINGULARITY", Tiers = {ABYSSAL=true, COSMIC=true, SINGULARITY=true, EXOTIC=true, OMNI=true}, Items = {} },
        { Title = "EXCLUSIVES",      Tiers = {VIP=true}, Items = {} }
    }

    for _, item in ipairs(allItems) do
        local split    = string.split(item.id, ":")
        local baseName = split[1]
        local itemData = LootTableModule.GetItemData(baseName)
        if not itemData or itemData.name == "None" then continue end
        if not ShouldShowItem(baseName) then continue end
        
        local tag = itemData.rarityTag or "COMMON"
        local foundCat = false
        for _, cat in ipairs(CategoriesConfig) do
            if cat.Tiers[tag] then
                table.insert(cat.Items, item)
                foundCat = true
                break
            end
        end
        if not foundCat then
            table.insert(CategoriesConfig[1].Items, item)
        end
    end

    local layoutOrderCat = 1
    for _, cat in ipairs(CategoriesConfig) do
        if #cat.Items == 0 then continue end
        
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
        
        if isPremium then
            grid.CellSize = UDim2.new(1, -20, 0, 95)
        else
            grid.CellSize = UDim2.new(0, 85, 0, 85)
        end
        
        for _, item in ipairs(cat.Items) do
            local baseName = item.id
            local itemData = LootTableModule.GetItemData(baseName)
            local isUnlocked = collectionCache[item.id] ~= nil and collectionCache[item.id] > 0

            local studBase = Instance.new("Frame", gridHolder)
            studBase.BackgroundTransparency = 1
            studBase.Name = item.id

            local slot = Instance.new("TextButton", studBase)
            slot.Size                   = UDim2.new(1, 0, 1, 0)
            slot.BackgroundColor3       = isUnlocked and Color3.fromRGB(16, 12, 20) or Color3.fromRGB(12, 8, 20)
            slot.BackgroundTransparency = isUnlocked and 0 or 0.3
            slot.Text                   = ""
            slot.AutoButtonColor        = false
            slot.ClipsDescendants       = false
            Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 8)

            local rColor   = GetRarityColor(itemData.rarityTag)
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

            local stroke    = Instance.new("UIStroke", slot)
            local strokeCfg = StrokeConfig[itemData.rarityTag]
            stroke.Thickness = (isUnlocked and strokeCfg and strokeCfg.thickness) or 1.5
            if isUnlocked then
                stroke.Color = rColor
                if itemData.rarityTag == "OMNI" then
                    StartOmniAnimation(stroke, "Color")
                elseif strokeCfg and strokeCfg.pulse then
                    StartStrokePulse(stroke, rColor)
                end
            else
                stroke.Color = Color3.fromRGB(80, 60, 110)
            end

            local ORNAMENT_TIERS = {
                LEGENDARY=true, MYTHIC=true, MUTANT=true,
                ABYSSAL=true, COSMIC=true, SINGULARITY=true, EXOTIC=true, OMNI=true
            }
            if isUnlocked and ORNAMENT_TIERS[itemData.rarityTag] then
                local outerStroke = Instance.new("UIStroke", studBase)
                outerStroke.Thickness    = 1.0
                outerStroke.Color        = rColor
                outerStroke.Transparency = 0.55
                if itemData.rarityTag == "OMNI" then
                    StartOmniAnimation(outerStroke, "Color")
                elseif StrokeConfig[itemData.rarityTag] and StrokeConfig[itemData.rarityTag].pulse then
                    StartStrokePulse(outerStroke, rColor)
                end
            end

            local rarCfg = RarityConfig[itemData.rarityTag]
            if isUnlocked and rarCfg and (rarCfg.GlowAlpha or 0) > 0 then
                local glow = Instance.new("Frame", studBase)
                glow.Name                   = "GlowFrame"
                glow.Size                   = UDim2.new(1, 16, 1, 16)
                glow.Position               = UDim2.new(0, -8, 0, -8)
                glow.ZIndex                 = slot.ZIndex - 2
                glow.BackgroundColor3       = rColor
                glow.BackgroundTransparency = 1 - rarCfg.GlowAlpha
                glow.BorderSizePixel        = 0
                Instance.new("UICorner", glow).CornerRadius = UDim.new(0, 14)
                
                if strokeCfg and strokeCfg.pulse then
                    task.spawn(function()
                        while glow and glow.Parent do
                            TweenService:Create(glow, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = 1 - (rarCfg.GlowAlpha * 1.5) }):Play()
                            task.wait(1.0)
                            if not (glow and glow.Parent) then break end
                            TweenService:Create(glow, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = 1 - rarCfg.GlowAlpha }):Play()
                            task.wait(1.0)
                        end
                    end)
                end
            end

            if isUnlocked and isPremium then
                local bgContainer = Instance.new("Frame", slot)
                bgContainer.Size = UDim2.new(1, 0, 1, 0)
                bgContainer.BackgroundTransparency = 1
                bgContainer.ClipsDescendants = true
                bgContainer.ZIndex = slot.ZIndex - 1
                Instance.new("UICorner", bgContainer).CornerRadius = UDim.new(0, 8)

                local bgTexture = Instance.new("ImageLabel", bgContainer)
                bgTexture.Name = "AnimatedBg"
                bgTexture.Size = UDim2.new(1, 30, 1, 30)
                bgTexture.Position = UDim2.new(0, -15, 0, -15)
                bgTexture.BackgroundTransparency = 1
                bgTexture.Image = "rbxassetid://10462002307" 
                bgTexture.ScaleType = Enum.ScaleType.Tile
                bgTexture.TileSize = UDim2.new(0, 256, 0, 256)
                bgTexture.ImageTransparency = 0.85
                bgTexture.ImageColor3 = rColor
                bgTexture.ZIndex = slot.ZIndex - 1
                
                slot.MouseMoved:Connect(function(x, y)
                    local absCenter = slot.AbsolutePosition + (slot.AbsoluteSize / 2)
                    local dx = (x - absCenter.X) / slot.AbsoluteSize.X
                    local dy = (y - absCenter.Y) / slot.AbsoluteSize.Y
                    
                    TweenService:Create(bgTexture, TweenInfo.new(0.2), {
                        Position = UDim2.new(0, -15 - (dx * 15), 0, -15 - (dy * 15))
                    }):Play()
                end)
                
                slot.MouseLeave:Connect(function()
                    TweenService:Create(bgTexture, TweenInfo.new(0.4), {
                        Position = UDim2.new(0, -15, 0, -15)
                    }):Play()
                end)
            end

            local watermark = Instance.new("TextLabel", slot)
            watermark.BackgroundTransparency = 1
            local finalNameStr = itemData.displayName or baseName
            watermark.Text                   = isUnlocked and string.sub(finalNameStr, 1, 1):upper() or "?"
            watermark.Font                   = Enum.Font.GothamBlack
            watermark.TextColor3             = rColor
            watermark.TextTransparency       = 0.93
            watermark.ZIndex                 = slot.ZIndex
            
            local iconImg = Instance.new("ImageLabel", slot)
            iconImg.Name                   = "ItemIcon"
            iconImg.BackgroundTransparency = 1
            iconImg.ScaleType              = Enum.ScaleType.Fit
            iconImg.Image                  = itemData.iconId or FALLBACK_ICON
            iconImg.ZIndex                 = slot.ZIndex + 1

            local nameLabel = Instance.new("TextLabel", slot)
            nameLabel.BackgroundTransparency = 1
            nameLabel.TextScaled             = true
            nameLabel.ZIndex                 = slot.ZIndex + 2
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
                nameConstraint.MaxTextSize = (rarCfg and rarCfg.FontSize) and (rarCfg.FontSize + 4) or 16
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
                nameConstraint.MaxTextSize = (rarCfg and rarCfg.FontSize) and (rarCfg.FontSize + 2) or 12
            end

            if itemData.rarityTag == "OMNI" and isUnlocked then
                StartOmniAnimation(watermark, "TextColor3")
                StartOmniAnimation(nameLabel, "TextColor3")
            end

            if not isUnlocked then
                iconImg.ImageColor3       = Color3.fromRGB(20, 15, 30)
                iconImg.ImageTransparency = 0.3
                nameLabel.Text             = "?"
                nameLabel.Font             = Enum.Font.GothamBlack
                nameLabel.TextColor3       = Color3.fromRGB(160, 140, 200)
                nameLabel.TextTransparency = 0.2
                nameConstraint.MaxTextSize = 20

                task.spawn(function()
                    while nameLabel and nameLabel.Parent and not isUnlocked do
                        local t1 = TweenService:Create(nameLabel, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { TextTransparency = 0.45 })
                        t1:Play(); t1.Completed:Wait()
                        if not (nameLabel and nameLabel.Parent) then break end
                        local t2 = TweenService:Create(nameLabel, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { TextTransparency = 0.1 })
                        t2:Play(); t2.Completed:Wait()
                    end
                end)
            else
                iconImg.ImageColor3 = Color3.new(1, 1, 1)
                nameLabel.Text             = string.upper(itemData.displayName or baseName)
                nameLabel.Font             = Enum.Font.GothamBlack
                nameLabel.TextColor3       = rColor
            end

            local nameLabelStroke = Instance.new("UIStroke", nameLabel)
            nameLabelStroke.Color        = Color3.fromRGB(0, 0, 0)
            nameLabelStroke.Thickness    = 1.2
            nameLabelStroke.Transparency = 0.2

            slot.MouseButton1Click:Connect(function()
                if not isUnlocked then return end

                if selectedSlot and selectedStroke then
                    TweenService:Create(selectedStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Thickness = 1.5 }):Play()
                    local prevStudBase = selectedSlot.Parent
                    local prevScale    = prevStudBase and prevStudBase:FindFirstChildOfClass("UIScale")
                    if prevScale then
                        TweenService:Create(prevScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
                    end
                end

                selectedSlot   = slot
                selectedStroke = stroke
                selectedItemId = item.id

                TweenService:Create(selectedStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Thickness = 3.5 }):Play()
                TweenService:Create(studScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 0.93 }):Play()

                IndexController.UpdateDetailsPanel()
            end)
        end
    end
end

function IndexController.UpdateDetailsPanel()
    if not selectedItemId or not DetailsPanel then return end

    local equipC    = DetailsPanel:FindFirstChild("EquipBtnContainer")
    local rarityTxt = DetailsPanel:FindFirstChild("Rarity")       :: TextLabel?
    local yieldTxt  = DetailsPanel:FindFirstChild("Power")        :: TextLabel?
    local costTxt   = DetailsPanel:FindFirstChild("Cost")         :: TextLabel?
    local chanceTxt = DetailsPanel:FindFirstChild("Chance")       :: TextLabel?
    local dIcon     = DetailsPanel:FindFirstChild("SelectedIcon") :: ImageLabel?

    if equipC    then equipC.Visible    = true end
    if rarityTxt then rarityTxt.Visible = true end
    if yieldTxt  then yieldTxt.Visible  = true end
    if costTxt   then costTxt.Visible   = true end
    if chanceTxt then chanceTxt.Visible = true end
    if dIcon     then dIcon.Visible     = true end

    local split    = string.split(selectedItemId, ":")
    local baseName = split[1]

    local itemData = LootTableModule.GetItemData(baseName)
    if not itemData or itemData.name == "None" then return end

    local title     = DetailsPanel:FindFirstChild("Title") :: TextLabel?
    local equipBtn  = DetailsPanel:FindFirstChild("EquipBtnContainer")
        and (DetailsPanel:FindFirstChild("EquipBtnContainer") :: Frame):FindFirstChild("EquipBtn") :: TextButton?

    if equipBtn then
        local isEquipped          = (selectedItemId == currentEquippedId)
        equipBtn.Text             = isEquipped and "EQUIPPED" or "EQUIP"
        equipBtn.BackgroundColor3 = isEquipped
            and Color3.fromRGB(60, 60, 65)
            or  Color3.fromRGB(0, 140, 50)
    end

    if dIcon then
        dIcon.Image = itemData.iconId or FALLBACK_ICON
    end

    if title then
        title.Text       = string.upper(itemData.displayName or baseName)
        title.TextColor3 = GetRarityColor(itemData.rarityTag)
        if itemData.rarityTag == "OMNI" then StartOmniAnimation(title, "TextColor3") end
    end

    if rarityTxt then
        rarityTxt.Text = itemData.rarityTag or "UNKNOWN"
        local RARITY_SIZES = {
            COMMON=12, UNCOMMON=12, RARE=13, EPIC=13,
            LEGENDARY=14, MYTHIC=14, MUTANT=14,
            ABYSSAL=15, COSMIC=15, SINGULARITY=16, EXOTIC=16, OMNI=18
        }
        rarityTxt.TextSize   = dRarity_text_size or (RARITY_SIZES[itemData.rarityTag] or 13)
        rarityTxt.Font       = Enum.Font.GothamBlack
        rarityTxt.TextColor3 = GetRarityColor(itemData.rarityTag)

        if not rarityTxt:FindFirstChildOfClass("UIStroke") then
            local rs = Instance.new("UIStroke", rarityTxt)
            rs.Color        = Color3.fromRGB(0, 0, 0)
            rs.Thickness    = 1.5
            rs.Transparency = 0.2
        end

        if itemData.rarityTag == "OMNI" then StartOmniAnimation(rarityTxt, "TextColor3") end
    end

    if chanceTxt then
        local totalWeight = 0
        for _, biome in pairs(LootTableModule.Biomes) do
            local found = false
            for _, a in ipairs(biome.Items) do
                if a.name == baseName then found = true end
            end
            if found then
                for _, a in ipairs(biome.Items) do totalWeight += a.weight end
                break
            end
        end

        local chanceReal = 1
        if itemData.weight and itemData.weight > 0 then
            chanceReal = math.floor(totalWeight / itemData.weight)
        end

        chanceTxt.Text = "DROP CHANCE: 1 in " .. FormatSuffix(chanceReal)
    end

    if yieldTxt then
        yieldTxt.Text = string.format("BOOSTS: Coins x%s | EXP x%s", FormatSuffix(itemData.coinMult or 1), FormatSuffix(itemData.expMult or 1))
    end

    if costTxt then
        local itemLoreText = ITEM_LORE[baseName] or ""
        costTxt.Text = itemLoreText ~= "" and ("\"" .. itemLoreText .. "\"") or ""
        costTxt.TextColor3 = Color3.fromRGB(180, 180, 200)
    end
end

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
        end
    })

    local gui = Instance.new("ScreenGui", LocalPlayer.PlayerGui)
    gui.Name         = "IndexGui"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 20

    BgShield = Instance.new("TextButton", gui)
    BgShield.Name                   = "InputSink"
    BgShield.Size                   = UDim2.fromScale(1, 1)
    BgShield.BackgroundTransparency = 1
    BgShield.Text                   = ""
    BgShield.AutoButtonColor        = false
    BgShield.Visible                = false
    BgShield.Active                 = true
    BgShield.MouseButton1Up:Connect(closePanel)

    MainPanel = Instance.new("Frame", gui)
    MainPanel.Size             = UDim2.new(0, 620, 0, 420)
    MainPanel.Position         = UDim2.new(0.5, -310, 0.5, -210)
    MainPanel.BackgroundColor3 = Color3.fromRGB(14, 11, 22)
    MainPanel.Active           = true
    MainPanel.Visible          = false
    Instance.new("UICorner", MainPanel).CornerRadius = UDim.new(0, 16)

    local mpGrad = Instance.new("UIGradient", MainPanel)
    mpGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 15, 35)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10,  8, 18)),
    })
    mpGrad.Rotation = 135

    local mpStroke = Instance.new("UIStroke", MainPanel)
    mpStroke.Color     = Color3.fromRGB(90, 60, 150)
    mpStroke.Thickness = 2

    PanelScale       = Instance.new("UIScale", MainPanel)
    PanelScale.Scale = 0

    local function closePanel()
        if not isOpen then return end
        isOpen           = false
        isAnimating       = true
        BgShield.Visible = false
        GetLocalEvent("NotifyMenuClosed"):Fire("Index")
        local tw = TweenService:Create(PanelScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
        tw:Play()
        tw.Completed:Connect(function()
            isAnimating = false
            if not isOpen then MainPanel.Visible = false end
        end)
    end

    local closeBtn = Instance.new("TextButton", MainPanel)
    closeBtn.Size                   = UDim2.new(0, 30, 0, 30)
    closeBtn.Position               = UDim2.new(1, -15, 0, 15)
    closeBtn.AnchorPoint            = Vector2.new(1, 0)
    closeBtn.AutoButtonColor     = false
    closeBtn.Text                   = "X"
    closeBtn.TextColor3             = Color3.fromRGB(255, 255, 255)
    closeBtn.TextScaled             = true
    closeBtn.Font                   = Enum.Font.GothamBlack
    closeBtn.BackgroundColor3       = Color3.fromRGB(220, 50, 50)
    closeBtn.BackgroundTransparency = 0

    local corner = Instance.new("UICorner", closeBtn)
    corner.CornerRadius = UDim.new(0, 8)
    
    local stroke = Instance.new("UIStroke", closeBtn)
    stroke.Color = Color3.fromRGB(120, 20, 20)
    stroke.Thickness = 2
    
    local cIcon = closeBtn:FindFirstChild("HD_Icon")
    if cIcon then cIcon:Destroy() end

    local TweenService = game:GetService("TweenService")
    local clickTw = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    closeBtn.MouseEnter:Connect(function() TweenService:Create(closeBtn, clickTw, {Size = UDim2.new(0, 32, 0, 32), BackgroundColor3 = Color3.fromRGB(255, 70, 70)}):Play() end)
    closeBtn.MouseLeave:Connect(function() TweenService:Create(closeBtn, clickTw, {Size = UDim2.new(0, 30, 0, 30), BackgroundColor3 = Color3.fromRGB(220, 50, 50)}):Play() end)
    closeBtn.MouseButton1Down:Connect(function() TweenService:Create(closeBtn, clickTw, {Size = UDim2.new(0, 26, 0, 26)}):Play() end)
    closeBtn.MouseButton1Up:Connect(function() TweenService:Create(closeBtn, clickTw, {Size = UDim2.new(0, 32, 0, 32)}):Play() end)

    closeBtn.MouseButton1Up:Connect(closePanel)

    local remotes = ReplicatedStorage:WaitForChild("Remotes")

    local equipBestBtn = Instance.new("TextButton", MainPanel)
    equipBestBtn.Size             = UDim2.new(0, 100, 0, 30)
    equipBestBtn.Position         = UDim2.new(1, -55, 0, 15)
    equipBestBtn.AnchorPoint      = Vector2.new(1, 0)
    equipBestBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 50)
    equipBestBtn.Text             = "EQUIP BEST"
    equipBestBtn.Font             = Enum.Font.GothamBlack
    equipBestBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
    equipBestBtn.TextSize         = 12
    equipBestBtn.AutoButtonColor  = false
    Instance.new("UICorner", equipBestBtn).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", equipBestBtn).Color        = Color3.fromRGB(0, 80, 30)

    local panelTitle = Instance.new("TextLabel", MainPanel)
    panelTitle.Size                   = UDim2.new(1, 0, 0, 50)
    panelTitle.BackgroundTransparency = 1
    panelTitle.Text                   = "COLLECTION"
    panelTitle.Font                   = Enum.Font.GothamBlack
    panelTitle.TextSize               = 22
    panelTitle.TextColor3             = Color3.fromRGB(255, 255, 255)

    local tabBar = Instance.new("Frame", MainPanel)
    tabBar.Name                   = "BiomeTabBar"
    tabBar.Size                   = UDim2.new(0.6, -20, 0, 36)
    tabBar.Position               = UDim2.new(0, 15, 0, 50)
    tabBar.BackgroundTransparency = 1
    tabBar.BorderSizePixel        = 0

    local tabLayout = Instance.new("UIListLayout", tabBar)
    tabLayout.FillDirection     = Enum.FillDirection.Horizontal
    tabLayout.Padding           = UDim.new(0, 6)
    tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local function MakeTab(label: string, biomeId: string?, accentColor: Color3)
        local btn = Instance.new("TextButton", tabBar)
        btn.Size             = UDim2.new(0, 0, 1, 0)
        btn.AutomaticSize    = Enum.AutomaticSize.X
        btn.BackgroundColor3 = Color3.fromRGB(25, 20, 35)
        btn.TextColor3       = accentColor
        btn.Text             = label
        btn.Font             = Enum.Font.GothamBlack
        btn.TextSize         = 13
        btn.AutoButtonColor  = false
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
        local pad = Instance.new("UIPadding", btn)
        pad.PaddingLeft  = UDim.new(0, 10)
        pad.PaddingRight = UDim.new(0, 10)

        local underline = Instance.new("Frame", btn)
        underline.Name                   = "Underline"
        underline.Size                   = UDim2.new(1, 0, 0, 3)
        underline.Position               = UDim2.new(0, 0, 1, -3)
        underline.BackgroundColor3       = accentColor
        underline.BackgroundTransparency = 1
        underline.BorderSizePixel        = 0

        btn.MouseButton1Click:Connect(function()
            selectedBiomeFilter = biomeId
            IndexController.Refresh(collectionCache, ascensionsCache)
            for _, t in ipairs(tabBar:GetChildren()) do
                if t:IsA("TextButton") then
                    local ul = t:FindFirstChild("Underline")
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

    for biomeId, biomeDef in pairs(LootTableModule.Biomes) do
        local color = biomeDef.Color or BIOME_FALLBACK_COLOR
        local bId   = biomeDef.Id or biomeId
        MakeTab(string.upper(biomeDef.DisplayName or bId), bId, color)
    end

    GridContainer = Instance.new("ScrollingFrame", MainPanel)
    GridContainer.Size                   = UDim2.new(0.6, -20, 1, -100)
    GridContainer.Position               = UDim2.new(0, 15, 0, 90)
    GridContainer.BackgroundTransparency = 1
    GridContainer.ScrollBarThickness     = 4
    GridContainer.CanvasSize             = UDim2.new(0, 0, 0, 0)
    GridContainer.AutomaticCanvasSize    = Enum.AutomaticSize.Y

    local grid = Instance.new("UIGridLayout", GridContainer)
    grid.CellSize    = UDim2.new(0, 85, 0, 82)
    grid.CellPadding = UDim2.new(0, 6, 0, 6)

    local gridPad = Instance.new("UIPadding", GridContainer)
    gridPad.PaddingLeft   = UDim.new(0, 6)
    gridPad.PaddingTop    = UDim.new(0, 6)
    gridPad.PaddingRight  = UDim.new(0, 6)
    gridPad.PaddingBottom = UDim.new(0, 6)

    DetailsPanel = Instance.new("Frame", MainPanel)
    DetailsPanel.Size             = UDim2.new(0.4, -20, 1, -70)
    DetailsPanel.Position         = UDim2.new(0.6, 5, 0, 55)
    DetailsPanel.BackgroundColor3 = Color3.fromRGB(18, 13, 30)
    Instance.new("UICorner", DetailsPanel).CornerRadius = UDim.new(0, 12)
    Instance.new("UIStroke", DetailsPanel).Color        = Color3.fromRGB(80, 50, 130)

    local dpGrad = Instance.new("UIGradient", DetailsPanel)
    dpGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 18, 44)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 10, 22)),
    })
    dpGrad.Rotation = 160

    local selectedIcon = Instance.new("ImageLabel", DetailsPanel)
    selectedIcon.Name                   = "SelectedIcon"
    selectedIcon.Size                   = UDim2.new(0, 60, 0, 60)
    selectedIcon.Position               = UDim2.new(1, -68, 0, 8)
    selectedIcon.AnchorPoint            = Vector2.new(0, 0)
    selectedIcon.BackgroundTransparency = 1
    selectedIcon.ScaleType              = Enum.ScaleType.Fit
    selectedIcon.Image                  = FALLBACK_ICON
    selectedIcon.Visible                = false

    local dTitle = Instance.new("TextLabel", DetailsPanel)
    dTitle.Name                   = "Title"
    dTitle.Size                   = UDim2.new(1, -75, 0, 60)
    dTitle.Position               = UDim2.new(0, 10, 0, 0)
    dTitle.BackgroundTransparency = 1
    dTitle.Text                   = "SELECT ITEM"
    dTitle.Font                   = Enum.Font.GothamBlack
    dTitle.TextSize               = 18
    dTitle.TextColor3             = Color3.fromRGB(120, 120, 130)
    dTitle.TextXAlignment         = Enum.TextXAlignment.Left

    local dRarity = Instance.new("TextLabel", DetailsPanel)
    dRarity.Name                   = "Rarity"
    dRarity.Size                   = UDim2.new(1, 0, 0, 25)
    dRarity.Position               = UDim2.new(0, 10, 0, 60)
    dRarity.BackgroundTransparency = 1
    dRarity.Font                   = Enum.Font.GothamBlack
    dRarity.TextSize               = 14
    dRarity.TextColor3             = Color3.fromRGB(120, 120, 130)
    dRarity.Text                   = ""
    dRarity.Visible                = false
    dRarity.TextXAlignment         = Enum.TextXAlignment.Left

    local dPower = Instance.new("TextLabel", DetailsPanel)
    dPower.Name                   = "Power"
    dPower.Size                   = UDim2.new(1, -20, 0, 30)
    dPower.Position               = UDim2.new(0, 10, 0, 85)
    dPower.BackgroundTransparency = 1
    dPower.Font                   = Enum.Font.GothamBold
    dPower.TextSize               = 13
    dPower.TextColor3             = Color3.fromRGB(200, 200, 200)
    dPower.Text                   = ""
    dPower.Visible                = false
    dPower.TextXAlignment         = Enum.TextXAlignment.Left
    dPower.TextScaled             = true
    Instance.new("UITextSizeConstraint", dPower).MaxTextSize = 13

    local dCost = Instance.new("TextLabel", DetailsPanel)
    dCost.Name                   = "Cost"
    dCost.Size                   = UDim2.new(1, -20, 0, 50)
    dCost.Position               = UDim2.new(0, 10, 0, 115)
    dCost.BackgroundTransparency = 1
    dCost.Font                   = Enum.Font.GothamBold
    dCost.TextSize = 12
    dCost.TextWrapped = true
    dCost.TextScaled = true
    dCost.Text = ""
    dCost.Visible = false
    dCost.TextXAlignment = Enum.TextXAlignment.Left
    Instance.new("UITextSizeConstraint", dCost).MaxTextSize = 12

    local dChance = Instance.new("TextLabel", DetailsPanel)
    dChance.Name                   = "Chance"
    dChance.Size                   = UDim2.new(1, -20, 0, 30)
    dChance.Position               = UDim2.new(0, 10, 0, 165)
    dChance.BackgroundTransparency = 1
    dChance.Font                   = Enum.Font.GothamBlack
    dChance.TextSize               = 14
    dChance.TextColor3             = Color3.fromRGB(255, 215, 0)
    dChance.Text                   = ""
    dChance.Visible                = false
    dChance.TextXAlignment         = Enum.TextXAlignment.Left
    dChance.TextScaled             = true
    Instance.new("UITextSizeConstraint", dChance).MaxTextSize = 14

    local cStroke = Instance.new("UIStroke", dChance)
    cStroke.Color     = Color3.fromRGB(0, 0, 0)
    cStroke.Thickness = 1.5

    local equipBtnC = Instance.new("Frame", DetailsPanel)
    equipBtnC.Name                   = "EquipBtnContainer"
    equipBtnC.Size                   = UDim2.new(0, 160, 0, 45)
    equipBtnC.Position               = UDim2.new(0.5, -80, 1, -65)
    equipBtnC.BackgroundTransparency = 1
    equipBtnC.Visible                = false

    local equipBtn = Instance.new("TextButton", equipBtnC)
    equipBtn.Name             = "EquipBtn"
    equipBtn.Size             = UDim2.new(1, 0, 1, -4)
    equipBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 50)
    equipBtn.Text             = "EQUIP"
    equipBtn.Font             = Enum.Font.GothamBlack
    equipBtn.TextColor3       = Color3.new(1, 1, 1)
    Instance.new("UICorner", equipBtn).CornerRadius = UDim.new(0, 8)

    GetLocalEvent("ToggleIndex").Event:Connect(function()
        if isAnimating then return end
        if isOpen then
            closePanel()
        else
            isOpen            = true
            isAnimating       = true
            MainPanel.Visible = true
            BgShield.Visible  = true
            PanelScale.Scale  = 0
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

    equipBtn.MouseButton1Click:Connect(function()
        if selectedItemId and selectedItemId ~= currentEquippedId then
            equipBtn.Text = "WAITING..."
            remotes.EquipRequest:FireServer(selectedItemId)
        end
    end)

    equipBestBtn.MouseButton1Click:Connect(function()
        local bestItemId = GetBestItemId()
        if bestItemId then
            if bestItemId == currentEquippedId then
                equipBestBtn.Text = "ALREADY BEST"
                task.delay(1.5, function() equipBestBtn.Text = "EQUIP BEST" end)
            else
                equipBestBtn.Text = "EQUIPPING..."
                remotes.EquipRequest:FireServer(bestItemId)
            end
        else
            equipBestBtn.Text = "NO ITEMS"
            task.delay(1.5, function() equipBestBtn.Text = "EQUIP BEST" end)
        end
    end)

    remotes.UpdateCollection.OnClientEvent:Connect(function(col, asc)
        collectionCache = col
        ascensionsCache = asc
        IndexController.Refresh(col, asc)
        IndexController.UpdateDetailsPanel()
    end)

    remotes.SyncVisualEffects.OnClientEvent:Connect(function(targetPlayer: any, equippedKey: string)
        local isLocal = (targetPlayer == LocalPlayer)
            or (typeof(targetPlayer) == "string" and targetPlayer == LocalPlayer.Name)

        if isLocal then
            local split = string.split(equippedKey, ":")
            local uiKey = split[1]
            if #split >= 2 and not tonumber(split[2]) then
                uiKey = uiKey .. ":" .. split[2]
            end

            currentEquippedId = uiKey
            if equipBestBtn.Text == "EQUIPPING..." then
                equipBestBtn.Text = "BEST EQUIPPED!"
                task.delay(1.5, function() equipBestBtn.Text = "EQUIP BEST" end)
            end
            IndexController.UpdateDetailsPanel()
        end
    end)
end

return IndexController
