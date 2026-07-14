--!strict
--@author OrkGabb
--@module QuestsController.luau
--@version 1.0
-- src/Client/Controllers/QuestsController.lua
-- Dynamic Quests UI Controller.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local QuestRegistry = require(ReplicatedStorage.Shared.Modules.QuestRegistry)
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)
local UIHelpers = require(script.Parent.Parent.UI.UIHelpers)
local PSUTypes = require(ReplicatedStorage.Shared.Types.PSUTypes)

local QuestsController = {}
local MainPanel: Frame
local PanelScale: UIScale
local BgShield: TextButton
local isOpen = false
-- Bumped on every open/close transition; stale animation callbacks compare
-- against it and stand down if a newer transition has taken over.
local animGen = 0
local UI_Cache: {[string]: {ProgTxt: TextLabel, Desc: TextLabel, Bar: Frame, Btn: TextButton, CoinTxt: TextLabel, ExpTxt: TextLabel}} = {}
local CurrentQuestData: PSUTypes.QuestClientData = { Progress = {}, Claimed = {} }
local currentRebirths = 0

local function FormatNumber(n: number): string
    if not n or n ~= n then return "0" end
    n = math.floor(n)
    if n < 1000 then return tostring(n) end
    if n >= 1e21 then
        local exp = math.floor(math.log10(n))
        return string.format("%.1fe%d", n / (10 ^ exp), exp)
    end
    local tiers: {{Value: number, Suffix: string}} = {
        {Value = 1e18, Suffix = "Qi"}, {Value = 1e15, Suffix = "Qa"}, {Value = 1e12, Suffix = "T"},
        {Value = 1e9,  Suffix = "B"},  {Value = 1e6,  Suffix = "M"},  {Value = 1e3,  Suffix = "K"},
    }
    for _, tier in ipairs(tiers) do
        if n >= tier.Value then
            local formatted = string.format("%.1f", n / tier.Value):gsub("%.0$", "")
            return formatted .. tier.Suffix
        end
    end
    return tostring(n)
end

local function GetLocalEvent(name: string): BindableEvent
    local folder = ReplicatedStorage:WaitForChild("LocalEvents")
    return folder:WaitForChild(name) :: BindableEvent
end

local function WaitForLeaderstats(player: Player, timeout: number?): Folder?
    local deadline = os.clock() + (timeout or 15)
    repeat task.wait(0.1) until player:FindFirstChild("leaderstats") or os.clock() >= deadline
    return player:FindFirstChild("leaderstats") :: Folder?
end

-- Claim-button state stroke (created lazily, reused thereafter)
local function GetButtonStroke(btn: TextButton): UIStroke
    local existing = btn:FindFirstChild("UIStroke")
    if existing and existing:IsA("UIStroke") then
        return existing
    end
    local stroke = Instance.new("UIStroke")
    stroke.Parent = btn
    return stroke
end

local function RefreshUI()
    if not isOpen then return end

    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local level = ls and ls:FindFirstChild("Level") and (ls.Level :: NumberValue).Value or 1

    local mult = QuestRegistry.GetMultiplier(level, currentRebirths)
    for _, quest in ipairs(QuestRegistry.Quests) do
        local el = UI_Cache[quest.Id]
        if not el then continue end

        local current = CurrentQuestData.Progress[quest.Id] or 0
        local claimed = CurrentQuestData.Claimed[quest.Id] or false
        local isComplete = current >= quest.Target
        
        local finalCoins = quest.BaseCoins * mult
        local finalEXP = quest.BaseEXP * mult

        el.ProgTxt.Text = string.format("%s / %s", FormatNumber(current), FormatNumber(quest.Target))
        el.Desc.Text = quest.Desc
        el.CoinTxt.Text = "+" .. FormatNumber(finalCoins)
        el.ExpTxt.Text = "+" .. FormatNumber(finalEXP)
        
        TweenService:Create(el.Bar, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = UDim2.fromScale(math.clamp(current / quest.Target, 0, 1), 1)
        }):Play()

        if claimed then
            el.Btn.Text = "CLAIMED"
            el.Btn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
            el.Btn.TextColor3 = Color3.fromRGB(120, 120, 120)
            GetButtonStroke(el.Btn).Enabled = false
        elseif isComplete then
            el.Btn.Text = "CLAIM"
            el.Btn.BackgroundColor3 = Color3.fromRGB(0, 180, 70)
            el.Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            local stroke = GetButtonStroke(el.Btn)
            stroke.Color = Color3.fromRGB(0, 255, 100)
            stroke.Thickness = 1.5
            stroke.Enabled = true
        else
            el.Btn.Text = "IN PROGRESS"
            el.Btn.BackgroundColor3 = Color3.fromRGB(45, 25, 25)
            el.Btn.TextColor3 = Color3.fromRGB(180, 100, 100)
            local stroke = GetButtonStroke(el.Btn)
            stroke.Color = Color3.fromRGB(90, 40, 40)
            stroke.Thickness = 1
            stroke.Enabled = true
        end
    end
