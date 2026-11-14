@echo off
rem Double-click this file to change a server you already set up (name, MOTD, plugins, version, Bedrock ...).
rem It runs mc-setup.ps1 -Customize (must be in the same folder) without changing your PowerShell settings.
title Minecraft Server - Customise
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mc-setup.ps1" -Customize %*
echo.
pause
