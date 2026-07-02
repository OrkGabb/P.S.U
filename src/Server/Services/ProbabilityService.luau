--!strict
--@author OrkGabb
--@module ProbabilityService.luau
--@version 1.0
-- src/Server/Services/ProbabilityService.lua
-- Refactored for the new core loop: Simple, Fast, UI-focused and without VFX.
-- Integration with MonetizationService (Auto-Roll Gamepass).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local LootTableModule = require(ReplicatedStorage.Shared.Modules.LootTable)
local DataService = require(ServerScriptService.Server.Services.DataService)
local NetworkService = require(ServerScriptService.Server.Services.NetworkService)
local UpgradeRegistry = require(ReplicatedStorage.Shared.Modules.UpgradeRegistry)

-- Services injected in Start() to prevent circular dependencies and optimize loops
local QuestService
local ItemService
local MonetizationService

local ProbabilityService = {}
local engines: {[string]: any} = {}
local rollCooldowns: {[Player]: number} = {}

local BASE_ROLL_COOLDOWN = 3.5  -- Base roll cooldown increased to 3.5s for monetization baseline
local HARD_PITY_LIMIT = 100

type AutoRollState = { IsActive: boolean, BiomeId: string }
local autoRollPlayers: {[Player]: AutoRollState} = {}

