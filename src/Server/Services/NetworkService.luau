--!strict
-- @Author @OrkGabb
-- src/Server/Services/NetworkService.luau
-- Instantiates every remote declared in RemoteNames.Schema with the correct
-- class at boot (Defensive Network Layer: clients can never stall on
-- WaitForChild, and no service can create a wrong-class duplicate).
-- Also provides the FireClient convenience wrapper used by server services.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local NetworkService = {}
local Events: { [string]: RemoteEvent } = {}

function NetworkService.Init(): ()
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	for name, def in pairs(RemoteNames.Schema) do
		local wantedClass = if def.Kind == "Function" then "RemoteFunction" else "RemoteEvent"
		local existing = remotesFolder:FindFirstChild(name)
		if existing and not existing:IsA(wantedClass) then
			-- Wrong-class leftover (pre-schema drift); replace before anything
			-- grabs it. Boot order guarantees no live connections yet.
			warn(("[NetworkService] Remote '%s' existed as %s, expected %s — recreating.")
				:format(name, existing.ClassName, wantedClass))
			existing:Destroy()
			existing = nil
		end
		if not existing then
			existing = Instance.new(wantedClass)
			existing.Name = name
			existing.Parent = remotesFolder
		end
		if existing:IsA("RemoteEvent") then
			Events[name] = existing
		end
	end
end

function NetworkService.FireClient(player: Player, remoteName: string, ...: any)
	local remote = Events[remoteName]
	if remote then
		remote:FireClient(player, ...)
	else
		-- A name outside the schema is SSoT drift — surface it instead of
		-- silently dropping the payload (the old behavior).
		warn(("[NetworkService] FireClient: '%s' is not declared in RemoteNames.Schema — payload dropped.")
			:format(remoteName))
	end
end

return NetworkService
