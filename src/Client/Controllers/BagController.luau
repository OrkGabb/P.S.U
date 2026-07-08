--!strict
--@author OrkGabb
--@module BagController.luau
--@version 1.0
-- src/Client/Controllers/BagController.lua
-- Inventory UI Controller. Implements professional glassmorphism card layouts, detail badges, and slot hover micro-interactions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local ItemRegistry = require(ReplicatedStorage.Shared.Modules.ItemRegistry)
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local BagController = {}
local MainPanel: Frame
local GridContainer: ScrollingFrame
local DetailsPanel: Frame
local PanelScale: UIScale
local BgShield: TextButton 
local isOpen = false
-- Bumped on every open/close transition; stale animation callbacks compare
-- against it and stand down if a newer transition has taken over.
local animGen = 0

local inventoryCache: {[string]: number} = {}
local selectedItemId: string? = nil
local activeBuffsCache: {[string]: any} = {}

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

-- ─── UI Refresh ──────────────────────────────────────────────────────────────
function BagController.Refresh()
    if not GridContainer then return end

    for _, child in ipairs(GridContainer:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextButton") then child:Destroy() end
    end

    local hasItems = false

    for itemId, amount in pairs(inventoryCache) do
        if amount <= 0 then continue end
        
        local itemData = ItemRegistry.Potions and ItemRegistry.Potions[itemId]
        if not itemData then continue end
        
        hasItems = true
        local isSelected = (itemId == selectedItemId)

        local slot = Instance.new("TextButton", GridContainer)
        slot.Size = UDim2.new(0, 85, 0, 85)
        slot.BackgroundColor3 = isSelected and Color3.fromRGB(36, 28, 54) or Color3.fromRGB(22, 17, 32)
        slot.Text = ""
        slot.AutoButtonColor = false
        Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 12)
        
        local stroke = Instance.new("UIStroke", slot)
        stroke.Color = isSelected and Color3.fromRGB(255, 255, 255) or (itemData.Color or Color3.fromRGB(60, 60, 70))
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
                TweenService:Create(stroke, TweenInfo.new(0.15), {Color = Color3.fromRGB(150, 120, 220)}):Play()
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
            icon.Size = UDim2.fromScale(0.8, 0.8)
            icon.Position = UDim2.fromScale(0.1, 0.1)
            icon.BackgroundTransparency = 1
            icon.Image = itemData.IconId
            icon.ScaleType = Enum.ScaleType.Fit
        else
            local blob = Instance.new("Frame", slot)
            blob.Size = UDim2.new(0.5, 0, 0.5, 0)
            blob.Position = UDim2.new(0.25, 0, 0.25, 0)
            blob.BackgroundColor3 = itemData.Color or Color3.fromRGB(255, 255, 255)
            Instance.new("UICorner", blob).CornerRadius = UDim.new(1, 0)
        end

        -- Active Indicator Capsule
        local activeBuff = activeBuffsCache[itemId]
        local isBuffActive = activeBuff and activeBuff.EndTime > os.time()

        local activeIndicator = Instance.new("Frame", slot)
        activeIndicator.Name = "ActiveIndicator"
        activeIndicator.Size = UDim2.new(0, 38, 0, 13)
        activeIndicator.Position = UDim2.new(0, 4, 1, -4)
        activeIndicator.AnchorPoint = Vector2.new(0, 1)
        activeIndicator.BackgroundColor3 = Color3.fromRGB(0, 200, 80)
        activeIndicator.BorderSizePixel = 0
        activeIndicator.Visible = isBuffActive
        Instance.new("UICorner", activeIndicator).CornerRadius = UDim.new(0, 4)

        local activeTxt = Instance.new("TextLabel", activeIndicator)
        activeTxt.Size = UDim2.fromScale(1, 1)
        activeTxt.BackgroundTransparency = 1
        activeTxt.Text = "ACTIVE"
        activeTxt.Font = Enum.Font.GothamBlack
        activeTxt.TextSize = 7
        activeTxt.TextColor3 = Color3.new(1, 1, 1)

        -- Sleek Semi-Transparent Quantity Capsule Badge
        local amountBadge = Instance.new("Frame", slot)
        amountBadge.Size = UDim2.new(0, 30, 0, 16)
        amountBadge.Position = UDim2.new(1, -4, 1, -4)
        amountBadge.AnchorPoint = Vector2.new(1, 1)
        amountBadge.BackgroundColor3 = Color3.fromRGB(15, 12, 22)
        amountBadge.BackgroundTransparency = 0.25
        amountBadge.ZIndex = 10
        Instance.new("UICorner", amountBadge).CornerRadius = UDim.new(0, 4)

        local badgeStroke = Instance.new("UIStroke", amountBadge)
        badgeStroke.Color = Color3.fromRGB(0, 150, 255)
        badgeStroke.Thickness = 1

        local amtTxt = Instance.new("TextLabel", amountBadge)
        amtTxt.Size = UDim2.new(1, -2, 1, 0)
        amtTxt.Position = UDim2.new(0, 1, 0, 0)
        amtTxt.BackgroundTransparency = 1
        amtTxt.TextScaled = true
        amtTxt.Font = Enum.Font.GothamBlack
        amtTxt.TextColor3 = Color3.new(1, 1, 1)
        amtTxt.ZIndex = 11
        amtTxt.Text = "x" .. tostring(amount)

        slot.MouseButton1Click:Connect(function()
            selectedItemId = itemId
            BagController.Refresh() -- Refresh to update selection frame border
        end)
    end
    
    if not hasItems or not inventoryCache[selectedItemId or ""] then
        selectedItemId = nil
    end
    BagController.UpdateDetailsPanel()