local function ProcessRoll(player: Player, _biomeId: string, spinId: number?)
    local profile = DataService.Profiles[player]
    if not profile then return end

    local speedPotionMult = ItemService:GetVolatileMultiplier(player, "Speed")
    local speedMasteryLvl = (profile.Data.Upgrades and profile.Data.Upgrades["SpeedMastery"]) or 0
    local speedMasteryBonus = speedMasteryLvl * (UpgradeRegistry.Defs["SpeedMastery"] and UpgradeRegistry.Defs["SpeedMastery"].Increment or 0)
    local speedMult = speedPotionMult + speedMasteryBonus 
    
    local hasDoubleSpeed = MonetizationService and MonetizationService.HasGamepass(player, "DoubleSpeed")
    -- [MONETIZATION INJECTION]: Apply double speed buff if player owns the Gamepass
    if hasDoubleSpeed then
        speedMult = speedMult * 2
    end
    
    speedMult = math.max(speedMult, 0.1)
    local currentCooldown = BASE_ROLL_COOLDOWN / speedMult

    -- [BALANCE FIX]: Clamp free players to never reach 1.5s or lower (Target ~1.75s floor)
    if not hasDoubleSpeed then
        currentCooldown = math.max(currentCooldown, 1.75)
    end

    local now = os.clock()
    -- Grace period of 0.3s to prevent the server from rejecting legitimate client requests
    if (rollCooldowns[player] or 0) + currentCooldown - 0.3 > now then return end
    rollCooldowns[player] = now

    local biomeId = profile.Data.CurrentBiome or "Default"
    
    if not profile.Data.UnlockedBiomes or not profile.Data.UnlockedBiomes[biomeId] then
        warn("[ProbabilityService] Player", player.Name, "attempted roll in locked biome:", biomeId)
        biomeId = "Default"
        profile.Data.CurrentBiome = "Default"
    end

    local engine = engines[biomeId]
    if not engine then
        rollCooldowns[player] = 0
        return
    end

    local biomeDef = LootTableModule.Biomes[biomeId]
    if not biomeDef then
        rollCooldowns[player] = 0
        return
    end

    if profile.Data.Coins < biomeDef.Cost or profile.Data.Level < (biomeDef.LevelReq or 1) then
        rollCooldowns[player] = 0
        if autoRollPlayers[player] and autoRollPlayers[player].IsActive then
            autoRollPlayers[player].IsActive = false
            ReplicatedStorage.Remotes.ToggleAutoRoll:FireClient(player, false)
        end
        return
    end

    profile.Data.Coins -= biomeDef.Cost
    if player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Coins") then
        player.leaderstats.Coins.Value = profile.Data.Coins
    end

    local rolled: LootTableModule.LootEntry
    local isPity = false

    local baseLuck = 1
    local luckMasteryLvl = (profile.Data.Upgrades and profile.Data.Upgrades["LuckMastery"]) or 0
    local luckBonus = luckMasteryLvl * (UpgradeRegistry.Defs["LuckMastery"] and UpgradeRegistry.Defs["LuckMastery"].Increment or 0)
    local luckMult = ((profile.Data.LuckMultiplier or 1) * baseLuck) + luckBonus

    -- [MONETIZATION INJECTION]: Apply double luck buff if player owns the Gamepass
    if MonetizationService and MonetizationService.HasGamepass(player, "DoubleLuck") then
        luckMult = luckMult * 2
    end

    if profile.Data.PityCounter >= HARD_PITY_LIMIT then
        rolled = engine:Roll(luckMult * 100)
        profile.Data.PityCounter = 0
        isPity = true
    else
        rolled = engine:Roll(luckMult)
        if rolled.weight <= 20 then 
            profile.Data.PityCounter = 0 
        else 
            profile.Data.PityCounter += 1 
        end
    end

    local finalItemKey = rolled.name

    if QuestService then
        QuestService.AddProgress(player, "Roll", 1)
        if rolled.rarityTag ~= "COMMON" then
            QuestService.AddProgress(player, "RollUncommon", 1)
        end
    end

    local isNewItem = not profile.Data.Collection or not profile.Data.Collection[finalItemKey] or (profile.Data.Collection[finalItemKey] or 0) <= 0

    DataService:AddAura(player, finalItemKey, 1)

    if not isNewItem then
        DataService:RecycleMaxedAura(player, finalItemKey)
    end

    if profile.Data.Aura == "" or profile.Data.Aura == "None" then
        profile.Data.Aura = finalItemKey
        profile.Data.ManualEquip = false
        if player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Aura") then
            player.leaderstats.Aura.Value = rolled.displayName or rolled.name
        end
        DataService:SyncFullState(player)
    else
        if isNewItem then
            profile.Data.Aura = finalItemKey
            profile.Data.ManualEquip = false
            if player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Aura") then
                player.leaderstats.Aura.Value = rolled.displayName or rolled.name
            end
            DataService:SyncFullState(player)
        elseif not profile.Data.ManualEquip then
            local currentKey = profile.Data.Aura
            local cItemData = LootTableModule.GetAuraData(currentKey)
            local cWeight = cItemData and cItemData.weight or math.huge
            local rWeight = rolled.weight

            if rWeight < cWeight then
                profile.Data.Aura = finalItemKey
                if player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Aura") then
                    player.leaderstats.Aura.Value = rolled.displayName or rolled.name
                end
                DataService:SyncFullState(player)
            end
        end
    end

    NetworkService.FireClient(player, "UpdateCollection", profile.Data.Collection, {})
    NetworkService.FireClient(player, "UpdateClient", finalItemKey, profile.Data.Aura, biomeId, spinId)
end

function ProbabilityService.Init(): () 
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    if not remotes:FindFirstChild("RollRequest") then
        Instance.new("RemoteEvent", remotes).Name = "RollRequest"
    end
    if not remotes:FindFirstChild("ToggleAutoRoll") then
        Instance.new("RemoteEvent", remotes).Name = "ToggleAutoRoll"
    end
    if not remotes:FindFirstChild("ForceDisableAutoRoll") then
        Instance.new("RemoteEvent", remotes).Name = "ForceDisableAutoRoll"
    end
end

