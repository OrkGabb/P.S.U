--!strict
--@author OrkGabb
--@module StoreRegistry.luau
--@version 1.0
-- src/Shared/Config/StoreRegistry.luau
-- Centralized Store & Monetization Registry configuration.
-- Buyers can map their own generic Developer Product or Gamepass IDs here.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared") :: Folder
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver")) :: any

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

-- Gamepass IDs mapping by Key
StoreRegistry.GamepassIDs = {} :: { [string]: number }

-- Developer Product IDs mapping to rewards
StoreRegistry.DevProducts = {} :: { [number]: RewardConfig }

-- Catalog Items mapping for UI rendering
StoreRegistry.Catalog = {} :: { StoreItem }

return StoreRegistry
