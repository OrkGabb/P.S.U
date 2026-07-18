--!strict
--@author OrkGabb
--@module UIAssetPacks.luau
--@version 1.0
-- Per-menu UI asset packs with fallback to the shared Default pack.
--
-- The Default pack is AssetRegistry.UI (icons + layout constants). To give a
-- menu an exclusive look, add a table under Packs keyed by the menu id — any
-- key present there overrides the Default; anything missing falls back. A
-- pack may also carry a Theme sub-table (Color3 overrides consumed by
-- MenuPanel for the shared panel chrome).
--
--   Packs.Skills = {
--       CoinIcon = "rbxassetid://123456789",
--       Theme = { PanelBackground = Color3.fromRGB(30, 18, 40) },
--   }
--
-- Deleting a pack (or this whole Packs table) reverts every menu to the
-- Default pack — nothing else references pack tables directly.

local AssetRegistry = require(script.Parent.AssetRegistry)

export type UIAssetPack = { [string]: any }

local UIAssetPacks = {}

-- Shared base pack every menu inherits.
UIAssetPacks.Default = (AssetRegistry.UI :: any) :: UIAssetPack

-- Per-menu overrides. Key = menu id (the same id passed to MenuPanel.Create /
-- used in Toggle<Id> events).
UIAssetPacks.Packs = {} :: { [string]: UIAssetPack }

local mergedCache: { [string]: UIAssetPack } = {}

--- Resolved asset view for a menu: pack overrides first, Default fallback.
function UIAssetPacks.For(menuId: string?): UIAssetPack
	if not menuId then
		return UIAssetPacks.Default
	end
	local pack = UIAssetPacks.Packs[menuId]
	if not pack then
		return UIAssetPacks.Default
	end
	local merged = mergedCache[menuId]
	if not merged then
		merged = setmetatable(table.clone(pack), { __index = UIAssetPacks.Default }) :: any
		mergedCache[menuId] = merged
	end
	return merged
end

return UIAssetPacks
