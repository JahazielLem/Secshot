#!/bin/zsh
# SecShot — security evidence capture tool for macOS.
# Copyright (C) 2026 JahazielLem
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Made by AI
#
# Builds SecShot, installs it into /Applications and registers it as a regular app.
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh

DEST=/Applications/SecShot.app
pkill -x SecShot 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
ditto build/SecShot.app "$DEST"

# Register the app with LaunchServices (Launchpad, Spotlight, Finder/Dock icon) and remove
# the build copy so Spotlight does not list SecShot twice.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$PWD/build/SecShot.app" 2>/dev/null || true
rm -rf build/SecShot.app
"$LSREGISTER" -f "$DEST"
touch "$DEST"

echo "✅ Installed at $DEST"
codesign -dv "$DEST" 2>&1 | grep -E "^Authority|Signature=adhoc" || true
open "$DEST"
