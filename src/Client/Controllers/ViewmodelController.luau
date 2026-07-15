--!strict
-- @Author @OrkGabb
-- Manages the first-person viewmodel: clone, parent to camera, expose state.
--
-- RENDER AUTHORITY: this module does NOT run its own RenderStepped loop.
-- WeaponController owns the single per-frame PivotTo (composing viewmodel
-- offset, sway, bob, ADS and switch-transition). Two competing render loops
-- previously fought over the same model — whichever connection ran last won,
-- and the winner changed after every weapon switch (the historical
-- viewmodel-desync bug). This module only provides the model and offsets.
--
-- Equip is ATOMIC: a per-equip generation token ensures that if a new equip arrives
-- before a previous clone completes, the stale clone is silently discarded.
-- The stale viewmodel is destroyed BEFORE cloning the new one — two models never coexist.
--
-- LocalTransparencyModifier is applied ONLY to BasePart instances. Decal is
-- not a BasePart and the property doesn't exist on it; applying via any-cast
-- silently failed, which is why the body used to stay visible. Accessory
-- Handles are BaseParts nested under Accessory instances, not direct children
-- of the character, but GetDescendants() already reaches them. The
-- DescendantAdded listener covers parts that stream in after CharacterAdded fires.
--
-- The orphaned-part window between vm.Parent and activeViewmodel assignment
-- is closed by destroying the old model synchronously, inside a single atomic
-- block with the generation check immediately before parenting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared          = ReplicatedStorage:WaitForChild("Shared") :: Folder
local FeatureResolver = require(Shared:WaitForChild("Modules"):WaitForChild("FeatureResolver")) :: any

local ViewmodelController = {}

local activeViewmodel: Model? = nil

-- Generation token: incremented on every LoadViewmodel call.
-- An async clone whose token no longer matches _equipGeneration is discarded.
local _equipGeneration: number = 0

local currentAimOffset = Vector3.new()

-- Transition state (weapon-switch lower/raise tween), driven by WeaponController via SetTransitionOffset.
local _transitionOffset: number = 0  -- Y offset applied on top of currentAimOffset

-- LocalTransparencyModifier only exists on BasePart; applying it to a Decal
-- via (part :: any) silently fails, which is why the character used to stay visible.
local function HidePart(part: Instance): ()
	if part:IsA("BasePart") then
		(part :: BasePart).LocalTransparencyModifier = 1
	end
end

local function HideCharacter(char: Model): ()
	for _, part in ipairs(char:GetDescendants()) do
		HidePart(part)
	end
	-- Cover parts that stream in after CharacterAdded fires (e.g. accessories)
	char.DescendantAdded:Connect(HidePart)
end

function ViewmodelController.Init(): ()
	if not FeatureResolver.IsCategoryActive("FPS_Shooter") then return end
end

function ViewmodelController.Start(): ()
	if not FeatureResolver.IsCategoryActive("FPS_Shooter") then return end

	local Players = game:GetService("Players")

	-- Without forcing first person, the camera stays default third-person:
	-- the locally-hidden character plus a camera-parented viewmodel looks
	-- broken from any zoomed-out distance, and the crosshair no longer
	-- corresponds to the shot origin.
	Players.LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson

	Players.LocalPlayer.CharacterAdded:Connect(function(char: Model): ()
		ViewmodelController.ClearViewmodel()
		HideCharacter(char)
	end)

	-- Handle initial character that may already exist when Start() runs
	if Players.LocalPlayer.Character then
		HideCharacter(Players.LocalPlayer.Character)
	end
end

-- Always called before cloning a new model so two models never coexist.
function ViewmodelController.ClearViewmodel(): ()
	if activeViewmodel then
		activeViewmodel:Destroy()
		activeViewmodel = nil
	end
end

-- Called by WeaponController during weapon-switch tween.
-- offset: Y world-space drop (negative = lower, 0 = normal).
function ViewmodelController.SetTransitionOffset(offset: number): ()
	_transitionOffset = offset
end

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

	_equipGeneration += 1
	local myGeneration: number = _equipGeneration

	-- Destroy existing model before any other work (synchronous)
	ViewmodelController.ClearViewmodel()

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

	-- Resolved once per equip, not per frame
	currentAimOffset = typeof(wCfg.AimOffset) == "Vector3" and wCfg.AimOffset or Vector3.new()

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

	-- No yield has occurred yet, but check again anyway before cloning
	if myGeneration ~= _equipGeneration then
		return
	end

	local vm: Model = (modelTemplate :: Model):Clone()

	local rootPart = vm:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart then
		vm.PrimaryPart = rootPart
	else
		warn("[ViewmodelController] HumanoidRootPart not found in viewmodel: " .. tostring(folderName))
		vm.PrimaryPart = vm:FindFirstChildWhichIsA("BasePart") :: BasePart?
	end

	for _, child in ipairs(vm:GetDescendants()) do
		if child:IsA("BasePart") then
			local part = child :: BasePart
			part.CanCollide  = false
			part.CanTouch    = false
			part.CanQuery    = false
			part.CastShadow  = false
		end
	end

	-- Final generation check immediately before parenting closes the window
	-- between clone completion and parenting. If another equip arrived,
	-- destroy the clone and exit cleanly — no orphan.
	if myGeneration ~= _equipGeneration then
		vm:Destroy()
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		warn("[ViewmodelController] No CurrentCamera found")
		vm:Destroy()
		return
	end

	if vm.PrimaryPart then
		vm:PivotTo(camera.CFrame)
	end

	-- No code path can call ClearViewmodel() between these two lines because
	-- there is no yield or task boundary here.
	vm.Parent     = camera
	activeViewmodel = vm

	print("[ViewmodelController] Viewmodel loaded: " .. tostring(folderName))

	-- Per-frame positioning is owned by WeaponController (single render authority)
	_transitionOffset = 0
end

-- Offset accessors, consumed by WeaponController's render pass.

-- Per-weapon ADS offset from config (applied while scoped).
function ViewmodelController.GetAimOffset(): Vector3
	return currentAimOffset
end

-- Y drop applied during the weapon-switch lower/raise tween.
function ViewmodelController.GetTransitionOffset(): number
	return _transitionOffset
end

-- WeaponController uses this to apply procedural sway/bob each RenderStepped.
function ViewmodelController.GetActiveViewmodel(): Model?
	return activeViewmodel
end

return ViewmodelController
