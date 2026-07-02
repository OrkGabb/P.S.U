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

local DataService: any = nil -- Lazy-loaded in Start()
local MonetizationService: any = nil -- Lazy-loaded in Start()

local ChatTagService = {}

--- Returns true if the player is VIP: either a timed VIP subscription
--- (VIPExpiry, granted by the VIP dev-product path) or the active genre's
--- permanent "VIP" gamepass.
function ChatTagService.IsVIP(player: Player): boolean
    if not DataService then return false end
    local data = DataService:GetProfileData(player)
    if data and (data.VIPExpiry or 0) > os.time() then
        return true
    end
    if MonetizationService and MonetizationService.HasGamepass(player, "VIP") then
        return true
    end
    return false
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
    MonetizationService = require(ServerScriptService.Server.Services.MonetizationService)

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
