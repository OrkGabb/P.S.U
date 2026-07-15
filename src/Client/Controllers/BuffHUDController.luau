--!strict
-- @Author @OrkGabb
-- Potion buff active-duration HUD. Compact layout with viewport scale constraints and auto-hiding during menu views.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local RunService = game:GetService("RunService")
local ItemRegistry = require(ReplicatedStorage.Shared.Modules.ItemRegistry)
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)

local BuffHUDController = {}

local container: Frame
local hudScale: UIScale
local activeBuffsCache: {[string]: {EndTime: number, Boost: number}} = {}
local frameRefs: {[string]: {Frame: Frame, TimerLabel: TextLabel}} = {}

local MENU_NAMES = {
    "BagGui",
    "SkillsGui",
    "QuestsGui",
    "DailyGui",
    "ProfileGui",
    "IndexGui",
    "TransmutationGui",
    "StoreGui",
    "SettingsGui"
}

local function isAnyMenuOpen(): boolean
    local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
    if not playerGui then return false end

    for _, guiName in ipairs(MENU_NAMES) do
        local gui = playerGui:FindFirstChild(guiName) :: ScreenGui?
        if gui and gui.Enabled then
            local main = gui:FindFirstChild("MainPanel") or gui:FindFirstChild("MainFrame")
            if main and (main:IsA("Frame") and main.Visible) then
                return true
            end
        end
    end
    return false
end

local os_time: typeof(os.time) = os.time

local function onRenderStepped(): ()
    if isAnyMenuOpen() then
        container.Visible = false
        return
    else
        container.Visible = true
    end

    local now: number = os_time()
    for itemId, ref in pairs(frameRefs) do
        local buffData = activeBuffsCache[itemId]
        if buffData and buffData.EndTime > now then
            local timeLeft: number = math.floor(buffData.EndTime - now)
            local mins: number = math.floor(timeLeft / 60)
            local secs: number = timeLeft % 60
            local boostPct: number = math.floor((buffData.Boost or 0) * 100)
            
            -- Compact layout text: "+boost% | MM:SS"
            ref.TimerLabel.Text = string.format("+%d%% | %d:%02d", boostPct, mins, secs)
        elseif buffData and buffData.EndTime <= now then
            activeBuffsCache[itemId] = nil
            BuffHUDController.Refresh()
        end
    end
end

function BuffHUDController.Init(): () end

function BuffHUDController.Start(): ()
    local gui = Instance.new("ScreenGui", Players.LocalPlayer.PlayerGui)
    gui.Name = "BuffHUDGui"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 35

    container = Instance.new("Frame", gui)
    container.Size = UDim2.new(0, 150, 0, 200)
    container.AnchorPoint = Vector2.new(0, 1)
    container.Position = UDim2.new(0, 105, 1, -110) -- Shifts right to clear sidebar
    container.BackgroundTransparency = 1

    hudScale = Instance.new("UIScale", container)

    local function updateHUDScale(): ()
        local camera = workspace.CurrentCamera
        if not camera then return end
        local size = camera.ViewportSize
        -- Scale down on smaller viewports (e.g. mobile)
        local scaleX: number = size.X / 600
        local scaleY: number = size.Y / 480
        local scale: number = math.clamp(math.min(scaleX, scaleY, 1), 0.55, 1.0)
        hudScale.Scale = scale
    end

    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateHUDScale)
    updateHUDScale()

    local layout = Instance.new("UIListLayout", container)
    layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    layout.Padding = UDim.new(0, 4)
    layout.SortOrder = Enum.SortOrder.Name

    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local syncEvent = remotes:WaitForChild(RemoteNames.SyncActiveBuffs, 10) :: RemoteEvent?
    if syncEvent then
        syncEvent.OnClientEvent:Connect(function(buffs)
            activeBuffsCache = buffs
            BuffHUDController.Refresh()
        end)
    end

    RunService.RenderStepped:Connect(onRenderStepped)
end

function BuffHUDController.Refresh()
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    table.clear(frameRefs)

    for itemId, buffData in pairs(activeBuffsCache) do
        local itemDef = ItemRegistry.Potions[itemId]
        if not itemDef then continue end

        local f = Instance.new("Frame", container)
        f.Name = itemId
        f.Size = UDim2.new(0, 95, 0, 20)
        f.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
        f.BackgroundTransparency = 0.2
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, 4)
        
        local stroke = Instance.new("UIStroke", f)
        stroke.Color = itemDef.Color or Color3.fromRGB(100, 100, 100)
        stroke.Thickness = 1.0

        local icon = Instance.new("ImageLabel", f)
        icon.Size = UDim2.new(0, 12, 0, 12)
        icon.Position = UDim2.new(0, 4, 0.5, -6)
        icon.BackgroundTransparency = 1
        icon.ScaleType = Enum.ScaleType.Fit
        
        if itemDef.IconId then
            icon.Image = itemDef.IconId
            if itemDef.ImageRectOffset then
                icon.ImageRectOffset = itemDef.ImageRectOffset
                icon.ImageRectSize = AssetRegistry.UI.PotionSpriteSize or Vector2.new(256, 256)
            end
        end

        local timerTxt = Instance.new("TextLabel", f)
        timerTxt.Size = UDim2.new(1, -20, 1, 0)
        timerTxt.Position = UDim2.new(0, 17, 0, 0)
        timerTxt.BackgroundTransparency = 1
        timerTxt.Font = Enum.Font.GothamBold
        timerTxt.TextScaled = true
        timerTxt.TextColor3 = itemDef.Color or Color3.fromRGB(255, 255, 255)
        timerTxt.TextXAlignment = Enum.TextXAlignment.Left
        
        local tsc = Instance.new("UITextSizeConstraint", timerTxt)
        tsc.MinTextSize = 6
        tsc.MaxTextSize = 9
        
        frameRefs[itemId] = { Frame = f, TimerLabel = timerTxt }
    end
end

return BuffHUDController
