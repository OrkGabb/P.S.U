--!strict
--@author OrkGabb
--@module WeaponController.luau
--@version 1.0
-- src/Client/Controllers/WeaponController.luau
-- FPS_Shooter Client Pipeline.
--
-- Key bindings (final):
--   LMB hold   -> fire only (auto in Full-Auto; burst in Burst; single in Single)
--   RMB hold   -> scope ONLY (tween to ScopeFOV + vignette + slow movement)
--   F key      -> scope toggle (same effect as RMB, press-to-toggle)
--   LeftShift  -> sprint (WalkSpeed boost + FOV bump, no camera CFrame mutation)
--   C key      -> slide (camera FOV push + HipHeight crouch)
--   Z key      -> fire mode cycle (Single -> Burst -> Full-Auto, shown on HUD)
--   R key      -> reload
--   Q key      -> weapon prev
--   E key      -> weapon next
--   Tab key    -> in-match scoreboard (K / D / A) + cursor unlock
--               (cursor re-locks automatically when Tab is released)
--   V key      -> manual cursor toggle (for menu interaction)
--

local ContextActionService = game:GetService("ContextActionService") :: ContextActionService
local ReplicatedStorage    = game:GetService("ReplicatedStorage")    :: ReplicatedStorage
local Players              = game:GetService("Players")              :: Players
local UserInputService     = game:GetService("UserInputService")     :: UserInputService
local TweenService         = game:GetService("TweenService")         :: TweenService
local RunService           = game:GetService("RunService")           :: RunService

local Shared  = ReplicatedStorage:WaitForChild("Shared")  :: Folder
local Remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder

local FeatureResolver      = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver"))     :: any
local RemoteNames          = require(Shared:WaitForChild("Network"):WaitForChild("RemoteNames"))         :: any
local MatchStatsController = require(script.Parent:WaitForChild("MatchStatsController"))                 :: any
local Spring               = require(Shared:WaitForChild("Modules"):WaitForChild("Spring"))               :: any

local LocalPlayer = Players.LocalPlayer :: Player

-- ── Module ────────────────────────────────────────────────────────────────────
local WeaponController = {}

-- ── Config (sourced from FeatureResolver) ─────────────────────────────────────
local fpsConfig:        any    = FeatureResolver.GetCategoryConfig("FPS_Shooter")
local MAX_RAY_DISTANCE: number = 500
-- Crosshair is slightly adjusted to match the aesthetic layout.
local CROSSHAIR_SIZE:   number = 8
local MOBILE_FIRE_BTN_SIZE:   number = 80
local MOBILE_RELOAD_BTN_SIZE: number = 56

local DEFAULT_FOV:    number = 70
local SPRINT_CAM_FOV: number = 76  -- subtle FOV bump while sprinting (no CFrame mutation)

-- Fire mode constants
local FIRE_MODE_SINGLE:    number = 1
local FIRE_MODE_BURST:     number = 2
local FIRE_MODE_FULL_AUTO: number = 3
local BURST_ROUND_COUNT:   number = 3
local BURST_INTER_DELAY:   number = 0.08 -- seconds between burst rounds

-- Scoreboard UI palette
local COLOR_AMBER:       Color3 = Color3.new(1, 0.8, 0)
local COLOR_CYAN:        Color3 = Color3.new(0, 1, 1)
local COLOR_WHITE:       Color3 = Color3.new(1, 1, 1)
local COLOR_DARK_BG:     Color3 = Color3.new(0, 0, 0)
local COLOR_HEADER_BG:   Color3 = Color3.fromRGB(20, 20, 32)
local COLOR_DIVIDER:     Color3 = Color3.fromRGB(255, 204, 0)

local MEDAL_PREFIXES: { [number]: string } = {
	[1] = "\xF0\x9F\xA5\x87 ",
	[2] = "\xF0\x9F\xA5\x88 ",
	[3] = "\xF0\x9F\xA5\x89 ",
}

-- BUG 8 FIX: authoritative fixed array — never derived from pairs() over the Weapons dict.
-- Luau does not guarantee iteration order over dictionaries; any code that called pairs()
-- over fpsConfig.Weapons to build this list would produce a non-deterministic weapon order.
-- This constant is the single source of truth for Q/E cycling AND default spawn equip.
local WEAPON_ORDER: { string } = { "AR-GUN", "PISTOL", "SHOTGUN", "SNIPER" }
local WEAPON_NAMES: { [string]: string } = {}  -- key -> DisplayName

local BASE_WALK_SPEED:    number = 16
local SPRINT_MULT:        number = 1.75
local SCOPE_SLOW_MULT:    number = 0.4
local SLIDE_DURATION:     number = 0.85
local SLIDE_COOLDOWN:     number = 1.2
local DEFAULT_WEAPON_KEY: string = "AR-GUN"

-- Sound IDs from config (resolved at module load)
local currentFireSoundId:     number? = nil
local currentReloadSoundId:   number? = nil
local currentEquipSoundId:    number? = nil
local scopeEnterSoundId:      number? = nil
local scopeExitSoundId:       number? = nil
local hitConfirmSoundId:      number? = nil
local headshotConfirmSoundId: number? = nil

-- Viewmodel config per weapon
local currentViewmodelOffset:   Vector3? = nil
local currentViewmodelRotation: Vector3? = nil

-- Resolve config fields safely at module load time
if type(fpsConfig) == "table" then
	-- WEAPON_ORDER is intentionally NOT overwritten from fpsConfig.WeaponOrder.
	-- The hardcoded constant above is the SSoT; config provides supplemental data only.
	-- This prevents any non-deterministic dictionary-iteration from corrupting cycle order.
	local weaponsRaw: any = fpsConfig.Weapons
	if type(weaponsRaw) == "table" then
		for key: string, wData: any in pairs(weaponsRaw) do
			if type(wData) == "table" and type(wData.DisplayName) == "string" then
				WEAPON_NAMES[key] = wData.DisplayName
			end
		end
	end
	local dwRaw: any = fpsConfig.DefaultWeapon
	if type(dwRaw) == "string" then DEFAULT_WEAPON_KEY = dwRaw end

	local wsRaw: any = fpsConfig.WalkSpeed
	if type(wsRaw) == "number" then BASE_WALK_SPEED = wsRaw end

	local smRaw: any = fpsConfig.SprintMultiplier
	if type(smRaw) == "number" then SPRINT_MULT = smRaw end

	local scopeRaw: any = fpsConfig.ScopeSlowMultiplier
	if type(scopeRaw) == "number" then SCOPE_SLOW_MULT = scopeRaw end

	local slideDurRaw: any = fpsConfig.SlideDuration
	if type(slideDurRaw) == "number" then SLIDE_DURATION = slideDurRaw end

	local slideCoolRaw: any = fpsConfig.SlideCooldown
	if type(slideCoolRaw) == "number" then SLIDE_COOLDOWN = slideCoolRaw end

	-- Global FPS sound IDs
	if type(fpsConfig.ScopeEnterSoundId) == "number" then
		scopeEnterSoundId = fpsConfig.ScopeEnterSoundId :: number
	end
	if type(fpsConfig.ScopeExitSoundId) == "number" then
		scopeExitSoundId = fpsConfig.ScopeExitSoundId :: number
	end
	if type(fpsConfig.HitConfirmSoundId) == "number" then
		hitConfirmSoundId = fpsConfig.HitConfirmSoundId :: number
	end
	if type(fpsConfig.HeadshotConfirmSoundId) == "number" then
		headshotConfirmSoundId = fpsConfig.HeadshotConfirmSoundId :: number
	end
end

-- ── State ─────────────────────────────────────────────────────────────────────
local isActive:        boolean = false
local isCursorLocked:  boolean = false  -- true = LockCenter + no icon; false = Default + icon
local isScoreboardOpen: boolean = false -- true while Tab scoreboard is up
local isReloading:     boolean = false
local currentAmmo:     number  = 30
local maxAmmo:         number  = 30

-- Fire mode (Z key cycle)
local currentFireMode: number  = FIRE_MODE_FULL_AUTO
local isBurstFiring:   boolean = false

-- LMB state (fire only)
local isLmbHeld:    boolean = false
local lastFireTime: number  = 0

