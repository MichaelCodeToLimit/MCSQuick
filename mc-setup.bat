@echo off
rem Double-click this file to run the Minecraft server setup wizard.
rem It runs mc-setup.ps1 (must be in the same folder) without changing your PowerShell settings.
title Minecraft Server Setup
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mc-setup.ps1"
echo.
pause
