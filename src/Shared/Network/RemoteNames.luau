--!strict
-- @Author @OrkGabb
-- src/Shared/Network/RemoteNames.luau
--
-- Single source of truth for EVERY remote in the framework.
--
--   * `RemoteNames.<Key>`  — the wire name constant. All server services and
--     client controllers must reference remotes through these constants;
--     string literals at call sites are forbidden (they are how the old
--     dual-SSoT drift happened).
--   * `RemoteNames.Schema` — machine-readable contract per remote: instance
--     class, direction, owning system and human-readable signature.
--     NetworkService.Init instantiates every entry with the correct class at
--     boot, so no service or controller can ever stall on WaitForChild or
--     collide on a wrong-class duplicate.
--
-- Adding a remote = add ONE Schema entry (+ its name constant). Never
-- Instance.new a remote with a literal name anywhere else.

export type RemoteKind = "Event" | "Function"

export type RemoteDef = {
	Kind: RemoteKind,
	Direction: string, -- "C->S" | "S->C" | "S->all"
	System: string,    -- owning service / genre
	Signature: string, -- params (and return for Functions), documentation-grade
}

export type RemoteNamesType = {
	-- Core: data / progression
	UpdateProfileData: string,
	UpdateResourceValue: string,
	LevelUpFX: string,
	-- Core: quests
	UpdateQuests: string,
	ClaimQuestRequest: string,
	-- Core: daily rewards
	UpdateDaily: string,
	ClaimDailyRequest: string,
	-- Core: upgrades
	UpgradeRequest: string,
	UpdateUpgrades: string,
	-- Core: items / buffs
	RequestConsumeItem: string,
	SyncActiveBuffs: string,
	-- Core: monetization
	NotifyPurchase: string,
	CheckGamepassOwnership: string,
	CheckVIPStatus: string,
	BuyInGameItem: string,
	-- Core: admin / anticheat / vfx
	SysAdmin: string,
	SysAdminCheck: string,
	AntiCheatStateSync: string,
	EmitVFX: string,
	-- Dash
	DashRequest: string,
	DashGranted: string,
	-- Leaderboards
	GetLeaderboardData: string,
	GetBoardConfigs: string,
	-- Clicker_Farm
	ClickReward: string,
	GoldenDropSpawn: string,
	GoldenDropClaim: string,
	-- Aura_Collector
	RollRequest: string,
	EquipRequest: string,
	SetBiomeRequest: string,
	ToggleAutoRoll: string,
	UpdateClient: string,
	UpdateCollection: string,
	UpdateEquipped: string,
	UpdateBiome: string,
	ForceDisableAutoRoll: string,
	-- Pet_Simulator
	HatchRequest: string,
	PetEquipRequest: string,
	HatchResult: string,
	UpdatePetInventory: string,
	-- FPS_Shooter
	WeaponFire: string,
	WeaponReload: string,
	WeaponAmmoSync: string,
	WeaponSwitch: string,
	SlideRequest: string,
	SprintRequest: string,
	CrouchRequest: string,
	HitConfirm: string,
	HeadshotConfirm: string,
	MatchStatsSync: string,
	MatchStatsRequest: string,

	Schema: { [string]: RemoteDef },
}

