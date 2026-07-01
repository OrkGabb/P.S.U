# Graph Report - .  (2026-06-18)

## Corpus Check
- 77 files · ~79,342 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 420 nodes · 584 edges · 55 communities (48 shown, 7 thin omitted)
- Extraction: 84% EXTRACTED · 16% INFERRED · 0% AMBIGUOUS · INFERRED: 95 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Dynamic UI & Status HUD|Dynamic UI & Status HUD]]
- [[_COMMUNITY_Player Dash & Physics|Player Dash & Physics]]
- [[_COMMUNITY_Asset & Sound Loading|Asset & Sound Loading]]
- [[_COMMUNITY_Player Profile & Stats UI|Player Profile & Stats UI]]
- [[_COMMUNITY_Camera Management|Camera Management]]
- [[_COMMUNITY_Anti-Exploit Security|Anti-Exploit Security]]
- [[_COMMUNITY_Game Settings & VFX Toggle|Game Settings & VFX Toggle]]
- [[_COMMUNITY_Item Index & Rarity UI|Item Index & Rarity UI]]
- [[_COMMUNITY_Gamepasses & Purchases|Gamepasses & Purchases]]
- [[_COMMUNITY_Admin Panel Client|Admin Panel Client]]
- [[_COMMUNITY_Client Visual Effects|Client Visual Effects]]
- [[_COMMUNITY_Server Weapon & Hit Detection|Server Weapon & Hit Detection]]
- [[_COMMUNITY_Game Mode Feature Toggles|Game Mode Feature Toggles]]
- [[_COMMUNITY_General UI Navigation|General UI Navigation]]
- [[_COMMUNITY_Clicker Mechanics Client|Clicker Mechanics Client]]
- [[_COMMUNITY_Store Catalog Client|Store Catalog Client]]
- [[_COMMUNITY_Item Forging Client|Item Forging Client]]
- [[_COMMUNITY_Match Statistics Server|Match Statistics Server]]
- [[_COMMUNITY_Main UI HUD Controller|Main UI HUD Controller]]
- [[_COMMUNITY_Quest Tracker Client|Quest Tracker Client]]
- [[_COMMUNITY_Inventory Bag UI|Inventory Bag UI]]
- [[_COMMUNITY_Buff HUD UI|Buff HUD UI]]
- [[_COMMUNITY_UI Scaling & Upgrades|UI Scaling & Upgrades]]
- [[_COMMUNITY_Diagnostics & Testing|Diagnostics & Testing]]
- [[_COMMUNITY_Server Admin Service|Server Admin Service]]
- [[_COMMUNITY_Server Upgrade Mechanics|Server Upgrade Mechanics]]
- [[_COMMUNITY_World Proximity Interactions|World Proximity Interactions]]
- [[_COMMUNITY_Chat VIP Tags Client|Chat VIP Tags Client]]
- [[_COMMUNITY_Client Framework Core|Client Framework Core]]
- [[_COMMUNITY_Server Framework Core|Server Framework Core]]
- [[_COMMUNITY_ProfileService Database Wrapper|ProfileService Database Wrapper]]
- [[_COMMUNITY_Chat Tag Server|Chat Tag Server]]
- [[_COMMUNITY_Offline Debug Config|Offline Debug Config]]
- [[_COMMUNITY_Leaderboards Toggle Config|Leaderboards Toggle Config]]
- [[_COMMUNITY_Portals Toggle Config|Portals Toggle Config]]

## God Nodes (most connected - your core abstractions)
1. `FeatureResolver.IsCategoryActive()` - 31 edges
2. `FeatureResolver.GetConfigField()` - 13 edges
3. `UIController.RegisterHUDButton()` - 12 edges
4. `QuestService.AddProgress()` - 9 edges
5. `FeatureResolver.GetActiveCategories()` - 9 edges
6. `IndexController.Refresh()` - 8 edges
7. `SidebarController.Start()` - 8 edges
8. `SettingsController.Start()` - 7 edges
9. `BagController.Start()` - 6 edges
10. `ClickController.Start()` - 6 edges

## Surprising Connections (you probably didn't know these)
- `ForgeController.Init()` --calls--> `FeatureResolver.IsCategoryActive()`  [INFERRED]
  src/Client/Controllers/ForgeController.luau → src/Shared/Modules/FeatureResolver.luau
- `QuestsController.Init()` --calls--> `FeatureResolver.IsCategoryActive()`  [INFERRED]
  src/Client/Controllers/QuestsController.luau → src/Shared/Modules/FeatureResolver.luau
- `ProcessReceipt()` --calls--> `FeatureResolver.GetConfigField()`  [INFERRED]
  src/Server/Services/MonetizationService.luau → src/Shared/Modules/FeatureResolver.luau
- `FeatureResolver` --references--> `FeatureToggles`  [INFERRED]
  README.md → INSTRUCTIONS.md
