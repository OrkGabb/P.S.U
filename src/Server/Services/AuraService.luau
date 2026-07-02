--!strict
-- @Author @OrkGabb
-- src/Server/Services/AuraService.luau
-- Aura_Collector genre service: server-authoritative RNG rolls (with pity and
-- luck/speed masteries), aura collection, equip management and idle income.
--
-- Rebuilt from the legacy ProbabilityService/RngService era against the
-- abstract profile schema: balances live in Currencies.Primary, genre state
-- lives in GenreData.Aura_Collector — the core schema carries no aura fields.
--
-- Equipped-aura replication uses a player attribute ("EquippedAura"): Roblox
-- replicates it to every client automatically (including late joiners), so no
-- per-frame sync or bespoke broadcast remotes are needed. AuraVFXController
-- listens for the attribute and applies VFX locally.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AuraRegistry = require(ReplicatedStorage.Shared.Modules.AuraRegistry)
local UpgradeRegistry = require(ReplicatedStorage.Shared.Modules.UpgradeRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)
local CommerceRegistry = require(ReplicatedStorage.Shared.Config.CommerceRegistry)
local DataService = require(ServerScriptService.Server.Services.DataService)
local NetworkService = require(ServerScriptService.Server.Services.NetworkService)

local QuestService: any = nil
local ItemService: any = nil
local MonetizationService: any = nil
local LevelService: any = nil

local GENRE_KEY = "Aura_Collector"
local EQUIPPED_ATTRIBUTE = "EquippedAura"
local ROLL_SPEED_ATTRIBUTE = "RollSpeedMult"

local AuraService = {}

local rollCooldowns: {[Player]: number} = {}
local lastIncome: {[Player]: number} = {}

type AutoRollState = { IsActive: boolean }
local autoRollPlayers: {[Player]: AutoRollState} = {}

-- ─── Config (SSoT: FeatureToggles.Genres.Aura_Collector) ─────────────────────

local function cfg(field: string, default: number): number
	return FeatureResolver.GetConfigField(GENRE_KEY, field, default)
end

-- ─── Genre data ───────────────────────────────────────────────────────────────

type AuraGenreData = {
	Collection: {[string]: number},
	Equipped: string,
	ManualEquip: boolean,
	PityCounter: number,
	CurrentBiome: string,
	UnlockedBiomes: {[string]: boolean},
}

local function getAuraData(player: Player): AuraGenreData?
	local genreData = DataService:GetGenreData(player, GENRE_KEY)
	if not genreData then
		return nil
	end
	if type(genreData.Collection) ~= "table" then genreData.Collection = {} end
	if type(genreData.Equipped) ~= "string" then genreData.Equipped = "None" end
	if type(genreData.ManualEquip) ~= "boolean" then genreData.ManualEquip = false end
	if type(genreData.PityCounter) ~= "number" then genreData.PityCounter = 0 end
	if type(genreData.CurrentBiome) ~= "string" then genreData.CurrentBiome = "Default" end
	if type(genreData.UnlockedBiomes) ~= "table" then genreData.UnlockedBiomes = { Default = true } end
	return genreData :: AuraGenreData
end

-- ─── Multiplier helpers ───────────────────────────────────────────────────────

local function getMasteryBonus(data: {[string]: any}, masteryId: string): number
	local upgrades = data.Upgrades
	local level: number = if type(upgrades) == "table" then (upgrades[masteryId] or 0) else 0
	if level <= 0 then
		return 0
	end
	local def = UpgradeRegistry.GetDef(masteryId)
	return level * (if def and def.Increment then def.Increment else 0)
end

local function ownsPass(player: Player, passKey: string): boolean
	if MonetizationService then
		return MonetizationService.HasGamepass(player, passKey)
	end
	return false
end

