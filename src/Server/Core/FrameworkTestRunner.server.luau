--!strict
--@author OrkGabb
--@module FrameworkTestRunner.server.luau
--@version 1.0
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

-- Self-tests are a development aid: run only in Studio with DebugConfig on.
-- (Previously this ran — and printed [PASS]/[FAIL] — on every production boot.)
do
	local FeatureToggles = require(ReplicatedStorage.Shared.Config.FeatureToggles)
	if not (RunService:IsStudio() and FeatureToggles.DebugConfig.Enabled) then
		return
	end
end

local function getModuleScript(name: string, root: Instance): ModuleScript?
	local obj = root:FindFirstChild(name, true)
	if obj and obj:IsA("ModuleScript") then
		return obj
	end
	return nil
end

local function testFeatureToggles()
	local module = getModuleScript("FeatureToggles", ReplicatedStorage)
	if not module then
		print("[FAIL] FeatureToggles: Module not found")
		return
	end

	local success, result = pcall(require, module)
	if not success then
		print("[FAIL] FeatureToggles: Module failed to load")
		return
	end

	if type(result) ~= "table" then
		print("[FAIL] FeatureToggles: Did not return a table")
		return
	end

	local data = result :: any
	if data.FrameworkVersion ~= "ModularFramework Core v1.0.0" then
		print("[FAIL] FeatureToggles: Invalid FrameworkVersion")
		return
	end

	if type(data.DashConfig) == "table" then
		if data.DashConfig.Enabled == nil then
			print("[FAIL] FeatureToggles: DashConfig.Enabled is nil")
			return
		end
	end

	print("[PASS] FeatureToggles: Validation passed")
end

local function testVFXRegistry()
	local module = getModuleScript("VFXRegistry", ReplicatedStorage)
	if not module then
		print("[FAIL] VFXRegistry: Module not found")
		return
	end

	local success, result = pcall(require, module)
	if not success then
		print("[FAIL] VFXRegistry: Module failed to load")
		return
	end

	if type(result) ~= "table" then
		print("[FAIL] VFXRegistry: Did not return a table")
		return
	end

	local data = result :: any
	for key, entry in pairs(data) do
		if type(entry) == "table" then
			if entry.EmitCount == nil and entry.TweenDuration == nil then
				print("[WARN] VFXRegistry: Structural fields missing in entry '" .. tostring(key) .. "'")
			end
		end
	end

	print("[PASS] VFXRegistry: Validation passed")
end

local function testAntiExploitService()
	local module = getModuleScript("AntiExploitService", ServerScriptService)
	if not module then
		print("[FAIL] AntiExploitService: Module not found")
		return
	end

	local success, result = pcall(require, module)
	if not success then
		print("[FAIL] AntiExploitService: Module failed to load")
		return
	end

	if type(result) ~= "table" then
		print("[FAIL] AntiExploitService: Did not return a table")
		return
	end

	local api = result :: any
	if type(api.ValidateAction) ~= "function" then
		print("[FAIL] AntiExploitService: ValidateAction function missing")
		return
	end

	print("[PASS] AntiExploitService: Validation passed")
end

local function runDiagnostics()
	print("[INFO] Starting Framework Diagnostics Pass")
	testFeatureToggles()
	testVFXRegistry()
	testAntiExploitService()
	print("[INFO] Framework Diagnostics Pass Completed")
end

runDiagnostics()