local Schema: { [string]: RemoteDef } = {
	-- ── Core: data / progression ─────────────────────────────────────────────
	UpdateProfileData = { Kind = "Event", Direction = "S->C", System = "DataService",
		Signature = "(profileData: table) — full profile snapshot after any change" },
	UpdateResourceValue = { Kind = "Event", Direction = "S->C", System = "DataService",
		Signature = "(path: {string}, value: number) — single resource delta (e.g. {\"Currencies\",\"Primary\"}); lighter than a full UpdateProfileData snapshot for high-frequency changes (clicks, golden drops, passive income)" },
	LevelUpFX = { Kind = "Event", Direction = "S->C", System = "LevelService",
		Signature = "(newLevel: number) — level-up celebration trigger" },

	-- ── Core: quests ─────────────────────────────────────────────────────────
	UpdateQuests = { Kind = "Event", Direction = "S->C", System = "QuestService",
		Signature = "(questState: table) — active quest progress snapshot" },
	ClaimQuestRequest = { Kind = "Event", Direction = "C->S", System = "QuestService",
		Signature = "(questId: string) — claim a completed quest's reward" },

	-- ── Core: daily rewards ──────────────────────────────────────────────────
	UpdateDaily = { Kind = "Event", Direction = "S->C", System = "DailyService",
		Signature = "(dailyData: table) — { LastClaim: number, CurrentDay: number }" },
	ClaimDailyRequest = { Kind = "Event", Direction = "C->S", System = "DailyService",
		Signature = "() — claim today's daily reward, no args" },

	-- ── Core: upgrades ───────────────────────────────────────────────────────
	UpgradeRequest = { Kind = "Event", Direction = "C->S", System = "UpgradeService",
		Signature = "(upgradeId: string) — purchase one level of an upgrade" },
	UpdateUpgrades = { Kind = "Event", Direction = "S->C", System = "UpgradeService",
		Signature = "(upgrades: table) — owned upgrade levels snapshot" },

	-- ── Core: items / buffs ──────────────────────────────────────────────────
	RequestConsumeItem = { Kind = "Event", Direction = "C->S", System = "ItemService",
		Signature = "(itemId: string) — consume one unit of an inventory item" },
	SyncActiveBuffs = { Kind = "Event", Direction = "S->C", System = "ItemService",
		Signature = "(activeBuffs: table) — volatile buff timers snapshot" },

	-- ── Core: monetization ───────────────────────────────────────────────────
	NotifyPurchase = { Kind = "Event", Direction = "S->C", System = "MonetizationService",
		Signature = "(rewardType: string, amount: number, displayName: string, extraData: any?)" },
	CheckGamepassOwnership = { Kind = "Function", Direction = "C->S", System = "MonetizationService",
		Signature = "(passId: number) -> boolean" },
	CheckVIPStatus = { Kind = "Function", Direction = "C->S", System = "MonetizationService",
		Signature = "() -> boolean" },
	BuyInGameItem = { Kind = "Function", Direction = "C->S", System = "MonetizationService",
		Signature = "(itemId: string) -> boolean — soft-currency store purchase" },

	-- ── Core: admin / anticheat / vfx ────────────────────────────────────────
	sys_adm = { Kind = "Event", Direction = "C->S", System = "AdminService",
		Signature = "(command: string, ...args) — admin command channel (server validates rank)" },
	sys_adm_chk = { Kind = "Function", Direction = "C->S", System = "AdminService",
		Signature = "() -> boolean — is LocalPlayer an admin (UI visibility only)" },
	S2C_AntiCheatStateSync = { Kind = "Event", Direction = "S->C", System = "AntiExploitService",
		Signature = "(state: table) — debug anticheat state (DebugConfig.ExposeAntiCheatState)" },
	EmitVFX = { Kind = "Event", Direction = "S->C", System = "VFXService",
		Signature = "(vfxKey: string, position: Vector3?) — play a VFXRegistry effect" },

	-- ── Dash ─────────────────────────────────────────────────────────────────
	DashRequest = { Kind = "Event", Direction = "C->S", System = "Dash",
		Signature = "(direction: Vector3) — dash impulse request (server validates charges)" },
	DashGranted = { Kind = "Event", Direction = "S->C", System = "Dash",
		Signature = "(chargesLeft: number, cooldown: number)" },

	-- ── Leaderboards ─────────────────────────────────────────────────────────
	GetLeaderboardData = { Kind = "Function", Direction = "C->S", System = "Leaderboards",
		Signature = "(boardKey: string?) -> {entries} — top-N snapshot" },
	GetBoardConfigs = { Kind = "Function", Direction = "C->S", System = "Leaderboards",
		Signature = "() -> {boardConfig} — board display metadata" },

	-- ── Clicker_Farm ─────────────────────────────────────────────────────────
	ClickReward = { Kind = "Event", Direction = "C->S", System = "Clicker_Farm",
		Signature = "(batch: number?) — manual click(s); server applies anti-macro token bucket" },
	GoldenDropSpawn = { Kind = "Event", Direction = "S->C", System = "Clicker_Farm",
		Signature = "(guid: string, tier: string, duration: number) — golden drop event spawn" },
	GoldenDropClaim = { Kind = "Function", Direction = "C->S", System = "Clicker_Farm",
		Signature = "(guid: string) -> rewardInfo? — claim a live golden drop (GUID-validated)" },

	-- ── Aura_Collector ───────────────────────────────────────────────────────
	RollRequest = { Kind = "Event", Direction = "C->S", System = "Aura_Collector",
		Signature = "(clientBiome: any?, spinId: string?) — roll for an aura (server re-derives biome)" },
	EquipRequest = { Kind = "Event", Direction = "C->S", System = "Aura_Collector",
		Signature = "(auraId: string | nil) — equip owned aura / nil to unequip" },
	SetBiomeRequest = { Kind = "Event", Direction = "C->S", System = "Aura_Collector",
		Signature = "(biomeId: string) — select/unlock-purchase a roll biome" },
	ToggleAutoRoll = { Kind = "Event", Direction = "C->S", System = "Aura_Collector",
		Signature = "(isActive: boolean) — gamepass-gated auto-roll loop toggle" },
	UpdateClient = { Kind = "Event", Direction = "S->C", System = "Aura_Collector",
		Signature = "(rolledAuraId: string, equippedAuraId: string?, biomeId: string, spinId: string?)" },
	UpdateCollection = { Kind = "Event", Direction = "S->C", System = "Aura_Collector",
		Signature = "(collection: {[string]: number}, meta: table)" },
	UpdateEquipped = { Kind = "Event", Direction = "S->C", System = "Aura_Collector",
		Signature = "(auraId: string | nil)" },
	UpdateBiome = { Kind = "Event", Direction = "S->C", System = "Aura_Collector",
		Signature = "(biomeId: string) — authoritative current biome" },
	ForceDisableAutoRoll = { Kind = "Event", Direction = "S->C", System = "Aura_Collector",
		Signature = "() — server killed the auto-roll loop (funds/gamepass revoked)" },

	-- ── Pet_Simulator ────────────────────────────────────────────────────────
	HatchRequest = { Kind = "Event", Direction = "C->S", System = "Pet_Simulator",
		Signature = "(eggId: string) — hatch one egg (server validates cost/level/cooldown)" },
	PetEquipRequest = { Kind = "Event", Direction = "C->S", System = "Pet_Simulator",
		Signature = "(petId: string | nil) — equip owned pet / nil to unequip" },
	HatchResult = { Kind = "Event", Direction = "S->C", System = "Pet_Simulator",
		Signature = "(petId: string, eggId: string, isNew: boolean) — hatch reveal payload" },
	UpdatePetInventory = { Kind = "Event", Direction = "S->C", System = "Pet_Simulator",
		Signature = "(inventory: {[string]: number}, equippedPetId: string?)" },

	-- ── FPS_Shooter ──────────────────────────────────────────────────────────
	WeaponFire = { Kind = "Event", Direction = "C->S", System = "FPS_Shooter",
		Signature = "(origin: Vector3, direction: Vector3, weaponKey: string) — hitscan authority is server-side" },
	WeaponReload = { Kind = "Event", Direction = "C->S", System = "FPS_Shooter",
		Signature = "(weaponKey: string) — reload request (server owns timers/ammo)" },
	WeaponAmmoSync = { Kind = "Event", Direction = "S->C", System = "FPS_Shooter",
		Signature = "(weaponKey: string, mag: number, reserve: number) — authoritative ammo state" },
	WeaponSwitch = { Kind = "Event", Direction = "C->S", System = "FPS_Shooter",
		Signature = "(weaponKey: string) — weapon cycle (Q/E)" },
	SlideRequest = { Kind = "Event", Direction = "C->S", System = "FPS_Shooter",
		Signature = "(isSliding: boolean) — slide state (C key)" },
	SprintRequest = { Kind = "Event", Direction = "C->S", System = "FPS_Shooter",
		Signature = "(isSprinting: boolean) — sprint state (LeftShift)" },
	CrouchRequest = { Kind = "Event", Direction = "C->S", System = "FPS_Shooter",
		Signature = "(isCrouching: boolean) — crouch state (C key)" },
	HitConfirm = { Kind = "Event", Direction = "S->C", System = "FPS_Shooter",
		Signature = "(zone: string, damage: number) — hit feedback to the attacker" },
	HeadshotConfirm = { Kind = "Event", Direction = "S->C", System = "FPS_Shooter",
		Signature = "() — headshot ping to the attacker" },
	MatchStatsSync = { Kind = "Event", Direction = "S->all", System = "FPS_Shooter",
		Signature = "(stats: {ScoreboardEntry}) — debounced K/D/A broadcast" },
	MatchStatsRequest = { Kind = "Function", Direction = "C->S", System = "FPS_Shooter",
		Signature = "() -> {ScoreboardEntry} — Tab scoreboard fetch" },
}