local function getRollCooldown(player: Player, data: {[string]: any}): number
	local speedMult = 1 + getMasteryBonus(data, "SpeedMastery")
	if ItemService then
		-- Volatile speed potions multiply on top of masteries
		speedMult *= math.max(ItemService:GetVolatileMultiplier(player, "Speed"), 0.1)
	end

	local hasDoubleSpeed = ownsPass(player, "DoubleSpeed")
	if hasDoubleSpeed then
		speedMult *= 2
	end
	speedMult = math.max(speedMult, 0.1)

	local cooldown = cfg("BaseRollCooldown", 3.5) / speedMult
	if not hasDoubleSpeed then
		-- Free players never reach the paid roll cadence
		cooldown = math.max(cooldown, cfg("MinRollCooldown", 1.75))
	end

	-- Mirror the effective speed to the client so its local input gating and
	-- spin animation agree with the server (read by the roll UI).
	player:SetAttribute(ROLL_SPEED_ATTRIBUTE, cfg("BaseRollCooldown", 3.5) / cooldown)

	return cooldown
end

local function getLuckMultiplier(player: Player, data: {[string]: any}): number
	local luck = 1 + getMasteryBonus(data, "LuckMastery")
	if ItemService then
		luck += math.max(ItemService:GetVolatileMultiplier(player, "Luck") - 1, 0)
	end
	if ownsPass(player, "DoubleLuck") then
		luck *= 2
	end
	return luck
end

-- ─── Equip ────────────────────────────────────────────────────────────────────

local function setEquipped(player: Player, auraData: AuraGenreData, auraId: string, manual: boolean): ()
	auraData.Equipped = auraId
	auraData.ManualEquip = manual
	player:SetAttribute(EQUIPPED_ATTRIBUTE, auraId)
	NetworkService.FireClient(player, "UpdateEquipped", auraId)
end

-- ─── Roll ─────────────────────────────────────────────────────────────────────

