--!strict
--@author OrkGabb
--@module HUDResourceRegistry.luau
--@version 1.0
-- Maps abstract player resources (Coins, CoreFragments, Gems, any future
-- counter) to WHERE they render and HOW.
--
-- Without this layer, "where does resource X show up" gets hardcoded into
-- whichever controller draws it first. With this registry, controllers just
-- ask "give me every resource tagged for MY slot" — moving a resource to a
-- new slot, or adding a resource entirely, is a data change here, never a
-- controller rewrite. Same config-over-logic pattern as FeatureResolver /
-- UpgradeRegistry / DailyRegistry.
--
-- Adding a slot (e.g. "InventoryHeader", "MobileBar") requires: (1) a
-- controller that reads GetResourcesForSlot(slotName) and draws generically
-- like TopBarController does, (2) tagging a resource's Slots table with the
-- new slot name.

export type ResourceSlot = string -- "TopBar" | "Sidebar" | any future slot name

export type ResourceDef = {
	Id: string,
	-- Path into the profile-data table this resource reads from, e.g.
	-- {"Currencies", "Primary"} or {"Stats", "CoreFragments"}.
	DataPath: { string },
	IconId: string,
	Color: Color3,
	-- Which UI slots this resource should render in. A resource can be
	-- tagged for zero, one, or many slots simultaneously.
	Slots: { ResourceSlot },
	-- Display priority within a slot (lower = drawn first / higher up).
	Order: number,
	-- If true, hide this resource whenever no genre category (besides
	-- "Global") is active, or FPS_Shooter is active — mirrors
	-- TopBarController's existing genre-gating rule for currencies.
	HideOnFPS: boolean,
}

local HUDResourceRegistry = {}

local Resources: { [string]: ResourceDef } = {
	Coins = {
		Id = "Coins",
		DataPath = { "Currencies", "Primary" },
		IconId = "CoinIcon", -- resolved against AssetRegistry.UI at render time
		Color = Color3.fromRGB(255, 255, 255),
		Slots = { "TopBar" },
		Order = 1,
		HideOnFPS = true,
	},
	SecondaryCurrency = {
		Id = "SecondaryCurrency",
		DataPath = { "Currencies", "Secondary" },
		IconId = "CoinIcon",
		Color = Color3.fromRGB(255, 170, 220),
		Slots = { "TopBar" },
		Order = 2,
		HideOnFPS = true,
	},
	-- Universal milestone resource (DailyService, Leva 4).
	CoreFragments = {
		Id = "CoreFragments",
		DataPath = { "Stats", "CoreFragments" },
		IconId = "DailyIcon",
		Color = Color3.fromRGB(160, 220, 255),
		Slots = { "TopBar" },
		Order = 3,
		HideOnFPS = true,
	},
}
HUDResourceRegistry.Resources = Resources

-- Returns every resource tagged for a given slot, sorted by Order.
-- This is the ONLY function generic slot-renderers need to call.
function HUDResourceRegistry.GetResourcesForSlot(slot: ResourceSlot): { ResourceDef }
	local out: { ResourceDef } = {}
	for _, def in pairs(HUDResourceRegistry.Resources) do
		for _, s in ipairs(def.Slots) do
			if s == slot then
				table.insert(out, def)
				break
			end
		end
	end
	table.sort(out, function(a, b)
		return a.Order < b.Order
	end)
	return out
end

-- Reads a resource's current value out of a profile-data table using its
-- DataPath. Returns nil if any path segment is missing (renderer decides
-- how to handle nil — usually "skip this row").
function HUDResourceRegistry.ReadValue(def: ResourceDef, data: any): number?
	local cursor: any = data
	for _, key in ipairs(def.DataPath) do
		if type(cursor) ~= "table" then
			return nil
		end
		cursor = cursor[key]
	end
	if type(cursor) == "number" then
		return cursor
	end
	return nil
end

return HUDResourceRegistry
