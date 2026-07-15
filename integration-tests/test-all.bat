@echo off
rem Thin wrapper -- all logic lives in test-all.ps1. Keep this file trivial.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-all.ps1" %*
exit /b %ERRORLEVEL%
