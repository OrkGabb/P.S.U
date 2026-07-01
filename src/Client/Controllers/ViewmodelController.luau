--!strict
--@author OrkGabb
--@module ViewmodelController.luau
--@version 1.1
-- src/Client/Controllers/ViewmodelController.luau
-- Manages the first-person viewmodel: clone, parent to camera, and animate each frame.
--
-- Equip is ATOMIC: a per-equip generation token ensures that if a new equip arrives
-- before a previous clone completes, the stale clone is silently discarded.
-- The stale viewmodel is destroyed BEFORE cloning the new one — two models never coexist.
--
-- FIX BUG 6: LocalTransparencyModifier is applied ONLY to BasePart instances.
-- Decal is not a BasePart and the property does not exist on it; applying via any-cast
-- silently fails — that was why the body remained visible.
-- Accessory Handles are BaseParts nested under Accessory instances, not direct children
-- of the character; GetDescendants() already reaches them, but the IsA("BasePart") guard
-- now correctly excludes Decal/SpecialMesh etc. that have no such property.
-- The DescendantAdded listener covers parts that stream in after CharacterAdded fires.
--
-- FIX STRAY MESH REGRESSION: the orphaned-part window between vm.Parent and
-- activeViewmodel assignment is closed — the old model is destroyed synchronously
-- inside a single atomic block with the generation check immediately before parenting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Shared          = ReplicatedStorage:WaitForChild("Shared") :: Folder
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver")) :: any

local ViewmodelController = {}

-- ── State ─────────────────────────────────────────────────────────────────────

local activeViewmodel:   Model?               = nil
local renderConnection:  RBXScriptConnection? = nil

-- Generation token: incremented on every LoadViewmodel call.
-- An async clone whose token no longer matches _equipGeneration is discarded.
local _equipGeneration: number = 0

local currentAimOffset = Vector3.new()

-- Transition state (weapon-switch lower/raise tween).
-- WeaponController drives this via SetTransitionOffset.
local _transitionOffset: number = 0  -- Y offset applied on top of currentAimOffset

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- WHY: LocalTransparencyModifier only exists on BasePart.
-- Applying it to a Decal via (part :: any) silently fails in runtime — Decal has
-- no such property — which is why the previous code left the character visible.
local function HidePart(part: Instance): ()
	if part:IsA("BasePart") then
		(part :: BasePart).LocalTransparencyModifier = 1
	end
end

local function HideCharacter(char: Model): ()
	-- Scan all descendants already present at connection time
	for _, part in ipairs(char:GetDescendants()) do
		HidePart(part)
	end
	-- Cover parts that stream in after CharacterAdded fires (e.g. accessories)
	char.DescendantAdded:Connect(HidePart)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function ViewmodelController.Init(): ()
	if not FeatureResolver.IsCategoryActive("FPS_Shooter") then return end
end

function ViewmodelController.Start(): ()
	if not FeatureResolver.IsCategoryActive("FPS_Shooter") then return end

	local Players = game:GetService("Players")

	Players.LocalPlayer.CharacterAdded:Connect(function(char: Model): ()
		ViewmodelController.ClearViewmodel()
		HideCharacter(char)
	end)

	-- Handle initial character that may already exist when Start() runs
	if Players.LocalPlayer.Character then
		HideCharacter(Players.LocalPlayer.Character)
	end
end

-- ── ClearViewmodel ────────────────────────────────────────────────────────────
-- Destroys any currently parented viewmodel and disconnects the render loop.
-- Always called before cloning a new model so two models never coexist.

function ViewmodelController.ClearViewmodel(): ()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if activeViewmodel then
		activeViewmodel:Destroy()
		activeViewmodel = nil
	end
end

-- ── SetTransitionOffset ───────────────────────────────────────────────────────
-- Called by WeaponController during weapon-switch tween.
-- offset: Y world-space drop (negative = lower, 0 = normal).

function ViewmodelController.SetTransitionOffset(offset: number): ()
	_transitionOffset = offset
end

-- ── LoadViewmodel ─────────────────────────────────────────────────────────────
-- Atomic equip pattern:
--   1. Increment generation token immediately (synchronous).
--   2. Destroy the current viewmodel before any other work (synchronous).
--   3. Resolve config and locate template (synchronous — no yield).
--   4. Clone model (synchronous).
--   5. Check token again; if stale, destroy clone and return.
--   6. Parent to camera and start render loop.
-- There is no yield between steps 5 and 6, so no orphaned-part window exists.