- `BagController.Start()` --calls--> `UIController.RegisterHUDButton()`  [INFERRED]
  src/Client/Controllers/BagController.luau → src/Client/Controllers/UIController.luau

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Game Mode Configuration** — config_featuretoggles_fps_shooter, config_featuretoggles_clicker_farm, config_featuretoggles_pet_simulator, config_featuretoggles_rpg_adventure [EXTRACTED 1.00]
- **Data-Driven Gameplay Loop** — modules_featureresolver_featureresolver, registries_upgraderegistry_upgraderegistry, controllers_uicontroller_uicontroller, services_dataservice_dataservice [INFERRED 0.85]

## Communities (55 total, 7 thin omitted)

### Community 0 - "Dynamic UI & Status HUD"
Cohesion: 0.07
Nodes (25): DynamicUIOrchestrator.Start(), FormatSuffix(), GetMaxExp(), StatusHUDController.Init(), StatusHUDController.Start(), UpdateHUD(), WaitForLeaderstats(), FeatureResolver.GetActiveGenre() (+17 more)

### Community 1 - "Player Dash & Physics"
Cohesion: 0.08
Nodes (14): drawPhysicsVectors(), getAnimationId(), performDash(), setupMobileUI(), FeatureResolver.GetConfigField(), LootTable.GetAuraData(), LootTable.GetItemData(), LootTable.LoadEvent() (+6 more)

### Community 2 - "Asset & Sound Loading"
Cohesion: 0.10
Nodes (18): AssetService.ApplyIcon(), AssetService.GetIconData(), AssetService.LoadViewmodel(), DailyUIController.Start(), GetLocalEvent(), GetMidnightUTC(), CreateNotifDot(), CreateToggleArrow() (+10 more)

### Community 3 - "Player Profile & Stats UI"
Cohesion: 0.09
Nodes (13): GetDisplayName(), GetLocalEvent(), ProfileController.Start(), FormatNumber(), InitHUDFromLeaderstats(), TopBarController.Start(), TweenCoins(), UpdateProfile() (+5 more)

### Community 4 - "Camera Management"
Cohesion: 0.15
Nodes (12): CameraController.Init(), CameraController.Start(), cleanCams(), onSeated(), playCamAnimation(), setCharacterTransparency(), setupCharacter(), DebugUtility.Log() (+4 more)

### Community 5 - "Anti-Exploit Security"
Cohesion: 0.24
Nodes (11): DebugUtility.Warn(), AntiExploitService.Init(), AntiExploitService.ValidateAction(), AntiExploitService.ValidateFireRate(), calculateStandardDeviation(), getHumanoid(), getHumanoidRootPart(), incrementSuspicion() (+3 more)

### Community 6 - "Game Settings & VFX Toggle"
Cohesion: 0.27
Nodes (12): ApplyLowEnd(), ApplyOthersVFX(), GetLocalEvent(), RebuildTweens(), RestoreOtherCharacter(), RestoreSnapList(), SettingsController.Start(), StartDescendantWatcher() (+4 more)

### Community 7 - "Item Index & Rarity UI"
Cohesion: 0.32
Nodes (11): FormatSuffix(), GetBestItemId(), GetLocalEvent(), GetRarityColor(), IndexController.Refresh(), IndexController.Start(), IndexController.UpdateDetailsPanel(), RebuildMembershipCache() (+3 more)

### Community 8 - "Gamepasses & Purchases"
Cohesion: 0.18
Nodes (5): MonetizationService.HasGamepass(), ProcessReceipt(), NetworkService.FireClient(), ProbabilityService.Start(), ProcessRoll()

### Community 9 - "Admin Panel Client"
Cohesion: 0.23
Nodes (5): MakeButton(), MakeDualButton(), MakeInput(), MakeSectionHeader(), NextOrder()

### Community 10 - "Client Visual Effects"
Cohesion: 0.29
Nodes (7): ApplyTinting(), GetPlayerBodyPart(), VisualEffectsController.ApplyVisualEffects(), VisualEffectsController.ClearEffects(), VisualEffectsController.Init(), VisualEffectsController.PlayGenericFallbackEffect(), VisualEffectsController.PlayVFX()

### Community 11 - "Server Weapon & Hit Detection"
Cohesion: 0.29
Nodes (9): ApplyWalkSpeed(), ClassifyZone(), FireRay(), GetHumanoid(), GetMatchStats(), GetWeaponConfig(), InitSession(), SyncAmmo() (+1 more)

### Community 12 - "Game Mode Feature Toggles"
Cohesion: 0.24
Nodes (10): Clicker Farm Toggle, FeatureToggles, FPS Shooter Toggle, Pet Simulator Toggle, RPG Adventure Toggle, FeatureResolver, Data-Driven Architecture, ModularFramework (+2 more)

### Community 13 - "General UI Navigation"
Cohesion: 0.33
Nodes (6): BindUpgradePurchase(), GetLocalEvent(), SetSidebarVisible(), ToggleUpgradePanel(), UIController.InitializeDynamicHUD(), UIController.InitializeDynamicPanels()

### Community 14 - "Clicker Mechanics Client"
Cohesion: 0.33
Nodes (5): ClickController.Start(), Format(), GetLocalEvent(), PlayClickSound(), SpawnParticle()

