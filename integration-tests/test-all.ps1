# integration-tests/test-all.ps1
#
# Sequential integration test across every supported LLM provider (Windows).
# Ports integration-tests/test-all.sh 1:1 -- keep both in sync. Flow per provider:
#   Flow A (cache/watcher): tetris.ai.md / convert.ai.md (committed prebuilt
#     artifacts) -- verifies prebuilt-serving, background rebuild-on-touch via
#     the watcher, and that a settled cache serves without a further LLM call.
#   Flow B (real generation): src/<llm>/tetris.ai.md, src/<llm>/convert.ai.md
#     (fresh copies with no prebuilt dist counterpart) -- verifies the LLM is
#     actually invoked end-to-end for that provider.
#
# test-all.bat is a thin wrapper around this script -- put logic here, not there.
# This file supersedes an earlier hand-rolled .bat port of the same logic: that
# port hit a reproducible cmd.exe parser bug (`for %%n in (...) do call :label`
# failed to find labels that plainly existed later in the file) and generally
# made every quoting-sensitive step (PowerShell one-liners embedded in batch,
# mtime comparisons, etc.) fragile. None of that class of bug applies to a
# real .ps1 file.

$ErrorActionPreference = "Continue"
$ScriptStart = Get-Date

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot

# COMPOSE_PROJECT_NAME outranks docker-compose.yml's `name: ai-md-${LLM_NAME}`.
# An older version of this script used to set it per-provider and never
# cleared it, so a leftover value from a prior run in the same shell session
# would silently mislabel every container group created afterward (container
# names stay correct because those come from LLM_NAME, set fresh per deploy --
# only the compose *project* label goes stale). Nothing here should ever set
# COMPOSE_PROJECT_NAME; clear it defensively in case the calling shell has a
# stale one lying around.
Remove-Item Env:\COMPOSE_PROJECT_NAME -ErrorAction SilentlyContinue

# Everything lands under logs/ (gitignored) instead of tmp/, so a run's full
# transcript -- including timestamps -- is sitting on disk for direct
# inspection instead of needing to be pasted back by hand.
$TS = Get-Date -Format "yyyyMMdd_HHmmss"
$LogsDir = Join-Path $RepoRoot "logs\$TS"
New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
$TmpDir = $LogsDir  # kept as $TmpDir: per-artifact file paths below all key off this name
$SummaryLog = Join-Path $TmpDir "summary.log"
New-Item -ItemType File -Force -Path $SummaryLog | Out-Null
$RunLog = Join-Path $TmpDir "run.log"
New-Item -ItemType File -Force -Path $RunLog | Out-Null

function Write-Log {
    # Prefixes every line with a wall-clock timestamp and an elapsed-since-start
    # marker, writes it to the console AND appends it to run.log, so a pasted
    # log makes it obvious which step actually ate the time (e.g. a 40s gap
    # between two lines means the command between them was slow, not "hung"),
    # and the full transcript is on disk even if the console scrollback isn't.
    param([string]$Msg)
    $elapsed = (Get-Date) - $ScriptStart
    $line = "[{0:HH:mm:ss} +{1:mm\:ss}] {2}" -f (Get-Date), $elapsed, $Msg
    Write-Host $line
    Add-Content -Path $RunLog -Value $line
    return $line
}

$LlmNames = @("minimax", "openai")
$KeyVars = @{
    minimax    = "MINIMAX_API_KEY"
    openai     = "OPENAI_API_KEY"
}

$script:PassCount = 0
$script:FailCount = 0

function Record {
    param([string]$Status, [string]$Item, [string]$Msg)
    $body = "[{0}] {1,-28} {2}" -f $Status, $Item, $Msg
    $line = Write-Log $body
    Add-Content -Path $SummaryLog -Value $line
    if ($Status -eq "PASS") { $script:PassCount++ }
    if ($Status -eq "FAIL") { $script:FailCount++ }
}

function Get-EngineLogs {
    docker compose logs engine 2>$null
}

function Get-EngineLogLineCount {
    $logs = Get-EngineLogs
    if ($null -eq $logs) { return 0 }
    return @($logs).Count
}

function Get-EngineLogSince {
    param([int]$Marker)
    $logs = @(Get-EngineLogs)
    if ($logs.Count -le $Marker) { return @() }
    return $logs[$Marker..($logs.Count - 1)]
}

