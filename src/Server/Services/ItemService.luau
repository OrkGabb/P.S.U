--!strict
--@author OrkGabb
--@module ItemService.luau
--@version 1.0
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local ServerScriptService = game:GetService("ServerScriptService")

-- NOTE: DataService/ItemRegistry are required lazily inside handlers to
-- avoid a circular require with DataService at module load.

local ItemService = {}
ItemService.activeBuffs = {} -- EXPORTED: Allows reading active buffs from DataService

-- Monotonic counter stamped onto each buff instance (see consumeEvent handler)
-- so a stale task.delay can detect it's no longer the active instance.
local buffGen = 0

function ItemService.Init(): ()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    if not remotes:FindFirstChild(RemoteNames.RequestConsumeItem) then
        Instance.new("RemoteEvent", remotes).Name = RemoteNames.RequestConsumeItem
    end
    if not remotes:FindFirstChild(RemoteNames.SyncActiveBuffs) then
        local syncEvent = Instance.new("RemoteEvent")
        syncEvent.Name = RemoteNames.SyncActiveBuffs
        syncEvent.Parent = remotes
    end
end

function ItemService.Start(): ()
    local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
    local consumeEvent = remotes:FindFirstChild(RemoteNames.RequestConsumeItem)
    local syncEvent    = remotes:FindFirstChild(RemoteNames.SyncActiveBuffs)
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
                -- Generation token: re-applying the same itemId before the prior
                -- instance expires must not let the prior task.delay wipe this one.
                buffGen += 1
                local gen = buffGen
                ItemService.activeBuffs[player][itemId] = {
                    EndTime = os.time() + itemData.Duration,
                    Stat    = itemData.Stat,
                    Boost   = itemData.Boost,
                    Gen     = gen
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

                -- Auto-expiration: clears the buff and updates the UI, but only if
                -- this task.delay's instance is still the active one (a re-applied
                -- buff before expiry bumps Gen, and the stale delay must no-op).
                task.delay(itemData.Duration, function()
                    local buffs = ItemService.activeBuffs[player]
                    if not buffs or not buffs[itemId] or buffs[itemId].Gen ~= gen then return end
                    buffs[itemId] = nil
                    if syncEvent then
                        syncEvent:FireClient(player, buffs)
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
