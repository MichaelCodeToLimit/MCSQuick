#!/usr/bin/env bash
# stage.sh <root> : lay out the files like an installed package under <root>/usr
set -euo pipefail
R="$1"; HERE="$(cd "$(dirname "$0")/.." && pwd)"
install -d "$R/usr/bin" "$R/usr/share/mcsquick" "$R/usr/share/applications" "$R/usr/share/icons/hicolor/scalable/apps"
install -m755 "$HERE/packaging/mcsquick" "$R/usr/bin/mcsquick"
install -m755 "$HERE/mc-setup.sh" "$HERE/mc-customize.sh" "$R/usr/share/mcsquick/"
install -m644 "$HERE/README.md" "$HERE/LICENSE" "$R/usr/share/mcsquick/"
install -m644 "$HERE/packaging/mcsquick.desktop" "$R/usr/share/applications/mcsquick.desktop"
install -m644 "$HERE/packaging/mcsquick.svg" "$R/usr/share/icons/hicolor/scalable/apps/mcsquick.svg"
