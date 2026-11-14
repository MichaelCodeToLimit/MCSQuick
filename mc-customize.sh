#!/usr/bin/env bash
# Change a server you already set up: name, MOTD, icon, plugins/mods, players, world, version, Bedrock, backups ...
# Usage:  bash mc-customize.sh [server folder] [--lang xx]
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mc-setup.sh" --customize "$@"
