--!strict
--@author OrkGabb
--@module UpgradeService.luau
--@version 1.0
-- src/Server/Services/UpgradeService.lua
-- Character Upgrades Management Service. Handles character mastery and stats scaling.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
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

    for id, def in pairs(UpgradeRegistry) do
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

function UpgradeService.GetCost(id: string, level: number): number
    local def = UpgradeRegistry[id]
    local cost = math.floor(def.BaseCost * math.pow(def.CostMultiplier, level))
    return math.max(0, cost)
end

-- ─── Event Handlers ──────────────────────────────────────────────────────────

local function OnUpgradeRequest(player: Player, upgradeId: string)
    local profile = DataService.Profiles[player]
    local def = UpgradeRegistry[upgradeId]
    if not profile or not def then return end

    -- Fallback for legacy save data structure
    if not profile.Data.Upgrades then profile.Data.Upgrades = {} end

    local currentLevel = profile.Data.Upgrades[upgradeId] or 0
    if currentLevel >= def.MaxLevel then return end

    local cost = UpgradeService.GetCost(upgradeId, currentLevel)
    
    -- Numeric overflow protection (prevents NaN / Infinity exploits)
    if cost ~= cost or cost == math.huge or cost < 0 then return end
    
    if profile.Data.Coins < cost then return end

    profile.Data.Coins -= cost
    profile.Data.Upgrades[upgradeId] = currentLevel + 1

    local ls = player:FindFirstChild("leaderstats")
    if ls and ls:FindFirstChild("Coins") then
        ls.Coins.Value = profile.Data.Coins
    end

    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local updateEvent = remotes:FindFirstChild("UpdateUpgrades") :: RemoteEvent?
    if updateEvent then
        updateEvent:FireClient(player, profile.Data.Upgrades)
    end

    -- Master sync after upgrade: synchronizes player state atomically
    DataService:SyncFullState(player)

    if QuestService then
        QuestService.AddProgress(player, "Upgrade", 1)
    end
end

-- ─── Lifecycle ──────────────────────────────────────────────────────────────

function UpgradeService.Init(): ()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    
    local requiredRemotes = {
        "UpgradeRequest",
        "UpdateUpgrades",
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
    
    local upgradeEvent = remotes:WaitForChild("UpgradeRequest") :: RemoteEvent
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
