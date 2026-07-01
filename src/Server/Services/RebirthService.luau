--!strict
--@author OrkGabb
--@module RebirthService.luau
--@version 1.0
-- src/Server/Services/RebirthService.lua
-- Refactored: Anti-Spam protection (debounce) and security delegation to DataService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local DataService = require(ServerScriptService.Server.Services.DataService)

local RebirthService = {}
local activeRequests: {[Player]: boolean} = {}

function RebirthService.Init(): ()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    if not remotes:FindFirstChild("RequestRebirth") then
        Instance.new("RemoteEvent", remotes).Name = "RequestRebirth"
    end
    if not remotes:FindFirstChild("NotifyRebirth") then
        Instance.new("RemoteEvent", remotes).Name = "NotifyRebirth"
    end
    if not remotes:FindFirstChild("RebirthError") then
        Instance.new("RemoteEvent", remotes).Name = "RebirthError"
    end
end

function RebirthService.Start(): ()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local requestEvt = remotes:WaitForChild("RequestRebirth") :: RemoteEvent
    
    requestEvt.OnServerEvent:Connect(function(player: Player)
        -- [ANTI-SPAM]: Prevents the player from spamming clicks and overloading DataService
        if activeRequests[player] then
            local errEvt = remotes:FindFirstChild("RebirthError") :: RemoteEvent?
            if errEvt then
                errEvt:FireClient(player, "SLOW DOWN")
            end
            return
        end
        activeRequests[player] = true
        
        -- PerformRebirth handles level validation, resetting progress, and firing notifications
        local success, errMsg = DataService:PerformRebirth(player)
        
        if success then
            local QuestService = require(ServerScriptService.Server.Services.QuestService)
            if QuestService then
                QuestService.AddProgress(player, "Rebirth", 1)
            end
        else
            local errEvt = remotes:FindFirstChild("RebirthError") :: RemoteEvent?
            if errEvt then
                errEvt:FireClient(player, errMsg or "REBIRTH FAILED")
            end
        end

        -- Global security cooldown of 3 seconds for this action
        task.delay(3, function()
            activeRequests[player] = nil
        end)
    end)

    -- Clean up memory if the player leaves during the cooldown
    Players.PlayerRemoving:Connect(function(player)
        activeRequests[player] = nil
    end)
end

return RebirthService
