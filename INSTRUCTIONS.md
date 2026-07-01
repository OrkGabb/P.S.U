Setup and Customization Instructions

This manual provides the steps necessary to set up, configure, and customize your game. Follow these instructions step-by-step to build your game without editing core programming files.

Setup Guide

To begin working with the framework, follow these steps:

Open the project file: Double-click the file named ModularFramework_Core.rbxl to load the project inside Roblox Studio.

Configure Offline Testing:

Open the file src/Shared/Config/FeatureToggles.luau.

Find the DebugConfig table and set MockDataStores to true to test locally without database errors.

DebugConfig = {
    Enabled = true,
    MockDataStores = true, -- SET TO TRUE FOR SAFE OFFLINE TESTING
    DrawPhysicsVectors = false,
}


Configuration Playbook

The file src/Shared/Config/FeatureToggles.luau controls which game modules are active.

Example 1: Active Clicker Game

To run a pure Clicker game, change the Clicker_Farm setting to true and make sure other modes are set to false.

local FeatureToggles = {
    FPS_Shooter = {
        Enabled = false, -- KEEP FALSE
    },
    Clicker_Farm = {
        Enabled = true, -- CHANGE THIS TO TRUE TO ACTIVATE CLICKER
    },
    Pet_Simulator = {
        Enabled = false, -- KEEP FALSE
    },
}


Example 2: Hybrid RPG + Pets Game

To run a game that combines RPG elements with a Pet system, set both RPG_Adventure and Pet_Simulator to true. The UI menus will automatically arrange themselves on the screen without overlapping.

local FeatureToggles = {
    Clicker_Farm = {
        Enabled = false, -- KEEP FALSE
    },
    Pet_Simulator = {
        Enabled = true, -- CHANGE TO TRUE TO ACTIVATE PET INVENTORIES
    },
    RPG_Adventure = {
        Enabled = true, -- CHANGE TO TRUE TO ACTIVATE RPG SKILL BARS
    },
}


Content Extension Guide

To add new content to your game, you only need to update the registry files. The framework will automatically build the user interface and handle the database logic.

Adding a New Upgrade

Open src/Shared/Registries/UpgradeRegistry.luau. Add a new block of data representing your upgrade.

local UpgradeRegistry = {
    ["CapacityNode"] = {
        StatTarget = "StorageLimit",
        BaseCost = 100,
        CostMultiplier = 1.25,
        MaxLevel = 50,
        ValueMultiplier = 1.0,
        FlatValue = 10
    },
    -- ADD YOUR NEW UPGRADE HERE:
    ["DamageNode"] = {
        StatTarget = "PrimaryDamage",
        BaseCost = 250,
        CostMultiplier = 1.5,
        MaxLevel = 10,
        ValueMultiplier = 1.2,
        FlatValue = 5
    },
}


When you press Play, the UIController will automatically detect DamageNode, create a new visual panel in the Upgrade Menu, format the title, and connect the purchase signals.

UI/UX Customization

The framework allows you to easily customize the size, styles, colors, and layout locations of your menus and UI elements.

Modifying Static Menus

For static menus (such as the player inventory screen, daily reward screen, store panels, and settings panels), you do not need to write code.

In the Explorer window on the right side, find StarterGui.

Locate the UI folder containing the menus.

Select the screen, button, or frame you wish to customize.

In the Properties panel below the Explorer, you can visually edit the Size, Position, BackgroundColor3, Font, and TextColor3.

Modifying Dynamic Scales

For dynamic, code-generated interfaces, you must adjust the scale and sizes inside the specific configuration files provided in the Config folder. The central configuration architecture ensures that button sizes and margins adapt seamlessly across both desktop and mobile platforms.

Hyper-Simple FAQ

What happens if screens get cluttered when enabling everything at once?
If you enable all modules (FPS, Clicker, Pets, and RPG) simultaneously, the interface elements can crowd the screen. We recommend limiting active modules to one or two complementary combinations (for example, combining RPG Adventure and Pet Simulator) to keep the screen organized.

Why do portals or leaderboards fail to spawn in the game?
Physical objects like Portals and Spawns will only instantiate in the workspace if their explicit feature flag is activated. Ensure Portals.Enabled or Leaderboards.Enabled is set to true in FeatureToggles.luau to display them.