--!strict
--@author OrkGabb
--@module WeaponService.luau
--@version 1.0
-- src/Server/Services/WeaponService.luau
-- FPS_Shooter Server Authority: validates hitscan, manages session ammo, enforces anti-exploit.
-- Supports per-weapon config registry, weapon switching, sprint, and slide mechanics.
-- Server-authoritative hitbox zone classification with quadratic distance-based damage falloff.
-- Kill events are forwarded to MatchStatsService.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared  = ReplicatedStorage:WaitForChild("Shared")  :: Folder
local Remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder

local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver")) :: any
local RemoteNames     = require(Shared:WaitForChild("Network"):WaitForChild("RemoteNames"))     :: any

-- ── Types ─────────────────────────────────────────────────────────────────────

type WeaponConfig = {
	DisplayName:        string,
	FireRate:           number,
	BaseDamage:         number,
	MaxAmmo:            number,
	ReloadTime:         number,
	AimFOV:             number,
	ScopeFOV:           number,
	MaxRange:           number,
	HeadshotMultiplier: number,
	LimbMultiplier:     number,
	PelletCount:        number?,
	PelletSpreadDegrees: number?,
	PelletDamage:       number?,
	SpreadDegrees:      number?,
}

type SessionAmmo = {
	current:     number,
	isReloading: boolean,
	reloadId:    number,
}

type PlayerSession = {
	weaponAmmo:    {[string]: SessionAmmo},
	currentWeapon: string,
	isSprinting:   boolean,
	isSliding:     boolean,
	isCrouching:   boolean,
	lastSlideTime: number,
}

-- ── Hitbox Zone Classification ───────────────────────────────────────────────
-- R15 names: Head → HEAD, UpperTorso/LowerTorso → TORSO, everything else → LIMB.
-- Multipliers come from per-weapon config (DDD); these string constants are internal only.

local ZONE_HEAD:  string = "head"
local ZONE_TORSO: string = "torso"
local ZONE_LIMB:  string = "limb"

local HEAD_PARTS:  {[string]: boolean} = { Head = true }
local TORSO_PARTS: {[string]: boolean} = { UpperTorso = true, LowerTorso = true, Torso = true }

local function ClassifyZone(partName: string): string
	if HEAD_PARTS[partName] then
		return ZONE_HEAD
	elseif TORSO_PARTS[partName] then
		return ZONE_TORSO
	end
	return ZONE_LIMB
end

-- ── Config ────────────────────────────────────────────────────────────────────

local fpsConfig: any   = FeatureResolver.GetCategoryConfig("FPS_Shooter")
local MAX_RAY_DISTANCE = 500
local BASE_WALK_SPEED: number
local SLIDE_COOLDOWN:  number
local SLIDE_DURATION:  number
local SLIDE_BOOST:     number
local SPRINT_MULT:     number
local SCOPE_SLOW:      number
local WEAPONS:  {[string]: WeaponConfig}
local WEAPON_ORDER: {string}
local DEFAULT_WEAPON: string

if type(fpsConfig) == "table" then
	BASE_WALK_SPEED = type(fpsConfig.WalkSpeed)           == "number" and fpsConfig.WalkSpeed           or 16
	SPRINT_MULT     = type(fpsConfig.SprintMultiplier)    == "number" and fpsConfig.SprintMultiplier    or 1.75
	SCOPE_SLOW      = type(fpsConfig.ScopeSlowMultiplier) == "number" and fpsConfig.ScopeSlowMultiplier or 0.4
	SLIDE_BOOST     = type(fpsConfig.SlideSpeedBoost)     == "number" and fpsConfig.SlideSpeedBoost     or 28
	SLIDE_DURATION  = type(fpsConfig.SlideDuration)       == "number" and fpsConfig.SlideDuration       or 0.85
	SLIDE_COOLDOWN  = type(fpsConfig.SlideCooldown)       == "number" and fpsConfig.SlideCooldown       or 1.2
	WEAPONS         = type(fpsConfig.Weapons)             == "table"  and fpsConfig.Weapons              or {}
	WEAPON_ORDER    = type(fpsConfig.WeaponOrder)         == "table"  and fpsConfig.WeaponOrder          or {}
	DEFAULT_WEAPON  = type(fpsConfig.DefaultWeapon)       == "string" and fpsConfig.DefaultWeapon        or "AR-GUN"
