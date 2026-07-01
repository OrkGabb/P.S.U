--!strict
--@author OrkGabb
--@module UpgradeRegistry.luau
--@version 1.0
export type UpgradeData = {
    StatTarget: string,
    BaseCost: number,
    CostMultiplier: number,
    MaxLevel: number,
    ValueMultiplier: number,
    FlatValue: number
}

export type UpgradeRegistryType = {
    [string]: UpgradeData
}

local UpgradeRegistry: UpgradeRegistryType = {
    ["CapacityNode"] = {
        StatTarget = "StorageLimit",
        BaseCost = 100,
        CostMultiplier = 1.25,
        MaxLevel = 50,
        ValueMultiplier = 1.0,
        FlatValue = 10
    },
    ["EfficiencyNode"] = {
        StatTarget = "ProcessingRate",
        BaseCost = 500,
        CostMultiplier = 1.5,
        MaxLevel = 25,
        ValueMultiplier = 1.1,
        FlatValue = 0
    },
    ["YieldNode"] = {
        StatTarget = "BaseGeneration",
        BaseCost = 1000,
        CostMultiplier = 2.0,
        MaxLevel = 10,
        ValueMultiplier = 1.0,
        FlatValue = 25
    }
}

return UpgradeRegistry
