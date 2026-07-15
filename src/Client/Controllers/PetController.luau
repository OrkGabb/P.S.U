--!strict
-- @Author @OrkGabb
-- Renders every player's equipped pet as a floating companion that follows
-- its owner. Pets are anchored, non-colliding client-side models moved by an
-- exponential-smoothing CFrame lerp each frame — no server physics, no
-- network traffic per frame.
--
-- Replication model: PetService sets the "EquippedPet" player attribute,
-- which Roblox replicates to every client (late joiners included). This
-- controller listens to that attribute for ALL players — the same pattern
-- AuraVFXController uses for auras.
--
-- Model sources, by priority per pet id:
--   1. A hand-made rig under
--      ReplicatedStorage.Shared.GlobalAssets.PetModels/<petId> (any Model;
--      cloned, anchored and de-collided automatically)
--   2. An original procedural build from PetRegistry's PetBuild recipe
--      (no third-party assets shipped — see STATUS.md license notes)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PetRegistry = require(ReplicatedStorage.Shared.Modules.PetRegistry)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local GENRE_KEY = "Pet_Simulator"
local EQUIPPED_ATTRIBUTE = "EquippedPet"
-- Beyond this distance the pet snaps instead of lerping (owner teleported)
local SNAP_DISTANCE = 60

local PetController = {}

type PetState = {
	Model: Model,
	Position: Vector3,
	-- Deterministic per-player phase so a crowd of pets doesn't bob in sync
	BobPhase: number,
}

local activePets: {[Player]: PetState} = {}
local petsFolder: Folder? = nil

local function cfgNum(field: string, default: number): number
	local value = FeatureResolver.GetConfigField(GENRE_KEY, field, default)
	return if type(value) == "number" then value else default
end

-- Model construction

