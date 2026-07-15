--!strict
--@author OrkGabb
-- Server-authoritative upgrade purchases. All cost math (formula, lookup-table
-- and milestone gates) is delegated to UpgradeRegistry so validation here and
-- display on the client can never disagree.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local ServerScriptService = game:GetService("ServerScriptService")

local DataService       = require(ServerScriptService.Server.Services.DataService)
local UpgradeRegistry   = require(ReplicatedStorage.Shared.Modules.UpgradeRegistry)
local QuestService: any = nil

local UpgradeService = {}

-- Ensures that no saved upgrade exceeds the MaxLevel in the registry.
-- Called once in PlayerAdded before any client synchronization.
local function SanitizeUpgrades(player: Player)
    local profile = DataService.Profiles[player]
    if not profile then return end

    local upgrades = profile.Data.Upgrades
    if not upgrades then return end

    for id, def in pairs(UpgradeRegistry.Defs) do
        local saved = upgrades[id]
        if saved and saved > def.MaxLevel then
            warn(string.format(
                "[UpgradeService] SanitizeUpgrades: %s.%s=%d > MaxLevel=%d — clamped.",
                player.Name, id, saved, def.MaxLevel
            ))
            upgrades[id] = def.MaxLevel
        end
    end
end

local function OnUpgradeRequest(player: Player, upgradeId: string)
    if type(upgradeId) ~= "string" then return end

    local profile = DataService.Profiles[player]
    local def = UpgradeRegistry.GetDef(upgradeId)
    if not profile or not def then return end

    -- Fallback for legacy save data structure
    if not profile.Data.Upgrades then profile.Data.Upgrades = {} end
    if not profile.Data.Currencies then
        profile.Data.Currencies = { Primary = 0, Secondary = 0, Premium = 0 }
    end

    local currentLevel = profile.Data.Upgrades[upgradeId] or 0
    if currentLevel >= def.MaxLevel then return end

    local cost, costCurrency = UpgradeRegistry.GetCost(upgradeId, currentLevel)
    if cost == nil then return end

    -- Numeric overflow protection (prevents NaN / Infinity exploits)
    if cost ~= cost or cost == math.huge or cost < 0 then return end

    local newLevel = currentLevel + 1
    local milestoneCost, milestoneCurrency = UpgradeRegistry.GetMilestoneCost(upgradeId, newLevel)

    local currencies = profile.Data.Currencies
    local baseBalance: number = currencies[costCurrency] or 0
    if baseBalance < cost then return end

    if milestoneCost > 0 then
        local milestoneBalance: number = currencies[milestoneCurrency] or 0
        if milestoneBalance < milestoneCost then return end
        currencies[milestoneCurrency] = milestoneBalance - milestoneCost
    end

    currencies[costCurrency] = baseBalance - cost
    profile.Data.Upgrades[upgradeId] = newLevel

    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local updateEvent = remotes:FindFirstChild(RemoteNames.UpdateUpgrades) :: RemoteEvent?
    if updateEvent then
        updateEvent:FireClient(player, profile.Data.Upgrades)
    end

    -- Syncs full state atomically after the upgrade
    DataService:SyncFullState(player)

    if QuestService then
        QuestService.AddProgress(player, "Upgrade", 1)
    end
end

function UpgradeService.Init(): ()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")

    local requiredRemotes = {
        RemoteNames.UpgradeRequest,
        RemoteNames.UpdateUpgrades,
    }

    for _, name in ipairs(requiredRemotes) do
        if not remotes:FindFirstChild(name) then
            local event = Instance.new("RemoteEvent")
            event.Name = name
            event.Parent = remotes
        end
    end
end

function UpgradeService.Start(): ()
    QuestService = require(ServerScriptService.Server.Services.QuestService)
    local remotes = ReplicatedStorage:WaitForChild("Remotes")

    local upgradeEvent = remotes:WaitForChild(RemoteNames.UpgradeRequest) :: RemoteEvent
    upgradeEvent.OnServerEvent:Connect(OnUpgradeRequest)

    local function onPlayerAdded(player: Player)
        local attempts = 0
        repeat
            task.wait(0.5)
            attempts += 1
        until DataService.Profiles[player] ~= nil or attempts >= 20

        SanitizeUpgrades(player)
    end

    Players.PlayerAdded:Connect(onPlayerAdded)
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(onPlayerAdded, player)
    end
end

return UpgradeService
