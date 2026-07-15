# integration-tests/clean-all.ps1
# Tears down every stack integration-tests/test-all.ps1 can leave behind
# (ai-md-<llm> per-provider projects + the default ai-md project) and
# removes the local artifacts those runs generate.
# clean-all.bat is a thin wrapper around this script -- put logic here, not there.

$ErrorActionPreference = "Continue"
$ScriptStart = Get-Date

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# logs/ is gitignored and timestamped per run, so this run's transcript is on
# disk for direct inspection afterward instead of needing to be pasted back.
$LogsDir = Join-Path $RepoRoot "logs"
New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
$LogFile = Join-Path $LogsDir ("clean-all-{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

function Write-Log {
    # Prefixes every line with a wall-clock timestamp and an elapsed-since-start
    # marker, writes it to the console AND appends it to $LogFile, so a pasted
    # log makes it obvious which step actually ate the time (e.g. a 40s gap
    # between two lines means the command between them was slow, not "hung").
    param([string]$Msg)
    $elapsed = (Get-Date) - $ScriptStart
    $line = "[{0:HH:mm:ss} +{1:mm\:ss}] {2}" -f (Get-Date), $elapsed, $Msg
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

if (-not (Test-Path (Join-Path $RepoRoot ".git"))) {
    Write-Log "[FAIL] repo-root could not verify repo root: no .git at `"$RepoRoot`""
    exit 1
}

# COMPOSE_PROJECT_NAME outranks docker-compose.yml's `name: ai-md-${LLM_NAME}`.
# A stale value left over in this shell session from an older script/run
# would make `docker compose -p ai-md-<x> down` below target the right
# project explicitly regardless -- but clear it anyway so nothing downstream
# (or run manually afterward in this same window) silently picks it up.
Remove-Item Env:\COMPOSE_PROJECT_NAME -ErrorAction SilentlyContinue
Set-Location $RepoRoot

$LlmNames = @("minimax", "openai")

# docker-compose.yml requires LLM_API_KEY to be set (${LLM_API_KEY:?...}) even
# just to parse the file for `down` -- without this, teardown silently no-ops
# and stale containers/mounts survive across runs.
if (-not $env:LLM_API_KEY) {
    $env:LLM_API_KEY = "noop-for-teardown"
}

Write-Log "Undeploying default ai-md project..."
docker compose -p ai-md-default down --remove-orphans *> $null

foreach ($name in $LlmNames) {
    Write-Log "Undeploying ai-md-$name..."
    docker compose -p "ai-md-$name" down --remove-orphans *> $null
    $srcDir = Join-Path $RepoRoot "src\$name"
    $distDir = Join-Path $RepoRoot "dist\$name"
    if (Test-Path $srcDir) { Remove-Item -Recurse -Force $srcDir }
    if (Test-Path $distDir) { Remove-Item -Recurse -Force $distDir }
}

Write-Log "Restoring committed dist/ artifacts..."
git checkout -- dist/tetris.ai.md.html dist/convert.ai.md.py 2>$null

Write-Log "Removing tmp\*..."
$tmpDir = Join-Path $RepoRoot "tmp"
if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }

Write-Log "Done."
exit 0