### Community 15 - "Store Catalog Client"
Cohesion: 0.39
Nodes (7): FormatComma(), GetLocalEvent(), InitializeCatalog(), PromptPurchase(), StoreController.PlayPurchaseEffect(), StoreController.RenderCategory(), StoreController.Start()

### Community 17 - "Item Forging Client"
Cohesion: 0.43
Nodes (7): ForgeController.Init(), ForgeController.Refresh(), ForgeController.Start(), ForgeController.UpdateDetailsPanel(), FormatSuffix(), GetLocalEvent(), GetPlayerCoins()

### Community 18 - "Match Statistics Server"
Cohesion: 0.57
Nodes (7): BuildScoreboard(), GetStats(), MatchStatsService.Init(), MatchStatsService.RecordAssist(), MatchStatsService.RecordKill(), MatchStatsService.Start(), ScheduleSync()

### Community 19 - "Main UI HUD Controller"
Cohesion: 0.48
Nodes (5): FormatSuffix(), GetCurrencyValue(), GetCurrentCost(), GetLocalEvent(), MainUIController.Start()

### Community 20 - "Quest Tracker Client"
Cohesion: 0.48
Nodes (6): FormatNumber(), GetLocalEvent(), QuestsController.Init(), QuestsController.Start(), RefreshUI(), WaitForLeaderstats()

### Community 23 - "Inventory Bag UI"
Cohesion: 0.60
Nodes (4): BagController.Refresh(), BagController.Start(), BagController.UpdateDetailsPanel(), GetLocalEvent()

### Community 24 - "Buff HUD UI"
Cohesion: 0.53
Nodes (4): BuffHUDController.Refresh(), BuffHUDController.Start(), isAnyMenuOpen(), onRenderStepped()

### Community 25 - "UI Scaling & Upgrades"
Cohesion: 0.47
Nodes (6): UIController, Dynamic Scale Configuration, Procedural User Interface, CapacityNode, DamageNode, UpgradeRegistry

### Community 26 - "Diagnostics & Testing"
Cohesion: 0.73
Nodes (5): getModuleScript(), runDiagnostics(), testAntiExploitService(), testFeatureToggles(), testVFXRegistry()

### Community 27 - "Server Admin Service"
Cohesion: 0.53
Nodes (4): AdminService.Init(), AdminService.Start(), IsAdmin(), SendFeedback()

### Community 31 - "Client Framework Core"
Cohesion: 0.83
Nodes (3): FrameworkClient.Boot(), FrameworkClient.RegisterController(), isFeatureEnabled()

### Community 32 - "Server Framework Core"
Cohesion: 0.83
Nodes (3): FrameworkServer.Boot(), FrameworkServer.RegisterService(), isFeatureEnabled()

### Community 35 - "Offline Debug Config"
Cohesion: 0.67
Nodes (3): DebugConfig, MockDataStores, Offline Testing Setup

## Knowledge Gaps
- **8 isolated node(s):** `DebugConfig`, `FPS Shooter Toggle`, `Clicker Farm Toggle`, `Pet Simulator Toggle`, `RPG Adventure Toggle` (+3 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `FeatureResolver.IsCategoryActive()` connect `Dynamic UI & Status HUD` to `Asset & Sound Loading`, `Player Profile & Stats UI`, `Camera Management`, `Client Visual Effects`, `General UI Navigation`, `Clicker Mechanics Client`, `Store Catalog Client`, `Item Forging Client`, `Main UI HUD Controller`, `Quest Tracker Client`, `Inventory Bag UI`, `Server Admin Service`?**
  _High betweenness centrality (0.333) - this node is a cross-community bridge._
- **Why does `UIController.RegisterHUDButton()` connect `Asset & Sound Loading` to `Player Profile & Stats UI`, `Game Settings & VFX Toggle`, `Item Index & Rarity UI`, `General UI Navigation`, `Store Catalog Client`, `Item Forging Client`, `Quest Tracker Client`, `Inventory Bag UI`?**
  _High betweenness centrality (0.135) - this node is a cross-community bridge._
- **Why does `FeatureResolver.GetConfigField()` connect `Player Dash & Physics` to `Dynamic UI & Status HUD`, `Player Profile & Stats UI`, `Gamepasses & Purchases`, `General UI Navigation`, `Match Statistics Server`?**
  _High betweenness centrality (0.097) - this node is a cross-community bridge._
- **Are the 29 inferred relationships involving `FeatureResolver.IsCategoryActive()` (e.g. with `BagController.Start()` and `ClickController.Start()`) actually correct?**
  _`FeatureResolver.IsCategoryActive()` has 29 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `FeatureResolver.GetConfigField()` (e.g. with `performDash()` and `setupMobileUI()`) actually correct?**
  _`FeatureResolver.GetConfigField()` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `UIController.RegisterHUDButton()` (e.g. with `BagController.Start()` and `DailyUIController.Start()`) actually correct?**
  _`UIController.RegisterHUDButton()` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 7 inferred relationships involving `QuestService.AddProgress()` (e.g. with `OnClickReward()` and `ForgeService.Start()`) actually correct?**
  _`QuestService.AddProgress()` has 7 INFERRED edges - model-reasoned connections that need verification._