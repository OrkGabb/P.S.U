--!strict
-- @Author @OrkGabb
-- Secure Monetization System for Roblox.
-- Support for Gamepasses (O(1) Cache) and Developer Products (Idempotent ProcessReceipt).

local MarketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local ServerScriptService: ServerScriptService = game:GetService("ServerScriptService")

local DataService: any = require(ServerScriptService.Server.Services.DataService)
local FeatureResolver: any = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("FeatureResolver"))
local StoreRegistry: any = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("StoreRegistry"))

local MonetizationService = {}

-- Gamepass cache for O(1) HasGamepass checks by genre services (e.g. AuraService)
local OwnedGamepasses: {[Player]: {[string]: boolean}} = {}

MonetizationService.GamepassIDs = StoreRegistry.GamepassIDs
MonetizationService.DevProducts = StoreRegistry.DevProducts

type RewardConfig = {
    Type: string,
    Amount: number,
    ItemId: string?
}

-- Gamepass logic (permanent)

function MonetizationService.HasGamepass(player: Player, passKey: string): boolean
    if OwnedGamepasses[player] and OwnedGamepasses[player][passKey] == true then return true end
    
    -- Fallback to ProfileService — needed for Studio test purchases to persist locally
    local profile: any = DataService.Profiles[player]
    if profile and profile.Data and profile.Data.PurchaseHistory then
        local passId: number? = MonetizationService.GamepassIDs[passKey]
        if passId and profile.Data.PurchaseHistory["GP_" .. tostring(passId)] then
            return true
        end
    end
    
    return false
end

local function LoadPlayerGamepasses(player: Player): ()
    OwnedGamepasses[player] = {}
    
    for key: string, passId: number in pairs(MonetizationService.GamepassIDs) do
        -- Web calls must be wrapped in pcall to prevent server crash
        local success: boolean, hasPass: any = pcall(function(): any
            return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
        end)
        
        if success and hasPass == true then
            OwnedGamepasses[player][key] = true
        elseif not success then
            warn("[MonetizationService] Failed to verify Gamepass " .. key .. " for " .. player.Name)
        end
    end
end

