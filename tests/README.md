# P.S.U. unit spec suite

Headless unit tests for the framework's pure logic, run with
[Lune](https://lune-org.github.io/docs) — no Roblox Studio required, so the
suite runs on a plain Linux CI runner.

## Running

```sh
rokit install            # installs lune (pinned in rokit.toml) + the rest
lune run tests/run.luau
```

The process exits non-zero if any case fails.

## What's covered (first cut)

| Spec | Module under test |
|---|---|
| `specs/RollEngine.spec.luau` | `Shared/Modules/RollEngine` — weighted-roll core |
| `specs/UpgradeRegistry.spec.luau` | `Shared/Modules/UpgradeRegistry` — cost/milestone/effect math |
| `specs/FeatureResolver.spec.luau` | `Shared/Modules/FeatureResolver` — genre resolution |
| `specs/Smoke.spec.luau` | load-smoke checks folded in from the retired `FrameworkTestRunner` |

## How the shim works

The framework's shared modules are authored for the Roblox VM: at module scope
they call `game:GetService("ReplicatedStorage")` and `require(<instance>)`, and
`FeatureToggles` constructs `Vector3`/`Color3`/`Enum` values. Lune has none of
those. `lune/psu.luau` bridges the gap — it evaluates a module from disk under a
controlled global environment that supplies a filesystem-backed
`game`/`ReplicatedStorage` instance proxy, an instance-aware `require`, and
inert datatype stubs. See the header comment in that file for detail.

- `psu.load(rel)` loads a module with its real on-disk dependencies.
- `psu.loadWith(rel, overrides)` loads it fresh with specific dependency modules
  replaced by stubs (used to feed `FeatureResolver` synthetic `FeatureToggles`
  for each resolution scenario).

`rel` is a `src`-relative module path without extension, e.g.
`"Shared/Modules/RollEngine"`.

Spec/harness/shim files are intentionally outside `src/` (so Rojo never builds
them into the game) and are marked `--!nocheck` (they use Lune-only `@lune/*`
requires that `luau-lsp analyze` — which targets `src/` — does not see).
