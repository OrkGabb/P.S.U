# P.S.U. — Setup & Customization Guide

This guide assumes **zero prior knowledge** of this codebase and only basic
familiarity with Roblox Studio. Follow it top to bottom the first time; after
that, each section stands alone.

---

## 1. Install the toolchain

P.S.U. is a [Rojo](https://rojo.space) project: the source code lives in
plain `.luau` files on disk, and Rojo turns them into a Roblox place.

**Option A — Rokit (recommended).** [Rokit](https://github.com/rojo-rbx/rokit)
reads `rokit.toml` and installs the exact Rojo version this project was
built with:

```
rokit install
```

**Option B — manual.** Download Rojo 7.6.x from
https://github.com/rojo-rbx/rojo/releases and put `rojo.exe` on your PATH.

Verify it works — from the project folder (the one containing
`default.project.json`), run:

```
rojo --version
```

## 2. Build and open the game

From the project folder:

```
rojo build default.project.json -o PSU.rbxlx
```

Double-click `PSU.rbxlx` to open it in Roblox Studio, then press **Play**.
You should see the P.S.U. loading screen followed by the currently active
demo mode (Aura Collector out of the box: a roll button, odds panel, and
biome bar at the bottom of the screen).

> **Live-sync workflow (optional, for iterating):** instead of rebuilding
> after every change, run `rojo serve` in a terminal, then in Studio install
> the Rojo plugin and click **Connect**. Edits to the `.luau` files now sync
> into Studio instantly.

### Safe offline testing

`src/Shared/Config/FeatureToggles.luau` → `DebugConfig.MockDataStores = true`
(the default) makes player data live in memory only, so you can playtest in
Studio without DataStore access or API permissions. **You don't need to turn
this off for production** — a safety block at the bottom of FeatureToggles
automatically disables all debug flags when the game runs on a real server.

For a published game you must still enable
**Game Settings → Security → Enable Studio Access to API Services** if you
want to test real saving from Studio.

## 3. Switch the active genre

Open `src/Shared/Config/FeatureToggles.luau` and find the `Genres` table.
Each genre has an `Enabled` flag:

```lua
Genres = {
    FPS_Shooter    = { Enabled = false, ... },
    Clicker_Farm   = { Enabled = false, ... },
    Aura_Collector = { Enabled = true,  ... },   -- ← the active demo
    Pet_Simulator  = { Enabled = false, ... },
    RPG_Adventure  = { Enabled = false },        -- reserved slot for your own genre
},
```

To switch: set the current genre to `false` and exactly one other to `true`.

> **The single-genre rule:** exactly **one** genre may be enabled at a time.
> This is enforced — the framework refuses to boot with two genres on
> (you'll see a "Multiple primary genres active" error in the output). Genres
> share the abstract save schema (Currencies/Progression/GenreData), so each
> player's progress in every genre is kept separately and survives switching.

Everything else about a genre — currency names, HUD elements, costs, pacing —
lives in that genre's config block right there in FeatureToggles. The values
are commented; change numbers, press Play, see the result.

### Global feature flags (work with any genre)

In the same file:

| Flag | What it does |
|---|---|
| `Monetization.Enabled` | Store button + gamepass/product prompts (see §5 first!) |
| `GlobalFlags.Dash` | LeftControl dash ability with server-validated cooldowns |
| `GlobalFlags.AntiExploit` | Teleport/fly detection and auto-kick |
| `Portals` | Physical biome portals in the world |
| `Leaderboards.Enabled` | Physical top-player boards |
| `Admin.Enabled` | In-game admin panel (configure admin UserIds in AdminService) |
| `Branding` | Game name + subtitle shown on the loading screen |

## 4. Where everything is configured

**The rule of thumb: content and numbers live in registries; you never edit
services or controllers to change game data.**

| You want to change… | Edit this file |
|---|---|
| Which genre runs, all pacing/economy numbers | `Shared/Config/FeatureToggles.luau` |
| Gamepass & dev-product IDs, prices, effects | `Shared/Config/CommerceRegistry.luau` |
| Music & sound effects (per genre) | `Shared/Config/AudioRegistry.luau` |
| UI icon asset IDs | `Shared/Config/AssetRegistry.luau` |
| Settings-panel entries | `Shared/Config/SettingsRegistry.luau` |
| Upgrades / masteries (all genres) | `Shared/Modules/UpgradeRegistry.luau` |
| Auras: biomes, drop weights, multipliers, VFX binding | `Shared/Modules/AuraRegistry.luau` |
| Aura VFX looks (particles, lights) | `Shared/Config/AuraVFXTemplates.luau` |
| Pets: eggs, hatch odds, pet appearance | `Shared/Modules/PetRegistry.luau` |
| Weapons: damage, ammo, sounds, viewmodels | `FeatureToggles.luau` → `Genres.FPS_Shooter.Weapons` |
| Consumable potions | `Shared/Modules/ItemRegistry.luau` |
| Quests / daily rewards | `Shared/Modules/QuestRegistry.luau` / `DailyRegistry.luau` |

Adding content = adding one entry to the right registry. Example — a new pet
in the Basic Egg (`PetRegistry.luau`):

```lua
{ Id = "Hamster", DisplayName = "Hamster", Weight = 200, RarityTag = "UNCOMMON",
  Build = { BodyShape = "Ball", BodyColor = Color3.fromRGB(220, 190, 140),
            AccentColor = Color3.fromRGB(250, 245, 235), Scale = 0.7 } },
```

Save, press Play: the egg shop odds list, the hatch roll, the inventory grid,
and the follower model all pick it up automatically. Drop rates are computed
from `Weight` relative to the other pets in the same egg — the UI always
shows the real server odds.

## 5. Before you publish: replace the placeholders

The kit deliberately ships with placeholder IDs you **must** replace:

1. **Monetization IDs** — `Shared/Config/CommerceRegistry.luau`. Every
   gamepass/dev product has a fake ID marked `-- PLACEHOLDER`. Create your
   own passes/products on the Roblox Creator Dashboard and paste the real
   IDs. Keep `Monetization.Enabled = false` until you've done this, or
   purchase prompts will fail.
2. **UI icons** — `Shared/Config/AssetRegistry.luau` (`UI` table) entries
   marked `-- PLACEHOLDER`, plus the `Pets` sidebar icon cell in
   `Client/Controllers/AssetService.luau` if you use Pet_Simulator.
3. **Admin UserIds** — if you enable the Admin panel.
4. **Branding** — `FeatureToggles.Branding` (game name/subtitle).

## 6. Optional drop-in art slots

The framework renders everything procedurally out of the box, and prefers
your hand-made assets automatically when you add them:

| Slot | Where to put it | Used by |
|---|---|---|
| Weapon viewmodels | `ReplicatedStorage/Viewmodels/<WeaponKey>` (a Model per weapon key, e.g. `AR-GUN`) | FPS_Shooter — missing models warn gracefully; the mode still plays |
| Aura VFX rigs | `ReplicatedStorage/Shared/GlobalAssets/VFXAssets/AuraTemplates/<TemplateName>` — a Model/Folder whose BaseParts are named after character parts (`Head`, `HumanoidRootPart`, …) carrying Attachments with your emitters | Aura_Collector — overrides the procedural template with the same name |
| Pet models | `ReplicatedStorage/Shared/GlobalAssets/PetModels/<PetId>` (any Model; it's cloned, anchored, and de-collided automatically) | Pet_Simulator — overrides that pet's procedural build |

Add these in Studio and save the place, or add them to the Rojo project —
either works. **Check the license of anything you drop in**: the base kit is
100% original/engine-shipped content precisely so you can resell your game
safely; keep it that way.

## 7. Publish to Roblox

1. `rojo build default.project.json -o PSU.rbxlx` and open it in Studio
   (skip if you're already connected via `rojo serve`).
2. **File → Publish to Roblox As…** and pick/create your experience.
3. On the Creator Dashboard, enable **Studio Access to API Services** so
   DataStores work when you test the published game from Studio.
4. Playtest on a live server (Studio's Play Solo is not enough for a final
   check — join the published game from the Roblox app).

### Suggested smoke test per genre

- **Clicker_Farm**: click income ticks up, buy an upgrade (5th level charges
  Cupcakes), claim a golden drop.
- **FPS_Shooter**: fire each weapon, headshot an accessorized dummy/player,
  reload-spam doesn't stick the HUD, crouch/slide and respawn cleanly.
- **Aura_Collector**: roll (watch the odds panel), equip/unequip from the
  Index, unlock the Abyssal Rift biome, verify aura VFX on both an R6 and an
  R15 avatar.
- **Pet_Simulator**: hatch both eggs (Royal is level-gated), equip a pet and
  walk/jump/teleport — it should follow smoothly; a second player's pet
  should be visible too.

## 8. Building your own genre (advanced)

The `RPG_Adventure` slot is reserved for exactly this. The short version:

1. Add a full config block for your genre under `FeatureToggles.Genres`
   (copy `Aura_Collector`'s shape: `Enabled`, `Currencies`, `HUD`, then your
   own numbers) and give it a typed `export type` like the other genres.
2. Write a `Server/Services/<YourGenre>Service.luau` and register it in
   `Server/Core/FrameworkServer.luau`'s `OPTIONAL_SERVICES` table with your
   toggle key — that's the only core file you touch, and it's a data table.
3. Write your client controllers under `Client/Controllers/` and gate them
   in `ReplicatedFirst/ClientMain.client.luau`'s skip-list block.
4. Store per-player state via `DataService:GetGenreData(player, "YourGenre")`
   — it persists automatically under the abstract schema.
5. Put every tunable number in a registry, not in your service.

Study `PetService`/`PetController`/`PetsUIController` as the reference — it's
the smallest complete genre (one service, two controllers, one registry).

---

**Support rule:** customization belongs in configs and registries. If you
edit core files (`Server/Core`, `Client/Core`, `DataService`,
`NetworkService`, …), you're on your own — those files are the engine.
