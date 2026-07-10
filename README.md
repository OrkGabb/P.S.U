# P.S.U. — Project Script Universal

**One engine. Four complete games. Zero code required to switch genres.**

P.S.U. is a genre-agnostic Roblox game framework written in strictly-typed
Luau. It ships as a single Rojo project containing a hardened core engine
plus **four fully playable demo modes** that all run on that same core:

| Mode | Genre pattern it proves | Highlights |
|---|---|---|
| **Clicker_Farm** | Idle/clicker economy | Click + passive income, milestone upgrade costs, cupcake secondary currency, golden-drop bonus events, anti-macro protection |
| **FPS_Shooter** | Server-authoritative combat | Hitscan with accessory punch-through, 4 weapons (AR/pistol/shotgun/sniper), ADS + scope, sprint/slide/crouch movement, first-person viewmodels |
| **Aura_Collector** | RNG collection (Sol's-RNG style) | Weighted rolls with visible odds, pity system, 12 rarity tiers, equippable aura VFX that work on any rig (R6/R15), collection index, auto-roll |
| **Pet_Simulator** | Egg-hatching companions | Currency-gated eggs, visible hatch odds, pet inventory, equippable companions that follow the player |

Exactly **one** genre is active at a time — you pick it by flipping a single
boolean in one config file. Any demo can be run as-is, reskinned, or gutted
and rebuilt into a new genre on the same core.

## The philosophy

- **The core never changes.** Genre logic lives in swappable services,
  controllers, and registries. Core files (data, networking, anti-exploit,
  UI shell) contain zero genre-specific code — adding a fifth genre means
  adding files and a config entry, not editing the engine.
- **Config ≠ Logic ≠ Data ≠ UI.** Every number a designer might tune —
  costs, drop rates, weapon damage, roll cooldowns — lives in exactly one
  registry or config file. Services validate against the same registry the
  UI displays, so what the player sees can never disagree with what the
  server does.
- **The server is the authority.** Clients send requests; the server
  validates cooldowns, costs, hit registration, and RNG. An exploiter
  editing their client cannot mint currency, skip cooldowns, or fake rolls.
- **Strictly typed.** Every first-party file is `--!strict` Luau and the
  repo analyzes clean with `luau-lsp` (the only vendored third-party module,
  ProfileService, is wrapped behind a typed facade).

## What's in the box

```
PSU/
├── default.project.json      Rojo project (builds the whole game)
├── rokit.toml                Pins the Rojo toolchain version
├── src/
│   ├── Server/               Core services + genre services (PetService, AuraService, …)
│   ├── Client/               Core controllers + genre controllers and UIs
│   ├── Shared/
│   │   ├── Config/           FeatureToggles, CommerceRegistry, AudioRegistry, …
│   │   └── Modules/          Content registries (AuraRegistry, PetRegistry, …) + shared logic
│   └── ReplicatedFirst/      Loading screen + client bootstrapper
├── README.md                 You are here
└── INSTRUCTIONS.md           Step-by-step setup, publishing, and customization
```

Core systems included with every genre: ProfileService-backed persistence
with schema reconciliation, session-locked data, leaderstats, leveling,
quests, daily rewards, consumable buff items, monetization scaffolding
(gamepasses/dev products via one registry), physical leaderboards, portals,
an anti-exploit layer, a settings panel, and a procedural UI shell (sidebar,
top bar, store, inventory) that genres plug into.

## Getting started

Read **[INSTRUCTIONS.md](INSTRUCTIONS.md)**. It assumes you have never used
Rojo or this codebase and walks through: installing the toolchain, building
and opening the place, switching genres, replacing the placeholder
monetization IDs and icons, adding your own content to the registries, and
publishing to Roblox.

## Why this exists

This is a portfolio project: a demonstration of building one system that
generalizes across genres instead of four one-off prototypes. The interesting
parts are architectural —

- **`FeatureResolver`** is the single source of truth for "what's running."
  It resolves exactly one active genre from `FeatureToggles.Genres` at boot
  (with an explicit `AllowMultipleGenres` opt-out for anyone who wants
  several genres live at once), and every service/controller asks it
  `IsCategoryActive(...)` instead of reading raw config flags directly. Adding
  a fifth genre is a config entry and new files, not a change to that
  resolution logic.
- **Type-safety pass.** The codebase is `--!strict` throughout, and shared
  client/server data shapes (quest progress, genre payloads, profile schema)
  are centralized in `Shared/Types/PSUTypes.luau` rather than left as `any`
  at each call site — the kind of cleanup that's easy to defer and easy to
  regret deferring.
- **Static analysis is enforced, not aspirational.** `luau-lsp analyze` runs
  clean across `src/` (see `scripts/analyze.ps1`); the only vendored
  third-party module, ProfileService, is wrapped behind a typed facade so
  the boundary between "code I wrote and typed" and "code I vendored" stays
  visible.

All code is original to this framework. Aura VFX are procedural and use only
Roblox-engine-shipped particle textures; pet models are procedurally built at
runtime.
