--!strict
--@author OrkGabb
--@module UIEvents.luau
--@version 1.0
-- Single implementation of the client-local event bus. Events are named
-- BindableEvents under ReplicatedStorage.LocalEvents, created on first use by
-- whichever side (firer or listener) asks first — so controllers never need
-- to know about each other, only about event names. Deleting a controller
-- simply leaves its events without a listener; nothing else breaks.
--
-- Menu contract (owned by UIController's coordination handlers):
--   Toggle<MenuId>     — open/close a panel; optional "switch" reason arg
--   NotifyMenuOpened   — fired by a panel after it opens (arg: menu id)
--   NotifyMenuClosed   — fired by a panel after it closes (arg: menu id)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIEvents = {}

function UIEvents.Get(name: string): BindableEvent
	local folder = ReplicatedStorage:FindFirstChild("LocalEvents")
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "LocalEvents"
		newFolder.Parent = ReplicatedStorage
		folder = newFolder
	end

	local evt = (folder :: Folder):FindFirstChild(name)
	if not evt then
		local newEvt = Instance.new("BindableEvent")
		newEvt.Name = name
		newEvt.Parent = folder
		evt = newEvt
	end
	return evt :: BindableEvent
end

return UIEvents