-- Developer product logic (consumables) — secure idempotent ProcessReceipt
local function ProcessReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
    local player: Player? = Players:GetPlayerByUserId(receiptInfo.PlayerId)
    if not player then
        -- Player purchased and left instantly. Return NotProcessedYet.
        -- Roblox will retry processing the receipt when the player returns.
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local profile: any = DataService.Profiles[player]
    if not profile or not profile.Data then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    -- Inject purchase history table for legacy data profiles that predate it
    if not profile.Data.PurchaseHistory then
        profile.Data.PurchaseHistory = {}
    end

    -- Idempotency: a receipt already processed and saved returns PurchaseGranted
    if profile.Data.PurchaseHistory[receiptInfo.PurchaseId] then
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end

    local reward: RewardConfig = MonetizationService.DevProducts[receiptInfo.ProductId]
    if not reward then
        warn("[MonetizationService] Developer product not configured! ID: " .. tostring(receiptInfo.ProductId))
        -- Skip processing until developer updates configuration table
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    if reward.Type == "Currency" then
        if not profile.Data.Currencies then
            profile.Data.Currencies = { ["Primary"] = 0, ["Secondary"] = 0, ["Premium"] = 0 }
        end
        local targetKey = reward.ItemId or "Primary"
        profile.Data.Currencies[targetKey] = (profile.Data.Currencies[targetKey] or 0) + reward.Amount
        
        local ls: Folder? = player:FindFirstChild("leaderstats") :: any
        if ls then
            local primaryName: string = targetKey
            if targetKey == "Primary" then
                primaryName = FeatureResolver.GetCurrencyNames().Primary
            elseif targetKey == "Secondary" then
                primaryName = FeatureResolver.GetCurrencyNames().Secondary
            end

            local primaryValObj: Instance? = ls:FindFirstChild(primaryName)
            if primaryValObj and (primaryValObj:IsA("IntValue") or primaryValObj:IsA("NumberValue")) then
                (primaryValObj :: any).Value = profile.Data.Currencies[targetKey]
            end
        end

    elseif reward.Type == "Item" and reward.ItemId then
        DataService:AddItem(player, reward.ItemId, reward.Amount)

    elseif reward.Type == "VIP" then
        -- Grant 30 days of VIP time; stacks if already active
        local VIP_DURATION: number = 30 * 86400 -- 30 days in seconds
        local currentExpiry: number = profile.Data.VIPExpiry or 0
        local now: number = os.time()
        local currentMidnight: number = now - (now % 86400)
        
        if currentExpiry < currentMidnight then
            profile.Data.VIPPendingDailyClaims = math.min(3, (profile.Data.VIPPendingDailyClaims or 0) + 1)
            profile.Data.VIPLastDailyClaimTime = math.max(profile.Data.VIPLastDailyClaimTime or 0, currentMidnight)
        end

        local base: number = math.max(currentExpiry, now)
        profile.Data.VIPExpiry = base + VIP_DURATION

        if not profile.Data.VIPLastDailyClaimTime or profile.Data.VIPLastDailyClaimTime == 0 then
            profile.Data.VIPLastDailyClaimTime = currentMidnight
        end
        if not profile.Data.VIPPendingDailyClaims then
            profile.Data.VIPPendingDailyClaims = 0
        end
        -- NOTE: cosmetic VIP perks (chat tag, genre cosmetics) are granted by
        -- the systems that own them, keyed off VIPExpiry — core grants none.
    end

    -- Mark as processed and force a full state save
    profile.Data.PurchaseHistory[receiptInfo.PurchaseId] = true
    DataService:SyncFullState(player)

    warn(string.format("[MonetizationService] Product %s delivered successfully to %s!", tostring(receiptInfo.ProductId), player.Name))

    local remotes: Folder? = ReplicatedStorage:FindFirstChild("Remotes") :: any
    if remotes and remotes:FindFirstChild(RemoteNames.NotifyPurchase) then
        local displayName: string = "REWARD"
        local extraData: any = nil
        if reward.Type == "Currency" then
            displayName = string.upper(reward.ItemId or "CURRENCY")
        elseif reward.Type == "VIP" then
            local daysRemaining: number = math.ceil(((profile.Data.VIPExpiry or 0) - os.time()) / 86400)
            displayName = "VIP PASS"
            extraData = {
                daysRemaining = daysRemaining,
                benefits = {"[VIP] Chat Tag", "+25% Click Power", "VIP Daily Rewards Unlocked"},
            }
        elseif reward.Type == "Item" and reward.ItemId then
            displayName = string.upper((string.gsub(reward.ItemId, "_", " ")))
        end
        (remotes:FindFirstChild(RemoteNames.NotifyPurchase) :: RemoteEvent):FireClient(player, reward.Type, reward.Amount, displayName, extraData)
    end

    return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.Init(): ()
    local remotes: Folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
    if not remotes:FindFirstChild(RemoteNames.NotifyPurchase) then
        local evt: RemoteEvent = Instance.new("RemoteEvent")
        evt.Name = RemoteNames.NotifyPurchase
        evt.Parent = remotes
    end
    if not remotes:FindFirstChild(RemoteNames.CheckGamepassOwnership) then
        local rf: RemoteFunction = Instance.new("RemoteFunction")
        rf.Name = RemoteNames.CheckGamepassOwnership
        rf.Parent = remotes
    end
    if not remotes:FindFirstChild(RemoteNames.BuyInGameItem) then
        local rf: RemoteFunction = Instance.new("RemoteFunction")
        rf.Name = RemoteNames.BuyInGameItem
        rf.Parent = remotes
    end
end

