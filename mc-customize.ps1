# Change a server you already set up: name, MOTD, icon, plugins/mods, players, world, version, Bedrock, backups ...
# Usage:  powershell -File mc-customize.ps1 [-Server <folder>] [-Lang xx]
param([string]$Server = '', [string]$Lang = '')
& (Join-Path $PSScriptRoot 'mc-setup.ps1') -Customize -Server $Server -Lang $Lang
