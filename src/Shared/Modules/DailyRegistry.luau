--!strict
--@author OrkGabb
--@module DailyRegistry.luau
--@version 1.0
-- src/Shared/Modules/DailyRegistry.lua
-- Dynamic Daily Rewards: Level-scaled coins + premium milestone rewards.
-- Single Source of Truth for ALL daily reward data.

export type DailyItem = {
    Id: string,
    Amount: number,
}

export type DailyEntry = {
    Day: number,
    Coins: number,
    Items: {DailyItem}?,
    IsMilestone: boolean,
}

local DailyRegistry = {
    Days = {} :: {[number]: DailyEntry}
}
-- ═══════════════════════════════════════════════════════════════════════════════
-- WEEK 1 (D1-D6 regular, D7 milestone)
-- ═══════════════════════════════════════════════════════════════════════════════
DailyRegistry.Days[1]  = { Day = 1,  Coins = 0,  IsMilestone = false }
DailyRegistry.Days[2]  = { Day = 2,  Coins = 0,  IsMilestone = false,
    Items = {{ Id = "LuckPotion_1", Amount = 1 }} }
DailyRegistry.Days[3]  = { Day = 3,  Coins = 0,  IsMilestone = false }
DailyRegistry.Days[4]  = { Day = 4,  Coins = 0,  IsMilestone = false,
    Items = {{ Id = "EXPPotion_1", Amount = 1 }} }
DailyRegistry.Days[5]  = { Day = 5,  Coins = 0,  IsMilestone = false }
DailyRegistry.Days[6]  = { Day = 6,  Coins = 0,  IsMilestone = false,
    Items = {{ Id = "CoinPotion_1", Amount = 1 }} }

