--!strict
-- @Author @OrkGabb
-- Genre-agnostic: everything it plays is resolved through AudioRegistry for
-- the active genre, so enabling a different genre changes the soundscape
-- with zero code changes here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local AudioRegistry = require(ReplicatedStorage.Shared.Config.AudioRegistry)

local AudioController = {}

local sfxCache: {[string]: Sound} = {}

local function getSfxSound(name: string): Sound?
	local cached = sfxCache[name]
	if cached then
		return cached
	end

	local def = AudioRegistry.GetSFX(name)
	if not def then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = "SFX_" .. name
	sound.SoundId = def.SoundId
	sound.Volume = def.Volume or 0.5
	sound.Parent = SoundService
	sfxCache[name] = sound
	return sound
end

-- Unknown names are a no-op so genre code can call this unconditionally.
function AudioController.PlaySFX(name: string): ()
	local sound = getSfxSound(name)
	if not sound then
		return
	end

	local def = AudioRegistry.GetSFX(name)
	if def and def.RandomPitch then
		sound.PlaybackSpeed = (def.PlaybackSpeed or 1) * (math.random(90, 110) / 100)
	elseif def and def.PlaybackSpeed then
		sound.PlaybackSpeed = def.PlaybackSpeed
	end

	sound:Play()
end

local function startBGM(): ()
	local playlist, volume = AudioRegistry.GetBGM()
	if #playlist == 0 then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "BGM"
	sound.Volume = volume
	sound.Parent = SoundService

	task.spawn(function()
		local index = 1
		while sound.Parent do
			sound.SoundId = playlist[index]
			sound:Play()
			sound.Ended:Wait()
			index = (index % #playlist) + 1
		end
	end)
end

function AudioController.Init(): ()
end

function AudioController.Start(): ()
	startBGM()
end

return AudioController
