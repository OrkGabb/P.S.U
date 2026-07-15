--!strict
--@author OrkGabb
--@module DebugUtility.luau
--@version 1.0
--- @description Utility for debugging operations such as logging and physical vector drawing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FeatureToggles = require(ReplicatedStorage.Shared.Config.FeatureToggles)

local DebugUtility = {}

function DebugUtility.Log(source: string, message: string)
	local debugConfig = FeatureToggles.DebugConfig
	if debugConfig and debugConfig.VerboseLogging then
		print(string.format("[%s] %s", source, message))
	end
end

function DebugUtility.Warn(source: string, message: string)
	local debugConfig = FeatureToggles.DebugConfig
	if debugConfig and debugConfig.VerboseLogging then
		warn(string.format("[%s] WARNING: %s", source, message))
	end
end

function DebugUtility.DrawVector(origin: Vector3, direction: Vector3, magnitude: number)
	local debugConfig = FeatureToggles.DebugConfig
	if not (debugConfig and debugConfig.DrawPhysicsVectors) then return end
	
	local tracer = Instance.new("Part")
	tracer.Name = "DebugVector"
	tracer.Shape = Enum.PartType.Cylinder
	tracer.Size = Vector3.new(0.2, magnitude, 0.2)
	tracer.Color = Color3.fromRGB(0, 255, 255)
	tracer.Material = Enum.Material.Neon
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CFrame = CFrame.lookAt(origin, origin + direction.Unit * magnitude) * CFrame.new(0, 0, -magnitude / 2) * CFrame.Angles(math.pi / 2, 0, 0)
	tracer.Parent = workspace
	
	task.delay(3, function()
		if tracer and tracer.Parent then
			tracer:Destroy()
		end
	end)
end

return DebugUtility