function ProbabilityService.Start(): ()
    QuestService = require(ServerScriptService.Server.Services.QuestService)
    ItemService = require(ServerScriptService.Server.Services.ItemService)
    MonetizationService = require(ServerScriptService.Server.Services.MonetizationService)
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    
    for id, biome in pairs(LootTableModule.Biomes) do
        engines[id] = LootTableModule.new(biome.Auras)
    end
    
    remotes:WaitForChild("RollRequest").OnServerEvent:Connect(function(player: Player, clientBiome: string, spinId: number?)
        local now = os.clock()
        local profile = DataService.Profiles[player]
        if not profile then return end

        local speedPotionMult = ItemService:GetVolatileMultiplier(player, "Speed")
        local speedMasteryLvl = (profile.Data.Upgrades and profile.Data.Upgrades["SpeedMastery"]) or 0
        local speedMasteryBonus = speedMasteryLvl * (UpgradeRegistry.Defs["SpeedMastery"] and UpgradeRegistry.Defs["SpeedMastery"].Increment or 0)
        local speedMult = speedPotionMult + speedMasteryBonus

        local hasDoubleSpeed = MonetizationService and MonetizationService.HasGamepass(player, "DoubleSpeed")
        if hasDoubleSpeed then
            speedMult = speedMult * 2
        end
        speedMult = math.max(speedMult, 0.1)
        local currentCooldown = BASE_ROLL_COOLDOWN / speedMult

        if not hasDoubleSpeed then
            currentCooldown = math.max(currentCooldown, 1.75)
        end
        
        if (rollCooldowns[player] or 0) + currentCooldown - 0.3 > now then return end
        
        if autoRollPlayers[player] and autoRollPlayers[player].IsActive then return end

        local currentBiome = profile and profile.Data.CurrentBiome or "Default"
        ProcessRoll(player, currentBiome, spinId)
    end)
    
    remotes:WaitForChild("ToggleAutoRoll").OnServerEvent:Connect(function(player: Player, isActive: boolean)
        local now = os.clock()
        local lastToggle = player:GetAttribute("LastAutoToggle") or 0
        if now - lastToggle < 1.0 then return end
        player:SetAttribute("LastAutoToggle", now)

        if isActive then
            -- [MONETIZATION: AUTO-ROLL PAYWALL]
            if MonetizationService and not MonetizationService.HasGamepass(player, "AutoRoll") then
                -- Player does not own the Gamepass. Alert client UI to disable button.
                local forceDisableEvt = remotes:FindFirstChild("ForceDisableAutoRoll")
                if forceDisableEvt then
                    (forceDisableEvt :: RemoteEvent):FireClient(player)
                end
                -- Ensure state remains false
                if autoRollPlayers[player] then autoRollPlayers[player].IsActive = false end
                return
            end

            if not autoRollPlayers[player] then autoRollPlayers[player] = { IsActive = false, BiomeId = "Default" } end
            if autoRollPlayers[player].IsActive then return end 
            
            autoRollPlayers[player].IsActive = true
            task.spawn(function()
                while autoRollPlayers[player] and autoRollPlayers[player].IsActive do
                    local profile = DataService.Profiles[player]
                    if not profile then return end

                    local speedPotionMult = ItemService:GetVolatileMultiplier(player, "Speed")
                    local speedMasteryLvl = (profile.Data.Upgrades and profile.Data.Upgrades["SpeedMastery"]) or 0
                    local speedMasteryBonus = speedMasteryLvl * (UpgradeRegistry.Defs["SpeedMastery"] and UpgradeRegistry.Defs["SpeedMastery"].Increment or 0)
                    local speedMult = speedPotionMult + speedMasteryBonus

                    local hasDoubleSpeed = MonetizationService and MonetizationService.HasGamepass(player, "DoubleSpeed")
                    if hasDoubleSpeed then
                        speedMult = speedMult * 2
                    end
                    speedMult = math.max(speedMult, 0.1)
                    local currentCooldown = BASE_ROLL_COOLDOWN / speedMult
                    
                    if not hasDoubleSpeed then
                        currentCooldown = math.max(currentCooldown, 1.75)
                    end
                    
                    if (rollCooldowns[player] or 0) + currentCooldown <= os.clock() then
                        local currentBiome = profile and profile.Data.CurrentBiome or "Default"
                        ProcessRoll(player, currentBiome, nil)
                    end
                    task.wait(currentCooldown)
                end
            end)
        else
            if autoRollPlayers[player] then autoRollPlayers[player].IsActive = false end
        end
    end)

    Players.PlayerRemoving:Connect(function(p) 
        rollCooldowns[p] = nil 
        autoRollPlayers[p] = nil
    end)
end

return ProbabilityService
