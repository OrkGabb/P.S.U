--!strict
-- @Author @OrkGabb
-- src/Server/Services/ClickService.luau
-- Clicker_Farm genre service: server-authoritative click income, passive
-- income accrual, and secondary-currency (milestone) minting.
--
-- Economy model (all values sourced from registries — no numbers live here):
--   clickPower  = 1 + Σ PerClick upgrades  (UpgradeRegistry.ComputeStat)
--   passive/sec = Σ Passive upgrades
--   both scaled by gamepass income multipliers (CommerceRegistry effects)
--   and the rebirth hook (Progression.Rebirths, rebirth-ready but dormant).
--
-- Anti-macro: token bucket per player. The client batches clicks; the server
-- only honors up to MaxClickBurst at once and ClickRefillRate sustained CPS.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local DataService = require(ServerScriptService.Server.Services.DataService)
local UpgradeRegistry = require(ReplicatedStorage.Shared.Modules.UpgradeRegistry)
local CommerceRegistry = require(ReplicatedStorage.Shared.Config.CommerceRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local LevelService: any = nil
local QuestService: any = nil
local MonetizationService: any = nil

local GENRE_KEY = "Clicker_Farm"

local ClickService = {}

type Bucket = { tokens: number, lastUpdate: number }
local bucketMap: {[Player]: Bucket} = {}

-- Wall-clock of the last credited passive accrual (in-memory only: a rejoin
-- resets it, so offline time is never double-credited).
local lastAccrual: {[Player]: number} = {}

-- ─── Config (SSoT: FeatureToggles.Genres.Clicker_Farm) ──────────────────────

local function cfg(field: string, default: number): number
	return FeatureResolver.GetConfigField(GENRE_KEY, field, default)
end

-- ─── Economy helpers ─────────────────────────────────────────────────────────

local function ownsPass(player: Player): (string) -> boolean
	return function(passKey: string): boolean
		if MonetizationService then
			return MonetizationService.HasGamepass(player, passKey)
		end
		return false
	end
end

local function getIncomeMultiplier(player: Player, data: {[string]: any}): number
	local multiplier = CommerceRegistry.GetIncomeMultiplier(ownsPass(player))
	-- Rebirth-ready hook: each rebirth adds +100% income. Dormant until a
	-- rebirth mechanic sets Progression.Rebirths.
	local progression = data.Progression
	if type(progression) == "table" then
		multiplier *= 1 + (progression.Rebirths or 0)
	end
	return multiplier
end

local function getClickPower(data: {[string]: any}): number
	local upgrades = if type(data.Upgrades) == "table" then data.Upgrades else {}
	return 1 + UpgradeRegistry.ComputeStat(upgrades, "PerClick")
end

local function getPassivePerSecond(data: {[string]: any}): number
	local upgrades = if type(data.Upgrades) == "table" then data.Upgrades else {}
	return UpgradeRegistry.ComputeStat(upgrades, "Passive")
end

local function addStat(data: {[string]: any}, key: string, amount: number): ()
	if type(data.Stats) ~= "table" then
		data.Stats = {}
	end
	data.Stats[key] = (data.Stats[key] or 0) + amount
end

-- ─── Click handling ──────────────────────────────────────────────────────────

local function OnClickReward(player: Player, batch: number?): ()
	local maxBurst = cfg("MaxClickBurst", 30)
	local refillRate = cfg("ClickRefillRate", 20)

	local now = os.clock()
	local bucket: Bucket = bucketMap[player] or { tokens = maxBurst, lastUpdate = now }

	local elapsed = now - bucket.lastUpdate
	bucket.tokens = math.min(maxBurst, bucket.tokens + elapsed * refillRate)
	bucket.lastUpdate = now

	local requestedClicks = if type(batch) == "number"
		then math.clamp(math.floor(batch), 1, maxBurst)
		else 1

	if bucket.tokens < 1 then
		bucketMap[player] = bucket
		return
	end

	local clickCount = math.min(requestedClicks, math.floor(bucket.tokens))
	bucket.tokens -= clickCount
	bucketMap[player] = bucket

	local data = DataService:GetProfileData(player)
	if not data then return end

	if type(data.Currencies) ~= "table" then
		data.Currencies = { Primary = 0, Secondary = 0, Premium = 0 }
	end

	-- Primary currency gain
	local gain = math.floor(getClickPower(data) * getIncomeMultiplier(player, data)) * clickCount
	data.Currencies.Primary += gain

	-- Lifetime stats
	addStat(data, "TotalClicks", clickCount)
	addStat(data, "LifetimeEarned", gain)

	-- Secondary currency minting: 1 per ClicksPerSecondaryCurrency MANUAL clicks,
	-- remainder carried in the genre sub-table.
	local clicksPerMint = cfg("ClicksPerSecondaryCurrency", 50)
	if clicksPerMint > 0 then
		local genreData = DataService:GetGenreData(player, GENRE_KEY)
		if genreData then
			local accumulator = (genreData.ClickAccumulator or 0) + clickCount
			local minted = accumulator // clicksPerMint
			genreData.ClickAccumulator = accumulator % clicksPerMint
			if minted > 0 then
				data.Currencies.Secondary += minted
			end
		end
	end

	if LevelService then
		LevelService.AddExp(player, clickCount)
	end
	if QuestService then
		QuestService.AddProgress(player, "Click", clickCount)
	end
end

-- ─── Passive income ──────────────────────────────────────────────────────────

local function accruePassive(): ()
	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		-- Always advance the clock so time spent before the profile loads is
		-- never credited (no startup burst).
		local last = lastAccrual[player] or now
		lastAccrual[player] = now

		local data = DataService:GetProfileData(player)
		if not data then continue end
		if type(data.Currencies) ~= "table" then continue end

		local elapsed = now - last
		local incomeMult = getIncomeMultiplier(player, data)

		local perSecond = getPassivePerSecond(data)

		-- Auto-clicker gamepass: server-side manual-click equivalent income
		local autoCps = CommerceRegistry.GetAutoClicksPerSecond(ownsPass(player))
		if autoCps > 0 then
			perSecond += getClickPower(data) * autoCps
		end

		if perSecond <= 0 then continue end

		local gain = perSecond * elapsed * incomeMult
		data.Currencies.Primary += gain
		addStat(data, "LifetimeEarned", gain)
	end
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

function ClickService.Init(): ()
	Players.PlayerAdded:Connect(function(player)
		lastAccrual[player] = os.clock()
	end)
	Players.PlayerRemoving:Connect(function(player)
		bucketMap[player] = nil
		lastAccrual[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		lastAccrual[player] = os.clock()
	end
end

function ClickService.Start(): ()
	LevelService = require(ServerScriptService.Server.Services.LevelService)
	QuestService = require(ServerScriptService.Server.Services.QuestService)
	MonetizationService = require(ServerScriptService.Server.Services.MonetizationService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local clickReward = remotes:WaitForChild(RemoteNames.ClickReward) :: RemoteEvent
	clickReward.OnServerEvent:Connect(OnClickReward)

	-- Passive accrual heartbeat (tick interval from genre config)
	local tickInterval = cfg("PassiveTickInterval", 1)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < tickInterval then return end
		acc = 0
		accruePassive()
	end)
end

return ClickService
