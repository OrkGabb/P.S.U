--!strict
-- @Author @OrkGabb
-- src/Client/Controllers/VisualEffectsController.luau
-- Generic one-shot VFX playback. VFXService (server) fires EmitVFX with an
-- effect id + target character; this controller clones the matching effect
-- folder's emitters into the character's limbs and lets Debris reap them.
--
-- Equipped-aura VFX is NOT handled here — see AuraVFXController, which owns
-- the persistent attachment-cloning pipeline for the Aura_Collector genre.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local Debris = game:GetService("Debris")

local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local VisualEffectsController = {}

function VisualEffectsController.PlayVFX(effectId: string, character: Model): ()
    local shared = ReplicatedStorage:WaitForChild("Shared", 0.1) :: Folder?
    if not shared then return end
    local globalAssets = shared:WaitForChild("GlobalAssets", 0.1) :: Folder?
    if not globalAssets then return end
    local vfxAssets = globalAssets:WaitForChild("VFXAssets", 0.1) :: Folder?
    if not vfxAssets then return end

    local effectFolder = vfxAssets:FindFirstChild(effectId)
    if not effectFolder then
        warn("[VisualEffectsController] Effect folder not found in VFXAssets: " .. effectId)
        return
    end

    local clonedObjects: {Instance} = {}
    local maxLifetime = 0.5

    -- Loop through the children folders inside that specific effect directory
    for _, limbFolder in ipairs(effectFolder:GetChildren()) do
        if not limbFolder:IsA("Folder") then continue end

        -- If a folder name matches a limb of the character model
        local targetLimb = character:FindFirstChild(limbFolder.Name) :: BasePart?
        if not targetLimb or not targetLimb:IsA("BasePart") then continue end

        -- Clone all its children (ParticleEmitters, Attachments, Beams, Trails, Lights) directly into the corresponding limb
        for _, asset in ipairs(limbFolder:GetChildren()) do
            if asset:IsA("ParticleEmitter") or asset:IsA("Attachment") or asset:IsA("Beam") or asset:IsA("Trail") or asset:IsA("Light") then
                local clone = asset:Clone() :: Instance
                clone.Parent = targetLimb
                table.insert(clonedObjects, clone)

                if asset:IsA("ParticleEmitter") then
                    local pe = asset :: ParticleEmitter
                    local currentMax = pe.Lifetime.Max
                    if currentMax > maxLifetime then
                        maxLifetime = currentMax
                    end
                end
            end
        end
    end

    -- Reap clones once the longest emitter lifetime has elapsed
    for _, clone in ipairs(clonedObjects) do
        Debris:AddItem(clone, maxLifetime + 0.5)
    end
end

function VisualEffectsController.Init(): ()
    if not FeatureResolver.IsCategoryActive("VFX") then
        return
    end

    local remotes = ReplicatedStorage:WaitForChild("Remotes", 0.1) :: Folder?
    if not remotes then return end

    local emitVFX = remotes:WaitForChild(RemoteNames.EmitVFX, 0.1) :: RemoteEvent?
    if emitVFX then
        emitVFX.OnClientEvent:Connect(function(effectId: any, targetCharacter: any)
            local character: Model? = nil
            local actualEffectId: string = ""

            if typeof(effectId) == "table" then
                actualEffectId = effectId.EffectID or ""
                local targetVal = effectId.Target or effectId.Origin
                if typeof(targetVal) == "Instance" and targetVal:IsA("Model") then
                    character = targetVal
                end
            elseif typeof(effectId) == "string" then
                actualEffectId = effectId
                if typeof(targetCharacter) == "Instance" and targetCharacter:IsA("Model") then
                    character = targetCharacter
                end
            end

            if actualEffectId ~= "" and character then
                VisualEffectsController.PlayVFX(actualEffectId, character :: Model)
            end
        end)
    end
end

function VisualEffectsController.Start(): () end

return VisualEffectsController