function Wait-ForMtimeChange {
    param([string]$Path, [datetime]$Old, [int]$TimeoutSec)
    $waited = 0
    Write-Log "Waiting for watcher rebuild of $(Split-Path -Leaf $Path)..." | Out-Null
    while ($waited -lt $TimeoutSec) {
        if (Test-Path $Path) {
            $new = (Get-Item $Path).LastWriteTimeUtc
            if ($new -ne $Old) { return $true }
        }
        Start-Sleep -Seconds 1
        $waited++
    }
    return $false
}

function Wait-ForPort {
    param([int]$Port, [int]$TimeoutSec)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $result = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
            if ($result.AsyncWaitHandle.WaitOne(300) -and $client.Connected) {
                return $true
            }
        } catch {
        } finally {
            $client.Close()
        }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Invoke-CurlTiming {
    # Returns @{ Code = <http_code>; Time = <seconds as double> }
    param([string]$Url, [string]$OutFile, [int]$MaxTimeSec)
    if (-not $OutFile) { $OutFile = "NUL" }
    $raw = & curl.exe -s --max-time $MaxTimeSec -o $OutFile -w "%{http_code} %{time_total}" $Url
    $parts = "$raw".Trim() -split '\s+'
    if ($parts.Count -lt 2) { return @{ Code = "000"; Time = 999 } }
    return @{ Code = $parts[0]; Time = [double]$parts[1] }
}

# -- 1. Dependency checks --------------------------------------------------

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Record FAIL docker "docker not found. Install: https://docs.docker.com/desktop/setup/install/windows-install/"
    exit 1
}
docker compose version *> $null
if ($LASTEXITCODE -ne 0) {
    Record FAIL docker-compose "'docker compose' plugin not available"
    exit 1
}
Record PASS docker "docker + compose plugin available"

$AvailableLlms = @()
foreach ($name in $LlmNames) {
    $keyvar = $KeyVars[$name]
    $val = [Environment]::GetEnvironmentVariable($keyvar)
    if ($val) {
        $AvailableLlms += $name
        Record PASS "api-key:$name" "$keyvar is set"
    } else {
        Record WARN "api-key:$name" "$keyvar not set -- $name will be SKIPPED"
    }
}
if ($AvailableLlms.Count -eq 0) {
    Record FAIL api-keys "no *_API_KEY is set for any provider -- cannot continue"
    exit 1
}

# -- 2. Cleanup + build once ------------------------------------------------

foreach ($name in $LlmNames) {
    $srcDir = Join-Path $RepoRoot "src\$name"
    $distDir = Join-Path $RepoRoot "dist\$name"
    if (Test-Path $srcDir) { Remove-Item -Recurse -Force $srcDir }
    if (Test-Path $distDir) { Remove-Item -Recurse -Force $distDir }
}

Write-Log "Cleaning up any leftover deployment from a previous run..." | Out-Null
foreach ($name in $LlmNames) {
    $env:LLM_NAME = $name
    & "$RepoRoot\undeploy-$name.bat" *>> (Join-Path $TmpDir "undeploy-initial.log")
}
Remove-Item Env:\LLM_NAME -ErrorAction SilentlyContinue
git checkout -- dist/tetris.ai.md.html dist/convert.ai.md.py 2>>(Join-Path $TmpDir "undeploy-initial.log")
Record PASS cleanup "prior test artifacts removed, prebuilt dist restored (all provider projects)"

Write-Log "Building docker images (this may take a while)..." | Out-Null
& "$RepoRoot\build.bat" *> (Join-Path $TmpDir "build.log")
if ($LASTEXITCODE -ne 0) {
    Record FAIL build "docker compose build failed -- see $TmpDir\build.log"
    exit 1
}
Record PASS build "docker compose build succeeded"

# Each provider gets its own compose project (ai-md-<name>, set via LLM_NAME in
# docker-compose.yml's top-level `name:`) and its own nginx port, so multiple
# providers can stay deployed and visible as separate container groups
# (Docker Desktop) at the same time instead of being torn down one-by-one.
$NextPortStart = 18080
$DeployedLlms = @()
$PortOf = @{}

Write-Host ""
Write-Log "==== dependency checks + build done. Next step calls real LLM APIs. ====" | Out-Null
Read-Host "Press Enter to continue" | Out-Null

