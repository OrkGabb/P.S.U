--!strict
--@author OrkGabb
--@module ChatTagService.luau
--@version 1.0
-- src/Server/Services/ChatTagService.lua
-- Server-side service that exposes VIP status to clients via RemoteFunction.
-- The actual chat tag rendering happens on the client (ChatTagController)
-- because TextChannel.OnIncomingMessage is a client-side callback.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataService -- Lazy-loaded in Start()

local ChatTagService = {}

--- Returns true if the player has an active VIP subscription (VIPExpiry > now).
function ChatTagService.IsVIP(player: Player): boolean
    if not DataService then return false end
    local profile = DataService:GetProfile(player)
    if not profile or not profile.Data then return false end
    return (profile.Data.VIPExpiry or 0) > os.time()
end

function ChatTagService.Init(): ()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    if not remotes:FindFirstChild("CheckVIPStatus") then
        local rf = Instance.new("RemoteFunction")
        rf.Name = "CheckVIPStatus"
        rf.Parent = remotes
    end
end

function ChatTagService.Start(): ()
    DataService = require(ServerScriptService.Server.Services.DataService)

    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local checkVIP = remotes:WaitForChild("CheckVIPStatus") :: RemoteFunction

    -- Clients can query any player's VIP status by UserId
    checkVIP.OnServerInvoke = function(_caller: Player, targetUserId: number): boolean
        if type(targetUserId) ~= "number" then return false end
        local targetPlayer = Players:GetPlayerByUserId(targetUserId)
        if not targetPlayer then return false end
        return ChatTagService.IsVIP(targetPlayer)
    end
end

return ChatTagService
