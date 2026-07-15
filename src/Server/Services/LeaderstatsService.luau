--!strict
-- @Author @OrkGabb
--- @description Dynamic, abstract schema leaderstats system.

local Players: Players = game:GetService("Players")
local ServerScriptService: ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService: any = require(ServerScriptService.Server.Services.DataService)
local FeatureResolver: any = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("FeatureResolver"))

local LeaderstatsService = {}

local function SetupLeaderstats(player: Player): ()
	local profile: any = nil
	repeat
		profile = DataService.Profiles[player]
		task.wait(0.1)
	until profile ~= nil or not player:IsDescendantOf(Players)
	
	if not profile then return end

	local leaderstats: Folder = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	-- Currency display names come from the active genre's config (SSoT) —
	-- no genre special-casing in core.
	local currencyNames = FeatureResolver.GetCurrencyNames()
	local primaryName: string = currencyNames.Primary
	local secondaryName: string = currencyNames.Secondary

	local primaryValue: IntValue = Instance.new("IntValue")
	primaryValue.Name = primaryName
	primaryValue.Value = 0
	primaryValue.Parent = leaderstats

	local secondaryValue: IntValue = Instance.new("IntValue")
	secondaryValue.Name = secondaryName
	secondaryValue.Value = 0
	secondaryValue.Parent = leaderstats

	local levelValue: NumberValue = Instance.new("NumberValue")
	levelValue.Name = "Level"
	levelValue.Value = 1
	levelValue.Parent = leaderstats

	local expValue: NumberValue = Instance.new("NumberValue")
	expValue.Name = "EXP"
	expValue.Value = 0
	expValue.Parent = leaderstats

	task.spawn(function(): ()
		while player:IsDescendantOf(Players) and DataService.Profiles[player] do
			local currentProfile: any = DataService.Profiles[player]
			if currentProfile and currentProfile.Data then
				local currencies: { [string]: number }? = currentProfile.Data.Currencies
				local progression: { [string]: any }? = currentProfile.Data.Progression
				
				if currencies then
					primaryValue.Value = currencies["Primary"] or 0
					secondaryValue.Value = currencies["Secondary"] or 0
				end
				
				if progression then
					levelValue.Value = progression["Level"] or 1
					expValue.Value = progression["Experience"] or 0
				end
				
				-- Fallback compatibility for legacy scripts
				if currentProfile.Data.Coins then
					primaryValue.Value = currentProfile.Data.Coins
				end
				if currentProfile.Data.Level then
					levelValue.Value = currentProfile.Data.Level
				end
				if currentProfile.Data.EXP then
					expValue.Value = currentProfile.Data.EXP
				end
			end
			task.wait(0.5)
		end
	end)
end

function LeaderstatsService.Init(): ()
	for _, player: Player in ipairs(Players:GetPlayers()) do
		task.spawn(SetupLeaderstats, player)
	end
	Players.PlayerAdded:Connect(SetupLeaderstats)
end

return LeaderstatsService