# -- 3. Per-provider verification -------------------------------------------

function Test-FlowASpa {
    # Flow A / SPA target (tetris.ai.md -> dist/tetris.ai.md.html)
    param([string]$Llm, [string]$Spec, [string]$BaseUrl)
    $srcPath = Join-Path $RepoRoot "src\$Spec"
    $distPath = Join-Path $RepoRoot "dist\$Spec.html"

    $mark1 = Get-EngineLogLineCount
    $r = Invoke-CurlTiming -Url "$BaseUrl/$Spec" -OutFile (Join-Path $TmpDir "$Llm-$Spec-hit1.html") -MaxTimeSec 5
    if ($r.Code -eq "200" -and $r.Time -lt 2) {
        Record PASS "$Llm`:$Spec`:prebuilt-hit1" "http=$($r.Code) time=$($r.Time)s"
    } else {
        Record FAIL "$Llm`:$Spec`:prebuilt-hit1" "http=$($r.Code) time=$($r.Time)s"
    }
    if ((Get-EngineLogSince $mark1) -match "compile start name=$Spec") {
        Record FAIL "$Llm`:$Spec`:prebuilt-no-llm-call" "unexpected compile on first hit"
    } else {
        Record PASS "$Llm`:$Spec`:prebuilt-no-llm-call" "no compile triggered, served from committed dist/"
    }

    $oldMtime = if (Test-Path $distPath) { (Get-Item $distPath).LastWriteTimeUtc } else { [datetime]0 }
    (Get-Item $srcPath).LastWriteTime = Get-Date
    if (Wait-ForMtimeChange -Path $distPath -Old $oldMtime -TimeoutSec 30) {
        Record PASS "$Llm`:$Spec`:rebuild-mtime" "dist artifact mtime changed after touch (watcher rebuild)"
    } else {
        Record FAIL "$Llm`:$Spec`:rebuild-mtime" "dist artifact was not rebuilt within 30s"
    }
    if ((Get-EngineLogSince $mark1) -match "compile ok name=$Spec") {
        Record PASS "$Llm`:$Spec`:rebuild-log" "engine log confirms compile ok for $Spec"
    } else {
        Record FAIL "$Llm`:$Spec`:rebuild-log" "no 'compile ok name=$Spec' found in engine log"
    }

    $mark2 = Get-EngineLogLineCount
    $r3 = Invoke-CurlTiming -Url "$BaseUrl/$Spec" -OutFile (Join-Path $TmpDir "$Llm-$Spec-hit3.html") -MaxTimeSec 5
    if ($r3.Code -eq "200" -and $r3.Time -lt 2) {
        Record PASS "$Llm`:$Spec`:recache-hit3" "http=$($r3.Code) time=$($r3.Time)s"
    } else {
        Record FAIL "$Llm`:$Spec`:recache-hit3" "http=$($r3.Code) time=$($r3.Time)s"
    }
    if ((Get-EngineLogSince $mark2) -match "compile start name=$Spec") {
        Record FAIL "$Llm`:$Spec`:recache-no-llm-call" "unexpected compile on settled re-hit"
    } else {
        Record PASS "$Llm`:$Spec`:recache-no-llm-call" "no additional LLM call after rebuild settled"
    }
}

