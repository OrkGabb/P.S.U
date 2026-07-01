--!strict
--@author OrkGabb
--@module ViewmodelHandler.luau
--@version 1.0
-- src/Client/Controllers/ViewmodelHandler.luau
-- Handles first‑person viewmodel creation, attachment to the camera, and simple bobbing/sway animation.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AssetService = require(script.Parent:WaitForChild("AssetService")) :: any

export type CleanupHandle = {
    Disconnect: () -> ()
}

local ViewmodelHandler = {}

-- Creates the viewmodel Model (or nil) and attaches it to the current camera.
function ViewmodelHandler.CreateAndAttach(assetId: number?): Model?
    local vm = AssetService.LoadViewmodel(assetId)
    if not vm then
        return nil
    end
    -- Ensure the model has a PrimaryPart for positioning.
    if not vm.PrimaryPart then
        vm.PrimaryPart = vm:FindFirstChildWhichIsA("BasePart")
    end
    local cam = Workspace.CurrentCamera
    if cam then
        vm.Parent = cam
        -- Position initially at the camera origin.
        vm:SetPrimaryPartCFrame(cam.CFrame)
    end
    return vm
end

-- Starts bobbing and sway animation for the given viewmodel.
-- Returns a cleanup handle that disconnects the RenderStepped connection.
function ViewmodelHandler.StartAnimation(viewmodel: Model, humanoid: Humanoid): CleanupHandle
    local cam = Workspace.CurrentCamera
    local bobCF = CFrame.new()
    local swayCF = CFrame.new()
    local connection = RunService.RenderStepped:Connect(function()
        if not viewmodel.PrimaryPart or not cam then
            return
        end
        local moving = humanoid.MoveDirection.Magnitude > 0
        local runFactor = if moving then 1 else 0
        local walkSpeed = humanoid.WalkSpeed
        local tickTime = tick()
        local bobX = math.cos(tickTime * 5 * walkSpeed / 16) * 0.2
        local bobY = math.abs(math.sin(tickTime * 6 * walkSpeed / 16) * 0.3)
        bobCF = bobCF:Lerp(CFrame.new(bobX * runFactor, bobY * runFactor, 0), 0.4)
        local mouseDelta = UserInputService:GetMouseDelta() / 50
        local swayX = math.clamp(mouseDelta.X, -0.2, 0.2)
        local swayY = math.clamp(mouseDelta.Y, -0.2, 0.2)
        swayCF = swayCF:Lerp(CFrame.new(swayX, swayY, 0), 0.3)
        local finalCF = cam.CFrame * bobCF * swayCF
        viewmodel:SetPrimaryPartCFrame(finalCF)
    end)
    return {Disconnect = function()
        connection:Disconnect()
    end}
end

return ViewmodelHandler