else
	BASE_WALK_SPEED = 16
	SPRINT_MULT     = 1.75
	SCOPE_SLOW      = 0.4
	SLIDE_BOOST     = 28
	SLIDE_DURATION  = 0.85
	SLIDE_COOLDOWN  = 1.2
	WEAPONS         = {}
	WEAPON_ORDER    = {}
	DEFAULT_WEAPON  = "AR-GUN"
end

-- ── State ─────────────────────────────────────────────────────────────────────

local WeaponService = {}
local isActive      = false

local _sessions:      { [Player]: PlayerSession } = {}
local _lastFireTime:  { [Player]: number }        = {}
local _lastReloadReq: { [Player]: number }        = {}

-- ── Remotes (injected in Init) ─────────────────────────────────────────────────

local fireRemote:            RemoteEvent? = nil
local reloadRemote:          RemoteEvent? = nil
local ammoSyncRemote:        RemoteEvent? = nil
local switchRemote:          RemoteEvent? = nil
local slideRemote:           RemoteEvent? = nil
local sprintRemote:          RemoteEvent? = nil
local hitConfirmRemote:      RemoteEvent? = nil
local headshotConfirmRemote: RemoteEvent? = nil
local crouchRemote:          RemoteEvent? = nil

-- Lazily resolved after both services start — avoids require-order dependency
local _matchStatsService: any = nil

local function GetMatchStats(): any
	if _matchStatsService then return _matchStatsService end
	local ok, svc = pcall(function(): any
		return require(ServerScriptService.Server.Services.MatchStatsService)
	end)
	if ok and svc then
		_matchStatsService = svc
	end
	return _matchStatsService
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function GetRoot(player: Player): BasePart?
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function GetHumanoid(player: Player): Humanoid?
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

local function GetWeaponConfig(key: string): WeaponConfig?
	return WEAPONS[key] :: WeaponConfig?
end

local function SyncAmmo(player: Player, targetWeapon: string?): ()
	local session = _sessions[player]
	if session and ammoSyncRemote then
		local wKey = targetWeapon or session.currentWeapon
		local cfg: WeaponConfig? = GetWeaponConfig(wKey)
		local maxAmmo: number    = cfg and cfg.MaxAmmo or 30
		local currentAmmo: number = session.weaponAmmo[wKey] and session.weaponAmmo[wKey].current or 0
		ammoSyncRemote:FireClient(player, currentAmmo, maxAmmo, wKey)
	end
end

local function InitSession(player: Player): ()
	local weaponAmmo: {[string]: SessionAmmo} = {}
	for key, cfg in pairs(WEAPONS) do
		weaponAmmo[key] = { current = cfg.MaxAmmo or 30, isReloading = false, reloadId = 0 }
	end
	if not weaponAmmo[DEFAULT_WEAPON] then
		local cfg: WeaponConfig? = GetWeaponConfig(DEFAULT_WEAPON)
		weaponAmmo[DEFAULT_WEAPON] = { current = cfg and cfg.MaxAmmo or 30, isReloading = false, reloadId = 0 }
	end

	_sessions[player] = {
		weaponAmmo    = weaponAmmo,
		currentWeapon = DEFAULT_WEAPON,
		isSprinting   = false,
		isSliding     = false,
		isCrouching   = false,
		lastSlideTime = 0,
	}
end

local function ApplyWalkSpeed(player: Player): ()
	local session = _sessions[player]
	if not session then return end
	local h: Humanoid? = GetHumanoid(player)
	if not h then return end

	local speed: number = BASE_WALK_SPEED
	if session.isSliding then
		speed = SLIDE_BOOST
	elseif session.isSprinting then
		speed = BASE_WALK_SPEED * SPRINT_MULT
	end
	h.WalkSpeed = speed
end

-- ── Server-side damage calculation ───────────────────────────────────────────
-- Falloff:     BaseDamage * (1 - clamp(distance, 0, MaxRange) / MaxRange)^2
-- FinalDamage: Falloff * zoneMultiplier  (HEAD = HeadshotMultiplier, LIMB = LimbMultiplier, TORSO = 1.0)