local function processRoll(player: Player, spinId: number?): ()
	local data = DataService:GetProfileData(player)
	local auraData = getAuraData(player)
	if not data or not auraData then return end

	-- Cooldown (0.3s grace so legitimate client requests aren't rejected on ping)
	local cooldown = getRollCooldown(player, data)
	local now = os.clock()
	if (rollCooldowns[player] or 0) + cooldown - 0.3 > now then return end
	rollCooldowns[player] = now

	-- Biome gate
	local biomeId = auraData.CurrentBiome
	if not auraData.UnlockedBiomes[biomeId] then
		biomeId = "Default"
		auraData.CurrentBiome = "Default"
	end
	local biome = AuraRegistry.GetBiome(biomeId)
	local engine = AuraRegistry.GetEngine(biomeId)
	if not biome or not engine then
		rollCooldowns[player] = 0
		return
	end

	-- Cost / level gate (abstract schema)
	if type(data.Currencies) ~= "table" then
		data.Currencies = { Primary = 0, Secondary = 0, Premium = 0 }
	end
	local level: number = if type(data.Progression) == "table" then (data.Progression.Level or 1) else 1
	if data.Currencies.Primary < biome.RollCost or level < biome.LevelReq then
		rollCooldowns[player] = 0
		local autoState = autoRollPlayers[player]
		if autoState and autoState.IsActive then
			autoState.IsActive = false
			NetworkService.FireClient(player, "ToggleAutoRoll", false)
		end
		return
	end
	data.Currencies.Primary -= biome.RollCost

	-- Weighted roll with pity
	local luck = getLuckMultiplier(player, data)
	local rolled: AuraRegistry.AuraDef
	if auraData.PityCounter >= cfg("HardPityLimit", 100) then
		rolled = engine:Roll(luck * 100)
		auraData.PityCounter = 0
	else
		rolled = engine:Roll(luck)
		if rolled.Weight <= cfg("PityWeightThreshold", 20) then
			auraData.PityCounter = 0
		else
			auraData.PityCounter += 1
		end
	end

	-- Collection. Duplicates mint Essence (Currencies.Secondary) scaled by
	-- rarity — the sink is the Essence-priced masteries in UpgradeRegistry.
	local isNew = (auraData.Collection[rolled.Id] or 0) <= 0
	auraData.Collection[rolled.Id] = (auraData.Collection[rolled.Id] or 0) + 1
	if not isNew then
		data.Currencies.Secondary = (data.Currencies.Secondary or 0)
			+ AuraRegistry.GetRarity(rolled.RarityTag).EssenceOnDupe
	end

	-- Auto-equip policy: always equip a brand-new aura; otherwise upgrade the
	-- equipped one when the drop is rarer — unless the player equipped manually.
	local equippedDef = AuraRegistry.GetAuraData(auraData.Equipped)
	if auraData.Equipped == "None" or auraData.Equipped == "" or isNew then
		setEquipped(player, auraData, rolled.Id, false)
	elseif not auraData.ManualEquip and rolled.Weight < equippedDef.Weight then
		setEquipped(player, auraData, rolled.Id, false)
	end

	if QuestService then
		QuestService.AddProgress(player, "Roll", 1)
		if rolled.RarityTag ~= "COMMON" then
			QuestService.AddProgress(player, "RollUncommon", 1)
		end
	end

	DataService:SyncFullState(player)
	NetworkService.FireClient(player, "UpdateCollection", auraData.Collection, {})
	NetworkService.FireClient(player, "UpdateClient", rolled.Id, auraData.Equipped, biomeId, spinId)
end

-- ─── Idle income ──────────────────────────────────────────────────────────────

local function accrueIncome(): ()
	local interval = cfg("IncomeInterval", 1)
	local base = cfg("IncomeBase", 10)
	local expBase = cfg("IncomeExpBase", 2)
	local now = os.clock()

	for _, player in ipairs(Players:GetPlayers()) do
		local last = lastIncome[player] or now
		if now - last < interval then continue end
		lastIncome[player] = now

		local data = DataService:GetProfileData(player)
		local auraData = getAuraData(player)
		if not data or not auraData then continue end
		if type(data.Currencies) ~= "table" then continue end

		local def = AuraRegistry.GetAuraData(auraData.Equipped)

		-- Coins: aura multiplier × CoinMastery × Coin potion × owned
		-- IncomeMultiplier gamepasses (e.g. VIP)
		local coinMult = math.max(1, def.CoinMult) * (1 + getMasteryBonus(data, "CoinMastery"))
		if ItemService then
			coinMult *= math.max(ItemService:GetVolatileMultiplier(player, "Coin"), 0.1)
		end
		if MonetizationService then
			coinMult *= CommerceRegistry.GetIncomeMultiplier(function(passKey: string): boolean
				return MonetizationService.HasGamepass(player, passKey)
			end)
		end
		data.Currencies.Primary = (data.Currencies.Primary or 0) + base * coinMult

		-- Experience: aura multiplier × EXPMastery × EXP potion, cascaded
		-- through LevelService (handles level-ups and leaderstats)
		if LevelService then
			local expMult = math.max(1, def.ExpMult) * (1 + getMasteryBonus(data, "EXPMastery"))
			if ItemService then
				expMult *= math.max(ItemService:GetVolatileMultiplier(player, "EXP"), 0.1)
			end
			LevelService.AddExp(player, expBase * expMult)
		end
	end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function AuraService.Init(): ()
	local remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	for _, name in ipairs({ "RollRequest", "ToggleAutoRoll", "ForceDisableAutoRoll", "UpdateClient", "UpdateCollection", "UpdateEquipped", "EquipRequest", "SetBiomeRequest", "UpdateBiome" }) do
		if not remotes:FindFirstChild(name) then
			local evt = Instance.new("RemoteEvent")
			evt.Name = name
			evt.Parent = remotes
		end
	end
end

-- Grants the paid VIP aura once to VIP gamepass owners (new joins and
-- in-session purchases). Paid auras are never rolled.
local function grantVipAuraIfOwned(player: Player): ()
	if not (MonetizationService and MonetizationService.HasGamepass(player, "VIP")) then
		return
	end
	local auraData = getAuraData(player)
	if not auraData or (auraData.Collection.VIP or 0) > 0 then
		return
	end
	auraData.Collection.VIP = 1
	NetworkService.FireClient(player, "UpdateCollection", auraData.Collection, {})
	DataService:SyncFullState(player)
end

-- Handles biome switch requests: switching to an unlocked biome is free;
-- switching to a locked one charges its UnlockCost (Currencies.Primary)
-- and requires the biome's LevelReq.
local function processSetBiome(player: Player, biomeId: any): ()
	if type(biomeId) ~= "string" then return end
	local biome = AuraRegistry.GetBiome(biomeId)
	if not biome then return end

	local data = DataService:GetProfileData(player)
	local auraData = getAuraData(player)
	if not data or not auraData then return end

	if not auraData.UnlockedBiomes[biomeId] then
		local level: number = if type(data.Progression) == "table" then (data.Progression.Level or 1) else 1
		if level < biome.LevelReq then return end

		local unlockCost = biome.UnlockCost or 0
		if type(data.Currencies) ~= "table" then return end
		if (data.Currencies.Primary or 0) < unlockCost then return end
		data.Currencies.Primary -= unlockCost
		auraData.UnlockedBiomes[biomeId] = true
	end

	auraData.CurrentBiome = biomeId
	DataService:SyncFullState(player)
	NetworkService.FireClient(player, "UpdateBiome", biomeId)
end

function AuraService.Start(): ()
	QuestService = require(ServerScriptService.Server.Services.QuestService)
	ItemService = require(ServerScriptService.Server.Services.ItemService)
	MonetizationService = require(ServerScriptService.Server.Services.MonetizationService)
	LevelService = require(ServerScriptService.Server.Services.LevelService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder

	;(remotes:WaitForChild("SetBiomeRequest") :: RemoteEvent).OnServerEvent:Connect(processSetBiome)

	-- VIP aura for in-session gamepass purchases (join grants happen in
	-- onPlayerAdded once the profile is available)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, _passId: number, wasPurchased: boolean)
		if wasPurchased then
			grantVipAuraIfOwned(player)
		end
	end)

	;(remotes:WaitForChild("RollRequest") :: RemoteEvent).OnServerEvent:Connect(function(player: Player, _clientBiome: any, spinId: any)
		local autoState = autoRollPlayers[player]
		if autoState and autoState.IsActive then return end
		processRoll(player, if type(spinId) == "number" then spinId else nil)
	end)

	;(remotes:WaitForChild("EquipRequest") :: RemoteEvent).OnServerEvent:Connect(function(player: Player, auraId: any)
		if type(auraId) ~= "string" then return end
		local auraData = getAuraData(player)
		if not auraData then return end

		if auraId == "None" then
			setEquipped(player, auraData, "None", true)
			return
		end
		-- Only owned auras can be equipped
		if (auraData.Collection[auraId] or 0) <= 0 then return end
		setEquipped(player, auraData, auraId, true)
	end)

	;(remotes:WaitForChild("ToggleAutoRoll") :: RemoteEvent).OnServerEvent:Connect(function(player: Player, isActive: any)
		local now = os.clock()
		local lastToggle: number = (player:GetAttribute("LastAutoToggle") :: number?) or 0
		if now - lastToggle < 1.0 then return end
		player:SetAttribute("LastAutoToggle", now)

		if isActive == true then
			-- Auto-roll is a gamepass perk
			if not ownsPass(player, "AutoRoll") then
				NetworkService.FireClient(player, "ForceDisableAutoRoll")
				local state = autoRollPlayers[player]
				if state then state.IsActive = false end
				return
			end

			local state = autoRollPlayers[player]
			if not state then
				state = { IsActive = false }
				autoRollPlayers[player] = state
			end
			if state.IsActive then return end
			state.IsActive = true

			task.spawn(function()
				while true do
					local currentState = autoRollPlayers[player]
					if not currentState or not currentState.IsActive then return end
					if not player:IsDescendantOf(Players) then return end

					local data = DataService:GetProfileData(player)
					if data then
						processRoll(player, nil)
					end

					local waitData = DataService:GetProfileData(player)
					local cooldown = if waitData then getRollCooldown(player, waitData) else 1
					task.wait(cooldown)
				end
			end)
		else
			local state = autoRollPlayers[player]
			if state then state.IsActive = false end
		end
	end)

	-- Re-assert the equipped attribute for players whose profile loads late,
	-- grant the VIP aura to pass owners, and seed income clocks.
	local function onPlayerAdded(player: Player): ()
		lastIncome[player] = os.clock()
		task.spawn(function()
			-- Wait for the profile, then publish equipped state
			for _ = 1, 40 do
				local auraData = getAuraData(player)
				if auraData then
					player:SetAttribute(EQUIPPED_ATTRIBUTE, auraData.Equipped)
					grantVipAuraIfOwned(player)
					return
				end
				task.wait(0.5)
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		rollCooldowns[player] = nil
		autoRollPlayers[player] = nil
		lastIncome[player] = nil
	end)

	-- Idle income heartbeat
	task.spawn(function()
		while true do
			task.wait(cfg("IncomeInterval", 1))
			accrueIncome()
		end
	end)
end

return AuraService