end

-- ─── Details Panel Rendering ─────────────────────────────────────────────────
function BagController.UpdateDetailsPanel()
    if not DetailsPanel then return end

    local dTitle = DetailsPanel:FindFirstChild("Title") :: TextLabel?
    local dPreview = DetailsPanel:FindFirstChild("PreviewFrame") :: Frame?
    local dPillContainer = DetailsPanel:FindFirstChild("PillContainer") :: Frame?
    local useBtnC = DetailsPanel:FindFirstChild("UseBtnContainer") :: Frame?
    local useBtn = useBtnC and useBtnC:FindFirstChild("UseBtn") :: TextButton?

    if not selectedItemId or not inventoryCache[selectedItemId] then
        if dTitle then
            dTitle.Text = "SELECT AN ITEM"
            dTitle.TextColor3 = Color3.fromRGB(120, 120, 130)
        end
        if dPreview then dPreview.Visible = false end
        if dPillContainer then dPillContainer.Visible = false end
        if useBtnC then useBtnC.Visible = false end
        return
    end

    local itemData = ItemRegistry.Potions[selectedItemId]
    if not itemData then return end

    -- Update Preview Potion Icon
    if dPreview then
        dPreview.Visible = true
        local pIcon = dPreview:FindFirstChild("Icon") :: ImageLabel?
        if pIcon then
            pIcon.Image = itemData.IconId or ""
            pIcon.ImageRectOffset = Vector2.new(0, 0)
            pIcon.ImageRectSize = Vector2.new(0, 0)
        end
        local pGlow = dPreview:FindFirstChild("Glow") :: Frame?
        if pGlow then
            pGlow.BackgroundColor3 = itemData.Color or Color3.fromRGB(130, 90, 230)
        end
    end

    -- Update Item Title
    if dTitle then
        dTitle.Text = itemData.Name:upper()
        dTitle.TextColor3 = itemData.Color or Color3.fromRGB(255, 255, 255)
    end

    -- Update Detail Pills
    if dPillContainer then
        dPillContainer.Visible = true
        
        local typePill = dPillContainer:FindFirstChild("TypePill") :: Frame?
        if typePill then
            local lbl = typePill:FindFirstChild("TextLabel") :: TextLabel?
            if lbl then lbl.Text = "Type: " .. (itemData.Type or "Potion"):upper() end
        end

        local boostPill = dPillContainer:FindFirstChild("BoostPill") :: Frame?
        if boostPill then
            local lbl = boostPill:FindFirstChild("TextLabel") :: TextLabel?
            if lbl then
                local boostPct = (itemData.Boost or 0) * 100
                local statName = (itemData.Stat or "Boost"):upper()
                lbl.Text = string.format("Effect: +%d%% %s", boostPct, statName)
            end
        end

        local durPill = dPillContainer:FindFirstChild("DurationPill") :: Frame?
        if durPill then
            local lbl = durPill:FindFirstChild("TextLabel") :: TextLabel?
            if lbl then
                local minutes = math.floor((itemData.Duration or 0) / 60)
                lbl.Text = string.format("Duration: %d min", minutes)
            end
        end
    end

    if useBtnC and useBtn then
        useBtnC.Visible = true
        
        local activeBuff = activeBuffsCache[selectedItemId]
        local isBuffActive = activeBuff and activeBuff.EndTime > os.time()
        local uStroke = useBtn:FindFirstChild("UIStroke") :: UIStroke?
        
        if isBuffActive then
            local timeLeft = math.max(0, activeBuff.EndTime - os.time())
            local min = math.floor(timeLeft / 60)
            local sec = timeLeft % 60
            useBtn.Text = string.format("ACTIVE (%02d:%02d)", min, sec)
            useBtn.BackgroundColor3 = Color3.fromRGB(80, 78, 88)
            if uStroke then uStroke.Color = Color3.fromRGB(40, 38, 48) end
        else
            useBtn.Text = "USE ITEM"
            useBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 50)
            if uStroke then uStroke.Color = Color3.fromRGB(0, 80, 25) end
        end
    end