function Test-FlowAApi {
    # Flow A / API target (convert.ai.md -> dist/convert.ai.md.py)
    param([string]$Llm, [string]$Spec, [string]$BaseUrl)
    $srcPath = Join-Path $RepoRoot "src\$Spec"
    $distPath = Join-Path $RepoRoot "dist\$Spec.py"

    $mark1 = Get-EngineLogLineCount
    $r = Invoke-CurlTiming -Url "$BaseUrl/$Spec" -OutFile $null -MaxTimeSec 5
    # py artifact GET with no subpath redirects (302) to /docs -- that's the
    # "prebuilt, served without compiling" signal for an api target.
    if ($r.Code -eq "302" -and $r.Time -lt 2) {
        Record PASS "$Llm`:$Spec`:prebuilt-hit1" "http=$($r.Code) time=$($r.Time)s (redirect to /docs)"
    } else {
        Record FAIL "$Llm`:$Spec`:prebuilt-hit1" "http=$($r.Code) time=$($r.Time)s"
    }
    if ((Get-EngineLogSince $mark1) -match "compile start name=$Spec") {
        Record FAIL "$Llm`:$Spec`:prebuilt-no-llm-call" "unexpected compile on first hit"
    } else {
        Record PASS "$Llm`:$Spec`:prebuilt-no-llm-call" "no compile triggered, served from committed dist/"
    }

    $oldMtime = if (Test-Path $distPath) { (Get-Item $distPath).LastWriteTimeUtc } else { [datetime]0 }
    (Get-Item $srcPath).LastWriteTime = Get-Date
    if (Wait-ForMtimeChange -Path $distPath -Old $oldMtime -TimeoutSec 30) {
        Record PASS "$Llm`:$Spec`:rebuild-mtime" "dist artifact mtime changed after touch (watcher rebuild)"
    } else {
        Record FAIL "$Llm`:$Spec`:rebuild-mtime" "dist artifact was not rebuilt within 30s"
    }
    if ((Get-EngineLogSince $mark1) -match "compile ok name=$Spec") {
        Record PASS "$Llm`:$Spec`:rebuild-log" "engine log confirms compile ok for $Spec"
    } else {
        Record FAIL "$Llm`:$Spec`:rebuild-log" "no 'compile ok name=$Spec' found in engine log"
    }

    $mark2 = Get-EngineLogLineCount
    $r3 = Invoke-CurlTiming -Url "$BaseUrl/$Spec" -OutFile $null -MaxTimeSec 5
    if ($r3.Code -eq "302" -and $r3.Time -lt 2) {
        Record PASS "$Llm`:$Spec`:recache-hit3" "http=$($r3.Code) time=$($r3.Time)s"
    } else {
        Record FAIL "$Llm`:$Spec`:recache-hit3" "http=$($r3.Code) time=$($r3.Time)s"
    }
    if ((Get-EngineLogSince $mark2) -match "compile start name=$Spec") {
        Record FAIL "$Llm`:$Spec`:recache-no-llm-call" "unexpected compile on settled re-hit"
    } else {
        Record PASS "$Llm`:$Spec`:recache-no-llm-call" "no additional LLM call after rebuild settled"
    }
}

function Test-FlowB {
    param([string]$Llm, [string]$Spec, [string]$ExpectCode, [string]$BaseUrl)
    $mark = Get-EngineLogLineCount
    Write-Log "Generating $Spec via $Llm (real LLM call, may take up to 30s)..." | Out-Null
    $r = Invoke-CurlTiming -Url "$BaseUrl/$Spec" -OutFile (Join-Path $TmpDir "$Llm-$(Split-Path -Leaf $Spec)-fresh.out") -MaxTimeSec 30
    if ($r.Code -eq $ExpectCode) {
        Record PASS "$Llm`:$Spec`:fresh-generate" "http=$($r.Code) time=$($r.Time)s"
    } else {
        Record FAIL "$Llm`:$Spec`:fresh-generate" "http=$($r.Code) time=$($r.Time)s (expected $ExpectCode)"
    }
    if ((Get-EngineLogSince $mark) -match "llm call start") {
        Record PASS "$Llm`:$Spec`:llm-invoked" "engine log shows a real LLM call was made"
    } else {
        Record FAIL "$Llm`:$Spec`:llm-invoked" "no 'llm call start' found in engine log -- LLM was not actually invoked"
    }
}