function MonetizationService.Start(): ()
    MarketplaceService.ProcessReceipt = ProcessReceipt

    Players.PlayerAdded:Connect(LoadPlayerGamepasses)
    for _, player: Player in ipairs(Players:GetPlayers()) do
        task.spawn(LoadPlayerGamepasses, player)
    end

    -- Clear the cache on exit so OwnedGamepasses doesn't keep pinning a
    -- Player instance (and its subtable) for every player who has ever joined.
    Players.PlayerRemoving:Connect(function(player: Player)
        OwnedGamepasses[player] = nil
    end)


    local remotes: Folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
    local checkRf: RemoteFunction = remotes:WaitForChild(RemoteNames.CheckGamepassOwnership) :: RemoteFunction
    checkRf.OnServerInvoke = function(player: Player, passId: any): any
        local profile: any = DataService.Profiles[player]
        if profile and profile.Data and profile.Data.PurchaseHistory then
            return profile.Data.PurchaseHistory["GP_" .. tostring(passId)] == true
        end
        return false
    end

    local buyItemRf: RemoteFunction = remotes:WaitForChild(RemoteNames.BuyInGameItem) :: RemoteFunction
    buyItemRf.OnServerInvoke = function(player: Player, itemId: any): boolean
        local profile: any = DataService.Profiles[player]
        if not profile or not profile.Data or not profile.Data.Currencies then return false end

        local catalog = StoreRegistry.Catalog
        if not catalog then return false end
        
        local itemInfo
        for _, item in ipairs(catalog) do
            if item.Id == itemId then
                itemInfo = item
                break
            end
        end

        if not itemInfo or itemInfo.Type ~= "VirtualCurrency" then return false end
        
        local currencyKey = "Primary"
        if itemInfo.Reward and itemInfo.Reward.ItemId then
            currencyKey = itemInfo.Reward.ItemId
        end

        local balance = profile.Data.Currencies[currencyKey] or 0
        local price = itemInfo.Price or 0
        if balance >= price then
            profile.Data.Currencies[currencyKey] -= price
            
            local ls: Folder? = player:FindFirstChild("leaderstats") :: any
            if ls then
                local primaryName: string = currencyKey
                if currencyKey == "Primary" then
                    primaryName = FeatureResolver.GetCurrencyNames().Primary
                elseif currencyKey == "Secondary" then
                    primaryName = FeatureResolver.GetCurrencyNames().Secondary
                end

                local valObj: Instance? = ls:FindFirstChild(primaryName)
                if valObj and (valObj:IsA("IntValue") or valObj:IsA("NumberValue")) then
                    (valObj :: any).Value = profile.Data.Currencies[currencyKey]
                end
            end

            if itemInfo.Reward then
                if itemInfo.Reward.Type == "Item" and itemInfo.Reward.ItemId then
                    DataService:AddItem(player, itemInfo.Reward.ItemId, itemInfo.Reward.Amount)
                end
            end

            DataService:SyncFullState(player)
            return true
        end
        return false
    end

    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, wasPurchased: boolean): ()
        if not wasPurchased then return end

        local profile: any = DataService.Profiles[player]
        if profile and profile.Data then
            if not profile.Data.PurchaseHistory then profile.Data.PurchaseHistory = {} end
            profile.Data.PurchaseHistory["GP_" .. tostring(passId)] = true
        end

        local remotesFolder: Folder? = ReplicatedStorage:FindFirstChild("Remotes") :: any
        local notifyEvt: RemoteEvent? = remotesFolder and remotesFolder:FindFirstChild(RemoteNames.NotifyPurchase) :: any

        for key: string, configId: number in pairs(MonetizationService.GamepassIDs) do
            if passId == configId then
                if not OwnedGamepasses[player] then OwnedGamepasses[player] = {} end
                OwnedGamepasses[player][key] = true

                DataService:SyncFullState(player)

                if notifyEvt then
                    local displayName: string = string.upper((string.gsub(key, "_", " ")))
                    notifyEvt:FireClient(player, "Gamepass", 1, displayName)
                end

                warn(string.format("[MonetizationService] %s purchased Gamepass %s in-game!", player.Name, key))
                break
            end
        end
    end)
end

return MonetizationService
