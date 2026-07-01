--!strict
--@author Antigravity
--@module PISTOL.luau
--@version 1.0

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver"))

local Settings = {}

function Settings.GetConfig()
	local fpsConfig = FeatureResolver.GetCategoryConfig("FPS_Shooter")
	local wCfg = fpsConfig and fpsConfig.Weapons and fpsConfig.Weapons.Pistol
	
	return {
		AimOffset = wCfg and wCfg.AimOffset or Vector3.new(0, -0.1, -0.6),
		SwayAmount = wCfg and wCfg.SwayAmount or 0.15,
		BobAmount = wCfg and wCfg.BobAmount or 0.25,
		EquipTime = wCfg and wCfg.EquipTime or 0.3,
	}
end

return Settings
