@echo off
docker compose ps >nul 2>&1
if errorlevel 1 (
    echo No deployment to undeploy; skipping.
) else (
    echo Undeploying...
    docker compose down >nul 2>&1
)
exit /b 0
