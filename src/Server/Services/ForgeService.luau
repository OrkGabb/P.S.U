--!strict
--@author OrkGabb
--@module ForgeService.luau
--@version 1.0
-- src/Server/Services/ForgeService.lua
-- Refactored Forge Service. Allows players to craft boosts/potions using essences (duplicate rewards).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataService    = require(ServerScriptService.Server.Services.DataService)
local ItemRegistry   = require(ReplicatedStorage.Shared.Modules.ItemRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local QuestService: any = nil

local activeTransactions: {[Player]: boolean} = {}
local ForgeService = {}

function ForgeService.Init(): ()
    if not FeatureResolver.IsCategoryActive("Forge") then return end
end

function ForgeService.Start(): ()
    if not FeatureResolver.IsCategoryActive("Forge") then return end
    QuestService = require(ServerScriptService.Server.Services.QuestService)
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local forgeRequest = remotes:WaitForChild("ForgeRequest") :: RemoteEvent

    forgeRequest.OnServerEvent:Connect(function(player: Player, potionId: string)
        if activeTransactions[player] then return end
        activeTransactions[player] = true

        local success, val = pcall(function()
            local profile = DataService:GetProfile(player)
            if not profile then return false, "Profile not loaded" end

            local recipe = ItemRegistry.Recipes[potionId]
            if not recipe then return false, "Invalid recipe" end

            local potionData = ItemRegistry.Potions[potionId]
            if not potionData then return false, "Invalid item" end

            if not profile.Data.Currencies then
                profile.Data.Currencies = { ["Primary"] = 0, ["Secondary"] = 0, ["Premium"] = 0 }
            end
            local currencyKey = recipe.CurrencyKey or "Primary"
            local balance = profile.Data.Currencies[currencyKey] or 0

            -- 1. Verify currency cost
            if balance < recipe.Cost then
                return false, "Insufficient " .. currencyKey
            end

            -- 2. Verify all ingredients are present in inventory
            if not profile.Data.Inventory then profile.Data.Inventory = {} end
            for ingredientId, reqAmount in pairs(recipe.Ingredients) do
                local currentAmount = profile.Data.Inventory[ingredientId] or 0
                if currentAmount < reqAmount then
                    return false, "Missing ingredients"
                end
            end

            -- 3. Consume ingredients from inventory
            for ingredientId, reqAmount in pairs(recipe.Ingredients) do
                profile.Data.Inventory[ingredientId] -= reqAmount
                if profile.Data.Inventory[ingredientId] <= 0 then
                    profile.Data.Inventory[ingredientId] = nil
                end
            end

            -- 4. Deduct currency and sync leaderstats
            profile.Data.Currencies[currencyKey] -= recipe.Cost
            local ls = player:FindFirstChild("leaderstats")
            if ls then
                local primaryName = currencyKey
                local configPrimary = FeatureResolver.GetConfigField("Currencies", "PrimaryName", nil)
                if currencyKey == "Primary" and configPrimary then
                    primaryName = configPrimary
                end
                
                local coinsObj = ls:FindFirstChild(primaryName) or ls:FindFirstChild("Coins")
                if coinsObj and (coinsObj:IsA("IntValue") or coinsObj:IsA("NumberValue")) then
                    coinsObj.Value = profile.Data.Currencies[currencyKey]
                end
            end

            -- 5. Grant forged potion
            DataService:AddItem(player, potionId, 1)

            -- 6. Trigger Quest progression
            if QuestService then
                QuestService.AddProgress(player, "Craft", 1)
            end

            -- 7. Sync state to clients
            DataService:SyncFullState(player)

            -- Send satisfying dopamine visual feedback
            local notifyEvt = remotes:FindFirstChild("NotifyPurchase") :: RemoteEvent?
            if notifyEvt then
                notifyEvt:FireClient(player, "Item", 1, potionData.Name, nil)
            end

            forgeRequest:FireClient(player, true, "Successfully forged " .. potionData.Name)
            return true
        end)

        activeTransactions[player] = nil

        if not success then
            forgeRequest:FireClient(player, false, tostring(val or "Server Error"))
        elseif typeof(val) == "string" then
            forgeRequest:FireClient(player, false, val)
        end
    end)
end

return ForgeService
