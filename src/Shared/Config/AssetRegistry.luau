--!strict
--@author OrkGabb
--@module AssetRegistry.luau
--@version 1.0
--- @description Centralized, typed asset dictionary divided by category.
---              Replacing an Id here propagates automatically across the
---              entire game (frontend and backend). Never hardcode asset IDs
---              in service or controller scripts — always reference this module.

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

--- Standard properties every registered asset must carry.
export type AssetEntry = {
	Id: string,                            -- Full rbxassetid:// string
	Name: string,                          -- Human-readable display name
	Rarity: string,                        -- Rarity tier (Common, Uncommon, Rare …)
	CustomConfig: { [string]: any },       -- Extension table for feature-specific data
}

--- Category-level type aliases for readability.
export type AssetCategory = { [string]: AssetEntry }

export type AnimationCategory = {
	Dash: { [string]: AssetEntry },
}

export type AssetRegistryType = {
	Weapons: AssetCategory,
	Skins: AssetCategory,
	VFX: AssetCategory,
	UI_Themes: AssetCategory,
	Animations: AnimationCategory,
}

--------------------------------------------------------------------------------
-- Registry (SSoT)
-- Add, remove, or swap IDs here. All systems pull from this table at runtime.
--------------------------------------------------------------------------------
local AssetRegistry: AssetRegistryType = {
	---------------------------------------------------------------------------
	-- Weapons
	---------------------------------------------------------------------------
	Weapons = {
		StarterSword = {
			Id           = "rbxassetid://0",
			Name         = "Starter Sword",
			Rarity       = "Common",
			CustomConfig = { Damage = 10, SwingSpeed = 1.0 },
		},
	},

	---------------------------------------------------------------------------
	-- Skins
	---------------------------------------------------------------------------
	Skins = {
		DefaultSkin = {
			Id           = "rbxassetid://0",
			Name         = "Default",
			Rarity       = "Common",
			CustomConfig = {},
		},
	},

	---------------------------------------------------------------------------
	-- VFX
	---------------------------------------------------------------------------
	VFX = {
		HitSpark = {
			Id           = "rbxassetid://0",
			Name         = "Hit Spark",
			Rarity       = "Common",
			CustomConfig = { Duration = 0.3, Color = Color3.fromRGB(255, 200, 50) },
		},
	},

	---------------------------------------------------------------------------
	-- UI Themes
	---------------------------------------------------------------------------
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

	---------------------------------------------------------------------------
	-- Animations
	-- Dash animations referenced exclusively by DashService / DashController.
	-- To change the active dash animation, edit FeatureToggles.DashConfig.
	---------------------------------------------------------------------------
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
