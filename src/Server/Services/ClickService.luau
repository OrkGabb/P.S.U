--!strict
--@author OrkGabb
--@module ClickService.luau
--@version 1.0
-- src/Server/Services/ClickService.lua
-- Refactored: Clicker Game focused (Macro-tolerant Debounce and CPU Optimization)

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DataService = require(ServerScriptService.Server.Services.DataService)
local LootTable = require(ReplicatedStorage.Shared.Modules.LootTable)
local UpgradeRegistry = require(ReplicatedStorage.Shared.Modules.UpgradeRegistry)
local LevelService
local QuestService 
local ItemService -- Injected in Start() to prevent require overload
local MonetizationService

local ClickService = {}
local clickCounterMap: {[Player]: number} = {}
local bucketMap: {[Player]: {tokens: number, lastUpdate: number}} = {}
local MAX_BURST = 30
local REFILL_RATE = 20 -- 20 CPS allowed

local function OnClickReward(player: Player, batch: number?)
    local now = os.clock()
    local bucket = bucketMap[player] or {tokens = MAX_BURST, lastUpdate = now}
    
    local elapsed = now - bucket.lastUpdate
    bucket.tokens = math.min(MAX_BURST, bucket.tokens + elapsed * REFILL_RATE)
    bucket.lastUpdate = now
    
    local requestedClicks = type(batch) == "number" and math.clamp(math.floor(batch), 1, MAX_BURST) or 1
    
    if bucket.tokens < 1 then
        bucketMap[player] = bucket
        return 
    end
    
    local clickCount = math.min(requestedClicks, math.floor(bucket.tokens))
    bucket.tokens -= clickCount
    bucketMap[player] = bucket

    local profile = DataService.Profiles[player]
    if not profile or not profile.Data then return end

    -- Initialize abstract structures if missing
    if not profile.Data.Currencies then
        profile.Data.Currencies = { ["Primary"] = 0, ["Secondary"] = 0, ["Premium"] = 0 }
    end
    if not profile.Data.Progression then
        profile.Data.Progression = { ["EarningPower"] = 1, ["Level"] = 1, ["Experience"] = 0 }
    end

    local earningPower = profile.Data.Progression.EarningPower or 1

    local equippedKey  = profile.Data.Aura or ""
    local equippedData = LootTable.GetAuraData(equippedKey)
    local auraCoinMult = equippedData and equippedData.coinMult or 0
    local itemExpMult  = equippedData and equippedData.expMult  or 0
    
    local volatileExpBoost = ItemService:GetVolatileMultiplier(player, "EXP") - 1
    local volatileStrBoost = ItemService:GetVolatileMultiplier(player, "Strength") - 1
    
    local isVIP = (profile.Data.VIPExpiry or 0) > os.time()
    local vipMult = isVIP and 1.25 or 1
    
    -- We assume rebirths is still an abstract progression stat, but we can store it in Progression
    local rebirthMult = 1 + (profile.Data.Progression.Rebirths or 0)

    -- Dynamic Click Power
    local rawClickPower = (earningPower + auraCoinMult) * (1 + volatileStrBoost) * vipMult * rebirthMult
    local coinGain = math.floor(math.max(1, rawClickPower)) * clickCount
    
    -- EXP uses its own multiplier format logic
    local rawExpPower = (earningPower + itemExpMult) * (1 + volatileExpBoost) * rebirthMult
    local expGain = math.floor(math.max(1, rawExpPower)) * clickCount

    -- Assign to abstract fields
    profile.Data.Currencies.Primary += coinGain

    local ls = player:FindFirstChild("leaderstats")
    if ls then
        -- Attempt to sync to leaderstats if a matching key exists
        local primaryName = "Primary"
        local configPrimary = FeatureResolver.GetConfigField("Currencies", "PrimaryName", nil)
        if configPrimary then primaryName = configPrimary end

        local primaryValObj = ls:FindFirstChild(primaryName) or ls:FindFirstChild("Coins")
        if primaryValObj and (primaryValObj:IsA("IntValue") or primaryValObj:IsA("NumberValue")) then
            primaryValObj.Value = profile.Data.Currencies.Primary
        end
    end

    if LevelService then
        LevelService.AddExp(player, expGain)
    end
    
    if QuestService then QuestService.AddProgress(player, "Click", clickCount) end
end

function ClickService.Init(): ()
    Players.PlayerRemoving:Connect(function(player)
        bucketMap[player] = nil
        clickCounterMap[player] = nil
    end)
end

function ClickService.Start(): ()
    LevelService = require(ServerScriptService.Server.Services.LevelService)
    QuestService = require(ServerScriptService.Server.Services.QuestService)
    ItemService = require(ServerScriptService.Server.Services.ItemService)
    MonetizationService = require(ServerScriptService.Server.Services.MonetizationService)
    
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local clickReward = remotes:WaitForChild("ClickReward") :: RemoteEvent
    clickReward.OnServerEvent:Connect(OnClickReward)
end

return ClickService
