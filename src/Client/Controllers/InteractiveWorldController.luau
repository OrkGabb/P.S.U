--!strict
--@author OrkGabb
--@module InteractiveWorldController.luau
--@version 1.0
-- src/Client/Controllers/InteractiveWorldController.lua
-- Physical World Controller. Links ProximityPrompts on map NPCs to their corresponding premium UIs.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local Players                = game:GetService("Players")
local CollectionService      = game:GetService("CollectionService")
local LocalPlayer: Player    = Players.LocalPlayer

local InteractiveWorldController = {}

local function GetLocalEvent(eventName: string): BindableEvent
    local folder: Folder = ReplicatedStorage:FindFirstChild("LocalEvents") :: Folder or Instance.new("Folder", ReplicatedStorage)
    folder.Name = "LocalEvents"

    local evt: BindableEvent = folder:FindFirstChild(eventName) :: BindableEvent or Instance.new("BindableEvent", folder)
    evt.Name = eventName

    return evt
end

-- ========================================================================
-- NPC AND ALTAR MAPPING TO UI PANELS
-- ========================================================================
local PromptObjectMapping: {[string]: string} = {
    ["Forge Master"]      = "ToggleForge",
    ["Forge Table"]       = "ToggleForge",
    ["Forge of Souls"]    = "ToggleForge",
    ["Pet Crafter"]       = "ToggleForge",
    ["Pet Rainbow"]       = "ToggleForge",
    ["Premium Merchant"]  = "ToggleStore",
    ["Reroll Altar"]      = "ToggleStore",
    ["Astral Guide"]      = "ToggleProfile",
    ["Effect Pedestal"]   = "ToggleProfile",
    ["Rebirth Shop"]      = "ToggleProfile",
    ["Leaderboard"]       = "ToggleLeaderboard",
    ["Hall of Fame"]      = "ToggleLeaderboard",
    ["Egg Stand"]         = "TogglePets",
    ["EggStand"]          = "TogglePets",
    ["Pet Egg"]           = "TogglePets",
    ["Enchanting Table"]  = "ToggleSkills",
}

local function OnPromptTriggered(prompt: ProximityPrompt, player: Player)
    if player ~= LocalPlayer then return end

    -- 1. Check for attribute metadata
    local menuToggle = prompt:GetAttribute("MenuToggle")
    if type(menuToggle) == "string" and menuToggle ~= "" then
        GetLocalEvent(menuToggle):Fire()
        return
    end

    local triggerRoll = prompt:GetAttribute("TriggerRoll")
    if triggerRoll == true then
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes and remotes:FindFirstChild("RollRequest") then
            local mainInterface = LocalPlayer.PlayerGui:FindFirstChild("MainInterface") :: ScreenGui?
            if mainInterface then
                local rollBtn = mainInterface:FindFirstChild("RollButton") :: TextButton?
                if rollBtn and rollBtn:GetAttribute("IsLocked") ~= true then
                    (remotes.RollRequest :: RemoteEvent):FireServer()
                end
            end
        end
        return
    end

    -- 2. Check for CollectionService tags
    for _, tag in ipairs(CollectionService:GetTags(prompt)) do
        if string.sub(tag, 1, 7) == "Toggle_" then
            local eventName = string.sub(tag, 8)
            GetLocalEvent("Toggle" .. eventName):Fire()
            return
        end
    end

    -- 3. Fallback to mapped metadata based on object text
    local objectText: string = prompt.ObjectText
    local mappedEvent = PromptObjectMapping[objectText]
    if mappedEvent then
        GetLocalEvent(mappedEvent):Fire()
        return
    end

    if string.find(string.lower(objectText), "egg") then
        GetLocalEvent("TogglePets"):Fire()
        return
    end

    if objectText == "Destiny Orb" then
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes and remotes:FindFirstChild("RollRequest") then
            local mainInterface = LocalPlayer.PlayerGui:FindFirstChild("MainInterface") :: ScreenGui?
            if mainInterface then
                local rollBtn = mainInterface:FindFirstChild("RollButton") :: TextButton?
                if rollBtn and rollBtn:GetAttribute("IsLocked") ~= true then
                    (remotes.RollRequest :: RemoteEvent):FireServer()
                end
            end
        end
    end
end

-- ========================================================================
-- LIFECYCLE
-- ========================================================================

function InteractiveWorldController.Init(): ()
    -- Attach centralized O(1) prompt interaction listener
    ProximityPromptService.PromptTriggered:Connect(OnPromptTriggered)
end

function InteractiveWorldController.Start(): () end

return InteractiveWorldController
