--!strict
--@author OrkGabb
--@module DailyUIController.luau
--@version 1.0
-- src/Client/Controllers/DailyUIController.lua
-- Daily reward UI Controller. Integrates HUD button registration and midnight boundary checks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyUIController = {}

local function GetLocalEvent(eventName: string): BindableEvent
	local folder: Folder? = ReplicatedStorage:FindFirstChild("LocalEvents") :: Folder?
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "LocalEvents"
		newFolder.Parent = ReplicatedStorage
		folder = newFolder
	end
	local evt: BindableEvent? = (folder :: Folder):FindFirstChild(eventName) :: BindableEvent?
	if not evt then
		local newEvt = Instance.new("BindableEvent")
		newEvt.Name = eventName
		newEvt.Parent = folder :: Folder
		evt = newEvt
	end
	return evt :: BindableEvent
end

local function GetMidnightUTC(): number
	local now: number = os.time()
	return now - (now % 86400)
end

function DailyUIController.Init(): ()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 0.1) :: Folder?
	if not remotes then
		warn("[INFO] DailyUIController Suspension: Remote not found.")
		return
	end

	local updateDaily = remotes:WaitForChild("UpdateDaily", 0.1) :: RemoteEvent?
	if not updateDaily then
		warn("[INFO] DailyUIController Suspension: Remote not found.")
		return
	end
end

function DailyUIController.Start(): ()
	local UIController: any = require(script.Parent:WaitForChild("UIController"))
	local handle = UIController.RegisterHUDButton({
		Id = "Daily",
		Name = "DAILY",
		IconId = "Daily",
		Type = "Sidebar",
		LayoutOrder = 5,
		OnClick = function(): ()
			GetLocalEvent("ToggleDaily"):Fire()
		end
	})

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 0.1) :: Folder?
	if remotes then
		local updateDaily = remotes:WaitForChild("UpdateDaily", 0.1) :: RemoteEvent?
		if updateDaily then
			updateDaily.OnClientEvent:Connect(function(data: any): ()
				if data then
					local lastClaim: number = data.LastClaim or 0
					handle.SetNotificationActive(lastClaim < GetMidnightUTC())
				end
			end)
		end
	end
end

return DailyUIController