function ViewmodelController.LoadViewmodel(weaponKey: string): ()
	if not FeatureResolver.IsCategoryActive("FPS_Shooter") then return end

	-- Step 1: increment generation token (synchronous)
	_equipGeneration += 1
	local myGeneration: number = _equipGeneration

	-- Step 2: destroy existing model before any other work (synchronous)
	ViewmodelController.ClearViewmodel()

	-- Resolve folder name from config
	local fpsConfig = FeatureResolver.GetCategoryConfig("FPS_Shooter")
	local wCfg = fpsConfig and fpsConfig.Weapons and fpsConfig.Weapons[weaponKey]
	if not wCfg then
		warn("[ViewmodelController] No weapon config for key: " .. tostring(weaponKey))
		return
	end

	local folderName: string? = wCfg.ViewmodelFolderName
	if not folderName then
		warn("[ViewmodelController] ViewmodelFolderName missing for key: " .. tostring(weaponKey))
		return
	end

	-- Resolve aim offset from config (done once per equip, not per frame)
	currentAimOffset = typeof(wCfg.AimOffset) == "Vector3" and wCfg.AimOffset or Vector3.new()

	-- Locate the template
	local viewmodelsFolder = ReplicatedStorage:FindFirstChild("Viewmodels")
	if not viewmodelsFolder then
		warn("[ViewmodelController] Viewmodels folder not found in ReplicatedStorage")
		return
	end

	local modelTemplate = viewmodelsFolder:FindFirstChild(folderName :: string)
	if not modelTemplate or not modelTemplate:IsA("Model") then
		warn("[ViewmodelController] Model template not found for ViewmodelFolderName: " .. tostring(folderName))
		return
	end

	-- Check generation token before cloning (no yield has occurred, but keep the guard
	-- in place for any future async loading extension).
	if myGeneration ~= _equipGeneration then
		return
	end

	-- Step 3: clone (synchronous)
	local vm: Model = (modelTemplate :: Model):Clone()

	-- Set PrimaryPart
	local rootPart = vm:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart then
		vm.PrimaryPart = rootPart
	else
		warn("[ViewmodelController] HumanoidRootPart not found in viewmodel: " .. tostring(folderName))
		vm.PrimaryPart = vm:FindFirstChildWhichIsA("BasePart") :: BasePart?
	end

	-- Disable collision / shadows on all parts
	for _, child in ipairs(vm:GetDescendants()) do
		if child:IsA("BasePart") then
			local part = child :: BasePart
			part.CanCollide  = false
			part.CanTouch    = false
			part.CanQuery    = false
			part.CastShadow  = false
		end
	end

	-- Step 4: FINAL generation check immediately before parenting.
	-- This closes the window between clone completion and parenting.
	-- If another equip arrived, destroy the clone and exit cleanly — no orphan.
	if myGeneration ~= _equipGeneration then
		vm:Destroy()
		return
	end

	-- Parent to camera
	local camera = workspace.CurrentCamera
	if not camera then
		warn("[ViewmodelController] No CurrentCamera found")
		vm:Destroy()
		return
	end

	if vm.PrimaryPart then
		vm:PivotTo(camera.CFrame)
	end

	-- Atomic: parent and record activeViewmodel in the same expression boundary.
	-- No code path can call ClearViewmodel() between these two lines because
	-- there is no yield or task boundary here.
	vm.Parent     = camera
	activeViewmodel = vm

	print("[ViewmodelController] Viewmodel loaded: " .. tostring(folderName))

	-- Reset transition offset for new weapon
	_transitionOffset = 0

	-- Start render loop
	renderConnection = RunService.RenderStepped:Connect(function(_dt: number): ()
		local cam = workspace.CurrentCamera
		if not cam or not activeViewmodel or not activeViewmodel.PrimaryPart then return end
		local baseOffset = currentAimOffset + Vector3.new(0, _transitionOffset, 0)
		activeViewmodel:PivotTo(cam.CFrame * CFrame.new(baseOffset))
	end)
end

-- ── GetActiveViewmodel ─────────────────────────────────────────────────────────
-- Returns the currently parented viewmodel Model, or nil if none is loaded.
-- WeaponController uses this to apply procedural sway/bob each RenderStepped.

function ViewmodelController.GetActiveViewmodel(): Model?
	return activeViewmodel
end

return ViewmodelController
