--!strict
--@author OrkGabb
--@module ChatTagController.luau
--@version 1.0
-- Client-side controller that prepends a [VIP] tag on chat messages.
-- Uses TextChatService.OnIncomingMessage (the correct client-side callback)
-- and caches VIP lookups per-player to avoid excessive remote calls.

local TextChatService  = game:GetService("TextChatService")
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local ChatTagController = {}

local VIPCache: {[number]: { isVIP: boolean, checkedAt: number }} = {}
local CACHE_TTL = 60
local TIMEOUT_CACHE_TTL = 30 -- Shorter re-check after a timeout, so a stuck handler doesn't stall every message for INVOKE_TIMEOUT seconds

local CheckVIPRemote: RemoteFunction? = nil
local INVOKE_TIMEOUT = 5 -- seconds; OnIncomingMessage blocks message rendering, so this must not hang forever

local function GetVIPStatus(userId: number): boolean
    local now = os.clock()
    local cached = VIPCache[userId]
    if cached and (now - cached.checkedAt) < CACHE_TTL then
        return cached.isVIP
    end

    if not CheckVIPRemote then return false end

    -- Run the InvokeServer call on its own thread and bound how long we wait
    -- on it here — OnIncomingMessage is synchronous, so a stalled server
    -- handler must not hang chat rendering indefinitely.
    local done, ok, result = false, false, nil
    task.spawn(function()
        ok, result = pcall(function()
            return (CheckVIPRemote :: RemoteFunction):InvokeServer(userId)
        end)
        done = true
    end)

    local start = os.clock()
    while not done and (os.clock() - start) < INVOKE_TIMEOUT do
        task.wait()
    end

    if not done then
        -- Timed out: cache a negative result briefly so a stuck handler doesn't
        -- re-stall every subsequent message for INVOKE_TIMEOUT seconds; the
        -- shorter TTL still lets us recover soon after the server recovers.
        VIPCache[userId] = { isVIP = false, checkedAt = now - CACHE_TTL + TIMEOUT_CACHE_TTL }
        return false
    end

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

Players.PlayerRemoving:Connect(function(player: Player)
    VIPCache[player.UserId] = nil
end)

return ChatTagController
