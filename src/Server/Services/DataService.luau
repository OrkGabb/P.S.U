--!strict
--@author OrkGabb
--@module DataService.luau
--@version 1.0
-- src/Server/Services/DataService.lua

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local PSUTypes = require(ReplicatedStorage.Shared.Types.PSUTypes)

local FeatureResolver: any = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("FeatureResolver"))
local ProfileService: any = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("ProfileService"))

local DATA_STORE_NAME: string = FeatureResolver.GetConfigField("Data", "StoreName", "PSU_Production_01")

-- Abstract, genre-agnostic profile schema. Extend ADDITIVELY only: new fields
-- must default sensibly so ProfileService:Reconcile() upgrades old saves
-- without ever breaking existing data. Sub-table shapes are mirrored by the
-- profile-schema types in Shared/Types/PSUTypes.luau — keep both in sync.
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
    Settings = {},
    -- Named lifetime counters (TotalClicks, LifetimeEarned, GoldenClaims, …).
    -- Genre services own their keys; core only stores them.
    Stats = {},
    -- Per-genre persistent state, keyed by genre name (e.g. GenreData.Clicker_Farm).
    -- Keeps genre fields out of the core schema entirely.
    GenreData = {},
    -- Marketplace idempotency ledger (receipts + gamepass grants)
    PurchaseHistory = {}
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
    local updateData = (remotes :: Folder):FindFirstChild(RemoteNames.UpdateProfileData) :: RemoteEvent?
    if not updateData then
        local newUpdateData = Instance.new("RemoteEvent")
        newUpdateData.Name = RemoteNames.UpdateProfileData
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

-- Returns (creating if needed) the per-genre persistent sub-table for a player.
-- Genre services own the shape of their own sub-table.
function DataService:GetGenreData(player: Player, genreKey: string): { [string]: any }?
    local data: { [string]: any }? = DataService:GetProfileData(player)
    if data == nil then
        return nil
    end
    if type(data.GenreData) ~= "table" then
        data.GenreData = {}
    end
    local genreMap = data.GenreData :: PSUTypes.GenreDataMap
    if type(genreMap[genreKey]) ~= "table" then
        genreMap[genreKey] = {}
    end
    return genreMap[genreKey]
end

-- Adds a stackable item into the abstract inventory (Consumables slot).
function DataService:AddItem(player: Player, itemId: string, amount: number): boolean
    local data: { [string]: any }? = DataService:GetProfileData(player)
    if data == nil then
        return false
    end
    if type(data.Inventory) ~= "table" then
        data.Inventory = { Equipment = {}, Cosmetics = {}, Consumables = {} }
    end
    local inventory = data.Inventory :: PSUTypes.InventoryData
    if type(inventory.Consumables) ~= "table" then
        inventory.Consumables = {}
    end
    local current: number = inventory.Consumables[itemId] or 0
    inventory.Consumables[itemId] = current + amount
    return true
end

-- Removes a stackable item from the abstract inventory (Consumables slot).
-- Fails without side effects when the player owns fewer than `amount`.
function DataService:ConsumeItem(player: Player, itemId: string, amount: number): boolean
    local data: { [string]: any }? = DataService:GetProfileData(player)
    if data == nil or type(data.Inventory) ~= "table" or type(data.Inventory.Consumables) ~= "table" then
        return false
    end
    local inventory = data.Inventory :: PSUTypes.InventoryData
    local current: number = inventory.Consumables[itemId] or 0
    if current < amount then
        return false
    end
    local remaining: number = current - amount
    if remaining > 0 then
        inventory.Consumables[itemId] = remaining
    else
        inventory.Consumables[itemId] = nil
    end
    return true
end

function DataService:SyncFullState(player: Player): ()
    local profile = DataService.Profiles[player]
    if not profile then return end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
    local updateData = remotes and remotes:FindFirstChild(RemoteNames.UpdateProfileData) :: RemoteEvent?
    if updateData then
        updateData:FireClient(player, profile.Data)
    end
end

return DataService
