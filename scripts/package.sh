#!/bin/zsh
# SecShot — security evidence capture tool for macOS.
# Copyright (C) 2026 JahazielLem
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Made by AI
#
# Packages build/SecShot.app into dist/: a drag-to-Applications DMG, a ZIP and SHA256SUMS.txt.
# When APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD are set and the signature is a
# Developer ID, the app and the DMG are notarized and stapled.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${VERSION:-0.1.0}
APP=build/SecShot.app
DIST=dist
[[ -d "$APP" ]] || { echo "$APP not found; run ./build.sh first"; exit 1; }

rm -rf "$DIST"
mkdir -p "$DIST"

NOTARIZE=0
if [[ "${SIGN_IDENTITY:-}" == Developer\ ID\ Application* && -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    NOTARIZE=1
fi

notarize() {
    xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" --wait --timeout 30m
}

if (( NOTARIZE )); then
    echo "→ Notarizing the app…"
    ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
    notarize "$DIST/notarize.zip"
    rm "$DIST/notarize.zip"
    xcrun stapler staple "$APP"
fi

ZIP="$DIST/SecShot-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/SecShot.app"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/SecShot-$VERSION.dmg"
hdiutil create -volname "SecShot $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null

if [[ "${SIGN_IDENTITY:-}" == Developer\ ID\ Application* ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
if (( NOTARIZE )); then
    echo "→ Notarizing the DMG…"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
fi

(cd "$DIST" && shasum -a 256 SecShot-* > SHA256SUMS.txt)
echo "✅ Packages in $DIST/ (notarized: $NOTARIZE)"
ls -lh "$DIST"