local function ComputeDamage(
	baseDmg:      number,
	maxRange:     number,
	distance:     number,
	zone:         string,
	hsMultiplier: number,
	lbMultiplier: number
): number
	local falloff: number = baseDmg * (1 - math.min(distance, maxRange) / maxRange) ^ 2
	local mult: number = if zone == ZONE_HEAD then hsMultiplier
	                     elseif zone == ZONE_LIMB then lbMultiplier
	                     else 1.0
	return falloff * mult
end

-- Perturbs a unit direction vector by a random angle within angleDeg degrees.
local function PerturbDirection(dir: Vector3, angleDeg: number): Vector3
	if angleDeg <= 0 then return dir end
	local angleRad = math.rad(angleDeg)
	local lookCF = CFrame.lookAt(Vector3.zero, dir)
	local spreadX = (math.random() - 0.5) * 2 * angleRad
	local spreadY = (math.random() - 0.5) * 2 * angleRad
	return (lookCF * CFrame.Angles(spreadX, spreadY, 0)).LookVector
end

-- ── Init ──────────────────────────────────────────────────────────────────────

function WeaponService.Init(): ()
	local config = FeatureResolver.GetCategoryConfig("FPS_Shooter")
	if not (config and config.Enabled) then return end
	isActive = true

	local function MakeRemote(name: string): RemoteEvent
		local existing = Remotes:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing :: RemoteEvent
		end
		local r      = Instance.new("RemoteEvent")
		r.Name       = name
		r.Parent     = Remotes
		return r
	end

	fireRemote            = MakeRemote(RemoteNames.WeaponFire)
	reloadRemote          = MakeRemote(RemoteNames.WeaponReload)
	ammoSyncRemote        = MakeRemote(RemoteNames.WeaponAmmoSync)
	switchRemote          = MakeRemote(RemoteNames.WeaponSwitch)
	slideRemote           = MakeRemote(RemoteNames.SlideRequest)
	sprintRemote          = MakeRemote(RemoteNames.SprintRequest)
	hitConfirmRemote      = MakeRemote(RemoteNames.HitConfirm)
	headshotConfirmRemote = MakeRemote(RemoteNames.HeadshotConfirm)
	crouchRemote          = MakeRemote(RemoteNames.CrouchRequest)

	print("[WeaponService] FPS_Shooter active. Remotes injected.")
end

-- ── Start ─────────────────────────────────────────────────────────────────────

