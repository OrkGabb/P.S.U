--!strict
--@author OrkGabb
--@module QuestService.luau
--@version 1.0
-- src/Server/Services/QuestService.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local ServerScriptService = game:GetService("ServerScriptService")
local DataService = require(ServerScriptService.Server.Services.DataService)
local LevelService = require(ServerScriptService.Server.Services.LevelService)
local QuestRegistry = require(ReplicatedStorage.Shared.Modules.QuestRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)
local PSUTypes = require(ReplicatedStorage.Shared.Types.PSUTypes)

local QuestService = {}

-- Quests are a core capability: any genre that registers a quest set in
-- QuestRegistry gets the system; genres without quests skip it entirely.
local function QuestsAvailable(): boolean
    return #QuestRegistry.Quests > 0
end

-- Backfills the lazily-created quest sub-table and returns it typed — the
-- single any→typed boundary for quest persistence (same idiom as the genre
-- services' getAuraData/getPetData validators).
local function ValidateQuestData(profile: any): PSUTypes.QuestSaveData
    if type(profile.Data.Progression) ~= "table" then
        profile.Data.Progression = {}
    end
    local progression = profile.Data.Progression :: PSUTypes.ProgressionData
    if type(progression.Quests) ~= "table" then
        progression.Quests = { Progress = {}, Claimed = {}, LastReset = 0, LastWeeklyReset = 0 }
    end
    local quests = progression.Quests :: PSUTypes.QuestSaveData
    if type(quests.Progress) ~= "table" then
        quests.Progress = {}
    end
    if type(quests.Claimed) ~= "table" then
        quests.Claimed = {}
    end
    return quests
end

function QuestService.AddProgress(player: Player, actionType: string, amount: number)
    if not QuestsAvailable() then return end
    local profile = DataService.Profiles[player]
    if not profile then return end

    local quests = ValidateQuestData(profile)

    local updated = false
    for _, quest in ipairs(QuestRegistry.Quests) do
        if quest.ActionType == actionType and not quests.Claimed[quest.Id] then
            local current = quests.Progress[quest.Id] or 0
            if current < quest.Target then
                quests.Progress[quest.Id] = math.min(current + amount, quest.Target)
                updated = true
            end
        end
    end

    if updated then
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local event = remotes and remotes:FindFirstChild(RemoteNames.UpdateQuests) :: RemoteEvent
        if event then event:FireClient(player, quests) end
    end
end

local function OnClaimRequest(player: Player, questId: string)
    if not QuestsAvailable() then return end
    local profile = DataService.Profiles[player]
    if not profile then return end

    local quests = ValidateQuestData(profile)

    if quests.Claimed[questId] then return end

    local questDef = nil
    for _, q in ipairs(QuestRegistry.Quests) do
        if q.Id == questId then questDef = q; break end
    end
    if not questDef then return end

    local current = quests.Progress[questId] or 0
    if current >= questDef.Target then
        quests.Claimed[questId] = true
        
        local progression = if type(profile.Data.Progression) == "table"
            then profile.Data.Progression :: PSUTypes.ProgressionData
            else nil
        local level: number = if progression then (progression.Level or 1) else 1
        local mult = QuestRegistry.GetMultiplier(level, 0)
        local finalCoins = questDef.BaseCoins * mult
        local finalEXP = questDef.BaseEXP * mult

        -- Abstract schema: rewards land in Currencies.Primary
        if type(profile.Data.Currencies) ~= "table" then
            profile.Data.Currencies = { Primary = 0, Secondary = 0, Premium = 0 }
        end
        profile.Data.Currencies.Primary = (profile.Data.Currencies.Primary or 0) + finalCoins

        local ls = player:FindFirstChild("leaderstats")
        if ls then
            local primaryName: string = FeatureResolver.GetCurrencyNames().Primary
            local currencyVal = ls:FindFirstChild(primaryName)
            if currencyVal and (currencyVal:IsA("IntValue") or currencyVal:IsA("NumberValue")) then
                (currencyVal :: any).Value = profile.Data.Currencies.Primary
            end
        end

        LevelService.AddExp(player, finalEXP)

        -- Sync full state to update HUD on client
        DataService:SyncFullState(player)

        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local event = remotes and remotes:FindFirstChild(RemoteNames.UpdateQuests) :: RemoteEvent
        if event then event:FireClient(player, quests) end
    end
end

function QuestService.Init(): ()
    if not QuestsAvailable() then return end
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    if not remotes:FindFirstChild(RemoteNames.ClaimQuestRequest) then
        local event = Instance.new("RemoteEvent")
        event.Name = RemoteNames.ClaimQuestRequest
        event.Parent = remotes
    end
    if not remotes:FindFirstChild(RemoteNames.UpdateQuests) then
        local event = Instance.new("RemoteEvent")
        event.Name = RemoteNames.UpdateQuests
        event.Parent = remotes
    end
end

function QuestService.Start(): ()
    if not QuestsAvailable() then return end
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local event = remotes:WaitForChild(RemoteNames.ClaimQuestRequest) :: RemoteEvent
    event.OnServerEvent:Connect(function(player: Player, questId: any)
        if type(questId) == "string" then
            OnClaimRequest(player, questId)
        end
    end)
end

return QuestService
