--!strict
--@author OrkGabb
--@module PortalService.luau
--@version 1.0
-- src/Server/Services/PortalService.lua

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService: ServerScriptService = game:GetService("ServerScriptService")

local FeatureResolver: any = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FeatureResolver"))
local DataService: any = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Services"):WaitForChild("DataService"))

local PortalService = {}

function PortalService:Init(): ()
    print("[INFO] PortalService Init: Zone resolution active.")
end

function PortalService:Start(): ()
    print("[INFO] PortalService Start: Spatial hooks active.")
    self:InitializeZoneTriggers()
end

function PortalService:InitializeZoneTriggers(): ()
    local portalConfigs = FeatureResolver.GetConfigField("Portals", "Configs", {})
    
    if type(portalConfigs) ~= "table" then
        print("[WARN] PortalService: No portals located in registry.")
        return
    end

    for _, config in ipairs(portalConfigs) do
        if config.BiomeId then
            print(string.format("[INFO] PortalService: Portal configuration loaded for %s.", config.BiomeId))
        end
    end
end

function PortalService:GetZoneData(zoneId: string): any?
    local portalConfigs = FeatureResolver.GetConfigField("Portals", "Configs", {})
    if type(portalConfigs) == "table" then
        for _, config in ipairs(portalConfigs) do
            if config.BiomeId == zoneId then
                return config
            end
        end
    end
    return nil
end

function PortalService:HasZoneAccess(player: Player, zoneId: string): boolean
    local zoneData = self:GetZoneData(zoneId)
    if type(zoneData) ~= "table" then
        return false
    end

    local data: { [string]: any }? = DataService:GetProfileData(player)
    
    if data == nil or data.Progression == nil then
        return false
    end
    
    local unlockedZones: { [string]: boolean }? = data.Progression.UnlockedZones
    
    -- Strictly gated by abstract Unlock state (Zero Hardcoded Levels)
    if unlockedZones ~= nil and unlockedZones[zoneId] == true then
        return true
    end

    return false
end

function PortalService:TeleportPlayerToZone(player: Player, zoneId: string): boolean
    if self:HasZoneAccess(player, zoneId) == false then
        print(string.format("[INFO] PortalService: Transit rejected for Player %d (Zone: %s).", player.UserId, zoneId))
        return false
    end

    local zoneData = self:GetZoneData(zoneId)
    if type(zoneData) ~= "table" then
        return false
    end

    local spawnVector: Vector3 = zoneData.SpawnPosition
    if typeof(spawnVector) ~= "Vector3" then
        print(string.format("[FAIL] PortalService: Spatial offset undefined for Zone %s.", zoneId))
        return false
    end

    local character: Model? = player.Character
    if character ~= nil then
        local humanRoot: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if humanRoot ~= nil and humanRoot:IsA("BasePart") then
            humanRoot.CFrame = CFrame.new(spawnVector)
            print(string.format("[PASS] PortalService: Transited Player %d to Zone %s.", player.UserId, zoneId))
            return true
        end
    end

    return false
end

function PortalService:UnlockZone(player: Player, zoneId: string): boolean
    local data: { [string]: any }? = DataService:GetProfileData(player)
    if data == nil or data.Progression == nil then
        return false
    end

    local zoneData = self:GetZoneData(zoneId)
    if type(zoneData) ~= "table" then
        return false
    end

    if data.Progression.UnlockedZones == nil then
        data.Progression.UnlockedZones = {}
    end

    data.Progression.UnlockedZones[zoneId] = true
    print(string.format("[INFO] PortalService: Access granted to Player %d for Zone %s.", player.UserId, zoneId))
    
    return true
end

return PortalService
