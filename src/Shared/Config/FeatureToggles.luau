--!strict
--@author OrkGabb
--@module FeatureToggles.luau
--@version 1.0
-- src/Shared/Config/FeatureToggles.luau
-- Central configuration registry for active sub-genre frameworks and global feature flags.

local RunService = game:GetService("RunService")

export type DebugConfigType = {
	Enabled: boolean,
	MockDataStores: boolean,
	DrawPhysicsVectors: boolean,
	ExposeAntiCheatState: boolean,
	BypassCooldowns: boolean,
	VerboseLogging: boolean,
}

export type DashConfigType = {
	Enabled: boolean,
	ActiveAnimationKey: string,
	Cooldown: number,
	Force: number,
	MaxCharges: number,
	DesktopKeybinds: {Enum.KeyCode},
	MobileEnabled: boolean,
}

export type BrandingConfigType = {
	GameName: string,
	Subtitle: string,
}

export type PhysicalLeaderboardConfigType = {
	Enabled: boolean,
	Position: Vector3,
}

export type AntiExploitConfigType = {
	Enabled: boolean,
	TeleportThreshold: number,
	MaxSuspicionFlags: number,
	FlyCheckInterval: number,
}

export type FPSWeaponConfig = {
	DisplayName: string,
	FireRate: number,
	-- BaseDamage: damage at point-blank range (0 studs), TORSO zone.
	-- For SHOTGUN this is PelletDamage per pellet; BaseDamage is unused.
	BaseDamage: number,
	MaxAmmo: number,
	ReloadTime: number,
	AimFOV: number,
	ScopeFOV: number,
	NoAds: boolean?,
	-- Effective range: damage reaches 0 beyond this distance (studs)
	MaxRange: number,
	-- Zone multipliers applied AFTER falloff
	HeadshotMultiplier: number,
	LimbMultiplier: number,
	-- Shotgun: PelletCount raycasts per trigger pull, each within PelletSpreadDegrees half-angle cone
	PelletCount: number?,
	PelletSpreadDegrees: number?,
	-- Per-pellet base damage for SHOTGUN (replaces BaseDamage when PelletCount is set)
	PelletDamage: number?,
	-- AR-GUN: random angular jitter per shot (degrees, 0 = no spread)
	SpreadDegrees: number?,
	AllowedFireModes: {number}?,
	-- Viewmodel: folder name under ReplicatedStorage.Viewmodels
	ViewmodelFolderName: string?,
	ViewmodelAssetId: number?,
	ViewmodelOffset: Vector3?,
	ViewmodelRotation: Vector3?,
	AimOffset: Vector3?,
	SwayAmount: number?,
	BobAmount: number?,
	EquipTime: number?,
	-- Sound asset IDs (rbxassetid numeric portion)
	FireSoundId: number?,
	ReloadSoundId: number?,
	EquipSoundId: number?,
	HeadshotSoundId: number?,
	-- Decal asset ID (rbxassetid URL) for scope overlay
	ScopeImageId: string?,
}

export type FPSConfigType = {
	Enabled: boolean,
	Weapons: {[string]: FPSWeaponConfig},
	DefaultWeapon: string,
	WeaponOrder: {string},
	WalkSpeed: number,
	SprintMultiplier: number,
	ScopeSlowMultiplier: number,
	SlideSpeedBoost: number,
	SlideDuration: number,
	SlideHipHeight: number,
	SlideCooldown: number,
	-- Global FPS sound IDs
	ScopeEnterSoundId: number?,
	ScopeExitSoundId: number?,
	HitConfirmSoundId: number?,
	HeadshotConfirmSoundId: number?,
}

export type MatchStatsConfigType = {
	Enabled: boolean,
	SyncDebounce: number,
}

export type SystemConfigType = {
	Enabled: boolean,
	[string]: any,
}

export type PortalBiomeConfig = {
	BiomeId: string,
	Offset: Vector3,
	DisplayName: string,
	Color: Color3,
	ActionText: string,
	SpawnPosition: Vector3?,
}

export type PortalsConfigType = {
	Enabled: boolean,
	Configs: {PortalBiomeConfig},
}

export type LeaderboardBoardConfig = {
	Key: string,
	DataField: string,
	DisplayName: string,
	Offset: Vector3,
	ColorPrimary: Color3,
	ColorAccent: Color3,
	Icon: string,
	FormatType: string,
}

