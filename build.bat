@echo off
mkdir logs > NUL 2>&1
echo [DEBUG] docker compose build
docker compose build 2>&1 | tee logs\build.log
