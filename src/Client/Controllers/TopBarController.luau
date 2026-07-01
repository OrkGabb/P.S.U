--!strict
--@author OrkGabb
--@module TopBarController.luau
--@version 1.0
-- src/Client/Controllers/TopBarController.lua
-- Sleek premium top-right HUD displaying Coins and AuraCoins.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local FeatureResolver = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("FeatureResolver"))

local TopBarController = {}
local CoinLabel: TextLabel
local AuraCoinLabel: TextLabel
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
    local tiers = {
        {1e18, "Qi"}, {1e15, "Qa"}, {1e12, "T"},
        {1e9,  "B"},  {1e6,  "M"},  {1e3,  "K"},
    }
    for _, tier in ipairs(tiers) do
        if n >= tier[1] then
            local formatted = string.format("%.1f", n / tier[1]):gsub("%.0$", "")
            return formatted .. tier[2]
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
    coinsTween:Play()
    coinsTween.Completed:Connect(function(playbackState)
        if coinsTween == thisTween then
            if coinsValObj then coinsValObj:Destroy() coinsValObj = nil end
            if coinsTweenConnection then coinsTweenConnection:Disconnect() coinsTweenConnection = nil end
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
    if data.Coins ~= nil then
        TweenCoins(data.Coins)
    end
end

local function InitHUDFromLeaderstats()
    local ls = LocalPlayer:WaitForChild("leaderstats", 15)
    if ls then
        local coins = ls:WaitForChild("Coins", 10) :: NumberValue?
        if coins then
            TweenCoins(coins.Value)
            coins.Changed:Connect(function(newVal)
                TweenCoins(newVal)
            end)
        end
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
    Container.Size = UDim2.new(0, 126, 0, 28)
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

    -- Connect data sync events
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local updateData: RemoteEvent? = remotes:WaitForChild("UpdateProfileData", 5) :: any
    if updateData then
        updateData.OnClientEvent:Connect(UpdateProfile)
    else
        warn("[TopBarController] UpdateProfileData remote not found after 5s timeout.")
    end

    -- Initialize values
    task.spawn(InitHUDFromLeaderstats)
end

return TopBarController