export type LeaderboardsConfigType = {
	Enabled: boolean,
	Boards: {LeaderboardBoardConfig},
}

export type GlobalFlagsType = {
	Dash: DashConfigType,
	Forge: {
		Enabled: boolean,
	},
	PhysicalLeaderboard: PhysicalLeaderboardConfigType,
	AntiExploit: AntiExploitConfigType,
}

export type GenresType = {
	FPS_Shooter: FPSConfigType,
	Clicker_Farm: SystemConfigType,
	Pet_Simulator: SystemConfigType,
	RPG_Adventure: SystemConfigType,
}

export type FeatureTogglesType = {
	FrameworkVersion: string,
	GlobalFlags: GlobalFlagsType,
	DebugConfig: DebugConfigType,
	Monetization: SystemConfigType,
	VFX: SystemConfigType,
	Pets: SystemConfigType,
	Portals: PortalsConfigType,
	Genres: GenresType,
	Leaderboards: LeaderboardsConfigType,
	MatchStats: MatchStatsConfigType,
	Admin: SystemConfigType,
	Branding: BrandingConfigType,
}

local FeatureToggles: FeatureTogglesType = {
	FrameworkVersion = "ModularFramework Core v1.0.0",

	-- ─── Global Safety Flags ──────────────────────────────────────────────────
	GlobalFlags = {
		-- Q and LeftShift are now owned by WeaponController (weapon-cycle and sprint).
		-- Dash is remapped to LeftControl.
		Dash = {
			Enabled = false,
			ActiveAnimationKey = "DashForward",
			Cooldown = 2.0,
			Force = 50.0,
			MaxCharges = 3,
			DesktopKeybinds = { Enum.KeyCode.LeftControl },
			MobileEnabled = true,
		},
		Forge = {
			Enabled = false,
		},
		PhysicalLeaderboard = {
			Enabled = false,
			Position = Vector3.new(175.8, 33.65, 12.6),
		},
		AntiExploit = {
			Enabled = true,
			TeleportThreshold = 50,   -- studs per heartbeat; flag if exceeded
			MaxSuspicionFlags = 3,    -- flags before kick
			FlyCheckInterval  = 3.0,  -- seconds of sustained airtime before flag
		},
	},

	Branding = {
		GameName = "YOUR PROJECT",
		Subtitle = "FRAMEWORK CORE ACTIVE",
	},

	DebugConfig = {
		Enabled = true,
		MockDataStores = true,
		DrawPhysicsVectors = false,
		ExposeAntiCheatState = true,
		BypassCooldowns = true,
		VerboseLogging = true,
	},

	Monetization = {
		Enabled = false,
	},

	Admin = {
		Enabled = false,
	},

	VFX = {
		Enabled = true,
	},

	Pets = {
		Enabled = false,
	},

	Portals = {
		Enabled = false,
		Configs = {
			{
				BiomeId = "Blossom",
				Offset = Vector3.new(-5, 0, 0),
				DisplayName = "Blossom Realm",
				Color = Color3.fromRGB(255, 180, 200),
				ActionText = "Enter Portal",
				SpawnPosition = Vector3.new(233.122, 1251.8, 53.865),
			},
			{
				BiomeId = "AbyssalRift",
				Offset = Vector3.new(5, 0, 0),
				DisplayName = "Abyssal Rift",
				Color = Color3.fromRGB(120, 30, 220),
				ActionText = "Enter Portal",
				SpawnPosition = nil,
			},
		},
	},

	-- ─── Exclusivity Genres ───────────────────────────────────────────────────
	Genres = {
		FPS_Shooter = {
			Enabled = true,

			-- ── Per-weapon registry (server-authoritative) ────────────────────
			-- FireRate:            minimum seconds between shots (lower = faster)
			-- BaseDamage:          damage at 0 studs, TORSO zone (SHOTGUN: unused, see PelletDamage)
			-- MaxRange:            studs at which damage reaches 0; falloff is quadratic
			-- HeadshotMultiplier:  applied to final damage after falloff when zone = HEAD
			-- LimbMultiplier:      applied to final damage after falloff when zone = LIMB
			-- SpreadDegrees:       max angular jitter per shot (AR-GUN only; 0 = laser-precise)
			-- PelletCount:         number of raycasts per trigger pull (SHOTGUN only)
			-- PelletSpreadDegrees: half-angle of the pellet cone in degrees (SHOTGUN only)
			-- PelletDamage:        per-pellet base damage at 0 studs (SHOTGUN only)
			-- ViewmodelFolderName: child name under ReplicatedStorage.Viewmodels
			Weapons = {
				-- key must match ReplicatedStorage.Viewmodels child name via ViewmodelFolderName
				["AR-GUN"] = {
					DisplayName         = "AR-GUN",
					FireRate             = 0.08,
					BaseDamage           = 17,
					MaxAmmo              = 45,
					ReloadTime           = 2.5,
					AimFOV               = 50,
					ScopeFOV             = 40,
					NoAds                = false,
					MaxRange             = 100,
					HeadshotMultiplier   = 2.0,
					LimbMultiplier       = 0.75,
					SpreadDegrees        = 1.2,
					AllowedFireModes     = {1, 3},
					PelletCount          = nil,
					PelletSpreadDegrees  = nil,
					PelletDamage         = nil,
					ViewmodelFolderName  = "AR-GUN",
					ViewmodelAssetId     = 4842207161,
					ViewmodelOffset      = Vector3.new(0.3, -0.4, -1.2),
					ViewmodelRotation    = Vector3.new(0, 180, 0),
					AimOffset            = Vector3.new(0, -0.2, -1.0),
					SwayAmount           = 0.1,
					BobAmount            = 0.2,
					EquipTime            = 0.5,
					FireSoundId          = 168436671,
					ReloadSoundId        = 3742928054,
					EquipSoundId         = 3742927091,
					HeadshotSoundId      = nil,
					ScopeImageId         = "rbxassetid://134518326226050",
				},
				["SNIPER"] = {
					DisplayName         = "SNIPER",
					FireRate             = 1.2,
					BaseDamage           = 95,
					MaxAmmo              = 5,
					ReloadTime           = 3.5,
					AimFOV               = 30,
					ScopeFOV             = 10,
					NoAds                = true,
					MaxRange             = 250,
					HeadshotMultiplier   = 1.3,
					LimbMultiplier       = 0.75,
					SpreadDegrees        = 0,
					AllowedFireModes     = {1},
					PelletCount          = nil,
					PelletSpreadDegrees  = nil,
					PelletDamage         = nil,
					ViewmodelFolderName  = "SNIPER",
					ViewmodelAssetId     = 4842218829,
					ViewmodelOffset      = Vector3.new(0, -0.3, -1),
					ViewmodelRotation    = Vector3.new(0, 180, 0),
					AimOffset            = Vector3.new(0, 0, -0.5),
					SwayAmount           = 0.2,
					BobAmount            = 0.1,
					EquipTime            = 0.8,
					FireSoundId          = 492961938,
					ReloadSoundId        = 138084889,
					EquipSoundId         = 3666863095,
					HeadshotSoundId      = nil,
					ScopeImageId         = "rbxassetid://137293153903333",
				},
				["PISTOL"] = {
					DisplayName         = "PISTOL",
					FireRate             = 0.25,
					BaseDamage           = 26,
					MaxAmmo              = 12,
					ReloadTime           = 1.5,
					AimFOV               = 55,
					ScopeFOV             = 45,
					NoAds                = true,
					MaxRange             = 70,
					HeadshotMultiplier   = 2.2,
					LimbMultiplier       = 0.75,
					SpreadDegrees        = 0,
					AllowedFireModes     = {1},
					PelletCount          = nil,
					PelletSpreadDegrees  = nil,
					PelletDamage         = nil,
					ViewmodelFolderName  = "PISTOL",
					ViewmodelAssetId     = 4842197274,
					ViewmodelOffset      = Vector3.new(0.2, -0.3, -0.8),
					ViewmodelRotation    = Vector3.new(0, 180, 0),
					AimOffset            = Vector3.new(0, -0.1, -0.6),
					SwayAmount           = 0.15,
					BobAmount            = 0.25,
					EquipTime            = 0.3,
					FireSoundId          = 4502821590,
					ReloadSoundId        = 138084889,
					EquipSoundId         = 8217058484,
					HeadshotSoundId      = nil,
					ScopeImageId         = nil,
				},
				["SHOTGUN"] = {
					DisplayName         = "SHOTGUN",
					FireRate             = 0.65,
					BaseDamage           = 0,         -- unused for SHOTGUN; see PelletDamage
					MaxAmmo              = 8,
					ReloadTime           = 2.8,
					AimFOV               = 58,
					ScopeFOV             = 48,
					NoAds                = false,
					MaxRange             = 30,
					HeadshotMultiplier   = 2.0,
					LimbMultiplier       = 0.75,
					SpreadDegrees        = 0,
					AllowedFireModes     = {1},
					PelletCount          = 8,
					PelletSpreadDegrees  = 5,
					PelletDamage         = 13,        -- 8 x 13 = 104 at point-blank, lethal
					ViewmodelFolderName  = "SHOTGUN",
					ViewmodelAssetId     = 4842215723,
					ViewmodelOffset      = Vector3.new(0.3, -0.4, -1.0),
					ViewmodelRotation    = Vector3.new(0, 180, 0),
					AimOffset            = Vector3.new(0, -0.2, -0.8),
					SwayAmount           = 0.2,
					BobAmount            = 0.3,
					EquipTime            = 0.6,
					FireSoundId          = 5773418559,
					ReloadSoundId        = 138084889,
					EquipSoundId         = 131072992,
					HeadshotSoundId      = nil,
					ScopeImageId         = nil,
				},
			},

			-- Default weapon on spawn; order drives Q/E cycling.
			-- Only keys that have real assets in ReplicatedStorage.Viewmodels are listed.
			DefaultWeapon = "AR-GUN",
			WeaponOrder = { "AR-GUN", "PISTOL", "SHOTGUN", "SNIPER" },

			-- ── Movement tuning ───────────────────────────────────────────────
			WalkSpeed           = 16,
			SprintMultiplier    = 1.75,
			ScopeSlowMultiplier = 0.4,
			SlideSpeedBoost     = 28,
			SlideDuration       = 0.85,
			SlideHipHeight      = 0.5,
			SlideCooldown       = 1.2,

			-- ── Global FPS sound IDs ──────────────────────────────────────────
			ScopeEnterSoundId      = nil,
			ScopeExitSoundId       = nil,
			HitConfirmSoundId      = nil,
			HeadshotConfirmSoundId = nil,
		},
		Clicker_Farm = {
			Enabled = false,
		},
		Pet_Simulator = {
			Enabled = false,
		},
		RPG_Adventure = {
			Enabled = false,
		},
	},

	Leaderboards = {
		Enabled = true,
		Boards = {
			{
				Key = "Leaderboard_TotalCoins",
				DataField = "TotalCoins",
				DisplayName = "Top Coins",
				Offset = Vector3.new(-7, 4, 0),
				ColorPrimary = Color3.fromRGB(255, 195, 0),
				ColorAccent  = Color3.fromRGB(255, 215, 80),
				Icon         = "",
				FormatType   = "Number",
			},
			{
				Key = "Leaderboard_Rebirths",
				DataField = "Rebirths",
				DisplayName = "Top Rebirths",
				Offset = Vector3.new(0, 4, 0),
				ColorPrimary = Color3.fromRGB(130, 80, 255),
				ColorAccent  = Color3.fromRGB(170, 120, 255),
				Icon         = "",
				FormatType   = "Number",
			},
			{
				Key = "Leaderboard_PlayTime",
				DataField = "PlayTime",
				DisplayName = "Top Playtime",
				Offset = Vector3.new(7, 4, 0),
				ColorPrimary = Color3.fromRGB(0, 200, 150),
				ColorAccent  = Color3.fromRGB(80, 230, 180),
				Icon         = "",
				FormatType   = "Time",
			},
		},
	},

	-- ── In-match session stats (K/D/A) — no DataStore, match-scoped only ──────
	MatchStats = {
		Enabled      = true,
		SyncDebounce = 0.5,
	},
}

-- Studio Auto-Safety
if game.PlaceId ~= 0 and not RunService:IsStudio() then
	FeatureToggles.DebugConfig.BypassCooldowns   = false
	FeatureToggles.DebugConfig.MockDataStores     = false
	FeatureToggles.DebugConfig.ExposeAntiCheatState = false
end

return FeatureToggles
