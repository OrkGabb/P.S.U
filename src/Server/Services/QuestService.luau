--!strict
--@author OrkGabb
--@module QuestService.luau
--@version 1.0
-- src/Server/Services/QuestService.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataService = require(ServerScriptService.Server.Services.DataService)
local LevelService = require(ServerScriptService.Server.Services.LevelService)
local QuestRegistry = require(ReplicatedStorage.Shared.Modules.QuestRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local QuestService = {}
local MonetizationService

local function ValidateQuestData(profile: any)
    if type(profile.Data.Progression) ~= "table" then
        profile.Data.Progression = {}
    end
    if type(profile.Data.Progression.Quests) ~= "table" then
        profile.Data.Progression.Quests = { Progress = {}, Claimed = {}, LastReset = 0, LastWeeklyReset = 0 }
    end
    if type(profile.Data.Progression.Quests.Progress) ~= "table" then 
        profile.Data.Progression.Quests.Progress = {} 
    end
    if type(profile.Data.Progression.Quests.Claimed) ~= "table" then 
        profile.Data.Progression.Quests.Claimed = {} 
    end
end

function QuestService.AddProgress(player: Player, actionType: string, amount: number)
    if not FeatureResolver.IsCategoryActive("RPG_Adventure") then return end
    local profile = DataService.Profiles[player]
    if not profile then return end

    ValidateQuestData(profile)

    local updated = false
    for _, quest in ipairs(QuestRegistry.Quests) do
        if quest.ActionType == actionType and not profile.Data.Progression.Quests.Claimed[quest.Id] then
            local current = profile.Data.Progression.Quests.Progress[quest.Id] or 0
            if current < quest.Target then
                profile.Data.Progression.Quests.Progress[quest.Id] = math.min(current + amount, quest.Target)
                updated = true
            end
        end
    end

    if updated then
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local event = remotes and remotes:FindFirstChild("UpdateQuests") :: RemoteEvent
        if event then event:FireClient(player, profile.Data.Progression.Quests) end
    end
end

local function OnClaimRequest(player: Player, questId: string)
    if not FeatureResolver.IsCategoryActive("RPG_Adventure") then return end
    local profile = DataService.Profiles[player]
    if not profile then return end

    ValidateQuestData(profile)

    if profile.Data.Progression.Quests.Claimed[questId] then return end

    local questDef = nil
    for _, q in ipairs(QuestRegistry.Quests) do
        if q.Id == questId then questDef = q break end
    end
    if not questDef then return end

    local current = profile.Data.Progression.Quests.Progress[questId] or 0
    if current >= questDef.Target then
        profile.Data.Progression.Quests.Claimed[questId] = true
        
        local mult = QuestRegistry.GetMultiplier(profile.Data.Level or 1, profile.Data.Rebirths or 0)
        local finalCoins = questDef.BaseCoins * mult
        local finalEXP = questDef.BaseEXP * mult
        
        profile.Data.Coins += finalCoins
        profile.Data.TotalCoins += finalCoins
        
        local ls = player:FindFirstChild("leaderstats")
        if ls and ls:FindFirstChild("Coins") then
            ls.Coins.Value = profile.Data.Coins
        end
        
        LevelService.AddExp(player, finalEXP)

        -- Sync full state to update HUD on client
        DataService:SyncFullState(player)

        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local event = remotes and remotes:FindFirstChild("UpdateQuests") :: RemoteEvent
        if event then event:FireClient(player, profile.Data.Progression.Quests) end
    end
end

function QuestService.Init(): ()
    if not FeatureResolver.IsCategoryActive("RPG_Adventure") then return end
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    if not remotes:FindFirstChild("ClaimQuestRequest") then
        local event = Instance.new("RemoteEvent")
        event.Name = "ClaimQuestRequest"
        event.Parent = remotes
    end
    if not remotes:FindFirstChild("UpdateQuests") then
        local event = Instance.new("RemoteEvent")
        event.Name = "UpdateQuests"
        event.Parent = remotes
    end
end

function QuestService.Start(): ()
    if not FeatureResolver.IsCategoryActive("RPG_Adventure") then return end
    MonetizationService = require(ServerScriptService.Server.Services.MonetizationService)
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local event = remotes:WaitForChild("ClaimQuestRequest") :: RemoteEvent
    event.OnServerEvent:Connect(OnClaimRequest)
end

return QuestService
