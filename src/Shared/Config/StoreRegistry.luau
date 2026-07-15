--!strict
-- @Author @OrkGabb
-- Compiled store view for the active genre. All definitions live in
-- CommerceRegistry (the SSoT); this module only reshapes them into the
-- structures MonetizationService and StoreController consume:
--   GamepassIDs — passKey → numeric GamePass ID
--   DevProducts — numeric product ID → reward config
--   Catalog     — flat StoreItem list for store UI rendering

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)
local CommerceRegistry = require(ReplicatedStorage.Shared.Config.CommerceRegistry)

local FALLBACK_ICON: string = "rbxassetid://15059633013"

export type RewardConfig = {
	Type: string,
	Amount: number,
	ItemId: string?,
}

export type StoreItem = {
	Id: number,
	Type: "Gamepass" | "Product" | "VirtualCurrency",
	Name: string,
	Description: string,
	Price: number,
	Color: Color3,
	Icon: string,
	Category: "PASSES" | "BOOSTS",
	Genre: string?,
	Reward: RewardConfig?,
}

local StoreRegistry = {}

StoreRegistry.GamepassIDs = CommerceRegistry.GamepassIDs
StoreRegistry.DevProducts = CommerceRegistry.DevProducts

StoreRegistry.Catalog = {} :: { StoreItem }

do
	local genre: string? = FeatureResolver.GetActiveGenre()

	for _, pass in pairs(CommerceRegistry.ActiveGamepasses) do
		table.insert(StoreRegistry.Catalog, {
			Id = pass.Id,
			Type = "Gamepass" :: "Gamepass",
			Name = pass.Name,
			Description = pass.Description,
			Price = pass.Price,
			Color = pass.Color or Color3.fromRGB(255, 255, 255),
			Icon = pass.Icon or FALLBACK_ICON,
			Category = "PASSES" :: "PASSES",
			Genre = genre,
			Reward = nil,
		})
	end

	for _, product in pairs(CommerceRegistry.ActiveDevProducts) do
		table.insert(StoreRegistry.Catalog, {
			Id = product.Id,
			Type = "Product" :: "Product",
			Name = product.Name,
			Description = product.Description,
			Price = product.Price,
			Color = product.Color or Color3.fromRGB(255, 255, 255),
			Icon = product.Icon or FALLBACK_ICON,
			Category = "BOOSTS" :: "BOOSTS",
			Genre = genre,
			Reward = {
				Type = product.Reward.Type,
				Amount = product.Reward.Amount,
				ItemId = product.Reward.ItemId,
			},
		})
	end

	-- cheapest first within each category
	table.sort(StoreRegistry.Catalog, function(a: StoreItem, b: StoreItem): boolean
		if a.Category ~= b.Category then
			return a.Category < b.Category
		end
		return a.Price < b.Price
	end)
end

return StoreRegistry
