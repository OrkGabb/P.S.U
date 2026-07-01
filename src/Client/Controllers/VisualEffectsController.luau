--!strict
--@author OrkGabb
--@module VisualEffectsController.luau
--@version 1.0
-- src/Client/Controllers/VisualEffectsController.lua
-- Client-side Visual Effects Controller. Renders particle and model effects on character rigs.
-- Supports effects mounted on "Dummy Rigs" (e.g. CharacterEffect54).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local LootTableModule   = require(ReplicatedStorage.Shared.Modules.LootTable)
local FeatureResolver   = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local VisualEffectsController = {}
local PlayerEffects: {[Player]: string} = {}

-- Maps the members of the R6 dummy rig to the corresponding parts of the player's character (R15/R6)
local RIG_MAP: {[string]: {string}} = {
    ["Torso"]     = {"UpperTorso", "LowerTorso", "Torso"},
    ["Left Arm"]  = {"LeftUpperArm", "LeftLowerArm", "LeftHand", "Left Arm"},
    ["Right Arm"] = {"RightUpperArm", "RightLowerArm", "RightHand", "Right Arm"},
    ["Left Leg"]  = {"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "Left Leg"},
    ["Right Leg"] = {"RightUpperLeg", "RightLowerLeg", "RightFoot", "Right Leg"},
    ["Head"]      = {"Head"}
}

local function ApplyTinting(target: Instance, color: Color3): ()
    if target:IsA("BasePart") then
        local part = target :: BasePart
        if part.Material == Enum.Material.ForceField or part.Material == Enum.Material.Neon then
            part.Color = color
        end
    elseif target:IsA("ParticleEmitter") or target:IsA("Trail") or target:IsA("Beam") then
        (target :: any).Color = ColorSequence.new(color)
    elseif target:IsA("Light") then
        (target :: Light).Color = color
    end

    for _, obj in ipairs(target:GetDescendants()) do
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
            (obj :: any).Color = ColorSequence.new(color)
        elseif obj:IsA("Light") then
            (obj :: Light).Color = color
        elseif obj:IsA("BasePart") then
            local part = obj :: BasePart
            if part.Material == Enum.Material.ForceField or part.Material == Enum.Material.Neon then
                part.Color = color
            end
        end
    end
end

-- Finds the correct body part in the player's character based on the RIG_MAP.
local function GetPlayerBodyPart(character: Model, limbName: string): BasePart?
    local fallbacks: {string}? = RIG_MAP[limbName]
    if fallbacks then
        for _, fb in ipairs(fallbacks) do
            local part = character:FindFirstChild(fb)
            if part and part:IsA("BasePart") then return part end
        end
    end
    local fallbackLimb = character:FindFirstChild(limbName)
    return if fallbackLimb and fallbackLimb:IsA("BasePart") then fallbackLimb else nil
end

function VisualEffectsController.PlayGenericFallbackEffect(character: Model)
    local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then return end
    
    local fallback = Instance.new("Part")
    fallback.Name = "VFXFallback"
    fallback.Shape = Enum.PartType.Cylinder
    fallback.Size = Vector3.new(0.5, 4, 4)
    fallback.Color = Color3.fromRGB(0, 255, 0)
    fallback.Material = Enum.Material.Neon
    fallback.Anchored = false
    fallback.CanCollide = false
    fallback.Massless = true
    fallback:SetAttribute("IsLiteEffect", true)
    
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = fallback
    weld.Part1 = hrp
    weld.Parent = fallback
    
    fallback.CFrame = hrp.CFrame * CFrame.Angles(0, 0, math.pi / 2)
    fallback.Parent = character
end

function VisualEffectsController.ClearEffects(character: Model): ()
    if not character then return end
    for _, desc in ipairs(character:GetDescendants()) do
        if desc:GetAttribute("IsLiteEffect") then
            desc:Destroy()
        end
    end
end

function VisualEffectsController.ApplyVisualEffects(player: Player, equippedKey: string): ()
    if not player or not equippedKey then return end

    local character: Model? = player.Character
    if not character then return end

    VisualEffectsController.ClearEffects(character)

    if equippedKey == "None" or equippedKey == "" then
        PlayerEffects[player] = "None"
        return
    end

    PlayerEffects[player] = equippedKey

    local itemData = LootTableModule.GetAuraData(equippedKey)
    local finalColor: Color3 = if itemData and itemData.color then itemData.color else Color3.fromRGB(255, 255, 255)

    -- Reference ReplicatedStorage.Shared.GlobalAssets.VFXAssets directly
    local sharedFolder: Folder? = ReplicatedStorage:WaitForChild("Shared", 0.1) :: Folder?
    local globalAssets: Folder? = sharedFolder:WaitForChild("GlobalAssets", 0.1) :: Folder?
    local vfxAssets: Folder? = globalAssets:WaitForChild("VFXAssets", 0.1) :: Folder?
    if not vfxAssets then return end

    local targetFolder: Instance? = nil
    local baseLow: string = string.lower(equippedKey)
    
    -- Find the folder or model matching the visual effect's name
    for _, child in ipairs(vfxAssets:GetChildren()) do
        if string.lower(child.Name) == baseLow then
            targetFolder = child
            break
        end
    end

    if not targetFolder then 
        VisualEffectsController.PlayGenericFallbackEffect(character)
        return 
    end

    -- If the asset is a Model (Dummy Rig), traverse its limbs
    for _, sourceLimb in ipairs(targetFolder:GetChildren()) do
        -- Skip the Humanoid and BodyColors of the dummy rig
        if sourceLimb:IsA("Humanoid") or sourceLimb:IsA("BodyColors") then continue end
        
        -- Look for the equivalent limb on the actual player's character
        local playerLimb: BasePart? = GetPlayerBodyPart(character, sourceLimb.Name)
        
        -- If not found (e.g. ground effects), attach to the HumanoidRootPart
        if not playerLimb then
            playerLimb = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        end

        if playerLimb then
            -- Clone and attach visual effects from the dummy limb to the player limb
            for _, vfxAsset in ipairs(sourceLimb:GetChildren()) do
                -- Only clone VFX instances, skip default parts of the dummy head
                if vfxAsset:IsA("Attachment") or vfxAsset:IsA("ParticleEmitter") or vfxAsset:IsA("Trail") or vfxAsset:IsA("Beam") then
                    local clone = vfxAsset:Clone()
                    clone:SetAttribute("IsLiteEffect", true)
                    ApplyTinting(clone, finalColor)
                    clone.Parent = playerLimb
                elseif vfxAsset:IsA("BasePart") and vfxAsset.Name ~= "face" then
                    -- If it's a physical accessory (like a crown/ring), clone and weld it
                    local clone = vfxAsset:Clone() :: BasePart
                    clone:SetAttribute("IsLiteEffect", true)
                    clone.CanCollide = false
                    clone.CanQuery = false
                    clone.CanTouch = false
                    clone.Massless = true
                    clone.Anchored = false
                    clone.CFrame = playerLimb.CFrame
                    ApplyTinting(clone, finalColor)
                    clone.Parent = character

                    local weld = Instance.new("WeldConstraint")
                    weld.Part0 = clone
                    weld.Part1 = playerLimb
                    weld.Parent = weld.Part0
                end
            end
        end
    end
end

function VisualEffectsController.PlayVFX(effectId: string, character: Model): ()
    local shared = ReplicatedStorage:WaitForChild("Shared", 0.1) :: Folder?
    if not shared then return nil end
    local globalAssets = shared:WaitForChild("GlobalAssets", 0.1) :: Folder?
    if not globalAssets then return nil end
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

        -- If a folder name matches a limb of the R15 character model
        local targetLimb = character:FindFirstChild(limbFolder.Name) :: BasePart?
        if not targetLimb or not targetLimb:IsA("BasePart") then continue end

        -- Clone all its children (ParticleEmitters, Attachments, Beams, Trails, Lights) directly into the corresponding limb
        for _, asset in ipairs(limbFolder:GetChildren()) do
            if asset:IsA("ParticleEmitter") or asset:IsA("Attachment") or asset:IsA("Beam") or asset:IsA("Trail") or asset:IsA("Light") then
                local clone = asset:Clone()
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

    -- Apply Debris:AddItem() dynamically calculated by checking the maximum Lifetime property found across the cloned emitters
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

    local emitVFX = remotes:WaitForChild("EmitVFX", 0.1) :: RemoteEvent?
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
                VisualEffectsController.PlayVFX(actualEffectId, character)
            end
        end)
    end

    local syncVisualEffects = remotes:WaitForChild("SyncVisualEffects", 0.1) :: RemoteEvent?
    if syncVisualEffects then
        syncVisualEffects.OnClientEvent:Connect(function(targetPlayer: any, equippedKey: string)
            local playerInst: Player? = nil
            if typeof(targetPlayer) == "string" then
                playerInst = Players:FindFirstChild(targetPlayer) :: Player?
            elseif typeof(targetPlayer) == "Instance" and targetPlayer:IsA("Player") then
                playerInst = targetPlayer :: Player
            end
                
            if playerInst then
                VisualEffectsController.ApplyVisualEffects(playerInst, equippedKey)
            end
        end)
    end

    Players.PlayerRemoving:Connect(function(p: Player)
        PlayerEffects[p] = nil
    end)

    local function onCharacterAdded(char: Model): ()
        local p: Player? = Players:GetPlayerFromCharacter(char)
        if p and PlayerEffects[p] and PlayerEffects[p] ~= "None" then
            task.delay(0.5, function()
                if char.Parent then
                    VisualEffectsController.ApplyVisualEffects(p :: Player, PlayerEffects[p :: Player])
                end
            end)
        end
    end

    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then onCharacterAdded(p.Character) end
        p.CharacterAdded:Connect(onCharacterAdded)
    end

    Players.PlayerAdded:Connect(function(p: Player)
        p.CharacterAdded:Connect(onCharacterAdded)
    end)