-- ★ MILESTONE DAY 7: First Week Survivor
DailyRegistry.Days[7]  = { Day = 7,  Coins = 0,  IsMilestone = true,
    Items = {
        { Id = "LuckPotion_2", Amount = 2 },
        { Id = "CoinPotion_2", Amount = 2 },
        { Id = "Essence_RARE", Amount = 5 },
    }
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- WEEK 2 (D8-D13 regular, D14 milestone)
-- ═══════════════════════════════════════════════════════════════════════════════
DailyRegistry.Days[8]  = { Day = 8,  Coins = 0,  IsMilestone = false }
DailyRegistry.Days[9]  = { Day = 9,  Coins = 0,  IsMilestone = false,
    Items = {{ Id = "SpeedPotion_1", Amount = 1 }} }
DailyRegistry.Days[10] = { Day = 10, Coins = 0, IsMilestone = false,
    Items = {{ Id = "Essence_COMMON", Amount = 3 }} }
DailyRegistry.Days[11] = { Day = 11, Coins = 0, IsMilestone = false }
DailyRegistry.Days[12] = { Day = 12, Coins = 0, IsMilestone = false,
    Items = {{ Id = "StrengthPotion_1", Amount = 1 }} }
DailyRegistry.Days[13] = { Day = 13, Coins = 0, IsMilestone = false }

-- ★ MILESTONE DAY 14: Dedicated Grinder
DailyRegistry.Days[14] = { Day = 14, Coins = 0, IsMilestone = true,
    Items = {
        { Id = "LuckPotion_2", Amount = 3 },
        { Id = "SpeedPotion_2", Amount = 3 },
        { Id = "Essence_EPIC", Amount = 5 },
    }
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- WEEK 3 (D15-D20 regular, D21 milestone)
-- ═══════════════════════════════════════════════════════════════════════════════
DailyRegistry.Days[15] = { Day = 15, Coins = 0, IsMilestone = false,
    Items = {{ Id = "LuckPotion_1", Amount = 2 }} }
DailyRegistry.Days[16] = { Day = 16, Coins = 0, IsMilestone = false }
DailyRegistry.Days[17] = { Day = 17, Coins = 0, IsMilestone = false,
    Items = {{ Id = "EXPPotion_2", Amount = 1 }} }
DailyRegistry.Days[18] = { Day = 18, Coins = 0, IsMilestone = false,
    Items = {{ Id = "Essence_UNCOMMON", Amount = 3 }} }
DailyRegistry.Days[19] = { Day = 19, Coins = 0, IsMilestone = false }
DailyRegistry.Days[20] = { Day = 20, Coins = 0, IsMilestone = false,
    Items = {{ Id = "CoinPotion_2", Amount = 1 }} }

-- ★ MILESTONE DAY 21: Three Week Warrior
DailyRegistry.Days[21] = { Day = 21, Coins = 0, IsMilestone = true,
    Items = {
        { Id = "LuckPotion_3", Amount = 2 },
        { Id = "CoinPotion_3", Amount = 2 },
        { Id = "Essence_LEGENDARY", Amount = 3 },
    }
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- WEEK 4 (D22-D27 regular, D28 milestone)
-- ═══════════════════════════════════════════════════════════════════════════════
DailyRegistry.Days[22] = { Day = 22, Coins = 0, IsMilestone = false,
    Items = {{ Id = "SpeedPotion_2", Amount = 1 }} }
DailyRegistry.Days[23] = { Day = 23, Coins = 0, IsMilestone = false }
DailyRegistry.Days[24] = { Day = 24, Coins = 0, IsMilestone = false,
    Items = {{ Id = "Essence_EPIC", Amount = 2 }} }
DailyRegistry.Days[25] = { Day = 25, Coins = 0, IsMilestone = false,
    Items = {{ Id = "StrengthPotion_2", Amount = 1 }} }
DailyRegistry.Days[26] = { Day = 26, Coins = 0, IsMilestone = false }
DailyRegistry.Days[27] = { Day = 27, Coins = 0, IsMilestone = false,
    Items = {{ Id = "EXPPotion_2", Amount = 2 }} }

-- ★ MILESTONE DAY 28: Monthly Champion
DailyRegistry.Days[28] = { Day = 28, Coins = 0, IsMilestone = true,
    Items = {
        { Id = "SpeedPotion_3",  Amount = 2 },
        { Id = "EXPPotion_3",   Amount = 2 },
        { Id = "Essence_MUTANT", Amount = 2 },
    }
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- FINAL DAYS (D29-D30 regular, D31 ultimate milestone)
-- ═══════════════════════════════════════════════════════════════════════════════
DailyRegistry.Days[29] = { Day = 29, Coins = 0, IsMilestone = false,
    Items = {{ Id = "LuckPotion_2", Amount = 2 }} }
DailyRegistry.Days[30] = { Day = 30, Coins = 0, IsMilestone = false,
    Items = {{ Id = "Essence_LEGENDARY", Amount = 2 }} }

-- ★★★ MILESTONE DAY 31: Ultimate Dedication ★★★
DailyRegistry.Days[31] = { Day = 31, Coins = 0, IsMilestone = true,
    Items = {
        { Id = "LuckPotion_3",        Amount = 3 },
        { Id = "StrengthPotion_3",    Amount = 3 },
        { Id = "Essence_COSMIC",      Amount = 2 },
        { Id = "Essence_SINGULARITY", Amount = 2 },
        { Id = "Essence_MYTHIC",      Amount = 3 },
    }
}

-- Rebase BaseCoins to normal scale using formula: math.floor(500 * day * (1 + day * 0.1))
for day = 1, 31 do
    local entry: DailyEntry = DailyRegistry.Days[day] or { Day = day, Coins = 0, IsMilestone = false }
    entry.Coins = math.floor(500 * day * (1 + day * 0.1))
    DailyRegistry.Days[day] = entry
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- DYNAMIC LEVEL MULTIPLIER
-- ═══════════════════════════════════════════════════════════════════════════════
function DailyRegistry.GetMultiplier(level: number, rebirths: number?): number
    local R = rebirths or 0
    local L = math.max(1, level)
    return math.pow(L, 1.5) * (1 + R * 0.5)
end

return DailyRegistry
