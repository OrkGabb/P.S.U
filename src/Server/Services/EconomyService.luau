--!strict
--@author OrkGabb
--@module EconomyService.luau
--@version 1.0
-- src/Server/Services/EconomyService.lua

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService: ServerScriptService = game:GetService("ServerScriptService")

local FeatureResolver: any = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("FeatureResolver"))
local DataService: any = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Services"):WaitForChild("DataService"))

local EconomyService = {}

function EconomyService:Init(): ()
    print("[INFO] EconomyService Init: Registry bounds applied.")
end

function EconomyService:Start(): ()
    print("[INFO] EconomyService Start: Generic processing active.")
end

function EconomyService:AddCurrency(player: Player, currencyType: string, amount: number): boolean
    local data: { [string]: any }? = DataService:GetProfileData(player)
    if data == nil or data.Currencies == nil then
        return false
    end
    
    local currentBalance: number = data.Currencies[currencyType] or 0
    data.Currencies[currencyType] = currentBalance + amount
    return true
end

function EconomyService:RemoveCurrency(player: Player, currencyType: string, amount: number): boolean
    local data: { [string]: any }? = DataService:GetProfileData(player)
    if data == nil or data.Currencies == nil then
        return false
    end
    
    local currentBalance: number = data.Currencies[currencyType] or 0
    if currentBalance >= amount then
        data.Currencies[currencyType] = currentBalance - amount
        return true
    end
    return false
end

function EconomyService:GetCurrencyBalance(player: Player, currencyType: string): number
    local data: { [string]: any }? = DataService:GetProfileData(player)
    if data == nil or data.Currencies == nil then
        return 0
    end
    return data.Currencies[currencyType] or 0
end

function EconomyService:CalculateMultiplier(player: Player, statTarget: string): number
    local data: { [string]: any }? = DataService:GetProfileData(player)
    if data == nil or data.Upgrades == nil then
        return 1.0
    end

    local baseMultiplier: number = 1.0
    local upgradeConfigs: { [string]: any } = FeatureResolver.GetConfigField("Upgrades", "Configs", {})
    
    if type(upgradeConfigs) ~= "table" then
        return baseMultiplier
    end

    for categoryId: string, categoryData: any in pairs(upgradeConfigs) do
        if type(categoryData) == "table" and categoryData.StatTarget == statTarget then
            local playerUpgradeLevel: number = data.Upgrades[categoryId] or 0
            if playerUpgradeLevel > 0 then
                local valueMultiplier: number = categoryData.ValueMultiplier or 0
                local increment: number = playerUpgradeLevel * valueMultiplier
                baseMultiplier = baseMultiplier + increment
            end
        end
    end

    return baseMultiplier
end

function EconomyService:CalculateFlatIncrement(player: Player, statTarget: string): number
    local data: { [string]: any }? = DataService:GetProfileData(player)
    if data == nil or data.Upgrades == nil then
        return 0.0
    end

    local totalIncrement: number = 0.0
    local upgradeConfigs: { [string]: any } = FeatureResolver.GetConfigField("Upgrades", "Configs", {})
    
    if type(upgradeConfigs) ~= "table" then
        return totalIncrement
    end

    for categoryId: string, categoryData: any in pairs(upgradeConfigs) do
        if type(categoryData) == "table" and categoryData.StatTarget == statTarget then
            local playerUpgradeLevel: number = data.Upgrades[categoryId] or 0
            if playerUpgradeLevel > 0 then
                local flatValue: number = categoryData.FlatValue or 0
                totalIncrement = totalIncrement + (playerUpgradeLevel * flatValue)
            end
        end
    end

    return totalIncrement
end

function EconomyService:PurchaseUpgrade(player: Player, categoryId: string): boolean
    local data: { [string]: any }? = DataService:GetProfileData(player)
    if data == nil or data.Upgrades == nil then
        return false
    end

    local upgradeConfigs: { [string]: any } = FeatureResolver.GetConfigField("Upgrades", "Configs", {})
    local categoryData: any = upgradeConfigs[categoryId]

    if type(categoryData) ~= "table" then
        print(string.format("[WARN] EconomyService: Upgrade category %s undefined.", categoryId))
        return false
    end

    local currentLevel: number = data.Upgrades[categoryId] or 0
    local maxLevel: number = categoryData.MaxLevel or math.huge

    if currentLevel >= maxLevel then
        return false
    end

    local costCurrency: string = categoryData.CostCurrency or "Primary"
    local baseCost: number = categoryData.BaseCost or 0
    local costMultiplier: number = categoryData.CostMultiplier or 1
    local calculatedCost: number = baseCost * math.pow(costMultiplier, currentLevel)

    if self:RemoveCurrency(player, costCurrency, calculatedCost) == true then
        data.Upgrades[categoryId] = currentLevel + 1
        print(string.format("[PASS] EconomyService: Upgrade %s incremented for Player %d.", categoryId, player.UserId))
        return true
    end

    return false
end

return EconomyService
