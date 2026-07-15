@echo off
rem Thin wrapper -- all logic lives in build.ps1. Keep this file trivial.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
exit /b %ERRORLEVEL%
