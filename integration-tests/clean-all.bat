@echo off
rem Thin wrapper -- all logic lives in clean-all.ps1. Keep this file trivial.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0clean-all.ps1" %*
exit /b %ERRORLEVEL%
