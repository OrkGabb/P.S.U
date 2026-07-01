--!strict
--@author OrkGabb
--@module AssetService.luau
--@version 1.0
-- src/Client/Controllers/AssetService.lua
-- Client-side asset configuration and utility service.

local InsertService = game:GetService("InsertService")

export type IconData = {
    SpriteOffset: Vector2,
    Scale: Vector2,
    PixelShift: Vector2,
}

export type MenuConfig = {
    Id: string,
    Name: string,
    Order: number,
    LevelLocked: boolean,
}

export type FloatingConfig = {
    Id: string,
}

local AssetService = {
    UI = {
        SidebarAssetID   = "rbxassetid://92656818430075" :: string,
        ButtonSize       = 40 :: number,
        BottomButtonSize = 40 :: number,
        IconScale        = Vector2.new(0.85, 0.56) :: Vector2,
        SpriteMatrixSize = Vector2.new(256, 256) :: Vector2, -- size of ONE cell in the sheet
    },

    -- Single source of truth for all navigation icons (sidebar + floating)
    IconMap = {
        -- Sidebar
        Profile   = { SpriteOffset = Vector2.new(768, 512), Scale = Vector2.new(0.8925, 0.8925), PixelShift = Vector2.new(9,    10) } :: IconData,
        Skills    = { SpriteOffset = Vector2.new(256, 256), Scale = Vector2.new(0.8925, 0.8925), PixelShift = Vector2.new(-3,   5) } :: IconData,
        Index     = { SpriteOffset = Vector2.new(512, 0),   Scale = Vector2.new(0.966,  0.966),  PixelShift = Vector2.new(3,  0.1) } :: IconData,
        Quests    = { SpriteOffset = Vector2.new(0,   256), Scale = Vector2.new(0.8925, 0.8925), PixelShift = Vector2.new(-11,  4) } :: IconData,
        Daily     = { SpriteOffset = Vector2.new(256, 0),   Scale = Vector2.new(0.8925, 0.8925), PixelShift = Vector2.new(-3,   1) } :: IconData,
        Store     = { SpriteOffset = Vector2.new(0,   512), Scale = Vector2.new(0.8925, 0.8925), PixelShift = Vector2.new(-11,  4) } :: IconData,
        -- Floating
        Settings  = { SpriteOffset = Vector2.new(0,   0),   Scale = Vector2.new(0.8925, 0.8925), PixelShift = Vector2.new(-10,  -1) } :: IconData,
        Premium   = { SpriteOffset = Vector2.new(768, 0),   Scale = Vector2.new(0.8925, 0.8925), PixelShift = Vector2.new(9,    -1) } :: IconData,
    } :: {[string]: IconData},

    SidebarMenus = {
        { Id = "Profile",   Name = "Profile",   Order = 1, LevelLocked = false } :: MenuConfig,
        { Id = "Skills",    Name = "Skills",    Order = 2, LevelLocked = false } :: MenuConfig,
        { Id = "Index",     Name = "Index",     Order = 3, LevelLocked = false } :: MenuConfig,
        { Id = "Quests",    Name = "Quests",    Order = 4, LevelLocked = false } :: MenuConfig,
        { Id = "Daily",     Name = "Daily",     Order = 5, LevelLocked = false } :: MenuConfig,
    } :: {MenuConfig},

    FloatingButtons = {
        Settings = { Id = "Settings" } :: FloatingConfig,
        Premium  = { Id = "Premium"  } :: FloatingConfig,
    } :: {[string]: FloatingConfig},
}

-- Public API: returns icon metadata { SpriteOffset, PixelShift, Scale } by icon name
function AssetService.GetIconData(iconName: string): IconData?
    return AssetService.IconMap[iconName]
end

-- Public API: applies the sprite sheet configuration directly to an ImageLabel or ImageButton
function AssetService.ApplyIcon(guiObject: ImageLabel | ImageButton, iconName: string): ()
    local data: IconData? = AssetService.IconMap[iconName]
    assert(data, "[AssetService] Icon not found: " .. iconName)
    guiObject.Image           = AssetService.UI.SidebarAssetID
    guiObject.ImageRectOffset = data.SpriteOffset
    guiObject.ImageRectSize   = AssetService.UI.SpriteMatrixSize
    guiObject.Size            = UDim2.new(data.Scale.X, 0, data.Scale.Y, 0)
end

-- Helper to load viewmodel assets safely
function AssetService.LoadViewmodel(assetId: number?): Model?
    if not assetId then return nil end
    local ok, result = pcall(function()
        return InsertService:LoadAsset(assetId)
    end)
    if not ok then
        warn("[AssetService] Failed to load viewmodel asset: " .. tostring(assetId))
        return nil
    end
    if typeof(result) ~= "Model" then
        warn("[AssetService] Loaded asset is not a Model (ID: " .. tostring(assetId) .. ")")
        return nil
    end
    return result :: Model
end

-- Helper to load sound assets safely
function AssetService.LoadSound(soundId: number?): Sound?
    if not soundId then return nil end
    local ok, result = pcall(function()
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxassetid://" .. tostring(soundId)
        return sound
    end)
    if not ok then
        warn("[AssetService] Failed to create sound for ID: " .. tostring(soundId))
        return nil
    end
    if typeof(result) ~= "Sound" then
        warn("[AssetService] Created asset is not a Sound (ID: " .. tostring(soundId) .. ")")
        return nil
    end
    return result :: Sound
end

return AssetService
