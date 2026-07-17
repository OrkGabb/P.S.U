# Static analysis for P.S.U. Luau sources.
#
# Usage:
#   scripts/analyze.ps1                          # analyze all of src/
#   scripts/analyze.ps1 src/Client/Controllers/UIController.luau [...]
#
# Requires luau-lsp on PATH (installed by `rokit install`; see rokit.toml).
# Roblox API types are vendored at types/globalTypes.d.luau. Regenerate with:
#   https://github.com/JohnnyMorganz/luau-lsp/releases (globalTypes.d.luau asset)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

# Resolve luau-lsp from PATH, falling back to Rokit's shim directory (which is
# not on PATH in non-interactive shells).
$luauLsp = Get-Command luau-lsp -ErrorAction SilentlyContinue
if ($luauLsp) {
    $luauLsp = $luauLsp.Source
} else {
    $luauLsp = Join-Path $env:USERPROFILE ".rokit\bin\luau-lsp.exe"
    if (-not (Test-Path $luauLsp)) {
        Write-Error "luau-lsp not found on PATH or in ~/.rokit/bin. Run 'rokit install' first."
    }
}

$targets = $args
if ($targets.Count -eq 0) {
    $targets = @(Join-Path $repoRoot "src")
}

# Ignore globs for the three boot/loader files that perform dynamic requires
# (require of a computed ModuleScript / a runtime-resolved instance). luau-lsp
# cannot statically resolve those require paths and reports "Unknown require:
# unsupported path" — a false positive for this genre-toggle dispatch pattern.
# Keep this list identical to scripts/analyze.sh.
& $luauLsp analyze `
    --defs="$repoRoot\types\globalTypes.d.luau" `
    --sourcemap="$repoRoot\sourcemap.json" `
    --ignore="**/FrameworkServer.luau" `
    --ignore="**/ClientMain.client.luau" `
    --ignore="**/FrameworkClient.luau" `
    @targets
exit $LASTEXITCODE