function WeaponService.Start(): ()
	if not isActive then return end

	-- Seed sessions for players already in server (Studio test)
	for _, p in Players:GetPlayers() do
		InitSession(p)
	end

	Players.PlayerAdded:Connect(function(player: Player): ()
		InitSession(player)
	end)

	-- ── Fire Handler ────────────────────────────────────────────────────────────
	-- The server performs its OWN raycast from the shooter's HumanoidRootPart.
	-- Client supplies an aim direction (derived from its camera look vector).
	-- Zone classification and damage are computed entirely server-side.

	if fireRemote then
		fireRemote.OnServerEvent:Connect(function(
			player:        Player,
			aimDirection:  any   -- Vector3 unit direction from client camera look vector
		): ()
			-- Validate payload type
			if typeof(aimDirection) ~= "Vector3" then return end

			local session = _sessions[player]
			if not session then return end
			local activeAmmo = session.weaponAmmo[session.currentWeapon]
			if not activeAmmo then return end
			if activeAmmo.isReloading then return end
			if activeAmmo.current <= 0 then return end

			-- Reject dead players
			local shooterHumanoid: Humanoid? = GetHumanoid(player)
			if not shooterHumanoid or shooterHumanoid.Health <= 0 then return end

			local cfg: WeaponConfig? = GetWeaponConfig(session.currentWeapon)
			local fireRate:          number  = cfg and cfg.FireRate           or 0.1
			local baseDamage:        number  = cfg and cfg.BaseDamage         or 15
			local maxRange:          number  = cfg and cfg.MaxRange            or 500
			local headshotMult:      number  = cfg and cfg.HeadshotMultiplier  or 1.5
			local limbMult:          number  = cfg and cfg.LimbMultiplier       or 0.75
			local pelletCount:       number  = (cfg and cfg.PelletCount)       or 0
			local pelletSpreadDeg:   number  = (cfg and cfg.PelletSpreadDegrees) or 5
			local pelletDamage:      number  = (cfg and cfg.PelletDamage)      or baseDamage
			local spreadDeg:         number  = (cfg and cfg.SpreadDegrees)     or 0
			local isShotgun:         boolean = pelletCount >= 1

			-- Rate-limit
			local now      = os.clock()
			local lastFire = _lastFireTime[player] or 0
			if now - lastFire < (fireRate - 0.05) then return end
			_lastFireTime[player] = now

			-- Shooter origin: HumanoidRootPart + eye height offset
			local root = GetRoot(player)
			if not root then return end
			local origin: Vector3 = root.Position + Vector3.new(0, 1.5, 0)

			-- Sanitize client-supplied direction (must be a unit vector; reject zero or unreasonably large)
			local clientDir: Vector3 = aimDirection :: Vector3
			local dirMag = clientDir.Magnitude
			if dirMag < 0.5 or dirMag > 2 then return end
			local baseDir: Vector3 = clientDir.Unit

			-- Consume ammo
			activeAmmo.current -= 1
			SyncAmmo(player)

			-- RaycastParams: exclude shooter's own character and filter accessories
			-- so hair/hats never block a headshot. We only want character body parts.
			local char = player.Character
			local excludeList: {Instance} = {}
			if char then
				-- Collect all accessories/handles under the character to exclude them
				for _, desc in ipairs(char:GetDescendants()) do
					if desc:IsA("Accessory") or desc:IsA("Hat") then
						table.insert(excludeList, desc)
					end
				end
				table.insert(excludeList, char)
			end

			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = excludeList

			-- Inner function: cast one ray, classify zone, apply damage.
			local function FireOneRay(dir: Vector3): ()
				local hit = workspace:Raycast(origin, dir * MAX_RAY_DISTANCE, rayParams)
				if not hit or not hit.Instance then return end

				local hitPart = hit.Instance
				-- Verify the hit part belongs to a character model with a Humanoid
				local model    = hitPart:FindFirstAncestorOfClass("Model")
				local humanoid = model and model:FindFirstChildOfClass("Humanoid") :: Humanoid?
				if not humanoid or humanoid.Health <= 0 then return end

				-- Prevent team-kill on self (shouldn't happen due to exclude, but guard anyway)
				if model == char then return end

				local zone: string     = ClassifyZone(hitPart.Name)
				local distance: number = (hit.Position - origin).Magnitude

				-- SHOTGUN uses PelletDamage; all others use BaseDamage
				local dmgBase: number = if isShotgun then pelletDamage else baseDamage
				local finalDamage: number = ComputeDamage(
					dmgBase, maxRange, distance, zone, headshotMult, limbMult
				)

				if finalDamage <= 0 then return end

				humanoid:TakeDamage(finalDamage)

				-- Hit confirmation remotes
				if hitConfirmRemote then
					hitConfirmRemote:FireClient(player, zone)
				end
				if zone == ZONE_HEAD and headshotConfirmRemote then
					headshotConfirmRemote:FireClient(player)
				end

				-- Kill detection
				if humanoid.Health <= 0 then
					local victim: Player? = Players:GetPlayerFromCharacter(model)
					local stats = GetMatchStats()
					if stats then
						stats.RecordKill(player, victim)
					end
				end
			end

			if isShotgun then
				-- SHOTGUN: cast PelletCount independent rays, each randomly offset within the cone
				for _ = 1, pelletCount do
					local pelletDir: Vector3 = PerturbDirection(baseDir, pelletSpreadDeg)
					FireOneRay(pelletDir)
				end
			else
				-- Single shot; apply per-shot spread jitter for AR-GUN (SpreadDegrees > 0)
				local shotDir: Vector3 = PerturbDirection(baseDir, spreadDeg)
				FireOneRay(shotDir)
			end
		end)
	end

	-- ── Reload Handler ──────────────────────────────────────────────────────────

	if reloadRemote then
		reloadRemote.OnServerEvent:Connect(function(player: Player): ()
			local session = _sessions[player]
			if not session then return end
			local activeAmmo = session.weaponAmmo[session.currentWeapon]
			if not activeAmmo then return end
			if activeAmmo.isReloading then return end

			local cfg: WeaponConfig? = GetWeaponConfig(session.currentWeapon)
			local maxAmmo:    number = cfg and cfg.MaxAmmo    or 30
			local reloadTime: number = cfg and cfg.ReloadTime or 2.0

			if activeAmmo.current >= maxAmmo then return end

			-- Prevent reload-spam exploit
			local now     = os.clock()
			local lastReq = _lastReloadReq[player] or 0
			if now - lastReq < (reloadTime - 0.1) then return end
			_lastReloadReq[player] = now

			activeAmmo.isReloading = true
			activeAmmo.reloadId = (activeAmmo.reloadId or 0) + 1
			local currentReloadId = activeAmmo.reloadId
			SyncAmmo(player)

			local reloadingWeapon = session.currentWeapon

			task.delay(reloadTime, function(): ()
				local s = _sessions[player]
				if not s then return end
				local aAmmo = s.weaponAmmo[reloadingWeapon]
				if not aAmmo then return end
				if aAmmo.reloadId ~= currentReloadId then return end
				local c2: WeaponConfig? = GetWeaponConfig(reloadingWeapon)
				aAmmo.current     = c2 and c2.MaxAmmo or 30
				aAmmo.isReloading = false
				SyncAmmo(player, reloadingWeapon)
			end)
		end)
	end

	-- ── Weapon Switch Handler ───────────────────────────────────────────────────

	if switchRemote then
		switchRemote.OnServerEvent:Connect(function(player: Player, weaponKey: any): ()
			if type(weaponKey) ~= "string" then return end
			if not WEAPONS[weaponKey] then return end

			local session = _sessions[player]
			if not session then return end

			session.currentWeapon = weaponKey
			if not session.weaponAmmo[weaponKey] then
				local cfg = GetWeaponConfig(weaponKey)
				session.weaponAmmo[weaponKey] = { current = cfg and cfg.MaxAmmo or 30, isReloading = false, reloadId = 0 }
			end
			session.weaponAmmo[weaponKey].isReloading = false

			_lastReloadReq[player] = 0

			SyncAmmo(player)
		end)
	end

	-- ── Sprint Handler ──────────────────────────────────────────────────────────

	if sprintRemote then
		sprintRemote.OnServerEvent:Connect(function(player: Player, sprintingRaw: any): ()
			if type(sprintingRaw) ~= "boolean" then return end
			local session = _sessions[player]
			if not session then return end
			-- Slide takes priority over sprint
			if not session.isSliding then
				session.isSprinting = sprintingRaw :: boolean
				ApplyWalkSpeed(player)
			end
		end)
	end

	-- ── Slide Handler ───────────────────────────────────────────────────────────

	if slideRemote then
		slideRemote.OnServerEvent:Connect(function(player: Player): ()
			local session = _sessions[player]
			if not session then return end
			if session.isSliding then return end

			local now = os.clock()
			if now - session.lastSlideTime < SLIDE_COOLDOWN then return end

			local humanoid: Humanoid? = GetHumanoid(player)
			if not humanoid or humanoid.Health <= 0 then return end

			session.isSliding     = true
			session.isSprinting   = false
			session.lastSlideTime = now

			local originalHipHeight: number = humanoid.HipHeight
			humanoid.HipHeight = 0.5  -- crouch down

			ApplyWalkSpeed(player)

			task.delay(SLIDE_DURATION, function(): ()
				local s = _sessions[player]
				if not s then return end
				s.isSliding = false

				local h: Humanoid? = GetHumanoid(player)
				if h then
					h.HipHeight = s.isCrouching and 0.5 or originalHipHeight
				end
				ApplyWalkSpeed(player)
			end)
		end)
	end

	-- ── Crouch Handler ──────────────────────────────────────────────────────────

	if crouchRemote then
		crouchRemote.OnServerEvent:Connect(function(player: Player, isCrouchingRaw: any): ()
			if type(isCrouchingRaw) ~= "boolean" then return end
			local session = _sessions[player]
			if not session then return end
			if session.isSliding then return end

			session.isCrouching = isCrouchingRaw :: boolean

			local humanoid: Humanoid? = GetHumanoid(player)
			if humanoid then
				if session.isCrouching then
					humanoid.HipHeight = 0.5
				else
					humanoid.HipHeight = 2.0
				end
			end
			ApplyWalkSpeed(player)
		end)
	end
end

-- ── Cleanup ───────────────────────────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player: Player): ()
	_sessions[player]      = nil
	_lastFireTime[player]  = nil
	_lastReloadReq[player] = nil
end)

return WeaponService
