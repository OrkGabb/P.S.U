--!strict
--@author OrkGabb
--@module DataService.luau
--@version 1.0
-- src/Server/Services/DataService.lua

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureResolver: any = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("FeatureResolver"))
local ProfileService: any = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("ProfileService"))

local DATA_STORE_NAME: string = FeatureResolver.GetConfigField("Data", "StoreName", "PSU_Production_01")

local ProfileTemplate: { [string]: any } = {
    Currencies = {
        ["Primary"] = 0,
        ["Secondary"] = 0,
        ["Premium"] = 0
    },
    Inventory = {
        ["Equipment"] = {},
        ["Cosmetics"] = {},
        ["Consumables"] = {}
    },
    Progression = {
        ["Level"] = 1,
        ["Experience"] = 0,
        ["Milestones"] = {},
        ["UnlockedZones"] = {}
    },
    Upgrades = {},
    Settings = {}
}

local ProfileStore: any = ProfileService.GetProfileStore(
    DATA_STORE_NAME,
    ProfileTemplate
)

local DataService = {}
DataService.Profiles = {} :: { [Player]: any }

function DataService:Init(): ()
    print("[INFO] DataService Init: Abstract schema loaded.")
    local remotes: Folder? = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
    if not remotes then
        local newRemotes = Instance.new("Folder")
        newRemotes.Name = "Remotes"
        newRemotes.Parent = ReplicatedStorage
        remotes = newRemotes
    end
    local updateData = (remotes :: Folder):FindFirstChild("UpdateProfileData") :: RemoteEvent?
    if not updateData then
        local newUpdateData = Instance.new("RemoteEvent")
        newUpdateData.Name = "UpdateProfileData"
        newUpdateData.Parent = remotes
    end
end

function DataService:Start(): ()
    print("[INFO] DataService Start: Listening for player connections.")
    
    local playersList: {Player} = Players:GetPlayers()
    for _, player: Player in ipairs(playersList) do
        task.spawn(function()
            DataService:LoadProfile(player)
        end)
    end
    
    Players.PlayerAdded:Connect(function(player: Player)
        DataService:LoadProfile(player)
    end)
    
    Players.PlayerRemoving:Connect(function(player: Player)
        DataService:ReleaseProfile(player)
    end)
end

function DataService:LoadProfile(player: Player): ()
    if not ProfileStore then
        warn(string.format("[WARN] DataService: ProfileStore is nil. Load rejected for Player %d", player.UserId))
        return
    end

    local profileKey: string = "Player_" .. tostring(player.UserId)
    local profile: any = ProfileStore:LoadProfileAsync(profileKey)
    
    if profile ~= nil then
        profile:AddUserId(player.UserId)
        profile:Reconcile()
        profile:ListenToRelease(function()
            DataService.Profiles[player] = nil
            player:Kick("Profile session released.")
        end)
        
        if player:IsDescendantOf(Players) == true then
            DataService.Profiles[player] = profile
            print(string.format("[PASS] DataService: Profile loaded for Player %d", player.UserId))
            DataService:SyncFullState(player)
        else
            profile:Release()
        end
    else
        player:Kick("Data retrieval failed.")
        print(string.format("[FAIL] DataService: Profile load rejected for Player %d", player.UserId))
    end
end

function DataService:ReleaseProfile(player: Player): ()
    local profile: any = DataService.Profiles[player]
    if profile ~= nil then
        profile:Release()
        print(string.format("[INFO] DataService: Profile released for Player %d", player.UserId))
    end
end

function DataService:GetProfileData(player: Player): { [string]: any }?
    local profile: any = DataService.Profiles[player]
    if profile ~= nil then
        return profile.Data
    end
    return nil
end

function DataService:SyncFullState(player: Player): ()
    local profile = DataService.Profiles[player]
    if not profile then return end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
    local updateData = remotes and remotes:FindFirstChild("UpdateProfileData") :: RemoteEvent?
    if updateData then
        updateData:FireClient(player, profile.Data)
    end
end

return DataService