end

function QuestsController.Init(): ()
    if not FeatureResolver.IsCategoryActive("RPG_Adventure") then return end
end

local questHUDHandle: any = nil

function QuestsController.Start(): ()
    if not FeatureResolver.IsCategoryActive("RPG_Adventure") then return end

    local UIController: any = require(script.Parent:WaitForChild("UIController"))
    questHUDHandle = UIController.RegisterHUDButton({
        Id = "Quests",
        Name = "QUESTS",
        IconId = "Quests",
        Type = "Sidebar",
        LayoutOrder = 4,
        OnClick = function(): ()
            GetLocalEvent("ToggleQuests"):Fire()
        end
    })

    local gui = Instance.new("ScreenGui")
    gui.Name = "QuestsGui"
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
    -- (click-to-close is connected below, once closeQuestsMenu exists — the
    -- old forward reference silently connected nil and threw at startup)

    MainPanel = Instance.new("Frame")
    MainPanel.Size = UDim2.new(0, 460, 0, 420)
    MainPanel.AnchorPoint = Vector2.new(0.5, 0.5)
    MainPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
    MainPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    MainPanel.BackgroundTransparency = 0.15
    MainPanel.Visible = false
    MainPanel.Parent = gui
    Instance.new("UICorner", MainPanel).CornerRadius = UDim.new(0, 16)
    
    local panelGradient = Instance.new("UIGradient", MainPanel)
    panelGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 25, 35)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 15, 22))
    })

    local stroke = Instance.new("UIStroke", MainPanel)
    stroke.Color = Color3.fromRGB(90, 60, 150)
    stroke.Thickness = 2.5
    
    local strokeGradient = Instance.new("UIGradient", stroke)
    strokeGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 120, 150)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 40, 50))
    })

    PanelScale = Instance.new("UIScale", MainPanel)
    PanelScale.Scale = 0

    local function closeQuestsMenu(reason: string?)
        if isOpen then
            isOpen = false
            animGen += 1
            local gen = animGen
            gui.DisplayOrder = 60
            BgShield.Visible = false
            GetLocalEvent("NotifyMenuClosed"):Fire("Quests")
            -- A switch-triggered close (another panel is taking over) uses a
            -- fast start so the outgoing panel gets out of the way quickly; a
            -- manual close keeps the slower, weightier Back/In easing.
            local closeTween: TweenInfo = if reason == "switch"
                then TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                else TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)
            local tw = TweenService:Create(PanelScale, closeTween, {Scale = 0})
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
    end

    UIHelpers.CreateCloseButton(MainPanel, closeQuestsMenu)
    BgShield.MouseButton1Up:Connect(function() closeQuestsMenu() end)

    local title = Instance.new("TextLabel", MainPanel)
    title.Text = "DAILY QUESTS"
    title.Size = UDim2.new(1, 0, 0, 50)
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Font = Enum.Font.FredokaOne
    title.TextSize = 22
    title.BackgroundTransparency = 1
    
    local titleGradient = Instance.new("UIGradient", title)
    titleGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 255))
    })

    local divider = Instance.new("Frame", MainPanel)
    divider.Size = UDim2.new(1, -30, 0, 1)
    divider.Position = UDim2.new(0, 15, 0, 50)
    divider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    divider.BackgroundTransparency = 0.85
    divider.BorderSizePixel = 0

    local list = Instance.new("ScrollingFrame", MainPanel)
    list.Size = UDim2.new(1, -30, 1, -80)
    list.Position = UDim2.new(0, 15, 0, 65)
    list.BackgroundTransparency = 1
    list.ScrollBarThickness = 6
    list.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
    list.ScrollBarImageTransparency = 0.5
    list.BorderSizePixel = 0
    list.CanvasSize          = UDim2.new(0, 0, 0, 0)
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Instance.new("UIListLayout", list).Padding = UDim.new(0, 12)

    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local req = remotes:WaitForChild(RemoteNames.ClaimQuestRequest)

    for _, def in ipairs(QuestRegistry.Quests) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -10, 0, 110)
        row.BackgroundColor3 = Color3.fromRGB(22, 17, 32)
        row.Parent = list
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)
        
        local rowGradient = Instance.new("UIGradient", row)
        rowGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 20, 44)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 12, 24))
        })

        local rowStroke = Instance.new("UIStroke", row)
        rowStroke.Color = Color3.fromRGB(60, 48, 85)
        rowStroke.Thickness = 1.5
        
        local n = Instance.new("TextLabel", row)
        n.Text = def.Title:upper()
        n.Size = UDim2.new(0.6, 0, 0, 20)
        n.Position = UDim2.new(0, 15, 0, 10)
        n.TextColor3 = Color3.fromRGB(255, 255, 255)
        n.Font = Enum.Font.GothamBlack
        n.TextSize = 14
        n.TextXAlignment = Enum.TextXAlignment.Left
        n.BackgroundTransparency = 1

        local desc = Instance.new("TextLabel", row)
        desc.Size = UDim2.new(0.6, 0, 0, 16)
        desc.Position = UDim2.new(0, 15, 0, 30)
        desc.TextColor3 = Color3.fromRGB(180, 180, 180)
        desc.Font = Enum.Font.GothamMedium
        desc.TextSize = 11
        desc.TextXAlignment = Enum.TextXAlignment.Left
        desc.BackgroundTransparency = 1
        desc.TextWrapped = true

        local progTxt = Instance.new("TextLabel", row)
        progTxt.Size = UDim2.new(0, 120, 0, 20)
        progTxt.Position = UDim2.new(1, -135, 0, 10)
        progTxt.TextColor3 = Color3.fromRGB(220, 220, 220)
        progTxt.Font = Enum.Font.GothamBold
        progTxt.TextSize = 13
        progTxt.TextXAlignment = Enum.TextXAlignment.Right
        progTxt.BackgroundTransparency = 1

        local barBg = Instance.new("Frame", row)
        barBg.Size = UDim2.new(1, -30, 0, 6)
        barBg.Position = UDim2.new(0, 15, 0, 52)
        barBg.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
        barBg.BorderSizePixel = 0
        Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 3)
        
        local barFill = Instance.new("Frame", barBg)
        barFill.Size = UDim2.fromScale(0, 1)
        barFill.BackgroundColor3 = Color3.fromRGB(255, 120, 0)
        barFill.BorderSizePixel = 0
        Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 3)
        
        local barFillGradient = Instance.new("UIGradient", barFill)
        barFillGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 0)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 0))
        })

        local badgeContainer = Instance.new("Frame", row)
        badgeContainer.Size = UDim2.new(0.6, -10, 0, 26)
        badgeContainer.Position = UDim2.new(0, 15, 0, 68)
        badgeContainer.BackgroundTransparency = 1
        
        local badgeLayout = Instance.new("UIListLayout", badgeContainer)
        badgeLayout.FillDirection = Enum.FillDirection.Horizontal
        badgeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        badgeLayout.Padding = UDim.new(0, 8)

        local coinBadge = Instance.new("Frame", badgeContainer)
        coinBadge.Size = UDim2.new(0, 0, 1, 0)
        coinBadge.AutomaticSize = Enum.AutomaticSize.X
        coinBadge.BackgroundColor3 = Color3.fromRGB(45, 38, 20)
        coinBadge.BackgroundTransparency = 0.3
        Instance.new("UICorner", coinBadge).CornerRadius = UDim.new(0, 6)
        local coinStroke = Instance.new("UIStroke", coinBadge)
        coinStroke.Color = Color3.fromRGB(150, 120, 30)
        coinStroke.Thickness = 1
        
        local coinBadgeLayout = Instance.new("UIListLayout", coinBadge)
        coinBadgeLayout.FillDirection = Enum.FillDirection.Horizontal
        coinBadgeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        coinBadgeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        coinBadgeLayout.Padding = UDim.new(0, 4)
        
        local coinPadding = Instance.new("UIPadding", coinBadge)
        coinPadding.PaddingLeft = UDim.new(0, 6)
        coinPadding.PaddingRight = UDim.new(0, 6)

        local coinIcon = Instance.new("ImageLabel", coinBadge)
        coinIcon.Size = UDim2.fromOffset(14, 14)
        coinIcon.BackgroundTransparency = 1
        coinIcon.Image = AssetRegistry.UI.CoinIcon
        coinIcon.ScaleType = Enum.ScaleType.Fit

        local coinTxt = Instance.new("TextLabel", coinBadge)
        coinTxt.Size = UDim2.new(0, 0, 1, 0)
        coinTxt.AutomaticSize = Enum.AutomaticSize.X
        coinTxt.BackgroundTransparency = 1
        coinTxt.TextColor3 = Color3.fromRGB(255, 200, 50)
        coinTxt.Font = Enum.Font.GothamBold
        coinTxt.TextSize = 11
        coinTxt.TextXAlignment = Enum.TextXAlignment.Left

        local expBadge = Instance.new("Frame", badgeContainer)
        expBadge.Size = UDim2.new(0, 0, 1, 0)
        expBadge.AutomaticSize = Enum.AutomaticSize.X
        expBadge.BackgroundColor3 = Color3.fromRGB(30, 25, 45)
        expBadge.BackgroundTransparency = 0.3
        Instance.new("UICorner", expBadge).CornerRadius = UDim.new(0, 6)
        local expStroke = Instance.new("UIStroke", expBadge)
        expStroke.Color = Color3.fromRGB(120, 60, 200)
        expStroke.Thickness = 1

        local expBadgeLayout = Instance.new("UIListLayout", expBadge)
        expBadgeLayout.FillDirection = Enum.FillDirection.Horizontal
        expBadgeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        expBadgeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        expBadgeLayout.Padding = UDim.new(0, 4)
        
        local expPadding = Instance.new("UIPadding", expBadge)
        expPadding.PaddingLeft = UDim.new(0, 6)
        expPadding.PaddingRight = UDim.new(0, 6)

        local expIcon = Instance.new("ImageLabel", expBadge)
        expIcon.Size = UDim2.fromOffset(14, 14)
        expIcon.BackgroundTransparency = 1
        expIcon.Image = AssetRegistry.UI.EXPPotionIcon
        expIcon.ScaleType = Enum.ScaleType.Fit

        local expTxt = Instance.new("TextLabel", expBadge)
        expTxt.Size = UDim2.new(0, 0, 1, 0)
        expTxt.AutomaticSize = Enum.AutomaticSize.X
        expTxt.BackgroundTransparency = 1
        expTxt.TextColor3 = Color3.fromRGB(180, 120, 255)
        expTxt.Font = Enum.Font.GothamBold
        expTxt.TextSize = 11
        expTxt.TextXAlignment = Enum.TextXAlignment.Left

        local buy = Instance.new("TextButton", row)
        buy.Size = UDim2.new(0, 140, 0, 40)
        buy.Position = UDim2.new(1, -155, 0, 64)
        buy.Text = "IN PROGRESS"
        buy.TextColor3 = Color3.fromRGB(255, 255, 255)
        buy.Font = Enum.Font.GothamBlack
        buy.TextSize = 11
        buy.AutoButtonColor = false
        Instance.new("UICorner", buy).CornerRadius = UDim.new(0, 8)
        
        local btnScale = Instance.new("UIScale", buy)
        buy.MouseEnter:Connect(function() TweenService:Create(btnScale, TweenInfo.new(0.1), {Scale = 1.05}):Play() end)
        buy.MouseLeave:Connect(function() TweenService:Create(btnScale, TweenInfo.new(0.1), {Scale = 1}):Play() end)
        buy.MouseButton1Down:Connect(function() TweenService:Create(btnScale, TweenInfo.new(0.05), {Scale = 0.95}):Play() end)
        buy.MouseButton1Up:Connect(function() TweenService:Create(btnScale, TweenInfo.new(0.1), {Scale = 1.05}):Play() end)

        UI_Cache[def.Id] = {ProgTxt = progTxt, Desc = desc, Bar = barFill, Btn = buy, CoinTxt = coinTxt, ExpTxt = expTxt}
        
        buy.MouseButton1Click:Connect(function() 
            if CurrentQuestData.Progress[def.Id] and CurrentQuestData.Progress[def.Id] >= def.Target and not CurrentQuestData.Claimed[def.Id] then
                req:FireServer(def.Id) 
                if questHUDHandle then
                    questHUDHandle.SetNotificationActive(false)
                end
            end
        end)
    end

    local camera = workspace.CurrentCamera
    local targetScale = 1
    
    local function updateUIScale()
        if not camera then return end
        local size = camera.ViewportSize
        local scaleX = size.X / 500
        local scaleY = size.Y / 460
        targetScale = math.clamp(math.min(scaleX, scaleY, 1), 0.5, 1.2)
        if isOpen then
            -- Retarget with a tween: a direct Scale set while another tween is
            -- animating the property gets overwritten every frame.
            TweenService:Create(PanelScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = targetScale}):Play()
        end
    end
    
    camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateUIScale)
    updateUIScale()

    remotes:WaitForChild(RemoteNames.UpdateQuests).OnClientEvent:Connect(function(questData: any)
        CurrentQuestData = questData :: PSUTypes.QuestClientData
        if isOpen then RefreshUI() end

        local hasUnclaimed = false
        for _, quest in ipairs(QuestRegistry.Quests) do
            local current = CurrentQuestData.Progress[quest.Id] or 0
            local claimed = CurrentQuestData.Claimed[quest.Id] or false
            if current >= quest.Target and not claimed then
                hasUnclaimed = true
                break
            end
        end

        if questHUDHandle then
            questHUDHandle.SetNotificationActive(hasUnclaimed)
        end
    end)

    local ls = WaitForLeaderstats(LocalPlayer)
    if not ls then
        warn("[QuestsController] leaderstats not found after timeout — Level change-listener not connected.")
        return
    end
    local levelVal = ls:WaitForChild("Level", 10)
    if levelVal then levelVal.Changed:Connect(function() if isOpen then RefreshUI() end end) end

    GetLocalEvent("ToggleQuests").Event:Connect(function(reason: string?)
        if isOpen then
            closeQuestsMenu(reason)
        else
            isOpen = true
            animGen += 1
            gui.DisplayOrder = 61 -- render above the outgoing panel during a switch
            MainPanel.Visible = true
            BgShield.Visible = true
            RefreshUI()
            -- Retarget from the current scale (no reset to 0) so reopening during
            -- a close animation continues smoothly instead of snapping shut first.
            -- targetScale is kept fresh by the ViewportSize connection above.
            TweenService:Create(PanelScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = targetScale}):Play()

            GetLocalEvent("NotifyMenuOpened"):Fire("Quests")
        end
    end)

    -- Cross-menu exclusion is owned centrally by UIController's NotifyMenuOpened
    -- handler, which fires ToggleQuests when another menu opens.

    local updateProfileData = remotes:WaitForChild(RemoteNames.UpdateProfileData, 5)
    if updateProfileData then
        (updateProfileData :: RemoteEvent).OnClientEvent:Connect(function(data)
            currentRebirths = data.Rebirths or 0
            if isOpen then RefreshUI() end
        end)
    end

    local updateUpgrades = remotes:WaitForChild(RemoteNames.UpdateUpgrades, 5)
    if updateUpgrades then
        (updateUpgrades :: RemoteEvent).OnClientEvent:Connect(function()
            if isOpen then RefreshUI() end
        end)
    end

    isOpen = false
    MainPanel.Visible = false
    PanelScale.Scale = 0
end

return QuestsController