foreach ($name in $LlmNames) {
    if ($AvailableLlms -notcontains $name) { continue }

    (Write-Log "=== $name ===") | Tee-Object -FilePath $SummaryLog -Append | Out-Null
    $LogFile = Join-Path $TmpDir "$name-engine.log"

    # LLM_NAME drives docker-compose.yml's project name (ai-md-$name) and
    # container names, so each provider becomes its own container group.
    $env:LLM_NAME = $name
    $port = & "$RepoRoot\integration-tests\find-free-port.ps1" -Start $NextPortStart
    if (-not $port) {
        Record FAIL "$name`:port" "could not find a free port from $NextPortStart"
        continue
    }
    $env:NGINX_PORT = "$port"
    $PortOf[$name] = $port
    $NextPortStart = [int]$port + 1
    Record PASS "$name`:port" "using NGINX_PORT=$port (project ai-md-$name)"
    $BaseUrl = "http://localhost:$port"

    Write-Log "Deploying $name (docker compose pull/build/up) -- this can quietly take up to a minute, no output until it finishes. Log: $TmpDir\$name-deploy.log" | Out-Null
    & "$RepoRoot\deploy-with-$name.bat" *> (Join-Path $TmpDir "$name-deploy.log")
    if ($LASTEXITCODE -ne 0) {
        Record FAIL "$name`:deploy" "deploy-with-$name.bat failed -- see $TmpDir\$name-deploy.log"
        continue
    }
    $DeployedLlms += $name

    Write-Log "Waiting up to 30s for $name nginx to bind 127.0.0.1:$port..." | Out-Null
    if (Wait-ForPort -Port ([int]$port) -TimeoutSec 30) {
        Record PASS "$name`:nginx-port" "nginx bound port $port within 30s"
    } else {
        Record FAIL "$name`:nginx-port" "nginx did not bind port $port within 30s -- see $TmpDir\$name-nginx.log"
        docker compose logs nginx *> (Join-Path $TmpDir "$name-nginx.log")
        docker compose ps *> (Join-Path $TmpDir "$name-ps.log")
        Get-EngineLogs *> $LogFile
        continue
    }

    Write-Log "Waiting for $name engine to settle..." | Out-Null
    Start-Sleep -Seconds 5
    if ((Get-EngineLogs) -match "ERROR") {
        Record FAIL "$name`:no-errors" "engine log contains ERROR after startup"
        Get-EngineLogs *> $LogFile
    } else {
        Record PASS "$name`:no-errors" "no ERROR in engine log after 5s"
    }

    Test-FlowASpa -Llm $name -Spec "tetris.ai.md" -BaseUrl $BaseUrl
    Test-FlowAApi -Llm $name -Spec "convert.ai.md" -BaseUrl $BaseUrl

    $providerSrcDir = Join-Path $RepoRoot "src\$name"
    New-Item -ItemType Directory -Force -Path $providerSrcDir | Out-Null
    Copy-Item (Join-Path $RepoRoot "src\tetris.ai.md") (Join-Path $providerSrcDir "tetris.ai.md") -Force
    Copy-Item (Join-Path $RepoRoot "src\convert.ai.md") (Join-Path $providerSrcDir "convert.ai.md") -Force
    Test-FlowB -Llm $name -Spec "$name/tetris.ai.md" -ExpectCode "200" -BaseUrl $BaseUrl
    Test-FlowB -Llm $name -Spec "$name/convert.ai.md" -ExpectCode "302" -BaseUrl $BaseUrl

    Get-EngineLogs *> $LogFile

    # Intentionally NOT undeploying here: src/dist are shared bind mounts
    # across every provider's container group, so the committed prebuilt
    # spec files must be restored before the next provider runs flow A --
    # but the container group itself (ai-md-$name) is left running so it
    # stays visible as its own group in `docker compose ls` / Docker Desktop.
    git checkout -- dist/tetris.ai.md.html dist/convert.ai.md.py 2>>(Join-Path $TmpDir "$name-cleanup.log")
    # src/<name> and dist/<name> are intentionally kept for post-run inspection.

    Write-Host ""
    Write-Log "==== $name test done: PASS=$script:PassCount FAIL=$script:FailCount (running totals) ====" | Out-Null
    Read-Host "Press Enter to continue to the next provider" | Out-Null
}

"" | Tee-Object -FilePath $SummaryLog -Append | Out-Null
(Write-Log "PASS=$PassCount FAIL=$FailCount (detailed logs: $TmpDir)") | Tee-Object -FilePath $SummaryLog -Append | Out-Null

if ($DeployedLlms.Count -gt 0) {
    "" | Tee-Object -FilePath $SummaryLog -Append | Out-Null
    (Write-Log "Still running (one container group per provider):") | Tee-Object -FilePath $SummaryLog -Append | Out-Null
    foreach ($name in $DeployedLlms) {
        (Write-Log "  ai-md-$name  -> http://localhost:$($PortOf[$name])") | Tee-Object -FilePath $SummaryLog -Append | Out-Null
    }
    (Write-Log "To tear one down: $RepoRoot\undeploy-<name>.bat") | Tee-Object -FilePath $SummaryLog -Append | Out-Null
}

if ($FailCount -gt 0) {
    exit 1
}
exit 0
