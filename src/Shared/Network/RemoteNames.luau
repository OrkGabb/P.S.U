--!strict
--@author OrkGabb
--@module RemoteNames.luau
--@version 1.0
export type RemoteNames = {
	RollRequest:       string,
	UpdateClient:      string,
	ClickReward:       string,
	ForgeRequest:      string,
	EquipRequest:      string,
	UpdateEquipped:    string,
	UpdateCollection:  string,
	LevelUpRequest:    string,
	DashRequest:       string,
	DashGranted:       string,
	EmitVFX:           string,
	WeaponFire:        string,
	WeaponReload:      string,
	WeaponAmmoSync:    string,
	WeaponSwitch:      string,
	SlideRequest:      string,
	SprintRequest:     string,
	MatchStatsSync:    string,
	MatchStatsRequest: string,
	HitConfirm:        string,
	HeadshotConfirm:   string,
	CrouchRequest:     string,
}

local RemoteNames: RemoteNames = {
	RollRequest        = "RollRequest",
	UpdateClient       = "UpdateClient",
	ClickReward        = "ClickReward",
	ForgeRequest       = "ForgeRequest",
	EquipRequest       = "EquipRequest",
	UpdateEquipped     = "UpdateEquipped",
	UpdateCollection   = "UpdateCollection",
	LevelUpRequest     = "LevelUpRequest",
	DashRequest        = "DashRequest",
	DashGranted        = "DashGranted",
	EmitVFX            = "EmitVFX",
	WeaponFire         = "WeaponFire",        -- FPS: client -> server (hitscan authority)
	WeaponReload       = "WeaponReload",      -- FPS: client -> server (reload request)
	WeaponAmmoSync     = "WeaponAmmoSync",    -- FPS: server -> client (authoritative ammo state)
	WeaponSwitch       = "WeaponSwitch",      -- FPS: client -> server (weapon cycle Q/E)
	SlideRequest       = "SlideRequest",      -- FPS: client -> server (slide C key)
	SprintRequest      = "SprintRequest",     -- FPS: client -> server (sprint LeftShift state)
	MatchStatsSync     = "MatchStatsSync",    -- FPS: server -> all clients (K/D/A broadcast)
	MatchStatsRequest  = "MatchStatsRequest", -- FPS: client -> server RF (Tab scoreboard fetch)
	HitConfirm         = "HitConfirm",        -- FPS: server -> attacker (hit feedback with zone)
	HeadshotConfirm    = "HeadshotConfirm",   -- FPS: server -> attacker (headshot ping)
	CrouchRequest      = "CrouchRequest",     -- FPS: client -> server (crouch C key)
}

return RemoteNames
