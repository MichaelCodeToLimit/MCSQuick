#!/usr/bin/env bash
# build-deb.sh <version> <outdir>
set -euo pipefail
V="${1:-0.1.0}"; OUT="${2:-.}"; HERE="$(cd "$(dirname "$0")" && pwd)"; W=$(mktemp -d)
bash "$HERE/stage.sh" "$W/pkg"
install -d "$W/pkg/DEBIAN"
cat > "$W/pkg/DEBIAN/control" <<C
Package: mcsquick
Version: $V
Section: games
Priority: optional
Architecture: all
Depends: bash (>= 4.3), curl, jq, tar, ca-certificates
Recommends: tmux, unzip
Suggests: default-jre-headless | openjdk-21-jre-headless, miniupnpc
Maintainer: MichaelCodeToLimit <noreply@users.noreply.github.com>
Homepage: https://github.com/MichaelCodeToLimit/MCsQuick
Description: Interactive Minecraft Java server setup
 Asks a few questions, downloads Java and the server, and creates
 start scripts. Supports Vanilla, Paper, Velocity, Geyser/Floodgate,
 playit.gg tunnels and 14 languages. Run "mcsquick" to start.
C
dpkg-deb --root-owner-group --build "$W/pkg" "$OUT/mcsquick_${V}_all.deb" >/dev/null
rm -rf "$W"
