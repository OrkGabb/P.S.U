--!strict
-- @Author @OrkGabb
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

local LevelUpController = {}

function LevelUpController.Init(): () end

function LevelUpController.Start(): ()
    local gui = Instance.new("ScreenGui")
    gui.Name = "LevelUpGui"
    gui.ResetOnSpawn = false
    gui.Parent = LocalPlayer.PlayerGui

    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local levelUpEvent = remotes:WaitForChild(RemoteNames.LevelUpFX) :: RemoteEvent

    levelUpEvent.OnClientEvent:Connect(function(newLevel: number, rewardCoins: number)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 300, 0, 120)
        frame.AnchorPoint = Vector2.new(0.5, 0.5)
        frame.Position = UDim2.new(0.5, 0, 0.3, 0)
        frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        frame.BackgroundTransparency = 0.1
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 15)
        
        local stroke = Instance.new("UIStroke", frame)
        stroke.Color = Color3.fromRGB(255, 215, 0)
        stroke.Thickness = 3

        local title = Instance.new("TextLabel", frame)
        title.Size = UDim2.new(1, 0, 0, 50)
        title.BackgroundTransparency = 1
        title.Text = "LEVEL UP!"
        title.TextColor3 = Color3.fromRGB(255, 215, 0)
        title.Font = Enum.Font.FredokaOne
        title.TextSize = 36

        local subText = Instance.new("TextLabel", frame)
        subText.Size = UDim2.new(1, 0, 0, 30)
        subText.Position = UDim2.new(0, 0, 0, 45)
        subText.BackgroundTransparency = 1
        subText.Text = "You reached Level " .. tostring(newLevel)
        subText.TextColor3 = Color3.fromRGB(255, 255, 255)
        subText.Font = Enum.Font.GothamBold
        subText.TextSize = 18

        local rewardText = Instance.new("TextLabel", frame)
        rewardText.Size = UDim2.new(1, 0, 0, 30)
        rewardText.Position = UDim2.new(0, 0, 0, 75)
        rewardText.BackgroundTransparency = 1
        rewardText.Text = "+ " .. tostring(rewardCoins) .. " Coins"
        rewardText.TextColor3 = Color3.fromRGB(0, 255, 100)
        rewardText.Font = Enum.Font.GothamBold
        rewardText.TextSize = 16

        local scale = Instance.new("UIScale", frame)
        scale.Scale = 0
        frame.Parent = gui

        TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {Scale = 1}):Play()

        task.delay(3, function()
            local tweenOut = TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0})
            tweenOut:Play()
            tweenOut.Completed:Connect(function()
                frame:Destroy()
            end)
        end)
    end)
end

return LevelUpController
