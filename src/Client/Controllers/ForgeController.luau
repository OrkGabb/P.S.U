--!strict
--@author OrkGabb
--@module ForgeController.luau
--@version 1.0
-- src/Client/Controllers/ForgeController.lua
-- Professional Forge UI Controller. Allows players to spend duplicate essences to craft premium boosts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

local ItemRegistry = require(ReplicatedStorage.Shared.Modules.ItemRegistry)
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local ForgeController = {}
local MainPanel: Frame
local GridContainer: ScrollingFrame
local DetailsPanel: Frame
local PanelScale: UIScale
local BgShield: TextButton 

local isOpen = false
local isAnimating = false

local inventoryCache: {[string]: number} = {}
local selectedPotionId: string? = nil

-- ─── Formatting Helpers ──────────────────────────────────────────────────────
local function GetLocalEvent(name: string): BindableEvent
    local folder = ReplicatedStorage:FindFirstChild("LocalEvents") or Instance.new("Folder")
    folder.Name = "LocalEvents"
    folder.Parent = ReplicatedStorage
    local evt = folder:FindFirstChild(name) or Instance.new("BindableEvent")
    evt.Name = name
    evt.Parent = folder
    return evt :: BindableEvent
end

local function GetPlayerCoins(): number
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local coins = ls and ls:FindFirstChild("Coins") :: NumberValue?
    return coins and coins.Value or 0
end

local function FormatSuffix(n: number): string
    if not n or n < 1000 then return tostring(math.floor(n or 0)) end
    local suffixes = {"", "K", "M", "B", "T", "Qa"}
    local i = math.floor(math.log10(n) / 3)
    local v = n / (10 ^ (i * 3))
    return string.format("%.1f%s", v, suffixes[i + 1] or "Max")
end

