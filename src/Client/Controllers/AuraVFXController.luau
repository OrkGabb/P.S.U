--!strict
-- @Author @OrkGabb
-- src/Client/Controllers/AuraVFXController.luau
-- Renders equipped-aura VFX on every character via attachment-based cloning
-- by part-name matching: template Attachments (with their ParticleEmitters
-- and lights) are cloned into the real character part of the same name, so
-- Roblox's native Attachment system handles following rotation/animation on
-- any rig. This replaces the legacy weld/CFrame-copy approach whose clones
-- lost the template offset (crowns clipping into heads) and broke across
-- R6/R15.
--
-- Replication model: AuraService sets the "EquippedAura" player attribute,
-- which Roblox replicates to every client (late joiners included). This
-- controller listens to that attribute for ALL players — no bespoke sync
-- remotes, no per-frame position math.
--
-- Template sources, by priority per template name:
--   1. A Studio-authored rig under
--      ReplicatedStorage.Shared.GlobalAssets.VFXAssets.AuraTemplates/<name>
--      (BaseParts named after character parts, carrying Attachments)
--   2. The procedural spec in Shared/Config/AuraVFXTemplates.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AuraRegistry = require(ReplicatedStorage.Shared.Modules.AuraRegistry)
local AuraVFXTemplates = require(ReplicatedStorage.Shared.Config.AuraVFXTemplates)
local FeatureResolver = require(ReplicatedStorage.Shared.Modules.FeatureResolver)

local EQUIPPED_ATTRIBUTE = "EquippedAura"
local CLONE_TAG = "AuraVFXClone"    -- attribute stamped on every applied clone
local TINT_TAG = "UseAuraColor"     -- attribute marking instances tinted per-aura

-- Template parts that don't exist on the local rig fall back through these
-- alternatives (R15 names first, then R6).
local PART_ALIASES: {[string]: {string}} = {
	["Torso"]      = { "UpperTorso", "LowerTorso" },
	["UpperTorso"] = { "Torso" },
	["LowerTorso"] = { "Torso" },
	["Left Arm"]   = { "LeftUpperArm" },
	["Right Arm"]  = { "RightUpperArm" },
	["Left Leg"]   = { "LeftUpperLeg" },
	["Right Leg"]  = { "RightUpperLeg" },
}

type TemplateEntry = { PartName: string, Attachment: Attachment }

local AuraVFXController = {}

local builtTemplates: {[string]: {TemplateEntry}} = {}
local templateStorage: Folder? = nil
-- Last applied aura per player, so respawns re-apply without waiting for an
-- attribute change.
local appliedAura: {[Player]: string} = {}

-- ─── Template construction ────────────────────────────────────────────────────

local function buildEmitter(spec: AuraVFXTemplates.EmitterSpec): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = spec.Texture
	emitter.Size = spec.Size
	emitter.Transparency = spec.Transparency
	emitter.Lifetime = spec.Lifetime
	emitter.Rate = spec.Rate
	emitter.Speed = spec.Speed
	if spec.Color then
		emitter.Color = spec.Color
	else
		emitter:SetAttribute(TINT_TAG, true)
	end
	if spec.SpreadAngle then emitter.SpreadAngle = spec.SpreadAngle end
	if spec.Acceleration then emitter.Acceleration = spec.Acceleration end
	if spec.RotSpeed then emitter.RotSpeed = spec.RotSpeed end
	if spec.Rotation then emitter.Rotation = spec.Rotation end
	if spec.LightEmission then emitter.LightEmission = spec.LightEmission end
	if spec.LockedToPart then emitter.LockedToPart = spec.LockedToPart end
	if spec.EmissionDirection then emitter.EmissionDirection = spec.EmissionDirection end
	if spec.Drag then emitter.Drag = spec.Drag end
	if spec.ZOffset then emitter.ZOffset = spec.ZOffset end
	return emitter
end

-- Builds a procedural spec into template attachments held in local storage.
local function buildFromSpec(templateName: string, spec: AuraVFXTemplates.TemplateSpec): {TemplateEntry}
	local storage = templateStorage
	if not storage then
		local folder = Instance.new("Folder")
		folder.Name = "AuraVFXTemplateCache"
		folder.Parent = ReplicatedStorage
		templateStorage = folder
		storage = folder
	end

	-- Attachments must live under a BasePart-alike to clone cleanly; a Part
	-- per template keeps the cache inspectable in Studio.
	local holder = Instance.new("Part")
	holder.Name = templateName
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Parent = storage

	local entries: {TemplateEntry} = {}
	for i, attSpec in ipairs(spec.Attachments) do
		local attachment = Instance.new("Attachment")
		attachment.Name = string.format("AuraVFX_%s_%d", templateName, i)
		attachment.Position = attSpec.Offset or Vector3.zero
		for _, emitterSpec in ipairs(attSpec.Emitters) do
			buildEmitter(emitterSpec).Parent = attachment
		end
		if attSpec.Light then
			local light = Instance.new("PointLight")
			light.Brightness = attSpec.Light.Brightness
			light.Range = attSpec.Light.Range
			if attSpec.Light.Color then
				light.Color = attSpec.Light.Color
			else
				light:SetAttribute(TINT_TAG, true)
			end
			light.Parent = attachment
		end
		attachment.Parent = holder
		table.insert(entries, { PartName = attSpec.Part, Attachment = attachment })
	end
	return entries
