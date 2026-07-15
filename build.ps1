# build.ps1
# Runs `docker compose build` and tees output to logs/build-<timestamp>.log,
# console AND file, so a run doesn't need to be pasted back by hand for
# diagnosis -- the log is just there afterward.
# build.bat is a thin wrapper around this script -- put logic here, not there.

$ErrorActionPreference = "Continue"

# Resolve to this script's own directory (repo root) so docker-compose.yml is
# found regardless of the caller's current directory. pushd/popd (not cd) so
# the caller's CWD is restored on exit -- plain `cd` would leak into the same
# cmd.exe/PowerShell session when this is chained with `&`/`;` (e.g.
# `clean-all.bat & ..\build.bat & test-all.bat` run from integration-tests\),
# leaving the shell in repo root and breaking the next relative command.
$RepoRoot = $PSScriptRoot
Push-Location $RepoRoot
try {
    $LogsDir = Join-Path $RepoRoot "logs"
    New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
    $TS = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile = Join-Path $LogsDir "build-$TS.log"

    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] docker compose build -- log: $LogFile"
    docker compose build 2>&1 | Tee-Object -FilePath $LogFile
    $exitCode = $LASTEXITCODE
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] docker compose build exited $exitCode"
    exit $exitCode
} finally {
    Pop-Location
}
