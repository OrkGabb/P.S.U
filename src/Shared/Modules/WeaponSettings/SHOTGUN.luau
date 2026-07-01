--!strict
--@author Antigravity
--@module SHOTGUN.luau
--@version 1.0

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver"))

local Settings = {}

function Settings.GetConfig()
	local fpsConfig = FeatureResolver.GetCategoryConfig("FPS_Shooter")
	local wCfg = fpsConfig and fpsConfig.Weapons and fpsConfig.Weapons.Shotgun
	
	return {
		AimOffset = wCfg and wCfg.AimOffset or Vector3.new(0, -0.2, -0.8),
		SwayAmount = wCfg and wCfg.SwayAmount or 0.2,
		BobAmount = wCfg and wCfg.BobAmount or 0.3,
		EquipTime = wCfg and wCfg.EquipTime or 0.6,
	}
end

return Settings