local RemoteNames: RemoteNamesType = {
	-- Core: data / progression
	UpdateProfileData   = "UpdateProfileData",
	UpdateResourceValue = "UpdateResourceValue",
	LevelUpFX           = "LevelUpFX",
	-- Core: quests
	UpdateQuests       = "UpdateQuests",
	ClaimQuestRequest  = "ClaimQuestRequest",
	-- Core: daily rewards
	UpdateDaily        = "UpdateDaily",
	ClaimDailyRequest  = "ClaimDailyRequest",
	-- Core: upgrades
	UpgradeRequest     = "UpgradeRequest",
	UpdateUpgrades     = "UpdateUpgrades",
	-- Core: items / buffs
	RequestConsumeItem = "RequestConsumeItem",
	SyncActiveBuffs    = "SyncActiveBuffs",
	-- Core: monetization
	NotifyPurchase         = "NotifyPurchase",
	CheckGamepassOwnership = "CheckGamepassOwnership",
	CheckVIPStatus         = "CheckVIPStatus",
	BuyInGameItem          = "BuyInGameItem",
	-- Core: admin / anticheat / vfx (wire names differ from constant keys:
	-- legacy names kept so existing player-facing exploits/allowlists don't churn)
	SysAdmin           = "sys_adm",
	SysAdminCheck      = "sys_adm_chk",
	AntiCheatStateSync = "S2C_AntiCheatStateSync",
	EmitVFX            = "EmitVFX",
	-- Dash
	DashRequest = "DashRequest",
	DashGranted = "DashGranted",
	-- Leaderboards
	GetLeaderboardData = "GetLeaderboardData",
	GetBoardConfigs    = "GetBoardConfigs",
	-- Clicker_Farm
	ClickReward     = "ClickReward",
	GoldenDropSpawn = "GoldenDropSpawn",
	GoldenDropClaim = "GoldenDropClaim",
	-- Aura_Collector
	RollRequest          = "RollRequest",
	EquipRequest         = "EquipRequest",
	SetBiomeRequest      = "SetBiomeRequest",
	ToggleAutoRoll       = "ToggleAutoRoll",
	UpdateClient         = "UpdateClient",
	UpdateCollection     = "UpdateCollection",
	UpdateEquipped       = "UpdateEquipped",
	UpdateBiome          = "UpdateBiome",
	ForceDisableAutoRoll = "ForceDisableAutoRoll",
	-- Pet_Simulator
	HatchRequest       = "HatchRequest",
	PetEquipRequest    = "PetEquipRequest",
	HatchResult        = "HatchResult",
	UpdatePetInventory = "UpdatePetInventory",
	-- FPS_Shooter
	WeaponFire        = "WeaponFire",
	WeaponReload      = "WeaponReload",
	WeaponAmmoSync    = "WeaponAmmoSync",
	WeaponSwitch      = "WeaponSwitch",
	SlideRequest      = "SlideRequest",
	SprintRequest     = "SprintRequest",
	CrouchRequest     = "CrouchRequest",
	HitConfirm        = "HitConfirm",
	HeadshotConfirm   = "HeadshotConfirm",
	MatchStatsSync    = "MatchStatsSync",
	MatchStatsRequest = "MatchStatsRequest",

	Schema = Schema,
}

return RemoteNames
