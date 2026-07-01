--!strict
--@author OrkGabb
--@module FeatureResolver.luau
--@version 1.0
-- src/Shared/Modules/FeatureResolver.luau
-- Centralized single source of truth for dynamic category/feature discovery and resolution.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FeatureToggles = require(ReplicatedStorage.Shared.Config.FeatureToggles)

local FeatureResolver = {}

-- Returns whether a category or feature flag is active in FeatureToggles
function FeatureResolver.IsCategoryActive(name: string): boolean
	local toggle: any = (FeatureToggles :: any)[name]
	if toggle == nil then
		toggle = (FeatureToggles :: any)[name .. "Config"]
	end
	if toggle == nil and FeatureToggles.GlobalFlags then
		toggle = (FeatureToggles.GlobalFlags :: any)[name]
		if toggle == nil then
			toggle = (FeatureToggles.GlobalFlags :: any)[name .. "Config"]
		end
	end
	if toggle == nil and (FeatureToggles :: any).Genres then
		toggle = (FeatureToggles :: any).Genres[name]
		if toggle == nil then
			toggle = (FeatureToggles :: any).Genres[name .. "Config"]
		end
	end
	if type(toggle) == "table" then
		return toggle.Enabled == true
	end
	return toggle == true
end

-- Returns an array of all active gameplay/feature categories
function FeatureResolver.GetActiveCategories(): {string}
	local active: {string} = {}
	
	-- Categories list to check
	local categoriesToCheck: {string} = {
		"FPS_Shooter",
		"Clicker_Farm",
		"Pet_Simulator",
		"RPG_Adventure",
	}

	for _, name in ipairs(categoriesToCheck) do
		if FeatureResolver.IsCategoryActive(name) then
			table.insert(active, name)
		end
	end
	
	-- Automatically fallback to Global if no category is toggled
	if #active == 0 then
		table.insert(active, "Global")
	end
	
	return active
end

-- Returns the first active genre key, or nil if no genre is active
function FeatureResolver.GetActiveGenre(): string?
	local genreKeys: {string} = {
		"FPS_Shooter",
		"Clicker_Farm",
		"Pet_Simulator",
		"RPG_Adventure",
	}
	for _, key: string in ipairs(genreKeys) do
		local cfg: any = (FeatureToggles :: any).Genres and (FeatureToggles :: any).Genres[key]
		if type(cfg) == "table" and cfg.Enabled == true then
			return key
		end
	end
	return nil
end

-- Retrieves a GlobalFlags entry by name, returns nil if missing
function FeatureResolver.GetFlag(name: string): any
	if FeatureToggles.GlobalFlags then
		return (FeatureToggles.GlobalFlags :: any)[name]
	end
	return nil
end

-- Safely retrieves configuration table for a category
function FeatureResolver.GetCategoryConfig(name: string): any
	local config: any = (FeatureToggles :: any)[name]
	if config == nil then
		config = (FeatureToggles :: any)[name .. "Config"]
	end
	if config == nil and FeatureToggles.GlobalFlags then
		config = (FeatureToggles.GlobalFlags :: any)[name]
		if config == nil then
			config = (FeatureToggles.GlobalFlags :: any)[name .. "Config"]
		end
	end
	if config == nil and (FeatureToggles :: any).Genres then
		config = (FeatureToggles :: any).Genres[name]
		if config == nil then
			config = (FeatureToggles :: any).Genres[name .. "Config"]
		end
	end
	return config
end

-- Safely retrieves a specific field from a category configuration table
function FeatureResolver.GetConfigField(categoryName: string, field: string, defaultValue: any): any
	local config: any = FeatureResolver.GetCategoryConfig(categoryName)
	if type(config) == "table" then
		if config[field] ~= nil then
			return config[field]
		end
	end
	return defaultValue
end

return FeatureResolver
