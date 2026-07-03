--!strict
--@author OrkGabb
--@module ChatTagController.luau
--@version 1.0
-- src/Client/Controllers/ChatTagController.lua
-- Client-side controller that prepends a [VIP] tag on chat messages.
-- Uses TextChatService.OnIncomingMessage (the correct client-side callback)
-- and caches VIP lookups per-player to avoid excessive remote calls.

local TextChatService  = game:GetService("TextChatService")
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local ChatTagController = {}

-- Cache: UserId -> { isVIP: boolean, checkedAt: number }
local VIPCache: {[number]: { isVIP: boolean, checkedAt: number }} = {}
local CACHE_TTL = 60 -- Re-check every 60 seconds

local CheckVIPRemote: RemoteFunction? = nil

local function GetVIPStatus(userId: number): boolean
    local now = os.clock()
    local cached = VIPCache[userId]
    if cached and (now - cached.checkedAt) < CACHE_TTL then
        return cached.isVIP
    end

    -- Query the server
    if not CheckVIPRemote then return false end

    local ok, result = pcall(function()
        return (CheckVIPRemote :: RemoteFunction):InvokeServer(userId)
    end)

    local isVIP = ok and result == true
    VIPCache[userId] = { isVIP = isVIP, checkedAt = now }
    return isVIP
end

function ChatTagController.Init(): ()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
    if remotes then
        CheckVIPRemote = remotes:WaitForChild(RemoteNames.CheckVIPStatus, 15) :: RemoteFunction?
    end
end

function ChatTagController.Start(): ()
    if not CheckVIPRemote then
        warn("[ChatTagController] CheckVIPStatus remote not found — VIP tags disabled.")
        return
    end

    -- TextChatService.OnIncomingMessage is the correct client-side hook
    TextChatService.OnIncomingMessage = function(message: TextChatMessage)
        local props = Instance.new("TextChatMessageProperties")

        if message.TextSource then
            local userId = message.TextSource.UserId
            if GetVIPStatus(userId) then
                props.PrefixText = '<font color="#FFD700">[VIP]</font> ' .. message.PrefixText
            end
        end

        return props
    end
end

-- Clean up cache when players leave
Players.PlayerRemoving:Connect(function(player: Player)
    VIPCache[player.UserId] = nil
end)

return ChatTagController
