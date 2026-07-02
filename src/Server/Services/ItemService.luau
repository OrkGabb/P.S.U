--!strict
--@author OrkGabb
--@module ItemService.luau
--@version 1.0
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- NOTE: DataService/ItemRegistry are required lazily inside handlers to
-- avoid a circular require with DataService at module load.

local ItemService = {}
ItemService.activeBuffs = {} -- EXPORTED: Allows reading active buffs from DataService

function ItemService.Init(): ()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    if not remotes:FindFirstChild("RequestConsumeItem") then
        Instance.new("RemoteEvent", remotes).Name = "RequestConsumeItem"
    end
    if not remotes:FindFirstChild("SyncActiveBuffs") then
        local syncEvent = Instance.new("RemoteEvent")
        syncEvent.Name = "SyncActiveBuffs"
        syncEvent.Parent = remotes
    end
end

function ItemService.Start(): ()
    local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
    local consumeEvent = remotes:FindFirstChild("RequestConsumeItem")
    local syncEvent    = remotes:FindFirstChild("SyncActiveBuffs")
    local Players      = game:GetService("Players")

    local DataSvc      = require(script.Parent.DataService)
    local ItemRegistry = require(game:GetService("ReplicatedStorage").Shared.Modules.ItemRegistry)

    if consumeEvent then
        consumeEvent.OnServerEvent:Connect(function(player, itemId)
            local itemData = ItemRegistry.Potions[itemId]
            if not itemData then return end

            local success = DataSvc:ConsumeItem(player, itemId, 1)
            if success then
                -- Buff is stored only in volatile memory - NEVER saved to profile
                ItemService.activeBuffs[player] = ItemService.activeBuffs[player] or {}
                ItemService.activeBuffs[player][itemId] = {
                    EndTime = os.time() + itemData.Duration,
                    Stat    = itemData.Stat,
                    Boost   = itemData.Boost
                }

                -- Sync HUD
                if syncEvent then
                    syncEvent:FireClient(player, ItemService.activeBuffs[player])
                end

                -- Sync full state instead of partial profile update to prevent resetting UI
                DataSvc:SyncFullState(player)

                -- Track quest progress for potion usage
                local QuestService = require(ServerScriptService.Server.Services.QuestService)
                if QuestService then
                    QuestService.AddProgress(player, "UsePotion", 1)
                end

                -- Auto-expiration: clears the buff and updates the UI
                task.delay(itemData.Duration, function()
                    if not ItemService.activeBuffs[player] then return end
                    ItemService.activeBuffs[player][itemId] = nil
                    if syncEvent then
                        syncEvent:FireClient(player, ItemService.activeBuffs[player])
                    end
                    -- Update full state on expiration
                    DataSvc:SyncFullState(player)
                end)
            end
        end)
    end

    -- Memory safety: clean up volatile buffs when player leaves
    Players.PlayerRemoving:Connect(function(player)
        ItemService.activeBuffs[player] = nil
    end)
end

function ItemService:GetVolatileMultiplier(player: Player, statType: string): number
    local mult = 1
    if self.activeBuffs and self.activeBuffs[player] then
        for _, buff in pairs(self.activeBuffs[player]) do
            if buff.Stat == statType and buff.EndTime > os.time() then
                mult += buff.Boost
            end
        end
    end
    return mult
end

return ItemService
