--!strict
--@author OrkGabb
--@module TopBarController.luau
--@version 1.0
-- src/Client/Controllers/TopBarController.lua
-- Sleek premium top-right HUD displaying the active genre's two currencies.
-- Currency names resolve from the genre config (FeatureResolver.GetCurrencyNames).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local LocalPlayer = Players.LocalPlayer

local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local FeatureResolver = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("FeatureResolver"))

local TopBarController = {}
local CoinLabel: TextLabel
local SecondaryLabel: TextLabel? = nil
local Container: Frame

-- Handles all scales. No "inf"/"Max" fallback — very large numbers use scientific notation.
-- NOTE: NumberValue (used for coin tweening) is a 64-bit double — no 2^31 IntValue cap here.
local function FormatNumber(n: number): string
    if not n or n ~= n then return "0" end
    n = math.floor(n)
    if n < 1000 then return tostring(n) end
    -- Beyond Qi: fall back to scientific notation (e.g. 1.2e21)
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

local currentCoins = 0

local coinsTweenConnection: RBXScriptConnection? = nil
local coinsValObj: NumberValue? = nil
local coinsTween: Tween? = nil

local function TweenCoins(targetVal: number)
    if targetVal == currentCoins and coinsValObj == nil then return end
    
    local startVal = currentCoins
    if coinsValObj then startVal = coinsValObj.Value end

    if coinsTween then coinsTween:Cancel() end
    if coinsTweenConnection then coinsTweenConnection:Disconnect() end
    if coinsValObj then coinsValObj:Destroy() end

    coinsValObj = Instance.new("NumberValue")
    coinsValObj.Value = startVal
    coinsTweenConnection = coinsValObj.Changed:Connect(function()
        if coinsValObj then
            CoinLabel.Text = FormatNumber(coinsValObj.Value)
        end
    end)

    local thisTween = TweenService:Create(coinsValObj, TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {Value = targetVal})
    coinsTween = thisTween
    thisTween:Play()
    thisTween.Completed:Connect(function(playbackState)
        if coinsTween == thisTween then
            if coinsValObj then
                coinsValObj:Destroy()
                coinsValObj = nil
            end
            if coinsTweenConnection then
                coinsTweenConnection:Disconnect()
                coinsTweenConnection = nil
            end
            coinsTween = nil
            if playbackState == Enum.PlaybackState.Completed then
                CoinLabel.Text = FormatNumber(targetVal)
            end
        end
    end)
    currentCoins = targetVal
end

local function UpdateProfile(data: any)
    if not data then return end
    if type(data.Currencies) == "table" then
        if type(data.Currencies.Primary) == "number" then
            TweenCoins(data.Currencies.Primary)
        end
        if SecondaryLabel and type(data.Currencies.Secondary) == "number" then
            SecondaryLabel.Text = FormatNumber(data.Currencies.Secondary)
        end
    end
end