end

-- ─── Init / Start ────────────────────────────────────────────────────────────
function BagController.Init(): () end

function BagController.Start(): ()
    if FeatureResolver.IsCategoryActive("Forge") then
        local UIController: any = require(script.Parent:WaitForChild("UIController"))
        UIController.RegisterHUDButton({
            Id = "Bag",
            Name = "BAG",
            IconId = "Premium",
            Type = "Floating",
            LayoutOrder = 2,
            OnClick = function(): ()
                GetLocalEvent("ToggleBag"):Fire()
            end
        })
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "BagGui"
    gui.ResetOnSpawn = false 
    gui.DisplayOrder = 60 -- panel band: 60 resting/closing, 61 while open
    gui.Parent = LocalPlayer.PlayerGui

    BgShield = Instance.new("TextButton", gui)
    BgShield.Name = "InputSink"
    BgShield.Size = UDim2.fromScale(1, 1)
    BgShield.BackgroundTransparency = 1
    BgShield.Text = ""
    BgShield.AutoButtonColor = false
    BgShield.Visible = false
    BgShield.Active = true
    -- (click-to-close is connected below, once closePanel exists)

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
        ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 16, 38)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 8, 16)),
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
        if isOpen then
            -- Retarget with a tween: a direct Scale set while another tween is
            -- animating the property gets overwritten every frame.
            TweenService:Create(PanelScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = targetScale}):Play()
        end
    end
    
    camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateUIScale)
    updateUIScale()

    local function closePanel()
        if not isOpen then return end
        isOpen = false
        animGen += 1
        local gen = animGen
        gui.DisplayOrder = 60
        BgShield.Visible = false
        GetLocalEvent("NotifyMenuClosed"):Fire("Bag")
        local tw = TweenService:Create(PanelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0})
        tw:Play()
        tw.Completed:Connect(function(state: Enum.PlaybackState)
            -- A reopen cancels this tween (Completed still fires, state=Cancelled)
            -- and bumps the generation; hide only if this close ran to completion
            -- and is still the latest transition.
            if gen ~= animGen then return end
            if state ~= Enum.PlaybackState.Completed then return end
            MainPanel.Visible = false
        end)
    end

    local closeBtn = Instance.new("TextButton", MainPanel)
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -12, 0, 12)
    closeBtn.AnchorPoint = Vector2.new(1, 0)
    closeBtn.AutoButtonColor = false
    closeBtn.Text = "" 
    closeBtn.BackgroundTransparency = 1 
    
    local cIcon = Instance.new("ImageLabel", closeBtn)
    cIcon.Name = "HD_Icon"
    cIcon.Size = UDim2.fromScale(1, 1)
    cIcon.Position = UDim2.fromScale(0, 0)
    cIcon.BackgroundTransparency = 1
    cIcon.Image = AssetRegistry.UI.CloseIcon
    cIcon.ScaleType = Enum.ScaleType.Fit
    
    closeBtn.MouseEnter:Connect(function()
        TweenService:Create(cIcon, TweenInfo.new(0.15), {ImageColor3 = Color3.fromRGB(255, 100, 100)}):Play()
    end)
    closeBtn.MouseLeave:Connect(function()
        TweenService:Create(cIcon, TweenInfo.new(0.15), {ImageColor3 = Color3.fromRGB(255, 255, 255)}):Play()
    end)
    
    closeBtn.MouseButton1Up:Connect(closePanel)
    BgShield.MouseButton1Up:Connect(closePanel)

    local panelTitle = Instance.new("TextLabel", MainPanel)
    panelTitle.Size = UDim2.new(1, 0, 0, 50)
    panelTitle.BackgroundTransparency = 1
    panelTitle.Text = "INVENTORY"
    panelTitle.Font = Enum.Font.FredokaOne
    panelTitle.TextSize = 22
    panelTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    
    local titleStroke = Instance.new("UIStroke", panelTitle)
    titleStroke.Color = Color3.fromRGB(130, 90, 230)
    titleStroke.Thickness = 1.5

    -- Left: Scrollable Items Grid
    GridContainer = Instance.new("ScrollingFrame", MainPanel)
    GridContainer.Size = UDim2.new(0.6, -15, 1, -70)
    GridContainer.Position = UDim2.new(0, 12, 0, 55)
    GridContainer.BackgroundTransparency = 1
    GridContainer.ScrollBarThickness = 4
    GridContainer.ScrollBarImageColor3 = Color3.fromRGB(130, 90, 230)
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
    dStroke.Color = Color3.fromRGB(60, 48, 85)
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
    dTitle.Text = "SELECT AN ITEM"
    dTitle.Font = Enum.Font.GothamBlack
    dTitle.TextSize = 14
    dTitle.TextColor3 = Color3.fromRGB(120, 120, 130)

    -- Preview Image Frame
    local dPreview = Instance.new("Frame", DetailsPanel)
    dPreview.Name = "PreviewFrame"
    dPreview.Size = UDim2.new(0, 72, 0, 72)
    dPreview.Position = UDim2.new(0.5, -36, 0, 42)
    dPreview.BackgroundColor3 = Color3.fromRGB(15, 12, 22)
    dPreview.BackgroundTransparency = 0.5
    dPreview.BorderSizePixel = 0
    Instance.new("UICorner", dPreview).CornerRadius = UDim.new(0, 10)
    
    local dpStroke = Instance.new("UIStroke", dPreview)
    dpStroke.Color = Color3.fromRGB(50, 45, 65)
    dpStroke.Thickness = 1

    local glow = Instance.new("Frame", dPreview)
    glow.Name = "Glow"
    glow.Size = UDim2.new(0.7, 0, 0.7, 0)
    glow.Position = UDim2.new(0.15, 0, 0.15, 0)
    glow.BackgroundTransparency = 0.6
    glow.BackgroundColor3 = Color3.fromRGB(130, 90, 230)
    Instance.new("UICorner", glow).CornerRadius = UDim.new(1, 0)

    local previewIcon = Instance.new("ImageLabel", dPreview)
    previewIcon.Name = "Icon"
    previewIcon.Size = UDim2.fromScale(0.85, 0.85)
    previewIcon.Position = UDim2.fromScale(0.075, 0.075)
    previewIcon.BackgroundTransparency = 1
    previewIcon.ScaleType = Enum.ScaleType.Fit
    
    -- Horizontal Divider
    local divider = Instance.new("Frame", DetailsPanel)
    divider.Name = "Divider"
    divider.Size = UDim2.new(0.85, 0, 0, 1)
    divider.Position = UDim2.new(0.075, 0, 0, 124)
    divider.BackgroundColor3 = Color3.fromRGB(70, 55, 100)
    divider.BorderSizePixel = 0

    -- Structured detail capsules container
    local dPillContainer = Instance.new("Frame", DetailsPanel)
    dPillContainer.Name = "PillContainer"
    dPillContainer.Size = UDim2.new(1, -20, 0, 96)
    dPillContainer.Position = UDim2.new(0, 10, 0, 134)
    dPillContainer.BackgroundTransparency = 1
    
    local listLayout = Instance.new("UIListLayout", dPillContainer)
    listLayout.Padding = UDim.new(0, 6)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local function CreateDetailPill(name: string, layoutOrder: number): Frame
        local pill = Instance.new("Frame", dPillContainer)
        pill.Name = name
        pill.LayoutOrder = layoutOrder
        pill.Size = UDim2.new(1, 0, 0, 24)
        pill.BackgroundColor3 = Color3.fromRGB(15, 12, 22)
        pill.BackgroundTransparency = 0.4
        pill.BorderSizePixel = 0
        Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 6)

        local pillStroke = Instance.new("UIStroke", pill)
        pillStroke.Color = Color3.fromRGB(50, 40, 75)
        pillStroke.Thickness = 1

        local lbl = Instance.new("TextLabel", pill)
        lbl.Size = UDim2.new(1, -16, 1, 0)
        lbl.Position = UDim2.new(0, 8, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 10
        lbl.TextColor3 = Color3.fromRGB(190, 180, 205)
        lbl.TextXAlignment = Enum.TextXAlignment.Left

        return pill
    end

    CreateDetailPill("TypePill", 1)
    CreateDetailPill("BoostPill", 2)
    CreateDetailPill("DurationPill", 3)

    -- Use Button
    local useBtnC = Instance.new("Frame", DetailsPanel)
    useBtnC.Name = "UseBtnContainer"
    useBtnC.Size = UDim2.new(0, 160, 0, 45)
    useBtnC.Position = UDim2.new(0.5, -80, 1, -55)
    useBtnC.BackgroundTransparency = 1
    useBtnC.Visible = false

    local useBtn = Instance.new("TextButton", useBtnC)
    useBtn.Name = "UseBtn"
    useBtn.Size = UDim2.new(1, 0, 1, -4)
    useBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 50)
    useBtn.Text = "USE ITEM"
    useBtn.Font = Enum.Font.GothamBlack
    useBtn.TextColor3 = Color3.new(1, 1, 1)
    useBtn.TextSize = 12
    useBtn.AutoButtonColor = false
    Instance.new("UICorner", useBtn).CornerRadius = UDim.new(0, 8)
    
    local uStroke = Instance.new("UIStroke", useBtn)
    uStroke.Color = Color3.fromRGB(0, 80, 25)
    uStroke.Thickness = 1.5

    local useScale = Instance.new("UIScale", useBtn)
    useBtn.MouseEnter:Connect(function() TweenService:Create(useScale, TweenInfo.new(0.1), {Scale = 1.05}):Play() end)
    useBtn.MouseLeave:Connect(function() TweenService:Create(useScale, TweenInfo.new(0.1), {Scale = 1}):Play() end)
    useBtn.MouseButton1Down:Connect(function() TweenService:Create(useScale, TweenInfo.new(0.05), {Scale = 0.95}):Play() end)
    useBtn.MouseButton1Up:Connect(function() TweenService:Create(useScale, TweenInfo.new(0.1), {Scale = 1.05}):Play() end)

    local remotes = ReplicatedStorage:WaitForChild("Remotes")

    useBtn.MouseButton1Click:Connect(function()
        if selectedItemId then
            -- Spam protection active buff check using synchronized os.time()
            local activeBuff = activeBuffsCache[selectedItemId]
            if activeBuff and activeBuff.EndTime > os.time() then
                useBtn.Text = "ALREADY ACTIVE"
                useBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 30)
                uStroke.Color = Color3.fromRGB(90, 50, 15)
                task.delay(1.5, function()
                    BagController.UpdateDetailsPanel()
                end)
                return
            end

            local consumeEvent = remotes:FindFirstChild(RemoteNames.RequestConsumeItem)
            if consumeEvent then
                useBtn.Text = "USING..."
                useBtn.BackgroundColor3 = Color3.fromRGB(80, 78, 88)
                uStroke.Color = Color3.fromRGB(40, 38, 48)
                consumeEvent:FireServer(selectedItemId)

                local tw = TweenService:Create(useBtnC, TweenInfo.new(0.1, Enum.EasingStyle.Bounce), {Position = UDim2.new(0.5, -80, 1, -50)})
                tw:Play()
                tw.Completed:Connect(function()
                    TweenService:Create(useBtnC, TweenInfo.new(0.1), {Position = UDim2.new(0.5, -80, 1, -55)}):Play()
                end)
            else
                useBtn.Text = "SERVER OFFLINE"
                useBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
                uStroke.Color = Color3.fromRGB(90, 25, 25)
                task.delay(1.5, function()
                    BagController.UpdateDetailsPanel()
                end)
            end
        end
    end)

    -- ─── Networking & Events Connect ─────────────────────────────────────────

    GetLocalEvent("ToggleBag").Event:Connect(function()
        if isOpen then
            closePanel()
        else
            isOpen = true
            animGen += 1
            gui.DisplayOrder = 61 -- render above the outgoing panel during a switch
            MainPanel.Visible = true
            BgShield.Visible = true
            -- Retarget from the current scale (no reset to 0) so reopening during
            -- a close animation continues smoothly instead of snapping shut first.
            -- targetScale is kept fresh by the ViewportSize connection above.
            TweenService:Create(PanelScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = targetScale}):Play()

            GetLocalEvent("NotifyMenuOpened"):Fire("Bag")
            BagController.UpdateDetailsPanel()
        end
    end)

    remotes:WaitForChild("UpdateInventory").OnClientEvent:Connect(function(newInventory)
        inventoryCache = newInventory
        BagController.Refresh()
    end)

    remotes:WaitForChild(RemoteNames.SyncActiveBuffs).OnClientEvent:Connect(function(buffs)
        activeBuffsCache = buffs
        if isOpen then
            BagController.Refresh()
        end
    end)

    -- Cross-menu exclusion is owned centrally by UIController's NotifyMenuOpened
    -- handler, which fires ToggleBag when another menu opens.

    -- Real-time details button & remaining duration updates loop
    task.spawn(function()
        while true do
            task.wait(1)
            if isOpen and selectedItemId then
                BagController.UpdateDetailsPanel()
            end
        end
    end)
end

return BagController
