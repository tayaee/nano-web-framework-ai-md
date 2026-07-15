@echo off
rem Targets the compose project ai-md-%LLM_NAME% (default: ai-md-default; see docker-compose.yml).
rem Set LLM_NAME to match the deploy-with-<name>.bat you want to tear down.
setlocal
set "PROJNAME=%LLM_NAME%"
if "%PROJNAME%"=="" set "PROJNAME=default"
rem docker-compose.yml requires LLM_API_KEY to be set (${LLM_API_KEY:?...})
rem even just to parse the file for `ps`/`down` -- without this, teardown
rem silently no-ops (error hidden by >nul 2>&1) and stale containers survive.
if "%LLM_API_KEY%"=="" set "LLM_API_KEY=noop-for-teardown"
docker compose ps >nul 2>&1
if errorlevel 1 (
    echo No deployment to undeploy; skipping.
) else (
    echo Undeploying project ai-md-%PROJNAME%...
    docker compose down >nul 2>&1
)
endlocal
exit /b 0
