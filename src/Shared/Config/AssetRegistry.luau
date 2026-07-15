--!strict
-- @Author @OrkGabb
-- Centralized, typed asset dictionary divided by category. Replacing an Id
-- here propagates everywhere it's used — never hardcode asset IDs in service
-- or controller scripts, always reference this module.

export type AssetEntry = {
	Id: string,                            -- rbxassetid:// string
	Name: string,
	Rarity: string,                        -- Common, Uncommon, Rare …
	CustomConfig: { [string]: any },       -- extension table for feature-specific data
}

export type AssetCategory = { [string]: AssetEntry }

export type AnimationCategory = {
	Dash: { [string]: AssetEntry },
}

-- Flat UI asset table: icon ids plus a few layout constants that UI
-- controllers share. Restored after the June 2026 simplification pass
-- removed it while controllers still referenced it.
export type UIAssetCategory = {
	CoinIcon: string,
	CloseIcon: string,
	HideUI: string,
	AutoRollOnIcon: string,
	AutoRollOffIcon: string,
	RebirthIcon: string,
	EXPPotionIcon: string,
	LuckPotionIcon: string,
	CoinPotionIcon: string,
	SpeedPotionIcon: string,
	VIPPassIcon: string,
	ProfileIcon: string,
	SkillsIcon: string,
	QuestsIcon: string,
	DailyIcon: string,
	SettingsIcon: string,
	BagIcon: string,
	ButtonSize: number,
	BottomButtonSize: number,
	PotionSpriteSize: Vector2,
}

export type AssetRegistryType = {
	Weapons: AssetCategory,
	Skins: AssetCategory,
	VFX: AssetCategory,
	UI: UIAssetCategory,
	UI_Themes: AssetCategory,
	Animations: AnimationCategory,
}

-- Add, remove, or swap IDs here. All systems pull from this table at runtime.
local AssetRegistry: AssetRegistryType = {
	Weapons = {
		StarterSword = {
			Id           = "rbxassetid://0",
			Name         = "Starter Sword",
			Rarity       = "Common",
			CustomConfig = { Damage = 10, SwingSpeed = 1.0 },
		},
	},

	Skins = {
		DefaultSkin = {
			Id           = "rbxassetid://0",
			Name         = "Default",
			Rarity       = "Common",
			CustomConfig = {},
		},
	},

	VFX = {
		HitSpark = {
			Id           = "rbxassetid://0",
			Name         = "Hit Spark",
			Rarity       = "Common",
			CustomConfig = { Duration = 0.3, Color = Color3.fromRGB(255, 200, 50) },
		},
	},

	-- Shared icons + layout constants for HUD controllers. Icons marked
	-- PLACEHOLDER use a generic glyph — swap in your own branded assets.
	UI = {
		CoinIcon         = "rbxassetid://15059633013", -- PLACEHOLDER
		CloseIcon        = "rbxassetid://15059633013", -- PLACEHOLDER
		HideUI           = "rbxassetid://15059633013", -- PLACEHOLDER
		AutoRollOnIcon   = "rbxassetid://15059633013", -- PLACEHOLDER (Aura_Collector roll UI)
		AutoRollOffIcon  = "rbxassetid://15059633013", -- PLACEHOLDER (Aura_Collector roll UI)
		RebirthIcon      = "rbxassetid://15059633013", -- PLACEHOLDER
		EXPPotionIcon    = "rbxassetid://15059633013", -- PLACEHOLDER
		LuckPotionIcon   = "rbxassetid://15059633013", -- PLACEHOLDER
		CoinPotionIcon   = "rbxassetid://15059633013", -- PLACEHOLDER
		SpeedPotionIcon  = "rbxassetid://15059633013", -- PLACEHOLDER
		VIPPassIcon      = "rbxassetid://15059633013", -- PLACEHOLDER
		ProfileIcon      = "rbxassetid://15059633013", -- PLACEHOLDER
		SkillsIcon       = "rbxassetid://15059633013", -- PLACEHOLDER
		QuestsIcon       = "rbxassetid://15059633013", -- PLACEHOLDER
		DailyIcon        = "rbxassetid://15059633013", -- PLACEHOLDER
		SettingsIcon     = "rbxassetid://15059633013", -- PLACEHOLDER
		BagIcon          = "rbxassetid://15059633013", -- PLACEHOLDER
		ButtonSize       = 45,
		BottomButtonSize = 45,
		PotionSpriteSize = Vector2.new(256, 256),
	},

	UI_Themes = {
		DarkMode = {
			Id           = "rbxassetid://0",
			Name         = "Dark Mode",
			Rarity       = "Common",
			CustomConfig = {
				PrimaryColor   = Color3.fromRGB(30, 30, 40),
				AccentColor    = Color3.fromRGB(100, 140, 255),
			},
		},
	},

	-- Dash animations referenced exclusively by DashService / DashController.
	-- To change the active dash animation, edit FeatureToggles.DashConfig.
	Animations = {
		Dash = {
			DashA = {
				Id           = "rbxassetid://5989939664",
				Name         = "DashA",
				Rarity       = "Common",
				CustomConfig = {},
			},
			DashB = {
				Id           = "rbxassetid://3084314259",
				Name         = "DashB",
				Rarity       = "Common",
				CustomConfig = {},
			},
		},
	},
}

return AssetRegistry