-- ─── UI Refresh ──────────────────────────────────────────────────────────────
function ForgeController.Refresh()
    if not GridContainer then return end

    for _, child in ipairs(GridContainer:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextButton") then child:Destroy() end
    end

    local sortedPotions = {}
    for potionId, _ in pairs(ItemRegistry.Recipes) do
        table.insert(sortedPotions, potionId)
    end
    table.sort(sortedPotions)

    for _, potionId in ipairs(sortedPotions) do
        local recipe = ItemRegistry.Recipes[potionId]
        local itemData = ItemRegistry.Potions[potionId]
        if not recipe or not itemData then continue end

        local isSelected = (potionId == selectedPotionId)

        local slot = Instance.new("TextButton", GridContainer)
        slot.Size = UDim2.new(0, 85, 0, 85)
        slot.BackgroundColor3 = isSelected and Color3.fromRGB(36, 28, 54) or Color3.fromRGB(22, 17, 32)
        slot.Text = ""
        slot.AutoButtonColor = false
        Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 12)
        
        local stroke = Instance.new("UIStroke", slot)
        stroke.Color = isSelected and Color3.fromRGB(255, 200, 50) or (itemData.Color or Color3.fromRGB(60, 60, 70))
        stroke.Thickness = isSelected and 2.5 or 1.5

        -- Slot background gradient
        local slotGrad = Instance.new("UIGradient", slot)
        slotGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, isSelected and Color3.fromRGB(44, 32, 68) or Color3.fromRGB(28, 22, 40)),
            ColorSequenceKeypoint.new(1, isSelected and Color3.fromRGB(24, 18, 38) or Color3.fromRGB(16, 14, 24)),
        })
        slotGrad.Rotation = 135

        local slotScale = Instance.new("UIScale", slot)
        slot.MouseEnter:Connect(function()
            TweenService:Create(slotScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.05}):Play()
            if not isSelected then
                TweenService:Create(stroke, TweenInfo.new(0.15), {Color = Color3.fromRGB(255, 215, 0)}):Play()
            end
        end)
        slot.MouseLeave:Connect(function()
            TweenService:Create(slotScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
            if not isSelected then
                TweenService:Create(stroke, TweenInfo.new(0.15), {Color = itemData.Color or Color3.fromRGB(60, 60, 70)}):Play()
            end
        end)

        -- Icon image
        if itemData.IconId then
            local icon = Instance.new("ImageLabel", slot)
            icon.Size = UDim2.fromScale(0.75, 0.75)
            icon.Position = UDim2.fromScale(0.125, 0.125)
            icon.BackgroundTransparency = 1
            icon.Image = itemData.IconId
            icon.ScaleType = Enum.ScaleType.Fit
        end

        -- Name Label
        local lbl = Instance.new("TextLabel", slot)
        lbl.Size = UDim2.new(1, -6, 0, 16)
        lbl.Position = UDim2.new(0.5, 0, 1, -18)
        lbl.AnchorPoint = Vector2.new(0.5, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = itemData.Name:upper()
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 8
        lbl.TextColor3 = Color3.fromRGB(220, 220, 230)
        lbl.TextWrapped = true

        slot.MouseButton1Click:Connect(function()
            selectedPotionId = potionId
            ForgeController.Refresh()
        end)
    end

    if not selectedPotionId or not ItemRegistry.Recipes[selectedPotionId] then
        selectedPotionId = sortedPotions[1]
    end

    ForgeController.UpdateDetailsPanel()
end

-- ─── Details Panel Rendering ─────────────────────────────────────────────────
function ForgeController.UpdateDetailsPanel()
    if not DetailsPanel then return end

    local dTitle = DetailsPanel:FindFirstChild("Title") :: TextLabel?
    local dIngredients = DetailsPanel:FindFirstChild("IngredientsFrame") :: Frame?
    local craftBtnC = DetailsPanel:FindFirstChild("CraftBtnContainer") :: Frame?
    local craftBtn = craftBtnC and craftBtnC:FindFirstChild("Btn") :: TextButton?
    local console = DetailsPanel:FindFirstChild("StatusConsole") :: TextLabel?

    if not selectedPotionId or not ItemRegistry.Recipes[selectedPotionId] then
        if dTitle then
            dTitle.Text = "SELECT A RECIPE"
            dTitle.TextColor3 = Color3.fromRGB(120, 120, 130)
        end
        if dIngredients then dIngredients.Visible = false end
        if craftBtnC then craftBtnC.Visible = false end
        return
    end

    local recipe = ItemRegistry.Recipes[selectedPotionId]
    local itemData = ItemRegistry.Potions[selectedPotionId]
    if not recipe or not itemData then return end

    -- Update Item Title
    if dTitle then
        dTitle.Text = itemData.Name:upper()
        dTitle.TextColor3 = itemData.Color or Color3.fromRGB(255, 215, 0)
    end

    -- Update Ingredients List
    if dIngredients then
        dIngredients.Visible = true
        dIngredients:ClearAllChildren()

        local layout = Instance.new("UIListLayout", dIngredients)
        layout.Padding = UDim.new(0, 4)
        layout.SortOrder = Enum.SortOrder.LayoutOrder

        local canAffordIngredients = true

        -- Cost in Coins
        local costFrame = Instance.new("Frame", dIngredients)
        costFrame.Size = UDim2.new(1, 0, 0, 20)
        costFrame.BackgroundTransparency = 1
        costFrame.LayoutOrder = 0

        local playerCoins = GetPlayerCoins()
        local hasEnoughCoins = playerCoins >= recipe.Cost
        if not hasEnoughCoins then canAffordIngredients = false end

        local costLbl = Instance.new("TextLabel", costFrame)
        costLbl.Size = UDim2.fromScale(1, 1)
        costLbl.BackgroundTransparency = 1
        costLbl.Text = string.format("Coins: %s / %s", FormatSuffix(playerCoins), FormatSuffix(recipe.Cost))
        costLbl.Font = Enum.Font.GothamBold
        costLbl.TextSize = 11
        costLbl.TextColor3 = hasEnoughCoins and Color3.fromRGB(255, 220, 100) or Color3.fromRGB(255, 100, 100)
        costLbl.TextXAlignment = Enum.TextXAlignment.Left

        local ingredientOrder = 1
        for ingId, reqAmount in pairs(recipe.Ingredients) do
            local ingFrame = Instance.new("Frame", dIngredients)
            ingFrame.Size = UDim2.new(1, 0, 0, 20)
            ingFrame.BackgroundTransparency = 1
            ingFrame.LayoutOrder = ingredientOrder
            ingredientOrder += 1

            local ownedAmount = inventoryCache[ingId] or 0
            local hasEnough = ownedAmount >= reqAmount
            if not hasEnough then canAffordIngredients = false end

            local ingDef = ItemRegistry.Essences[ingId] or ItemRegistry.Potions[ingId]
            local ingName = ingDef and ingDef.Name or ingId

            local ingLbl = Instance.new("TextLabel", ingFrame)
            ingLbl.Size = UDim2.fromScale(1, 1)
            ingLbl.BackgroundTransparency = 1
            ingLbl.Text = string.format("• %s: %d / %d", ingName, ownedAmount, reqAmount)
            ingLbl.Font = Enum.Font.GothamMedium
            ingLbl.TextSize = 11
            ingLbl.TextColor3 = hasEnough and Color3.fromRGB(150, 255, 150) or Color3.fromRGB(255, 120, 120)
            ingLbl.TextXAlignment = Enum.TextXAlignment.Left
        end

        if craftBtnC and craftBtn then
            craftBtnC.Visible = true
            if craftBtn.Text ~= "FORGING..." then
                craftBtn.Text = canAffordIngredients and "FORGE BOOST" or "INSUFFICIENT MATERIALS"
                craftBtn.BackgroundColor3 = canAffordIngredients and Color3.fromRGB(0, 140, 50) or Color3.fromRGB(100, 30, 30)
                local s = craftBtn:FindFirstChildOfClass("UIStroke")
                if s then
                    s.Color = canAffordIngredients and Color3.fromRGB(0, 80, 25) or Color3.fromRGB(70, 20, 20)
                end
            end
        end
    end
end

-- ─── Init / Start ────────────────────────────────────────────────────────────
function ForgeController.Init(): ()
    if not FeatureResolver.IsCategoryActive("Forge") then return end
end

function ForgeController.Start(): ()
    if not FeatureResolver.IsCategoryActive("Forge") then return end

    local UIController = require(script.Parent:WaitForChild("UIController")) :: any
    UIController.RegisterHUDButton({
        Id = "Forge",
        Name = "FORGE",
        IconId = "Premium",
        Type = "Sidebar",
        LayoutOrder = 6,
        OnClick = function(): ()
            GetLocalEvent("ToggleForge"):Fire()
        end
    })

    local gui = Instance.new("ScreenGui")
    gui.Name = "ForgeGui"
    gui.ResetOnSpawn = false 
    gui.DisplayOrder = 45
    gui.Parent = LocalPlayer.PlayerGui

    BgShield = Instance.new("TextButton", gui)
    BgShield.Name = "InputSink"
    BgShield.Size = UDim2.fromScale(1, 1)
    BgShield.BackgroundTransparency = 1
    BgShield.Text = ""
    BgShield.AutoButtonColor = false
    BgShield.Visible = false
    BgShield.Active = true 
    BgShield.MouseButton1Up:Connect(closePanel)

    -- Main Panel
    MainPanel = Instance.new("Frame", gui)
    MainPanel.Size = UDim2.new(0, 620, 0, 420)
    MainPanel.AnchorPoint = Vector2.new(0.5, 0.5)
    MainPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
    MainPanel.BackgroundColor3 = Color3.fromRGB(15, 14, 22)
    MainPanel.BorderSizePixel = 0
    MainPanel.Active = true 
    MainPanel.Visible = false
    Instance.new("UICorner", MainPanel).CornerRadius = UDim.new(0, 16)
    
    local stroke = Instance.new("UIStroke", MainPanel)
    stroke.Color = Color3.fromRGB(90, 60, 150)
    stroke.Thickness = 2.5

    local panelGrad = Instance.new("UIGradient", MainPanel)
    panelGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 18, 36)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 10, 18)),
    })
    panelGrad.Rotation = 135

    PanelScale = Instance.new("UIScale", MainPanel)
    PanelScale.Scale = 0

    local camera = workspace.CurrentCamera
    local targetScale = 1
    
    local function updateUIScale()
        if not camera then return end
        local size = camera.ViewportSize
        local scaleX = size.X / 640
        local scaleY = size.Y / 440
        targetScale = math.clamp(math.min(scaleX, scaleY, 1), 0.5, 1.2)
        if isOpen and not isAnimating then
            PanelScale.Scale = targetScale
        end
    end
    
    camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateUIScale)
    updateUIScale()

    local function closePanel()
        if not isOpen then return end
        isOpen = false
        isAnimating = true
        BgShield.Visible = false
        GetLocalEvent("NotifyMenuClosed"):Fire("Forge")
        local tw = TweenService:Create(PanelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0})
        tw:Play()
        tw.Completed:Connect(function()
            isAnimating = false
            if not isOpen then MainPanel.Visible = false end
        end)
    end

    local closeBtn = Instance.new("TextButton", MainPanel)
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -12, 0, 12)
    closeBtn.AnchorPoint = Vector2.new(1, 0)
    closeBtn.AutoButtonColor = false
    closeBtn.Text = "X" 
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextScaled = true
    closeBtn.Font = Enum.Font.GothamBlack
    closeBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
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

    local panelTitle = Instance.new("TextLabel", MainPanel)
    panelTitle.Size = UDim2.new(1, 0, 0, 50)
    panelTitle.BackgroundTransparency = 1
    panelTitle.Text = "ALCHEMY FORGE"
    panelTitle.Font = Enum.Font.FredokaOne
    panelTitle.TextSize = 22
    panelTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
    
    local titleStroke = Instance.new("UIStroke", panelTitle)
    titleStroke.Color = Color3.fromRGB(150, 110, 30)
    titleStroke.Thickness = 1.5

    -- Left: Scrollable Recipes Grid
    GridContainer = Instance.new("ScrollingFrame", MainPanel)
    GridContainer.Size = UDim2.new(0.6, -15, 1, -70)
    GridContainer.Position = UDim2.new(0, 12, 0, 55)
    GridContainer.BackgroundTransparency = 1
    GridContainer.ScrollBarThickness = 4
    GridContainer.ScrollBarImageColor3 = Color3.fromRGB(200, 160, 50)
    GridContainer.BorderSizePixel = 0
    GridContainer.CanvasSize          = UDim2.new(0, 0, 0, 0)
    GridContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local grid = Instance.new("UIGridLayout", GridContainer)
    grid.CellSize = UDim2.new(0, 85, 0, 85)
    grid.CellPadding = UDim2.new(0, 8, 0, 8)

    local gridPad = Instance.new("UIPadding", GridContainer)
    gridPad.PaddingLeft = UDim.new(0, 6)
    gridPad.PaddingTop = UDim.new(0, 6)

    -- Right: Details Frame Panel
    DetailsPanel = Instance.new("Frame", MainPanel)
    DetailsPanel.Size = UDim2.new(0.4, -15, 1, -70)
    DetailsPanel.Position = UDim2.new(0.6, 5, 0, 55)
    DetailsPanel.BackgroundColor3 = Color3.fromRGB(22, 17, 32)
    DetailsPanel.BorderSizePixel = 0
    Instance.new("UICorner", DetailsPanel).CornerRadius = UDim.new(0, 12)
    
    local dStroke = Instance.new("UIStroke", DetailsPanel)
    dStroke.Color = Color3.fromRGB(90, 60, 150)
    dStroke.Thickness = 1.5

    local detailsGrad = Instance.new("UIGradient", DetailsPanel)
    detailsGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 20, 40)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 12, 22)),
    })
    detailsGrad.Rotation = 135

    -- Title Inside Details
    local dTitle = Instance.new("TextLabel", DetailsPanel)
    dTitle.Name = "Title"
    dTitle.Size = UDim2.new(1, -20, 0, 32)
    dTitle.Position = UDim2.new(0, 10, 0, 8)
    dTitle.BackgroundTransparency = 1
    dTitle.Text = "SELECT A RECIPE"
    dTitle.Font = Enum.Font.GothamBlack
    dTitle.TextSize = 14
    dTitle.TextColor3 = Color3.fromRGB(120, 120, 130)

    -- Ingredients List
    local dIngredients = Instance.new("Frame", DetailsPanel)
    dIngredients.Name = "IngredientsFrame"
    dIngredients.Size = UDim2.new(1, -20, 0, 180)
    dIngredients.Position = UDim2.new(0, 10, 0, 48)
    dIngredients.BackgroundTransparency = 1

    -- Status Console
    local console = Instance.new("TextLabel", DetailsPanel)
    console.Name = "StatusConsole"
    console.Size = UDim2.new(1, -20, 0, 36)
    console.Position = UDim2.new(0, 10, 1, -115)
    console.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    console.BackgroundTransparency = 0.5
    console.Text = "READY"
    console.Font = Enum.Font.Code
    console.TextSize = 10
    console.TextColor3 = Color3.fromRGB(130, 120, 150)
    Instance.new("UICorner", console).CornerRadius = UDim.new(0, 6)

    -- Craft Button
    local craftBtnC = Instance.new("Frame", DetailsPanel)
    craftBtnC.Name = "CraftBtnContainer"
    craftBtnC.Size = UDim2.new(1, -20, 0, 45)
    craftBtnC.Position = UDim2.new(0, 10, 1, -65)
    craftBtnC.BackgroundTransparency = 1
    craftBtnC.Visible = false

    local craftBtn = Instance.new("TextButton", craftBtnC)
    craftBtn.Name = "Btn"
    craftBtn.Size = UDim2.new(1, 0, 1, -4)
    craftBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 50)
    craftBtn.Text = "FORGE BOOST"
    craftBtn.Font = Enum.Font.GothamBlack
    craftBtn.TextColor3 = Color3.new(1, 1, 1)
    craftBtn.TextSize = 12
    craftBtn.AutoButtonColor = false
    Instance.new("UICorner", craftBtn).CornerRadius = UDim.new(0, 8)
    
    local cbStroke = Instance.new("UIStroke", craftBtn)
    cbStroke.Color = Color3.fromRGB(0, 80, 25)
    cbStroke.Thickness = 1.5

    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local forgeRequest = remotes:WaitForChild("ForgeRequest") :: RemoteEvent

    craftBtn.MouseButton1Click:Connect(function()
        if not selectedPotionId then return end
        if craftBtn.Text == "FORGING..." then return end

        craftBtn.Text = "FORGING..."
        craftBtn.BackgroundColor3 = Color3.fromRGB(120, 80, 20)
        cbStroke.Color = Color3.fromRGB(70, 40, 10)

        forgeRequest:FireServer(selectedPotionId)
    end)

    forgeRequest.OnClientEvent:Connect(function(success: boolean, message: string)
        console.Text = " " .. (success and "✓ " or "✗ ") .. string.upper(message)
        console.TextColor3 = success and Color3.fromRGB(0, 220, 100) or Color3.fromRGB(255, 80, 80)
        
        task.delay(3, function()
            if console.Text == " " .. (success and "✓ " or "✗ ") .. string.upper(message) then
                console.Text = "READY"
                console.TextColor3 = Color3.fromRGB(130, 120, 150)
            end
        end)

        ForgeController.Refresh()
    end)

    -- Event Connections
    GetLocalEvent("ToggleForge").Event:Connect(function()
        if isAnimating then return end
        if isOpen then
            closePanel()
        else
            isOpen = true
            isAnimating = true
            MainPanel.Visible = true
            BgShield.Visible = true
            PanelScale.Scale = 0
            local tw = TweenService:Create(PanelScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = targetScale})
            tw:Play()
            tw.Completed:Connect(function()
                isAnimating = false
            end)
            
            GetLocalEvent("NotifyMenuOpened"):Fire("Forge")
            ForgeController.Refresh()
        end
    end)

    GetLocalEvent("NotifyMenuOpened").Event:Connect(function(menuName: string)
        if isOpen and menuName ~= "Forge" then
            closePanel()
        end
    end)

    remotes:WaitForChild("UpdateInventory").OnClientEvent:Connect(function(newInventory)
        inventoryCache = newInventory
        if isOpen then
            ForgeController.Refresh()
        end
    end)
end

return ForgeController
