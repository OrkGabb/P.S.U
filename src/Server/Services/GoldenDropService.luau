--!strict
-- @Author @OrkGabb
-- src/Server/Services/GoldenDropService.luau
-- Clicker_Farm golden drop event (Cookie Clicker "Lucky"-style): on a random
-- cadence the server issues a GUID to one player; their client shows a falling
-- clickable icon; claiming it back within the descent window rolls a weighted
-- reward tier scaled by the player's current passive income.
--
-- Server-authoritative: the client only ever echoes the GUID back. Expired,
-- unknown or already-claimed GUIDs are rejected, so no reward can be forged.
-- All cadence/tier values live in FeatureToggles.Genres.Clicker_Farm.GoldenDrop.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataService = require(ServerScriptService.Server.Services.DataService)
local UpgradeRegistry = require(ReplicatedStorage.Shared.Modules.UpgradeRegistry)
local CommerceRegistry = require(ReplicatedStorage.Shared.Config.CommerceRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local GENRE_KEY = "Clicker_Farm"
local CLAIM_REMOTE_NAME = RemoteNames.GoldenDropClaim

local MonetizationService: any = nil

local GoldenDropService = {}

-- Lightweight HUD sync: pushes a single {path, value} delta instead of a full
-- UpdateProfileData snapshot (see TopBarController's UpdateResourceValue
-- listener). Set by Start(); nil-safe no-op before then.
local resourceValueRemote: RemoteEvent? = nil

-- One pending drop per player: guid → spawn os.time()
local activeDrops: {[Player]: {[string]: number}} = {}

type GoldenDropConfig = {
	Enabled: boolean,
	SpawnIntervalMin: number,
	SpawnIntervalMax: number,
	DescentDuration: number,
	DescentTolerance: number,
	ImageId: string,
	RewardTiers: {{Name: string, Weight: number, CpsSeconds: number, Floor: number}},
}

local function getConfig(): GoldenDropConfig?
	local dropCfg: any = FeatureResolver.GetConfigField(GENRE_KEY, "GoldenDrop", nil)
	if type(dropCfg) == "table" and dropCfg.Enabled == true then
		return dropCfg :: GoldenDropConfig
	end
	return nil
end

local function ownsPass(player: Player): (string) -> boolean
	return function(passKey: string): boolean
		if MonetizationService then
			return MonetizationService.HasGamepass(player, passKey)
		end
		return false
	end
end

local function rollTier(config: GoldenDropConfig): {Name: string, Weight: number, CpsSeconds: number, Floor: number}
	local totalWeight = 0
	for _, tier in ipairs(config.RewardTiers) do
		totalWeight += tier.Weight
	end

	local roll = math.random(1, math.max(1, totalWeight))
	local accumulated = 0
	for _, tier in ipairs(config.RewardTiers) do
		accumulated += tier.Weight
		if roll <= accumulated then
			return tier
		end
	end
	return config.RewardTiers[1]
end

local function spawnLoopFor(player: Player, config: GoldenDropConfig, spawnRemote: RemoteEvent): ()
	task.spawn(function()
		while player:IsDescendantOf(Players) do
			local waitTime = math.random(config.SpawnIntervalMin, config.SpawnIntervalMax)
			local maxLife = config.DescentDuration + config.DescentTolerance

			-- 1s ticks so missed drops expire promptly and the loop exits fast on leave
			for _ = 1, waitTime do
				task.wait(1)
				if not player:IsDescendantOf(Players) then return end

				local drops = activeDrops[player]
				if drops then
					local now = os.time()
					for guid, spawnTime in pairs(drops) do
						if now - spawnTime > maxLife then
							drops[guid] = nil
						end
					end
				end
			end

			-- Single active drop per player: a new spawn replaces any prior one
			local drops = activeDrops[player]
			if not drops then return end
			table.clear(drops)

			local guid = HttpService:GenerateGUID(false)
			drops[guid] = os.time()
			spawnRemote:FireClient(player, guid)
		end
	end)
end

local function onClaim(player: Player, guid: any): any
	if type(guid) ~= "string" then return nil end

	local config = getConfig()
	if not config then return nil end

	local drops = activeDrops[player]
	if not drops or not drops[guid] then return nil end

	local spawnTime = drops[guid]
	drops[guid] = nil -- consume immediately: double-claims impossible

	if os.time() - spawnTime > config.DescentDuration + config.DescentTolerance then
		return nil
	end

	local data = DataService:GetProfileData(player)
	if not data then return nil end
	if type(data.Currencies) ~= "table" then
		data.Currencies = { Primary = 0, Secondary = 0, Premium = 0 }
	end

	-- Reward scales with current passive income so it stays meaningful at
	-- every progression stage; the Floor only matters for brand-new players.
	local upgrades = if type(data.Upgrades) == "table" then data.Upgrades else {}
	local cps = UpgradeRegistry.ComputeStat(upgrades, "Passive")

	local tier = rollTier(config)
	local incomeMult = CommerceRegistry.GetIncomeMultiplier(ownsPass(player))
	local reward = math.max(1, math.floor(math.max(tier.Floor, tier.CpsSeconds * cps) * incomeMult))

	data.Currencies.Primary += reward
	if resourceValueRemote then
		resourceValueRemote:FireClient(player, {"Currencies", "Primary"}, data.Currencies.Primary)
	end
	if type(data.Stats) ~= "table" then data.Stats = {} end
	data.Stats.GoldenClaims = (data.Stats.GoldenClaims or 0) + 1
	data.Stats.LifetimeEarned = (data.Stats.LifetimeEarned or 0) + reward

	return { Amount = reward, Tier = tier.Name }
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

function GoldenDropService.Init(): ()
	local remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	if not remotes:FindFirstChild(CLAIM_REMOTE_NAME) then
		local rf = Instance.new("RemoteFunction")
		rf.Name = CLAIM_REMOTE_NAME
		rf.Parent = remotes
	end
end

function GoldenDropService.Start(): ()
	local config = getConfig()
	if not config then
		print("[GoldenDropService] GoldenDrop disabled in genre config — idle.")
		return
	end

	MonetizationService = require(ServerScriptService.Server.Services.MonetizationService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	local spawnRemote = remotes:WaitForChild(RemoteNames.GoldenDropSpawn) :: RemoteEvent
	local claimRemote = remotes:WaitForChild(CLAIM_REMOTE_NAME) :: RemoteFunction
	resourceValueRemote = remotes:WaitForChild(RemoteNames.UpdateResourceValue) :: RemoteEvent

	claimRemote.OnServerInvoke = onClaim

	local function onPlayerAdded(player: Player)
		activeDrops[player] = {}
		spawnLoopFor(player, config, spawnRemote)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		activeDrops[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return GoldenDropService
