--!strict
-- @Author @OrkGabb
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local DataService = require(ServerScriptService.Server.Services.DataService)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local LevelService = {}

-- Sets the first matching leaderstat under `container` to `value`
-- (NumberValue/IntValue only; silently skips missing stats).
local function setLeaderstat(container: Instance, names: {string}, value: number): ()
    for _, name in ipairs(names) do
        local stat = container:FindFirstChild(name)
        if stat then
            if stat:IsA("NumberValue") then
                stat.Value = value
                return
            elseif stat:IsA("IntValue") then
                stat.Value = value
                return
            end
        end
    end
end

function LevelService.GetMaxExp(level: number): number
    -- Exponential Curve: 1000 Base * 1.3^Level. Creates the grind wall.
    return math.floor(1000 * math.pow(1.3, math.max(0, level - 1)))
end

function LevelService.AddExp(player: Player, amount: number)
    local profile = DataService.Profiles[player]
    if not profile or not profile.Data then return end

    if not profile.Data.Progression then
        profile.Data.Progression = { ["Level"] = 1, ["Experience"] = 0, ["EarningPower"] = 1 }
    end
    
    local prog = profile.Data.Progression
    prog.Experience = (prog.Experience or 0) + amount
    local maxExp = LevelService.GetMaxExp(prog.Level or 1)
    local leveledUp = false
    local totalReward = 0

    -- Cascade: a big EXP gain can level up multiple times; rewards accumulate across all of them.
    while prog.Experience >= maxExp do
        prog.Experience -= maxExp
        prog.Level = (prog.Level or 1) + 1
        maxExp = LevelService.GetMaxExp(prog.Level)
        leveledUp = true

        totalReward += (prog.Level * 5000)
    end

    local ls = player:FindFirstChild("leaderstats")
    if ls then
        setLeaderstat(ls, { "EXP", "Experience" }, prog.Experience)

        if leveledUp then
            setLeaderstat(ls, { "Level" }, prog.Level)

            if not profile.Data.Currencies then
                profile.Data.Currencies = { ["Primary"] = 0, ["Secondary"] = 0, ["Premium"] = 0 }
            end
            profile.Data.Currencies.Primary = (profile.Data.Currencies.Primary or 0) + totalReward

            -- SSoT: the active genre's currency display name comes from
            -- FeatureResolver (was a bogus GetConfigField("Currencies", …)
            -- call that always fell back to "Coins")
            local primaryName: string = FeatureResolver.GetCurrencyNames().Primary
            setLeaderstat(ls, { primaryName, "Coins" }, profile.Data.Currencies.Primary)

            -- Fires once even if the cascade above leveled up multiple times
            local remotes = ReplicatedStorage:WaitForChild("Remotes")
            local levelUpEvent = remotes:FindFirstChild(RemoteNames.LevelUpFX) :: RemoteEvent
            if levelUpEvent then
                levelUpEvent:FireClient(player, prog.Level, totalReward)
            end
        end
    end
end

function LevelService.Init(): () 
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    if not remotes:FindFirstChild(RemoteNames.LevelUpFX) then
        local event = Instance.new("RemoteEvent")
        event.Name = RemoteNames.LevelUpFX
        event.Parent = remotes
    end
end

function LevelService.Start(): () end

return LevelService