-- Per-weapon
local currentWeaponIndex: number = 1
local currentWeaponKey:   string = DEFAULT_WEAPON_KEY
local currentFireRate:    number = 0.1
local currentScopeFOV:    number = 20

-- Sprint
local isSprinting: boolean = false

-- Slide
local isSliding:     boolean = false
local lastSlideTime: number  = 0

-- Scope
local isScoped: boolean = false

-- Remotes
local fireRemote:    RemoteEvent?  = nil
local reloadRemote:  RemoteEvent?  = nil
local switchRemote:  RemoteEvent?  = nil
local slideRemote:   RemoteEvent?  = nil
local sprintRemote:  RemoteEvent?  = nil

-- UI references
local fpsScreenGui:     ScreenGui? = nil
local crosshairUI:      Frame?     = nil
local ammoUI:           TextLabel? = nil
local weaponLabel:      TextLabel? = nil
local fireModeLabel:    TextLabel? = nil

-- Vignette panels
local vignetteTop:     Frame?  = nil
local vignetteBottom:  Frame?  = nil
local vignetteLeft:    Frame?  = nil
local vignetteRight:   Frame?  = nil
local vignetteVisible: boolean = false

-- Scoreboard
local scoreboardFrame:     Frame?          = nil
local scoreboardContainer: ScrollingFrame? = nil

local ViewmodelController = require(script.Parent:WaitForChild("ViewmodelController")) :: any

-- Procedural Viewmodel Sway/Bobbing state
local swaySpring    = Spring.create(5, 50, 4, 4)
local bobbingVector = Vector3.zero
local smoothedVelocity = 0

-- Cached sound instances
local fireSoundInstance:     Sound? = nil
local reloadSoundInstance:   Sound? = nil
local equipSoundInstance:    Sound? = nil
local scopeEnterSoundInst:  Sound? = nil
local scopeExitSoundInst:   Sound? = nil
local hitConfirmSoundInst:  Sound? = nil
local headshotConfirmInst:  Sound? = nil

type WeaponSounds = { FireSound: Sound?, ReloadSound: Sound?, EquipSound: Sound? }
local weaponSoundsCache: { [string]: WeaponSounds } = {}

-- Scope decal
local currentScopeImageId: string? = nil
local scopeImageUI:        ImageLabel? = nil

