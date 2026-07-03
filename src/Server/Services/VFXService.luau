--!strict
--@author OrkGabb
--@module VFXService.luau
--@version 1.0
-- src/Server/Services/VFXService.luau
-- Server-side Visual Effects Service. Emits lightweight, compressed structural replication data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local VFXService = {}

function VFXService.Init(): ()
    -- VFXService Init
end

function VFXService.Start(): ()
    -- VFXService Start
end

function VFXService.EmitVFX(player: Player?, effectId: string, origin: any, target: any)
    if not FeatureResolver.IsCategoryActive("VFX") then return end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end
    
    local emitVFXEvent = remotes:FindFirstChild(RemoteNames.EmitVFX) :: RemoteEvent?
    if not emitVFXEvent then return end

    local data = {
        EffectID = effectId,
        Origin = origin,
        Target = target,
    }

    if player then
        emitVFXEvent:FireClient(player, data)
    else
        emitVFXEvent:FireAllClients(data)
    end
end

return VFXService