end

-- Harvests a Studio-authored template rig: every BasePart child is treated
-- as a character part name; its Attachments are the effect sources.
local function buildFromRig(rig: Instance): {TemplateEntry}
	local entries: {TemplateEntry} = {}
	for _, child in ipairs(rig:GetChildren()) do
		if child:IsA("BasePart") then
			for _, attachment in ipairs(child:GetChildren()) do
				if attachment:IsA("Attachment") then
					table.insert(entries, { PartName = child.Name, Attachment = attachment })
				end
			end
		end
	end
	return entries
end

local function getTemplate(templateName: string): {TemplateEntry}?
	local cached = builtTemplates[templateName]
	if cached then
		return cached
	end

	-- Priority 1: hand-authored rig shipped in GlobalAssets
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local globalAssets = shared and shared:FindFirstChild("GlobalAssets")
	local vfxAssets = globalAssets and globalAssets:FindFirstChild("VFXAssets")
	local auraTemplates = vfxAssets and vfxAssets:FindFirstChild("AuraTemplates")
	local rig = auraTemplates and auraTemplates:FindFirstChild(templateName)
	if rig then
		local entries = buildFromRig(rig)
		if #entries > 0 then
			builtTemplates[templateName] = entries
			return entries
		end
	end

	-- Priority 2: procedural spec
	local spec = AuraVFXTemplates[templateName]
	if spec then
		local entries = buildFromSpec(templateName, spec)
		builtTemplates[templateName] = entries
		return entries
	end

	return nil
end

-- ─── Application ──────────────────────────────────────────────────────────────

local function findBodyPart(character: Model, partName: string): BasePart?
	local direct = character:FindFirstChild(partName)
	if direct and direct:IsA("BasePart") then
		return direct
	end
	local aliases = PART_ALIASES[partName]
	if aliases then
		for _, alias in ipairs(aliases) do
			local part = character:FindFirstChild(alias)
			if part and part:IsA("BasePart") then
				return part
			end
		end
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function clearAura(character: Model): ()
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:GetAttribute(CLONE_TAG) then
			descendant:Destroy()
		end
	end
end

local function applyAura(player: Player, auraId: string): ()
	local character = player.Character
	if not character then return end

	clearAura(character)

	if auraId == "" or auraId == "None" then
		appliedAura[player] = "None"
		return
	end
	appliedAura[player] = auraId

	local def = AuraRegistry.GetAuraData(auraId)
	local templateName = def.VFXTemplate
	if not templateName then return end

	local entries = getTemplate(templateName)
	if not entries then
		warn(`[AuraVFXController] No template named "{templateName}" (aura {auraId})`)
		return
	end

	for _, entry in ipairs(entries) do
		local targetPart = findBodyPart(character, entry.PartName)
		if not targetPart then continue end

		local clone = entry.Attachment:Clone()
		clone:SetAttribute(CLONE_TAG, true)
		for _, effect in ipairs(clone:GetDescendants()) do
			if effect:GetAttribute(TINT_TAG) then
				if effect:IsA("ParticleEmitter") then
					effect.Color = ColorSequence.new(def.Color)
				elseif effect:IsA("Light") then
					effect.Color = def.Color
				end
			end
		end
		clone.Parent = targetPart
	end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

local function watchPlayer(player: Player): ()
	player:GetAttributeChangedSignal(EQUIPPED_ATTRIBUTE):Connect(function()
		local auraId = player:GetAttribute(EQUIPPED_ATTRIBUTE)
		applyAura(player, if type(auraId) == "string" then auraId else "None")
	end)

	player.CharacterAdded:Connect(function(character: Model)
		local pending = appliedAura[player]
		if not pending or pending == "None" then return end
		-- Wait for the rig to assemble before mounting attachments
		task.delay(0.3, function()
			if character.Parent and player.Character == character then
				applyAura(player, pending)
			end
		end)
	end)

	local current = player:GetAttribute(EQUIPPED_ATTRIBUTE)
	if type(current) == "string" and current ~= "None" and current ~= "" then
		applyAura(player, current)
	end
end

function AuraVFXController.Init(): ()
end

function AuraVFXController.Start(): ()
	if not FeatureResolver.IsCategoryActive("VFX") then
		return
	end

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		appliedAura[player] = nil
	end)
end

return AuraVFXController