local function InitHUDFromLeaderstats()
    local currencyNames = FeatureResolver.GetCurrencyNames()
    local ls = LocalPlayer:WaitForChild("leaderstats", 15)
    if not ls then return end

    local primary = ls:WaitForChild(currencyNames.Primary, 10)
    if primary and (primary:IsA("IntValue") or primary:IsA("NumberValue")) then
        local primaryValue = primary :: IntValue
        TweenCoins(primaryValue.Value)
        primaryValue.Changed:Connect(function(newVal)
            TweenCoins(newVal)
        end)
    end

    local secondary = ls:FindFirstChild(currencyNames.Secondary)
    if secondary and (secondary:IsA("IntValue") or secondary:IsA("NumberValue")) then
        local secondaryValue = secondary :: IntValue
        if SecondaryLabel then
            SecondaryLabel.Text = FormatNumber(secondaryValue.Value)
        end
        secondaryValue.Changed:Connect(function(newVal)
            if SecondaryLabel then
                SecondaryLabel.Text = FormatNumber(newVal)
            end
        end)
    end
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

    if not hasActiveGenre or FeatureResolver.IsCategoryActive("FPS_Shooter") then
        print("[TopBarController] Fallback/FPS mode active: hiding top-right currencies display.")
        return
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "TopBarGui"
    gui.ResetOnSpawn = false 
    gui.IgnoreGuiInset = true
    gui.Parent = LocalPlayer.PlayerGui

    -- Sleek Premium dark glassmorphism Container
    Container = Instance.new("Frame")
    Container.Name = "HUDDisplay"
    Container.Size = UDim2.new(0, 126, 0, 52)
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

    -- --- Coin Row ---
    local coinRow = Instance.new("Frame")
    coinRow.Name = "CoinRow"
    coinRow.Size = UDim2.new(1, 0, 0, 20)
    coinRow.BackgroundTransparency = 1
    coinRow.LayoutOrder = 1
    coinRow.Parent = Container

    local coinIcon = Instance.new("ImageLabel")
    coinIcon.Name = "CoinIcon"
    coinIcon.Size = UDim2.new(0, 17, 0, 17)
    coinIcon.Position = UDim2.new(0, 0, 0.5, -8)
    coinIcon.BackgroundTransparency = 1
    coinIcon.Image = AssetRegistry.UI.CoinIcon
    coinIcon.ScaleType = Enum.ScaleType.Fit
    coinIcon.Parent = coinRow

    CoinLabel = Instance.new("TextLabel")
    CoinLabel.Name = "CoinValue"
    CoinLabel.Size = UDim2.new(1, -21, 1, 0)
    CoinLabel.Position = UDim2.new(0, 21, 0, 0)
    CoinLabel.BackgroundTransparency = 1
    CoinLabel.Text = "0"
    CoinLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    CoinLabel.Font = Enum.Font.GothamBold
    CoinLabel.TextSize = 10
    CoinLabel.TextXAlignment = Enum.TextXAlignment.Left
    CoinLabel.TextYAlignment = Enum.TextYAlignment.Center
    CoinLabel.Parent = coinRow

    -- --- Secondary Currency Row ---
    local secondaryRow = Instance.new("Frame")
    secondaryRow.Name = "SecondaryRow"
    secondaryRow.Size = UDim2.new(1, 0, 0, 20)
    secondaryRow.BackgroundTransparency = 1
    secondaryRow.LayoutOrder = 2
    secondaryRow.Parent = Container

    local secondaryIcon = Instance.new("ImageLabel")
    secondaryIcon.Name = "SecondaryIcon"
    secondaryIcon.Size = UDim2.new(0, 17, 0, 17)
    secondaryIcon.Position = UDim2.new(0, 0, 0.5, -8)
    secondaryIcon.BackgroundTransparency = 1
    secondaryIcon.Image = AssetRegistry.UI.CoinIcon
    secondaryIcon.ImageColor3 = Color3.fromRGB(255, 170, 220)
    secondaryIcon.ScaleType = Enum.ScaleType.Fit
    secondaryIcon.Parent = secondaryRow

    local secondaryLabel = Instance.new("TextLabel")
    secondaryLabel.Name = "SecondaryValue"
    secondaryLabel.Size = UDim2.new(1, -21, 1, 0)
    secondaryLabel.Position = UDim2.new(0, 21, 0, 0)
    secondaryLabel.BackgroundTransparency = 1
    secondaryLabel.Text = "0"
    secondaryLabel.TextColor3 = Color3.fromRGB(255, 210, 240)
    secondaryLabel.Font = Enum.Font.GothamBold
    secondaryLabel.TextSize = 10
    secondaryLabel.TextXAlignment = Enum.TextXAlignment.Left
    secondaryLabel.TextYAlignment = Enum.TextYAlignment.Center
    secondaryLabel.Parent = secondaryRow
    SecondaryLabel = secondaryLabel

    -- Connect data sync events
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local updateData: RemoteEvent? = remotes:WaitForChild(RemoteNames.UpdateProfileData, 5) :: any
    if updateData then
        updateData.OnClientEvent:Connect(UpdateProfile)
    else
        warn("[TopBarController] UpdateProfileData remote not found after 5s timeout.")
    end

    -- Initialize values
    task.spawn(InitHUDFromLeaderstats)
end

return TopBarController
