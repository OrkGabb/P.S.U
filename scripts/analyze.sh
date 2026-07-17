#!/usr/bin/env bash
# Static analysis for P.S.U. Luau sources (POSIX port of scripts/analyze.ps1).
#
# Usage:
#   scripts/analyze.sh                          # analyze all of src/
#   scripts/analyze.sh src/Client/Controllers/UIController.luau [...]
#
# Requires luau-lsp on PATH (installed by `rokit install`; see rokit.toml).
# Roblox API types are vendored at types/globalTypes.d.luau. Regenerate with:
#   https://github.com/JohnnyMorganz/luau-lsp/releases (globalTypes.d.luau asset)
#
# This is a thin wrapper: it delegates to the SAME luau-lsp invocation as
# analyze.ps1 and, like the PowerShell version, assumes sourcemap.json already
# exists (generate it with `rojo sourcemap`).
set -euo pipefail

repoRoot="$(cd "$(dirname "$0")/.." && pwd)"

# Resolve luau-lsp from PATH, falling back to Rokit's shim directory (which is
# not on PATH in non-interactive shells).
if luauLsp="$(command -v luau-lsp 2>/dev/null)"; then
    :
else
    luauLsp="${HOME}/.rokit/bin/luau-lsp"
    if [ ! -x "$luauLsp" ]; then
        echo "luau-lsp not found on PATH or in ~/.rokit/bin. Run 'rokit install' first." >&2
        exit 1
    fi
fi

if [ "$#" -eq 0 ]; then
    set -- "$repoRoot/src"
fi

exec "$luauLsp" analyze \
    --defs="$repoRoot/types/globalTypes.d.luau" \
    --sourcemap="$repoRoot/sourcemap.json" \
    "$@"