end

function VisualEffectsController.Start(): () end

function VisualEffectsController.DrawGunTracer(origin: Vector3, direction: Vector3)
    local distance = direction.Magnitude
    local tracer = Instance.new("Part")
    tracer.Name = "GunTracer"
    tracer.Shape = Enum.PartType.Cylinder
    tracer.Size = Vector3.new(0.2, distance, 0.2)
    tracer.Color = Color3.fromRGB(255, 255, 0) -- Neon-yellow
    tracer.Material = Enum.Material.Neon
    tracer.Anchored = true
    tracer.CanCollide = false
    tracer.CanQuery = false
    tracer.CFrame = CFrame.lookAt(origin, origin + direction) * CFrame.new(0, 0, -distance / 2) * CFrame.Angles(math.pi / 2, 0, 0)
    tracer.Parent = workspace
    
    task.delay(0.05, function()
        if tracer and tracer.Parent then
            tracer:Destroy()
        end
    end)
end

function VisualEffectsController.SpawnProceduralPet(petName: string): Model
    local model = Instance.new("Model")
    model.Name = "ProceduralPet"
    
    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.Shape = Enum.PartType.Ball
    root.Size = Vector3.new(2, 2, 2)
    root.Color = Color3.fromRGB(0, 200, 255)
    root.Material = Enum.Material.Neon
    root.Anchored = false
    root.CanCollide = false
    root.Parent = model
    model.PrimaryPart = root
    
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 100, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = root
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = petName or "Unknown Pet"
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.Parent = billboard
    
    return model
end

return VisualEffectsController