local function makePart(shape: Enum.PartType, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Original procedural companion: body + head + ears + tail + eyes, tinted
-- from the registry recipe. Every part is positioned relative to the body so
-- Model:PivotTo moves the whole rig.
local function buildProceduralModel(def: PetRegistry.PetDef): Model
	local build = def.Build
	local s = build.Scale
	local bodyMaterial = if build.Glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local shape = if build.BodyShape == "Block" then Enum.PartType.Block else Enum.PartType.Ball

	local model = Instance.new("Model")
	model.Name = "Pet_" .. def.Id

	local body = makePart(shape, Vector3.new(1.5, 1.3, 1.9) * s, build.BodyColor, bodyMaterial)
	body.Name = "Body"
	body.Parent = model
	model.PrimaryPart = body

	local origin = body.CFrame

	local head = makePart(shape, Vector3.new(1.1, 1.1, 1.1) * s, build.BodyColor, bodyMaterial)
	head.Name = "Head"
	head.CFrame = origin * CFrame.new(0, 0.75 * s, -0.85 * s)
	head.Parent = model

	for _, side in ipairs({ -1, 1 }) do
		local ear = makePart(Enum.PartType.Ball, Vector3.new(0.35, 0.45, 0.35) * s, build.AccentColor, bodyMaterial)
		ear.Name = "Ear"
		ear.CFrame = head.CFrame * CFrame.new(0.38 * s * side, 0.55 * s, 0)
		ear.Parent = model

		local eye = makePart(Enum.PartType.Ball, Vector3.new(0.16, 0.16, 0.1) * s, build.EyeColor or Color3.fromRGB(25, 25, 30), Enum.Material.SmoothPlastic)
		eye.Name = "Eye"
		eye.CFrame = head.CFrame * CFrame.new(0.24 * s * side, 0.08 * s, -0.52 * s)
		eye.Parent = model
	end

	local tail = makePart(Enum.PartType.Ball, Vector3.new(0.4, 0.4, 0.4) * s, build.AccentColor, bodyMaterial)
	tail.Name = "Tail"
	tail.CFrame = origin * CFrame.new(0, 0.35 * s, 1.05 * s)
	tail.Parent = model

	if build.Glow then
		local light = Instance.new("PointLight")
		light.Color = build.BodyColor
		light.Brightness = 0.8
		light.Range = 8
		light.Parent = body
	end

	return model
end

-- Owner + pet name tag, tinted by rarity.
local function attachNameTag(model: Model, def: PetRegistry.PetDef, owner: Player): ()
	local primary = model.PrimaryPart
	if not primary then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PetTag"
	billboard.Size = UDim2.new(0, 120, 0, 28)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.6 * def.Build.Scale + 0.6, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 60

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = string.format("%s's %s", owner.DisplayName, def.DisplayName)
	label.TextColor3 = PetRegistry.GetRarity(def.RarityTag).Color
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = label

	billboard.Parent = primary
end

-- Hand-made rig override: any Model dropped under GlobalAssets/PetModels
-- named after the pet id wins over the procedural build.
local function findRigOverride(petId: string): Model?
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local globalAssets = shared and shared:FindFirstChild("GlobalAssets")
	local petModels = globalAssets and globalAssets:FindFirstChild("PetModels")
	local rig = petModels and petModels:FindFirstChild(petId)
	if rig and rig:IsA("Model") then
		return rig
	end
	return nil
end

local function buildPetModel(def: PetRegistry.PetDef, owner: Player): Model
	local override = findRigOverride(def.Id)
	local model: Model
	if override then
		model = override:Clone()
		-- Anchor + de-collide so the follow lerp owns all movement
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
		if not model.PrimaryPart then
			model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
		end
	else
		model = buildProceduralModel(def)
	end
	attachNameTag(model, def, owner)
	return model
end

-- Follow loop

local function getStorageFolder(): Folder
	local existing = petsFolder
	if existing and existing.Parent then
		return existing
	end
	local found = workspace:FindFirstChild("ClientPets")
	if found and found:IsA("Folder") then
		petsFolder = found
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientPets"
	folder.Parent = workspace
	petsFolder = folder
	return folder
end

local function updatePet(player: Player, state: PetState, dt: number, now: number): ()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local primary = state.Model.PrimaryPart
	if not hrp or not primary then return end

	local followDistance = cfgNum("FollowDistance", 4)
	local hoverHeight = cfgNum("HoverHeight", 2)
	local responsiveness = cfgNum("FollowResponsiveness", 8)
	local bobAmplitude = cfgNum("BobAmplitude", 0.35)

	local bob = math.sin(now * 2 + state.BobPhase) * bobAmplitude
	local target = hrp.Position
		+ hrp.CFrame.RightVector * followDistance
		+ Vector3.new(0, hoverHeight + bob - 1, 0)

	if (target - state.Position).Magnitude > SNAP_DISTANCE then
		state.Position = target -- owner teleported; don't fly across the map
	else
		-- Frame-rate independent exponential smoothing
		local alpha = 1 - math.exp(-responsiveness * dt)
		state.Position = state.Position:Lerp(target, alpha)
	end

	-- Face the owner's heading (yaw only), keeping the pet level
	local look = hrp.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.zAxis
	end
	state.Model:PivotTo(CFrame.lookAt(state.Position, state.Position + flatLook.Unit))
end

-- Equip application

local function clearPet(player: Player): ()
	local state = activePets[player]
	if state then
		state.Model:Destroy()
		activePets[player] = nil
	end
end

local function applyPet(player: Player, petId: string): ()
	clearPet(player)
	if petId == "" or petId == "None" then return end

	local def = PetRegistry.GetPetData(petId)
	if def.Id == "None" then return end

	local model = buildPetModel(def, player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local startPos = if hrp then hrp.Position + Vector3.new(0, cfgNum("HoverHeight", 2), 0) else Vector3.zero
	model:PivotTo(CFrame.new(startPos))
	model.Parent = getStorageFolder()

	activePets[player] = {
		Model = model,
		Position = startPos,
		BobPhase = (player.UserId % 10) * 0.63,
	}
end

local function watchPlayer(player: Player): ()
	player:GetAttributeChangedSignal(EQUIPPED_ATTRIBUTE):Connect(function()
		local petId = player:GetAttribute(EQUIPPED_ATTRIBUTE)
		applyPet(player, if type(petId) == "string" then petId else "None")
	end)

	local current = player:GetAttribute(EQUIPPED_ATTRIBUTE)
	if type(current) == "string" and current ~= "None" and current ~= "" then
		applyPet(player, current)
	end
end

-- Lifecycle

function PetController.Init(): ()
end

function PetController.Start(): ()
	if not FeatureResolver.IsCategoryActive(GENRE_KEY) then
		return
	end

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end

	Players.PlayerRemoving:Connect(clearPet)

	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		for player, state in pairs(activePets) do
			updatePet(player, state, dt, now)
		end
	end)
end

return PetController
