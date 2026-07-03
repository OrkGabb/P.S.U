--!strict
-- @Author @OrkGabb
-- src/Server/Services/PetService.luau
-- Pet_Simulator genre service: server-authoritative egg hatches (weighted
-- RNG via the shared RollEngine core), pet inventory, equip management and
-- the flat idle income that funds hatches.
--
-- Pets are cosmetic companions only — no stat multipliers anywhere in this
-- service (that economy pattern belongs to Aura_Collector; the brief keeps
-- the two systems deliberately independent).
--
-- Built against the abstract profile schema: balances live in
-- Currencies.Primary, genre state lives in GenreData.Pet_Simulator — the
-- core schema carries no pet fields.
--
-- Equipped-pet replication uses a player attribute ("EquippedPet"): Roblox
-- replicates it to every client automatically (late joiners included), so no
-- sync remotes are needed. PetController listens for the attribute and
-- renders the companion locally on every client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local ServerScriptService = game:GetService("ServerScriptService")

local PetRegistry = require(ReplicatedStorage.Shared.Modules.PetRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)
local DataService = require(ServerScriptService.Server.Services.DataService)
local NetworkService = require(ServerScriptService.Server.Services.NetworkService)

local QuestService: any = nil
local LevelService: any = nil

local GENRE_KEY = "Pet_Simulator"
local EQUIPPED_ATTRIBUTE = "EquippedPet"

local PetService = {}

local hatchCooldowns: {[Player]: number} = {}
local lastIncome: {[Player]: number} = {}

-- ─── Config (SSoT: FeatureToggles.Genres.Pet_Simulator) ──────────────────────

local function cfg(field: string, default: number): number
	return FeatureResolver.GetConfigField(GENRE_KEY, field, default)
end

-- ─── Genre data ───────────────────────────────────────────────────────────────

type PetGenreData = {
	Inventory: {[string]: number},
	Equipped: string,
}

local function getPetData(player: Player): PetGenreData?
	local genreData = DataService:GetGenreData(player, GENRE_KEY)
	if not genreData then
		return nil
	end
	if type(genreData.Inventory) ~= "table" then genreData.Inventory = {} end
	if type(genreData.Equipped) ~= "string" then genreData.Equipped = "None" end
	return genreData :: PetGenreData
end

-- ─── Equip ────────────────────────────────────────────────────────────────────

local function setEquipped(player: Player, petData: PetGenreData, petId: string): ()
	petData.Equipped = petId
	player:SetAttribute(EQUIPPED_ATTRIBUTE, petId)
end

-- ─── Hatch ────────────────────────────────────────────────────────────────────

local function processHatch(player: Player, eggId: any): ()
	if type(eggId) ~= "string" then return end
	local egg = PetRegistry.GetEgg(eggId)
	local engine = PetRegistry.GetEngine(eggId)
	if not egg or not engine then return end

	-- Cooldown (0.2s grace so legitimate requests aren't rejected on ping)
	local now = os.clock()
	if (hatchCooldowns[player] or 0) + cfg("HatchCooldown", 1.0) - 0.2 > now then return end
	hatchCooldowns[player] = now

	local data = DataService:GetProfileData(player)
	local petData = getPetData(player)
	if not data or not petData then return end

	-- Cost / level gate (abstract schema)
	if type(data.Currencies) ~= "table" then
		data.Currencies = { Primary = 0, Secondary = 0, Premium = 0 }
	end
	local level: number = if type(data.Progression) == "table" then (data.Progression.Level or 1) else 1
	if level < egg.LevelReq then return end
	if (data.Currencies.Primary or 0) < egg.HatchCost then return end
	data.Currencies.Primary -= egg.HatchCost

	-- Weighted hatch (no luck modifiers — pets are cosmetic, keep it flat)
	local rolled = engine:Roll()
	local isNew = (petData.Inventory[rolled.Id] or 0) <= 0
	petData.Inventory[rolled.Id] = (petData.Inventory[rolled.Id] or 0) + 1

	-- First pet ever auto-equips so the companion is visible immediately
	if petData.Equipped == "None" or petData.Equipped == "" then
		setEquipped(player, petData, rolled.Id)
	end

	if LevelService then
		LevelService.AddExp(player, cfg("ExpPerHatch", 25))
	end
	if QuestService then
		QuestService.AddProgress(player, "Hatch", 1)
	end

	DataService:SyncFullState(player)
	NetworkService.FireClient(player, RemoteNames.UpdatePetInventory, petData.Inventory, petData.Equipped)
	NetworkService.FireClient(player, RemoteNames.HatchResult, rolled.Id, eggId, isNew)
end

-- ─── Idle income (flat — pets never multiply it) ─────────────────────────────

local function accrueIncome(): ()
	local interval = cfg("IncomeInterval", 1)
	local base = cfg("IncomeBase", 12)
	local now = os.clock()

	for _, player in ipairs(Players:GetPlayers()) do
		local last = lastIncome[player] or now
		if now - last < interval then continue end
		lastIncome[player] = now

		local data = DataService:GetProfileData(player)
		if not data then continue end
		if type(data.Currencies) ~= "table" then continue end
		data.Currencies.Primary = (data.Currencies.Primary or 0) + base
	end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function PetService.Init(): ()
	local remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	for _, name in ipairs({ RemoteNames.HatchRequest, RemoteNames.HatchResult, RemoteNames.PetEquipRequest, RemoteNames.UpdatePetInventory }) do
		if not remotes:FindFirstChild(name) then
			local evt = Instance.new("RemoteEvent")
			evt.Name = name
			evt.Parent = remotes
		end
	end
end

function PetService.Start(): ()
	QuestService = require(ServerScriptService.Server.Services.QuestService)
	LevelService = require(ServerScriptService.Server.Services.LevelService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder

	;(remotes:WaitForChild(RemoteNames.HatchRequest) :: RemoteEvent).OnServerEvent:Connect(processHatch)

	;(remotes:WaitForChild(RemoteNames.PetEquipRequest) :: RemoteEvent).OnServerEvent:Connect(function(player: Player, petId: any)
		if type(petId) ~= "string" then return end
		local petData = getPetData(player)
		if not petData then return end

		if petId == "None" then
			setEquipped(player, petData, "None")
			return
		end
		-- Only owned pets can be equipped
		if (petData.Inventory[petId] or 0) <= 0 then return end
		setEquipped(player, petData, petId)
	end)

	-- Publish equipped state once the profile loads, seed income clocks
	local function onPlayerAdded(player: Player): ()
		lastIncome[player] = os.clock()
		task.spawn(function()
			for _ = 1, 40 do
				local petData = getPetData(player)
				if petData then
					player:SetAttribute(EQUIPPED_ATTRIBUTE, petData.Equipped)
					NetworkService.FireClient(player, RemoteNames.UpdatePetInventory, petData.Inventory, petData.Equipped)
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
		hatchCooldowns[player] = nil
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

return PetService
