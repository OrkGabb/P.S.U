--!strict
--@author OrkGabb
--@module NetworkService.luau
--@version 1.0
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local NetworkService = {}
local Remotes: {[string]: RemoteEvent} = {}

function NetworkService.Init(): ()
    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotesFolder then
        remotesFolder = Instance.new("Folder")
        remotesFolder.Name = "Remotes"
        remotesFolder.Parent = ReplicatedStorage
    end

    for _, name in pairs(RemoteNames) do
        local existing = remotesFolder:FindFirstChild(name)
        local event: RemoteEvent
        if existing and existing:IsA("RemoteEvent") then
            event = existing
        else
            event = Instance.new("RemoteEvent")
            event.Name = name
            event.Parent = remotesFolder
        end
        Remotes[name] = event
    end
end

function NetworkService.FireClient(player: Player, remoteName: string, ...: any)
    local remote = Remotes[remoteName]
    if remote then
        remote:FireClient(player, ...)
    end
end

return NetworkService