-- ── Init ──────────────────────────────────────────────────────────────────────
function WeaponController.Init(): ()
	local config: any = FeatureResolver.GetCategoryConfig("FPS_Shooter")
	if config and config.Enabled then
		isActive = true
		print("[WeaponController] FPS_Shooter active.")
	end

	pcall(function()
		game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	if type(fpsConfig) == "table" and type(fpsConfig.Weapons) == "table" then
		local wCfg: any = fpsConfig.Weapons[DEFAULT_WEAPON_KEY]
		if type(wCfg) == "table" then
			currentFireRate  = type(wCfg.FireRate)  == "number" and wCfg.FireRate  or 0.1
			currentScopeFOV  = type(wCfg.ScopeFOV)  == "number" and wCfg.ScopeFOV  or 20
			maxAmmo          = type(wCfg.MaxAmmo)   == "number" and wCfg.MaxAmmo   or 30
			currentAmmo      = maxAmmo

			-- Per-weapon sound/viewmodel
			currentFireSoundId      = type(wCfg.FireSoundId)   == "number" and wCfg.FireSoundId   or nil
			currentReloadSoundId    = type(wCfg.ReloadSoundId) == "number" and wCfg.ReloadSoundId or nil
			currentEquipSoundId     = type(wCfg.EquipSoundId)  == "number" and wCfg.EquipSoundId  or nil
			currentViewmodelOffset   = typeof(wCfg.ViewmodelOffset)   == "Vector3" and wCfg.ViewmodelOffset   or nil
			currentViewmodelRotation = typeof(wCfg.ViewmodelRotation) == "Vector3" and wCfg.ViewmodelRotation or nil
			
			local allowedModes = (type(wCfg.AllowedFireModes) == "table" and #wCfg.AllowedFireModes > 0) and wCfg.AllowedFireModes or {FIRE_MODE_FULL_AUTO}
			local modeAllowed = false
			for _, mode in ipairs(allowedModes) do
				if mode == currentFireMode then
					modeAllowed = true
					break
				end
			end
			if not modeAllowed then
				currentFireMode = allowedModes[1]
			end
		end
	end
end

-- ── HUD Updates ───────────────────────────────────────────────────────────────
local function UpdateAmmoHUD(): ()
	if not ammoUI then return end
	if isReloading then
		ammoUI.Text       = "Reloading..."
		ammoUI.TextColor3 = Color3.fromRGB(255, 200, 50)
	else
		ammoUI.Text       = tostring(currentAmmo) .. " / " .. tostring(maxAmmo)
		ammoUI.TextColor3 = currentAmmo <= 5
			and Color3.fromRGB(255, 80, 80)
			or  COLOR_WHITE
	end
end

local function UpdateWeaponLabel(): ()
	if not weaponLabel then return end
	local displayName: string = WEAPON_NAMES[currentWeaponKey] or currentWeaponKey
	weaponLabel.Text = displayName:upper()
end

local FIRE_MODE_LABELS: { [number]: string } = {
	[FIRE_MODE_SINGLE]    = "SINGLE",
	[FIRE_MODE_BURST]     = "BURST",
	[FIRE_MODE_FULL_AUTO] = "AUTO",
}

local function UpdateFireModeLabel(): ()
	if not fireModeLabel then return end
	fireModeLabel.Text = FIRE_MODE_LABELS[currentFireMode] or "AUTO"
end

-- ── Vignette ──────────────────────────────────────────────────────────────────
local function SetVignetteVisible(visible: boolean): ()
	if vignetteVisible == visible then return end
	vignetteVisible = visible
	local panels: { Frame? } = { vignetteTop, vignetteBottom, vignetteLeft, vignetteRight }
	for _, panel in ipairs(panels) do
		if panel then
			panel.Visible = visible
		end
	end
end

-- ── Sound Helpers ─────────────────────────────────────────────────────────────
local function MakeSound(soundId: number?, parent: Instance): Sound?
	if not soundId then return nil end
	local sound: Sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.Volume  = 0.5
	sound.Parent  = parent
	return sound
end

local function PlaySound(sound: Sound?): ()
	if not sound then return end
	local s: Sound = sound :: Sound
	s:Play()
end

-- ── Cursor State (SSoT) ───────────────────────────────────────────────────────
-- SetCursorLocked is the SINGLE function allowed to write MouseBehavior or
-- MouseIconEnabled anywhere in this controller. No other code path may touch
-- either property directly.
--
-- locked = true  -> LockCenter, icon hidden,  crosshair visible
-- locked = false -> Default,    icon visible, crosshair hidden

local function SetCursorLocked(locked: boolean): ()
	isCursorLocked = locked
	if locked then
		UserInputService.MouseBehavior    = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		if crosshairUI then crosshairUI.Visible = true end
	else
		UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		if crosshairUI then crosshairUI.Visible = false end
	end
end

-- ── Camera Kick (recoil via Humanoid.CameraOffset) ────────────────────────────
local function ApplyCameraKick(): ()
	local char: Model? = LocalPlayer.Character
	if not char then return end
	local humanoid: Humanoid? = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid then return end

	-- Random lateral + vertical kick
	local kickX: number = (math.random() - 0.5) * 0.06
	local kickY: number = 0.08 + math.random() * 0.04
	humanoid.CameraOffset = Vector3.new(kickX, kickY, 0)

	-- Tween back to zero
	local ti: TweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(humanoid, ti, { CameraOffset = Vector3.zero }):Play()
end

-- ── Tracer VFX ────────────────────────────────────────────────────────────────
-- Debug visualization permanently disabled.
local function RenderTrace(_origin: Vector3, _hitPos: Vector3): ()
	-- Disabled: no debug ray renders during normal fire.
	return
end

-- ── Core Fire Logic ───────────────────────────────────────────────────────────
local function ExecuteOneFire(): ()
	if not isCursorLocked then return end  -- cursor unlocked = menu open, don't fire
	if isReloading then return end
	if currentAmmo <= 0 then
		if not isReloading and reloadRemote then
			reloadRemote:FireServer()
			isReloading = true
			UpdateAmmoHUD()
		end
		return
	end

	local now = os.clock()
	if now - lastFireTime < currentFireRate then return end
	lastFireTime = now

	currentAmmo = math.max(0, currentAmmo - 1)
	UpdateAmmoHUD()

	-- Compute aim direction from camera center ray (unit vector)
	-- The server uses this as the raycast direction from the shooter's HRP.
	local camera = workspace.CurrentCamera
	if not camera then return end
	local aimDirection: Vector3 = camera.CFrame.LookVector

	ApplyCameraKick()
	PlaySound(fireSoundInstance)

	-- Client-side visual trace (no debug part rendered; RenderTrace is a no-op)
	local vp     = camera.ViewportSize
	local camRay = camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
	local char   = LocalPlayer.Character
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	if char then rayParams.FilterDescendantsInstances = { char } end
	local result = workspace:Raycast(camRay.Origin, camRay.Direction * MAX_RAY_DISTANCE, rayParams)
	local hitPos: Vector3 = result and result.Position
		or camera.CFrame.Position + camera.CFrame.LookVector * MAX_RAY_DISTANCE
	RenderTrace(camera.CFrame.Position, hitPos)

	if fireRemote then
		-- Send aim direction (unit Vector3). Server does its own authoritative raycast.
		fireRemote:FireServer(aimDirection)
	else
		warn("[WeaponController] WeaponFire remote unavailable -- sandbox mode.")
	end
end

-- Executes a 3-round burst. Re-entry blocked by isBurstFiring.
local function ExecuteBurst(): ()
	if isBurstFiring then return end
	isBurstFiring = true
	for i = 1, BURST_ROUND_COUNT do
		ExecuteOneFire()
		if i < BURST_ROUND_COUNT then
			task.wait(BURST_INTER_DELAY)
		end
	end
	isBurstFiring = false
end

-- ── LMB Handler (fire ONLY) ──────────────────────────────────────────────────
local function HandleFire(
	_: string, state: Enum.UserInputState, _2: InputObject
): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		isLmbHeld = true
		if currentFireMode == FIRE_MODE_SINGLE then
			ExecuteOneFire()
		elseif currentFireMode == FIRE_MODE_BURST then
			task.spawn(ExecuteBurst)
		end
		-- Full-auto: handled in RenderStepped while isLmbHeld = true
	elseif state == Enum.UserInputState.End then
		isLmbHeld = false
	end
	return Enum.ContextActionResult.Sink
end

-- ── Scope ─────────────────────────────────────────────────────────────────────
local function EnterScope(): ()
	if isScoped then return end
	isScoped = true

	local camera = workspace.CurrentCamera
	if not camera then return end
	local ti = TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(camera, ti, { FieldOfView = currentScopeFOV }):Play()

	local char = LocalPlayer.Character
	if char then
		local h = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
		if h then h.WalkSpeed = BASE_WALK_SPEED * SCOPE_SLOW_MULT end
	end

	SetVignetteVisible(true)
	PlaySound(scopeEnterSoundInst)

	if currentScopeImageId and scopeImageUI then
		scopeImageUI.Image   = currentScopeImageId
		scopeImageUI.Visible = true
		if crosshairUI then crosshairUI.Visible = false end
	end
end

local function ExitScope(): ()
	if not isScoped then return end
	isScoped = false

	local camera = workspace.CurrentCamera
	if not camera then return end
	local targetFOV: number = isSprinting and SPRINT_CAM_FOV or DEFAULT_FOV
	local ti = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(camera, ti, { FieldOfView = targetFOV }):Play()

	local char = LocalPlayer.Character
	if char then
		local h = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
		if h then
			h.WalkSpeed = isSprinting and (BASE_WALK_SPEED * SPRINT_MULT) or BASE_WALK_SPEED
		end
	end

	SetVignetteVisible(false)
	PlaySound(scopeExitSoundInst)

	if scopeImageUI then
		scopeImageUI.Visible = false
		if crosshairUI and isCursorLocked then crosshairUI.Visible = true end
	end
end

-- RMB handler -- scope ONLY
local function HandleRmbScope(
	_: string, state: Enum.UserInputState, _2: InputObject
): Enum.ContextActionResult
	if not isCursorLocked then return Enum.ContextActionResult.Pass end
	if state == Enum.UserInputState.Begin then
		EnterScope()
	elseif state == Enum.UserInputState.End then
		ExitScope()
	end
	return Enum.ContextActionResult.Pass
end

-- F key scope toggle
local function HandleScopeFKey(
	_: string, state: Enum.UserInputState, _2: InputObject
): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	if not isCursorLocked then return Enum.ContextActionResult.Pass end
	if isScoped then ExitScope() else EnterScope() end
	return Enum.ContextActionResult.Sink
end

-- ── Reload Handler ────────────────────────────────────────────────────────────
local function TriggerReload(): ()
	if isReloading then return end
	if currentAmmo >= maxAmmo then return end
	isReloading = true
	UpdateAmmoHUD()
	PlaySound(reloadSoundInstance)
	if reloadRemote then reloadRemote:FireServer() end
end

local function HandleReload(
	_: string, state: Enum.UserInputState, _2: InputObject
): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	TriggerReload()
	return Enum.ContextActionResult.Sink
end

-- ── Fire Mode Toggle (Z key) ──────────────────────────────────────────────────
local function HandleFireModeToggle(
	_: string, state: Enum.UserInputState, _2: InputObject
): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	
	local wCfg: any = fpsConfig.Weapons[currentWeaponKey]
	local allowedModes = (wCfg and type(wCfg.AllowedFireModes) == "table" and #wCfg.AllowedFireModes > 0) and wCfg.AllowedFireModes or {FIRE_MODE_FULL_AUTO}

	local currentIndex = 1
	for i, mode in ipairs(allowedModes) do
		if mode == currentFireMode then
			currentIndex = i
			break
		end
	end

	currentIndex = (currentIndex % #allowedModes) + 1
	currentFireMode = allowedModes[currentIndex]

	UpdateFireModeLabel()
	return Enum.ContextActionResult.Sink
end

-- ── Sprint ────────────────────────────────────────────────────────────────────
-- Camera CFrame is NEVER written in RenderStepped -- sprint uses FOV bump only.
local function HandleSprint(
	_: string, state: Enum.UserInputState, _2: InputObject
): Enum.ContextActionResult
	if isScoped or isSliding then return Enum.ContextActionResult.Pass end

	local char = LocalPlayer.Character
	local h: Humanoid? = char and char:FindFirstChildOfClass("Humanoid") :: Humanoid? or nil

	if state == Enum.UserInputState.Begin then
		isSprinting = true
		if h then h.WalkSpeed = BASE_WALK_SPEED * SPRINT_MULT end

		local camera = workspace.CurrentCamera
		if camera and not isScoped then
			local ti = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			TweenService:Create(camera, ti, { FieldOfView = SPRINT_CAM_FOV }):Play()
		end

		if sprintRemote then sprintRemote:FireServer(true) end

	elseif state == Enum.UserInputState.End then
		isSprinting = false
		if h and not isSliding then h.WalkSpeed = BASE_WALK_SPEED end

		local camera = workspace.CurrentCamera
		if camera and not isScoped then
			local ti = TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			TweenService:Create(camera, ti, { FieldOfView = DEFAULT_FOV }):Play()
		end

		if sprintRemote then sprintRemote:FireServer(false) end
	end

	return Enum.ContextActionResult.Pass
end

-- ── Slide ─────────────────────────────────────────────────────────────────────
local function HandleSlide(
	_: string, state: Enum.UserInputState, _2: InputObject
): Enum.ContextActionResult
	local isHoldingShift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)

	if state == Enum.UserInputState.Begin then
		if isScoped then return Enum.ContextActionResult.Pass end

		if isHoldingShift then
			if isSliding then return Enum.ContextActionResult.Sink end
			local now = os.clock()
			if now - lastSlideTime < SLIDE_COOLDOWN then return Enum.ContextActionResult.Sink end

			local char = LocalPlayer.Character
			if not char then return Enum.ContextActionResult.Pass end
			local h: Humanoid? = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
			if not h or h.Health <= 0 then return Enum.ContextActionResult.Pass end

			isSliding     = true
			lastSlideTime = now
			isSprinting   = false

			local camera = workspace.CurrentCamera
			if camera then
				local ti = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				TweenService:Create(camera, ti, { FieldOfView = DEFAULT_FOV + 8 }):Play()
			end

			if slideRemote then slideRemote:FireServer() end

			task.delay(SLIDE_DURATION, function(): ()
				if not isSliding then return end
				isSliding = false

				local camera2 = workspace.CurrentCamera
				if camera2 then
					local ti = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
					TweenService:Create(camera2, ti, { FieldOfView = DEFAULT_FOV }):Play()
				end

				local char2 = LocalPlayer.Character
				if char2 then
					local h2: Humanoid? = char2:FindFirstChildOfClass("Humanoid") :: Humanoid?
					if h2 then
						h2.WalkSpeed = isSprinting and (BASE_WALK_SPEED * SPRINT_MULT) or BASE_WALK_SPEED
					end
				end
			end)
		else
			local crouchRemote = Remotes:FindFirstChild(RemoteNames.CrouchRequest)
			if crouchRemote and crouchRemote:IsA("RemoteEvent") then
				(crouchRemote :: RemoteEvent):FireServer(true)
			end
		end
	elseif state == Enum.UserInputState.End then
		local crouchRemote = Remotes:FindFirstChild(RemoteNames.CrouchRequest)
		if crouchRemote and crouchRemote:IsA("RemoteEvent") then
			(crouchRemote :: RemoteEvent):FireServer(false)
		end
	end

	return Enum.ContextActionResult.Sink
end

-- ── Weapon Switch ─────────────────────────────────────────────────────────────

-- SWITCH TWEEN: 0.175 s total — lower current viewmodel (drop Y by 0.5), then raise new one.
-- TweenService drives a numeric offset fed to ViewmodelController.SetTransitionOffset.
-- No new dependencies; TweenService is already cached at module scope.
local _switchTweenActive: boolean = false

local function RunSwitchTween(onMidpoint: () -> ()): ()
	if _switchTweenActive then
		-- If a switch is already in flight, call midpoint immediately and return.
		onMidpoint()
		return
	end
	_switchTweenActive = true

	-- Phase 1: lower current viewmodel over 0.08 s
	local DROP_DIST: number = -0.55
	-- TweenService can only tween Instance properties; drive manually via task.wait loop.
	local startTime = os.clock()
	local LOWER_DUR: number = 0.08
	local RAISE_DUR: number = 0.09

	-- Use a short coroutine-style loop so we don't block the main thread
	task.spawn(function(): ()
		-- Phase 1: lower
		while true do
			local elapsed = os.clock() - startTime
			if elapsed >= LOWER_DUR then break end
			local t: number = elapsed / LOWER_DUR
			ViewmodelController.SetTransitionOffset(t * DROP_DIST)
			task.wait()
		end
		ViewmodelController.SetTransitionOffset(DROP_DIST)

		-- Midpoint: swap weapon
		onMidpoint()

		-- Phase 2: raise new viewmodel
		local raiseStart = os.clock()
		while true do
			local elapsed = os.clock() - raiseStart
			if elapsed >= RAISE_DUR then break end
			local t: number = elapsed / RAISE_DUR
			ViewmodelController.SetTransitionOffset(DROP_DIST * (1 - t))
			task.wait()
		end
		ViewmodelController.SetTransitionOffset(0)
		_switchTweenActive = false
	end)
end

local function SwitchToIndex(newIndex: number): ()
	if isScoped then
		ExitScope()
	end
	if #WEAPON_ORDER == 0 then return end
	currentWeaponIndex = ((newIndex - 1) % #WEAPON_ORDER) + 1
	currentWeaponKey   = WEAPON_ORDER[currentWeaponIndex]

	isReloading   = false
	isBurstFiring = false
	isLmbHeld     = false

	if type(fpsConfig) == "table" and type(fpsConfig.Weapons) == "table" then
		local wCfg: any = fpsConfig.Weapons[currentWeaponKey]
		if type(wCfg) == "table" then
			currentFireRate  = type(wCfg.FireRate)  == "number" and wCfg.FireRate  or 0.1
			currentScopeFOV  = type(wCfg.ScopeFOV)  == "number" and wCfg.ScopeFOV  or 20
			maxAmmo          = type(wCfg.MaxAmmo)   == "number" and wCfg.MaxAmmo   or 30

			-- Update per-weapon sound/viewmodel config
			currentFireSoundId      = type(wCfg.FireSoundId)   == "number" and wCfg.FireSoundId   or nil
			currentReloadSoundId    = type(wCfg.ReloadSoundId) == "number" and wCfg.ReloadSoundId or nil
			currentEquipSoundId     = type(wCfg.EquipSoundId)  == "number" and wCfg.EquipSoundId  or nil
			currentViewmodelOffset   = typeof(wCfg.ViewmodelOffset)   == "Vector3" and wCfg.ViewmodelOffset   or nil
			currentViewmodelRotation = typeof(wCfg.ViewmodelRotation) == "Vector3" and wCfg.ViewmodelRotation or nil
			currentScopeImageId      = type(wCfg.ScopeImageId) == "string" and wCfg.ScopeImageId or nil

			local allowedModes = (type(wCfg.AllowedFireModes) == "table" and #wCfg.AllowedFireModes > 0) and wCfg.AllowedFireModes or {FIRE_MODE_FULL_AUTO}
			local modeAllowed = false
			for _, mode in ipairs(allowedModes) do
				if mode == currentFireMode then
					modeAllowed = true
					break
				end
			end
			if not modeAllowed then
				currentFireMode = allowedModes[1]
			end
		end
	end

	if switchRemote then switchRemote:FireServer(currentWeaponKey) end
	UpdateWeaponLabel()

	-- Retrieve pre-created sounds from cache
	local sounds = weaponSoundsCache[currentWeaponKey]
	if sounds then
		fireSoundInstance   = sounds.FireSound
		reloadSoundInstance = sounds.ReloadSound
		equipSoundInstance  = sounds.EquipSound
	end

	PlaySound(equipSoundInstance)

	-- Load viewmodel with lower->raise tween (total ~0.175 s)
	local weaponToLoad = currentWeaponKey
	RunSwitchTween(function(): ()
		ViewmodelController.LoadViewmodel(weaponToLoad)
	end)
end

local function FindWeaponIndex(key: string): number
	for i, k in ipairs(WEAPON_ORDER) do
		if k == key then return i end
	end
	return 1
end

local function HandleWeaponPrev(
	_: string, state: Enum.UserInputState, _2: InputObject
): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	SwitchToIndex(currentWeaponIndex - 1)
	return Enum.ContextActionResult.Sink
end

local function HandleWeaponNext(
	_: string, state: Enum.UserInputState, _2: InputObject
): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	SwitchToIndex(currentWeaponIndex + 1)
	return Enum.ContextActionResult.Sink
end

-- ── Cursor Toggle (V key) ────────────────────────────────────────────────────
-- V toggles locked <-> unlocked. SetCursorLocked is the single owner of
-- MouseBehavior and MouseIconEnabled — no other code path writes these directly.
local function HandleCursorToggle(
	_: string, state: Enum.UserInputState, _2: InputObject
): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	SetCursorLocked(not isCursorLocked)
	return Enum.ContextActionResult.Pass
end

-- ── Scoreboard UI ─────────────────────────────────────────────────────────────

local function BuildScoreboardRow(
	parent:        Instance,
	rank:          number,
	displayName:   string,
	kills:         number,
	deaths:        number,
	assists:       number,
	isHeader:      boolean,
	isLocalPlayer: boolean
): ()
	local ROW_HEIGHT: number = isHeader and 30 or 26
	local PADDING_X:  number = 8

	local row              = Instance.new("Frame")
	row.Name               = isHeader and "Header" or ("Row_" .. rank)
	row.Size               = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3   = Color3.fromRGB(255, 255, 255)
	row.BackgroundTransparency = isHeader and 0.9 or 0.95
	row.BorderSizePixel    = 0
	row.LayoutOrder        = isHeader and 0 or rank
	row.Parent             = parent

	if isLocalPlayer and not isHeader then
		local highlight       = Instance.new("UIStroke")
		highlight.Color       = COLOR_CYAN
		highlight.Thickness   = 2
		highlight.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		highlight.Parent      = row
	end

	if isHeader then
		local border             = Instance.new("Frame")
		border.Name              = "HeaderBorder"
		border.Size              = UDim2.new(1, 0, 0, 1)
		border.Position          = UDim2.new(0, 0, 1, -1)
		border.BackgroundColor3  = Color3.fromRGB(255, 255, 255)
		border.BackgroundTransparency = 0.85
		border.BorderSizePixel   = 0
		border.ZIndex            = 202
		border.Parent            = row
	end

	local nameText: string
	if isHeader then
		nameText = "PLAYER"
	else
		local prefix: string = ""
		if not isLocalPlayer then
			prefix = MEDAL_PREFIXES[rank] or ""
		end
		nameText = prefix .. displayName
	end

	local nameLabel              = Instance.new("TextLabel")
	nameLabel.Name               = "NameLabel"
	nameLabel.Size               = UDim2.new(0.52, -PADDING_X, 1, 0)
	nameLabel.Position           = UDim2.new(0, PADDING_X, 0, 0)
	nameLabel.Text               = nameText
	nameLabel.Font               = isHeader and Enum.Font.GothamBlack or Enum.Font.GothamMedium
	nameLabel.TextSize           = isHeader and 12 or 13
	nameLabel.TextColor3         = isHeader and COLOR_AMBER
		or (isLocalPlayer and COLOR_CYAN or COLOR_WHITE)
	nameLabel.TextXAlignment     = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment     = Enum.TextYAlignment.Center
	nameLabel.BackgroundTransparency = 1
	nameLabel.ZIndex             = 202
	nameLabel.ClipsDescendants   = true
	nameLabel.Parent             = row

	local statPositions: { { number } } = {
		{ 0.52, 0.14 },
		{ 0.67, 0.14 },
		{ 0.82, 0.15 },
	}
	local statHeaders: { string } = { "K", "D", "A" }
	local statValues:  { string } = {
		tostring(kills), tostring(deaths), tostring(assists),
	}

	for col = 1, 3 do
		local xStart: number = statPositions[col][1]
		local xWidth: number = statPositions[col][2]

		local sep            = Instance.new("Frame")
		sep.Name             = "Sep_" .. col
		sep.Size             = UDim2.new(0, 1, 0.7, 0)
		sep.Position         = UDim2.new(xStart, 0, 0.15, 0)
		sep.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		sep.BackgroundTransparency = 0.85
		sep.BorderSizePixel  = 0
		sep.ZIndex           = 202
		sep.Parent           = row

		local lbl                    = Instance.new("TextLabel")
		lbl.Name                     = statHeaders[col]
		lbl.Size                     = UDim2.new(xWidth, -2, 1, 0)
		lbl.Position                 = UDim2.new(xStart, 2, 0, 0)
		lbl.Text                     = isHeader and statHeaders[col] or statValues[col]
		lbl.Font                     = isHeader and Enum.Font.GothamBlack or Enum.Font.RobotoMono
		lbl.TextSize                 = isHeader and 12 or 13
		lbl.TextColor3               = isHeader and COLOR_AMBER
			or (isLocalPlayer and COLOR_CYAN or COLOR_WHITE)
		lbl.TextXAlignment           = Enum.TextXAlignment.Center
		lbl.TextYAlignment           = Enum.TextYAlignment.Center
		lbl.BackgroundTransparency   = 1
		lbl.ZIndex                   = 202
		lbl.Parent                   = row
	end
end

local function RefreshScoreboard(): ()
	if not scoreboardContainer then return end

	for _, child in ipairs(scoreboardContainer:GetChildren()) do
		if child:IsA("Frame") and child.LayoutOrder > 0 then
			child:Destroy()
		end
	end

	local entries: any = MatchStatsController.GetScoreboard()
	local localUserId: number = LocalPlayer.UserId

	if #entries == 0 then
		local ph                     = Instance.new("TextLabel")
		ph.Name                      = "Placeholder"
		ph.Size                      = UDim2.new(1, 0, 0, 36)
		ph.BackgroundTransparency    = 1
		ph.Text                      = "Waiting for match data..."
		ph.Font                      = Enum.Font.GothamMedium
		ph.TextSize                  = 13
		ph.TextColor3                = Color3.fromRGB(160, 160, 180)
		ph.TextXAlignment            = Enum.TextXAlignment.Center
		ph.TextYAlignment            = Enum.TextYAlignment.Center
		ph.LayoutOrder               = 1
		ph.ZIndex                    = 202
		ph.Parent                    = scoreboardContainer
		return
	end

	for rank: number, entry: any in ipairs(entries) do
		local isLocal: boolean = (type(entry.UserId) == "number") and (entry.UserId == localUserId)
		BuildScoreboardRow(
			scoreboardContainer,
			rank,
			entry.DisplayName,
			entry.Kills,
			entry.Deaths,
			entry.Assists,
			false,
			isLocal
		)
	end
end

-- SetScoreboardVisible uses SetCursorLocked exclusively — no direct property writes.
local function SetScoreboardVisible(open: boolean): ()
	if not scoreboardFrame then return end
	isScoreboardOpen = open
	scoreboardFrame.Visible = open

	if open then
		SetCursorLocked(false)
		MatchStatsController.FetchScoreboard()
		RefreshScoreboard()
	else
		if isActive then
			SetCursorLocked(true)
		end
	end
end

local function HandleTabScoreboard(
	_: string, state: Enum.UserInputState, _2: InputObject
): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		SetScoreboardVisible(true)
	elseif state == Enum.UserInputState.End then
		SetScoreboardVisible(false)
	end
	return Enum.ContextActionResult.Sink
end

-- ── FPS UI Setup ──────────────────────────────────────────────────────────────
local function SetupFPSUI(): ()
	local pGui     = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local existing = pGui:FindFirstChild("FPSGui")
	if existing then existing:Destroy() end

	local screen          = Instance.new("ScreenGui")
	screen.Name           = "FPSGui"
	screen.ResetOnSpawn   = false
	screen.DisplayOrder   = 100
	screen.IgnoreGuiInset = true
	screen.Parent         = pGui
	fpsScreenGui          = screen

	-- ── Crosshair ────────────────────────────────────────────────────────────

	local dot             = Instance.new("Frame")
	dot.Name              = "Crosshair"
	dot.Size              = UDim2.new(0, CROSSHAIR_SIZE, 0, CROSSHAIR_SIZE)
	dot.Position          = UDim2.new(0.5, 0, 0.5, 0)
	dot.AnchorPoint       = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3  = Color3.fromRGB(0, 255, 0)
	dot.BorderSizePixel   = 0
	dot.ZIndex            = 100
	dot.Parent            = screen
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	crosshairUI = dot

	local hLine                  = Instance.new("Frame")
	hLine.Size                   = UDim2.new(0, 20, 0, 2)
	hLine.Position               = UDim2.new(0.5, 0, 0.5, 0)
	hLine.AnchorPoint            = Vector2.new(0.5, 0.5)
	hLine.BackgroundColor3       = Color3.fromRGB(0, 255, 0)
	hLine.BackgroundTransparency = 0.4
	hLine.BorderSizePixel        = 0
	hLine.ZIndex                 = 99
	hLine.Parent                 = screen

	local vLine                  = Instance.new("Frame")
	vLine.Size                   = UDim2.new(0, 2, 0, 20)
	vLine.Position               = UDim2.new(0.5, 0, 0.5, 0)
	vLine.AnchorPoint            = Vector2.new(0.5, 0.5)
	vLine.BackgroundColor3       = Color3.fromRGB(0, 255, 0)
	vLine.BackgroundTransparency = 0.4
	vLine.BorderSizePixel        = 0
	vLine.ZIndex                 = 99
	vLine.Parent                 = screen

	-- ── Scope Image ──────────────────────────────────────────────────────────

	local sImage                 = Instance.new("ImageLabel")
	sImage.Name                  = "ScopeImage"
	sImage.Size                  = UDim2.new(1, 0, 1, 0)
	sImage.Position              = UDim2.new(0.5, 0, 0.5, 0)
	sImage.AnchorPoint           = Vector2.new(0.5, 0.5)
	sImage.BackgroundTransparency= 1
	sImage.ScaleType             = Enum.ScaleType.Fit
	sImage.Visible               = false
	sImage.ZIndex                = 101
	sImage.Parent                = screen
	scopeImageUI = sImage

	-- ── Ammo label ───────────────────────────────────────────────────────────

	local ammo                   = Instance.new("TextLabel")
	ammo.Name                    = "AmmoLabel"
	ammo.Size                    = UDim2.new(0, 160, 0, 50)
	ammo.Position                = UDim2.new(1, -180, 1, -70)
	ammo.BackgroundTransparency  = 1
	ammo.Text                    = tostring(maxAmmo) .. " / " .. tostring(maxAmmo)
	ammo.Font                    = Enum.Font.GothamBlack
	ammo.TextSize                = 24
	ammo.TextColor3              = COLOR_WHITE
	ammo.TextXAlignment          = Enum.TextXAlignment.Right
	ammo.ZIndex                  = 100
	ammo.Parent                  = screen
	local ammoStroke             = Instance.new("UIStroke")
	ammoStroke.Thickness         = 2
	ammoStroke.Color             = COLOR_DARK_BG
	ammoStroke.Parent            = ammo
	ammoUI = ammo

	-- ── Weapon name label ─────────────────────────────────────────────────────

	local wLabel                 = Instance.new("TextLabel")
	wLabel.Name                  = "WeaponLabel"
	wLabel.Size                  = UDim2.new(0, 160, 0, 30)
	wLabel.Position              = UDim2.new(1, -180, 1, -100)
	wLabel.BackgroundTransparency = 1
	wLabel.Text                  = (WEAPON_NAMES[currentWeaponKey] or currentWeaponKey):upper()
	wLabel.Font                  = Enum.Font.GothamBold
	wLabel.TextSize              = 14
	wLabel.TextColor3            = Color3.fromRGB(200, 200, 255)
	wLabel.TextXAlignment        = Enum.TextXAlignment.Right
	wLabel.ZIndex                = 100
	wLabel.Parent                = screen
	local wStroke                = Instance.new("UIStroke")
	wStroke.Thickness            = 1.5
	wStroke.Color                = COLOR_DARK_BG
	wStroke.Parent               = wLabel
	weaponLabel = wLabel

	-- ── Fire mode label (Z key cycle) ─────────────────────────────────────────

	local fmLabel                = Instance.new("TextLabel")
	fmLabel.Name                 = "FireModeLabel"
	fmLabel.Size                 = UDim2.new(0, 160, 0, 24)
	fmLabel.Position             = UDim2.new(1, -180, 1, -122)
	fmLabel.BackgroundTransparency = 1
	fmLabel.Text                 = FIRE_MODE_LABELS[currentFireMode] or "AUTO"
	fmLabel.Font                 = Enum.Font.GothamBold
	fmLabel.TextSize             = 12
	fmLabel.TextColor3           = COLOR_AMBER
	fmLabel.TextXAlignment       = Enum.TextXAlignment.Right
	fmLabel.ZIndex               = 100
	fmLabel.Parent               = screen
	local fmStroke               = Instance.new("UIStroke")
	fmStroke.Thickness           = 1
	fmStroke.Color               = COLOR_DARK_BG
	fmStroke.Parent              = fmLabel
	fireModeLabel = fmLabel

	-- ── Vignette panels ───────────────────────────────────────────────────────

	local function MakeVignettePanel(
		name:       string,
		size:       UDim2,
		position:   UDim2,
		anchor:     Vector2,
		gradColor0: Color3,
		gradColor1: Color3,
		rotation:   number
	): Frame
		local panel                  = Instance.new("Frame")
		panel.Name                   = name
		panel.Size                   = size
		panel.Position               = position
		panel.AnchorPoint            = anchor
		panel.BackgroundColor3       = gradColor0
		panel.BackgroundTransparency = 0
		panel.BorderSizePixel        = 0
		panel.ZIndex                 = 95
		panel.Visible                = false
		panel.Parent                 = screen

		local grad        = Instance.new("UIGradient")
		grad.Color        = ColorSequence.new({
			ColorSequenceKeypoint.new(0, gradColor0),
			ColorSequenceKeypoint.new(0.6, gradColor0),
			ColorSequenceKeypoint.new(1, gradColor1),
		})
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.6, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		grad.Rotation = rotation
		grad.Parent   = panel

		return panel
	end

	local black = COLOR_DARK_BG

	vignetteTop = MakeVignettePanel(
		"VignetteTop",
		UDim2.new(1, 0, 0.28, 0),
		UDim2.new(0.5, 0, 0, 0),
		Vector2.new(0.5, 0),
		black, black, 180
	)
	vignetteBottom = MakeVignettePanel(
		"VignetteBottom",
		UDim2.new(1, 0, 0.28, 0),
		UDim2.new(0.5, 0, 1, 0),
		Vector2.new(0.5, 1),
		black, black, 0
	)
	vignetteLeft = MakeVignettePanel(
		"VignetteLeft",
		UDim2.new(0.2, 0, 1, 0),
		UDim2.new(0, 0, 0.5, 0),
		Vector2.new(0, 0.5),
		black, black, 90
	)
	vignetteRight = MakeVignettePanel(
		"VignetteRight",
		UDim2.new(0.2, 0, 1, 0),
		UDim2.new(1, 0, 0.5, 0),
		Vector2.new(1, 0.5),
		black, black, 270
	)

	-- ── Scoreboard overlay ────────────────────────────────────────────────────

	local backdrop                    = Instance.new("Frame")
	backdrop.Name                     = "ScoreboardBackdrop"
	backdrop.Size                     = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3         = COLOR_DARK_BG
	backdrop.BackgroundTransparency   = 0.45
	backdrop.BorderSizePixel          = 0
	backdrop.ZIndex                   = 198
	backdrop.Visible                  = false
	backdrop.Parent                   = screen

	local sbBg                        = Instance.new("Frame")
	sbBg.Name                         = "ScoreboardBg"
	sbBg.Size                         = UDim2.new(0, 560, 0, 400)
	sbBg.Position                     = UDim2.new(0.5, 0, 0.5, 0)
	sbBg.AnchorPoint                  = Vector2.new(0.5, 0.5)
	sbBg.BackgroundColor3             = COLOR_DARK_BG
	sbBg.BackgroundTransparency       = 0.25
	sbBg.BorderSizePixel              = 0
	sbBg.ZIndex                       = 200
	sbBg.Visible                      = false
	sbBg.Active                       = true
	sbBg.Parent                       = screen
	scoreboardFrame                   = sbBg

	local capturedBackdrop: Frame = backdrop
	local capturedSbBg:     Frame = sbBg

	task.defer(function(): ()
		capturedSbBg:GetPropertyChangedSignal("Visible"):Connect(function(): ()
			capturedBackdrop.Visible = capturedSbBg.Visible
		end)
	end)

	local sbCorner            = Instance.new("UICorner")
	sbCorner.CornerRadius     = UDim.new(0, 10)
	sbCorner.Parent           = sbBg

	local sbOuterStroke       = Instance.new("UIStroke")
	sbOuterStroke.Color       = Color3.fromRGB(255, 255, 255)
	sbOuterStroke.Thickness   = 1
	sbOuterStroke.Transparency = 0.85
	sbOuterStroke.Parent      = sbBg

	local titleBar                    = Instance.new("Frame")
	titleBar.Name                     = "TitleBar"
	titleBar.Size                     = UDim2.new(1, 0, 0, 44)
	titleBar.BackgroundColor3         = COLOR_DARK_BG
	titleBar.BackgroundTransparency   = 0.25
	titleBar.BorderSizePixel          = 0
	titleBar.ZIndex                   = 201
	titleBar.Parent                   = sbBg

	local titleBarCorner              = Instance.new("UICorner")
	titleBarCorner.CornerRadius       = UDim.new(0, 10)
	titleBarCorner.Parent             = titleBar

	local titleBarCoverBottom         = Instance.new("Frame")
	titleBarCoverBottom.Size          = UDim2.new(1, 0, 0.5, 0)
	titleBarCoverBottom.Position      = UDim2.new(0, 0, 0.5, 0)
	titleBarCoverBottom.BackgroundColor3 = COLOR_DARK_BG
	titleBarCoverBottom.BackgroundTransparency = 0.25
	titleBarCoverBottom.BorderSizePixel = 0
	titleBarCoverBottom.ZIndex        = 201
	titleBarCoverBottom.Parent        = titleBar

	local sbTitle                     = Instance.new("TextLabel")
	sbTitle.Name                      = "Title"
	sbTitle.Size                      = UDim2.new(1, 0, 1, 0)
	sbTitle.BackgroundTransparency    = 1
	sbTitle.Text                      = "MATCH SCOREBOARD"
	sbTitle.Font                      = Enum.Font.GothamBlack
	sbTitle.TextSize                  = 17
	sbTitle.TextColor3                = COLOR_AMBER
	sbTitle.TextXAlignment            = Enum.TextXAlignment.Center
	sbTitle.TextYAlignment            = Enum.TextYAlignment.Center
	sbTitle.ZIndex                    = 202
	sbTitle.Parent                    = titleBar

	local titleDivider                = Instance.new("Frame")
	titleDivider.Size                 = UDim2.new(1, 0, 0, 1)
	titleDivider.Position             = UDim2.new(0, 0, 0, 44)
	titleDivider.BackgroundColor3     = Color3.fromRGB(255, 255, 255)
	titleDivider.BackgroundTransparency = 0.85
	titleDivider.BorderSizePixel      = 0
	titleDivider.ZIndex               = 201
	titleDivider.Parent               = sbBg

	local sbScroll                    = Instance.new("ScrollingFrame")
	sbScroll.Name                     = "ScoreContainer"
	sbScroll.Size                     = UDim2.new(1, -8, 1, -52)
	sbScroll.Position                 = UDim2.new(0, 4, 0, 48)
	sbScroll.BackgroundTransparency   = 1
	sbScroll.ScrollBarThickness       = 3
	sbScroll.ScrollBarImageColor3     = COLOR_AMBER
	sbScroll.BorderSizePixel          = 0
	sbScroll.CanvasSize               = UDim2.new(0, 0, 0, 0)
	sbScroll.AutomaticCanvasSize      = Enum.AutomaticSize.Y
	sbScroll.ZIndex                   = 201
	sbScroll.Parent                   = sbBg
	scoreboardContainer               = sbScroll

	local sbLayout         = Instance.new("UIListLayout")
	sbLayout.Padding       = UDim.new(0, 8)
	sbLayout.SortOrder     = Enum.SortOrder.LayoutOrder
	sbLayout.Parent        = sbScroll

	BuildScoreboardRow(sbScroll, 0, "PLAYER", 0, 0, 0, true, false)

	MatchStatsController.OnUpdate(function(): ()
		if isScoreboardOpen then
			RefreshScoreboard()
		end
	end)
end

-- ── Start ─────────────────────────────────────────────────────────────────────
function WeaponController.Start(): ()
	if not isActive then
		local pGui = LocalPlayer:FindFirstChild("PlayerGui")
		if pGui then
			local g = pGui:FindFirstChild("FPSGui")
			if g then g:Destroy() end
		end
		return
	end

	SetupFPSUI()

	currentWeaponIndex = FindWeaponIndex(DEFAULT_WEAPON_KEY)
	UpdateWeaponLabel()
	UpdateFireModeLabel()

	-- Lock cursor via SSoT function; do NOT write MouseBehavior directly.
	SetCursorLocked(true)

	local function TryResolve(name: string): RemoteEvent?
		local r = Remotes:FindFirstChild(name)
		return (r and r:IsA("RemoteEvent")) and r :: RemoteEvent or nil
	end

	fireRemote   = TryResolve(RemoteNames.WeaponFire)
	reloadRemote = TryResolve(RemoteNames.WeaponReload)
	switchRemote = TryResolve(RemoteNames.WeaponSwitch)
	slideRemote  = TryResolve(RemoteNames.SlideRequest)
	sprintRemote = TryResolve(RemoteNames.SprintRequest)

	task.spawn(function(): ()
		local function WaitRemote(name: string): RemoteEvent?
			local r = Remotes:WaitForChild(name, 8)
			return (r and r:IsA("RemoteEvent")) and r :: RemoteEvent or nil
		end
		if not fireRemote   then fireRemote   = WaitRemote(RemoteNames.WeaponFire)    end
		if not reloadRemote then reloadRemote = WaitRemote(RemoteNames.WeaponReload)  end
		if not switchRemote then switchRemote = WaitRemote(RemoteNames.WeaponSwitch)  end
		if not slideRemote  then slideRemote  = WaitRemote(RemoteNames.SlideRequest)  end
		if not sprintRemote then sprintRemote = WaitRemote(RemoteNames.SprintRequest) end
		if not fireRemote then
			warn("[WeaponController] WeaponFire remote not found after 8s -- sandbox mode.")
		end
	end)

	-- AmmoSync: server is authoritative for ammo state
	task.spawn(function(): ()
		local syncRemote = Remotes:WaitForChild(RemoteNames.WeaponAmmoSync, 8)
		if not (syncRemote and syncRemote:IsA("RemoteEvent")) then return end
		;(syncRemote :: RemoteEvent).OnClientEvent:Connect(
			function(serverCurrent: number, serverMax: number, weaponKey: string?): ()
				if weaponKey and weaponKey ~= currentWeaponKey then return end
				currentAmmo = serverCurrent
				maxAmmo     = serverMax
				if serverCurrent >= serverMax then
					isReloading = false
				end
				UpdateAmmoHUD()
			end
		)
	end)

	-- HitConfirm: server -> client (hit feedback with zone)
	task.spawn(function(): ()
		local hitRemote = Remotes:WaitForChild(RemoteNames.HitConfirm, 8)
		if not (hitRemote and hitRemote:IsA("RemoteEvent")) then return end
		;(hitRemote :: RemoteEvent).OnClientEvent:Connect(
			function(zone: string): ()
				if zone == "head" then
					PlaySound(headshotConfirmInst)
				else
					PlaySound(hitConfirmSoundInst)
				end
			end
		)
	end)

	-- Initialize sounds for all weapons and global sounds
	task.defer(function(): ()
		local cam: Camera? = workspace.CurrentCamera
		if not cam then return end
		local camInst: Instance = cam :: Instance

		if type(fpsConfig) == "table" and type(fpsConfig.Weapons) == "table" then
			for wKey: string, wCfg: any in pairs(fpsConfig.Weapons) do
				if type(wCfg) == "table" then
					weaponSoundsCache[wKey] = {
						FireSound   = MakeSound(type(wCfg.FireSoundId)   == "number" and wCfg.FireSoundId   or nil, camInst),
						ReloadSound = MakeSound(type(wCfg.ReloadSoundId) == "number" and wCfg.ReloadSoundId or nil, camInst),
						EquipSound  = MakeSound(type(wCfg.EquipSoundId)  == "number" and wCfg.EquipSoundId  or nil, camInst),
					}
				end
			end
		end

		local initialSounds = weaponSoundsCache[DEFAULT_WEAPON_KEY]
		if initialSounds then
			fireSoundInstance   = initialSounds.FireSound
			reloadSoundInstance = initialSounds.ReloadSound
			equipSoundInstance  = initialSounds.EquipSound
		end

		scopeEnterSoundInst  = MakeSound(scopeEnterSoundId,      camInst)
		scopeExitSoundInst   = MakeSound(scopeExitSoundId,       camInst)
		hitConfirmSoundInst  = MakeSound(hitConfirmSoundId,      camInst)
		headshotConfirmInst  = MakeSound(headshotConfirmSoundId, camInst)
	end)

	local function cleanupCharacter(char: Model): ()
		for _, desc in ipairs(char:GetDescendants()) do
			if desc:IsA("SelectionBox") or desc:IsA("BoxHandleAdornment") or (desc:IsA("BillboardGui") and (desc.Name == "ZoneDebug" or desc.Name == "HitboxDebug")) then
				desc:Destroy()
			elseif desc:IsA("BasePart") and (desc.Name == "ZoneDebug" or desc.Name == "HitboxDebug" or string.find(desc.Name, "Visualizer")) then
				desc:Destroy()
			end
		end
	end

	local function onPlayerAdded(player: Player): ()
		player.CharacterAdded:Connect(cleanupCharacter)
		if player.Character then
			cleanupCharacter(player.Character)
		end
	end

	-- Clean up debug markers for all players
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	-- Load initial viewmodel
	task.spawn(function(): ()
		ViewmodelController.LoadViewmodel(DEFAULT_WEAPON_KEY)
	end)

	-- Reload equipped weapon viewmodel on local player respawn and clean up markers
	LocalPlayer.CharacterAdded:Connect(function(char: Model): ()
		cleanupCharacter(char)
		task.defer(function(): ()
			ViewmodelController.LoadViewmodel(currentWeaponKey)
		end)
	end)

	-- ── Input bindings ──────────────────────────────────────────────────────

	-- LMB -- fire ONLY (no ADS)
	ContextActionService:BindAction("WeaponFire", HandleFire, true, Enum.UserInputType.MouseButton1)
	ContextActionService:SetTitle("WeaponFire", "FIRE")
	ContextActionService:SetImage("WeaponFire", "rbxassetid://6034281037")

	-- RMB -- scope only
	ContextActionService:BindAction("WeaponScope", HandleRmbScope, false, Enum.UserInputType.MouseButton2)

	-- F -- alternate scope toggle
	ContextActionService:BindAction("ScopeFKey", HandleScopeFKey, false, Enum.KeyCode.F)

	-- R -- reload
	ContextActionService:BindAction("WeaponReload", HandleReload, true, Enum.KeyCode.R)
	ContextActionService:SetTitle("WeaponReload", "R")

	-- Z -- fire mode cycle (Single -> Burst -> Full-Auto)
	ContextActionService:BindAction("FireModeToggle", HandleFireModeToggle, false, Enum.KeyCode.Z)

	-- LeftShift -- sprint
	ContextActionService:BindAction("Sprint", HandleSprint, false, Enum.KeyCode.LeftShift)

	-- C -- slide
	ContextActionService:BindAction("Slide", HandleSlide, false, Enum.KeyCode.C)

	-- Q -- weapon prev
	ContextActionService:BindAction("WeaponPrev", HandleWeaponPrev, false, Enum.KeyCode.Q)

	-- E -- weapon next
	ContextActionService:BindAction("WeaponNext", HandleWeaponNext, false, Enum.KeyCode.E)

	-- Tab -- scoreboard (also drives cursor lock/unlock)
	ContextActionService:BindAction("Scoreboard", HandleTabScoreboard, false, Enum.KeyCode.Tab)

	-- V -- manual cursor toggle
	ContextActionService:BindAction("CursorToggle", HandleCursorToggle, false, Enum.KeyCode.V)

	-- ── Mobile button sizing ─────────────────────────────────────────────────
	task.defer(function(): ()
		local fireBtn = ContextActionService:GetButton("WeaponFire")
		if fireBtn then
			fireBtn.Size                   = UDim2.new(0, MOBILE_FIRE_BTN_SIZE, 0, MOBILE_FIRE_BTN_SIZE)
			fireBtn.Position               = UDim2.new(1, -(MOBILE_FIRE_BTN_SIZE + 20), 1, -(MOBILE_FIRE_BTN_SIZE + 30))
			fireBtn.BackgroundColor3       = Color3.fromRGB(200, 50, 50)
			fireBtn.BackgroundTransparency = 0.3
			local c        = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent       = fireBtn
		end
		local reloadBtn = ContextActionService:GetButton("WeaponReload")
		if reloadBtn then
			reloadBtn.Size     = UDim2.new(0, MOBILE_RELOAD_BTN_SIZE, 0, MOBILE_RELOAD_BTN_SIZE)
			reloadBtn.Position = UDim2.new(
				1, -(MOBILE_FIRE_BTN_SIZE + MOBILE_RELOAD_BTN_SIZE + 40),
				1, -(MOBILE_RELOAD_BTN_SIZE + 40)
			)
			reloadBtn.BackgroundColor3       = Color3.fromRGB(60, 60, 80)
			reloadBtn.BackgroundTransparency = 0.3
			local c        = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent       = reloadBtn
		end
	end)

	-- ── RenderStepped ───────────────────────────────────────────────────────
	-- SetCursorLocked is the ONLY path that writes MouseBehavior or MouseIconEnabled.
	-- RenderStepped does NOT touch those properties directly.
	RunService.RenderStepped:Connect(function(dt: number): ()
		if not isActive then return end

		-- Re-assert lock each frame when the cursor should be locked.
		-- This defends against Roblox engine resets (e.g., character respawn)
		-- without bypassing the scoreboard unlock.
		-- SetCursorLocked is the ONLY path that may change these properties.
		if isCursorLocked then
			SetCursorLocked(true)
		end

		-- Full-auto continuous fire while LMB held
		if isLmbHeld and currentFireMode == FIRE_MODE_FULL_AUTO and isCursorLocked then
			ExecuteOneFire()
		end

		-- Procedural viewmodel sway/bobbing (drives ViewmodelController's model via PivotTo)
		local cam = workspace.CurrentCamera
		if not cam then return end

		local char = LocalPlayer.Character
		local speed = 0
		if char then
			local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart then
				speed = rootPart.AssemblyLinearVelocity.Magnitude
			end
		end
		smoothedVelocity = math.lerp(smoothedVelocity, speed, 0.1)

		local t = os.clock()
		local mega = 7.85398
		local amplitude = 0.12
		local speedmod = if smoothedVelocity / 16 > 1.5 then 2 else 1
		local bobX = -math.cos(t * mega * speedmod)
		local bobY = 1 - (bobX * bobX)
		bobX = -bobX * amplitude * (smoothedVelocity / 16)
		bobY = -bobY * amplitude * (smoothedVelocity / 16)
		bobbingVector = bobbingVector:Lerp(Vector3.new(bobX, bobY, 0), 0.2)

		local md = UserInputService:GetMouseDelta()
		swaySpring:shove(Vector3.new(md.Y, md.X, 0) * 0.05)
		local sway = swaySpring:update(dt)

		-- Build combined camera-relative CFrame for the viewmodel
		local camcf = cam.CFrame
		local offset   = currentViewmodelOffset   or Vector3.zero
		local rotation = currentViewmodelRotation or Vector3.zero

		camcf = camcf * CFrame.new(offset)
		camcf = camcf * CFrame.new(bobbingVector)
		camcf = camcf * CFrame.Angles(
			math.rad(rotation.X),
			math.rad(rotation.Y),
			math.rad(rotation.Z)
		)
		camcf = camcf * CFrame.new(0, 0, -4)
		camcf = camcf * CFrame.Angles(
			math.rad(-sway.X / 25),
			math.rad(-sway.Y / 25),
			0
		)
		camcf = camcf * CFrame.new(0, 0, 4)

		-- ViewmodelController owns activeViewmodel; update it here via its own render connection.
		-- (ViewmodelController's RenderStepped does the PivotTo from its AimOffset.
		--  The sway/bob logic here is a secondary pass; override its result.)
		-- Note: ViewmodelController's render loop uses AimOffset only.
		-- The sway/bob transform overrides it by pivoting the model directly.
		local activeVm: any = ViewmodelController
		if type(activeVm.GetActiveViewmodel) == "function" then
			local vm: Model? = activeVm.GetActiveViewmodel()
			if vm and vm.PrimaryPart then
				vm:PivotTo(camcf)
			end
		end
	end)

	print("[WeaponController] Input bound. LMB-fire, RMB-scope, F-scope, Z-firemode, sprint, slide, Q/E-switch, Tab-scoreboard, V-cursor.")
end

return WeaponController
