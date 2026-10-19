#!/bin/zsh
# SecShot — security evidence capture tool for macOS.
# Copyright (C) 2026 JahazielLem
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Made by AI
#
# Builds SecShot and produces build/SecShot.app.
#
# Optional environment variables:
#   VERSION=1.2.0        CFBundleShortVersionString (default 0.1.0)
#   BUILD_NUMBER=42      CFBundleVersion (default 1)
#   UNIVERSAL=1          universal arm64 + x86_64 binary (requires Xcode)
#   SIGN_IDENTITY="..."  signing identity. Defaults to "SecShot Local Signing" if present, otherwise ad-hoc.
#                        "Developer ID Application: …" enables hardened runtime + timestamp (notarizable).
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${VERSION:-0.1.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}
BUNDLE_ID=local.secshot.app

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/SecShot"

APP=build/SecShot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$BIN" "$APP/Contents/MacOS/SecShot"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SecShot</string>
    <key>CFBundleDisplayName</key><string>SecShot</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>SecShot</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSQuitAlwaysKeepsWindows</key><false/>
    <key>NSScreenCaptureUsageDescription</key><string>SecShot needs screen recording access to capture evidence screenshots.</string>
</dict>
</plist>
PLIST

# Login agent: launches the app in the background (no windows).
cat > "$APP/Contents/Library/LaunchAgents/${BUNDLE_ID}.login.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>${BUNDLE_ID}.login</string>
    <key>BundleProgram</key><string>Contents/MacOS/SecShot</string>
    <key>ProgramArguments</key>
    <array>
        <string>Contents/MacOS/SecShot</string>
        <string>--background</string>
    </array>
    <key>AssociatedBundleIdentifiers</key><string>${BUNDLE_ID}</string>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST

# App icon generated from the app symbol.
if "$APP/Contents/MacOS/SecShot" --make-icon build/AppIcon.iconset >/dev/null 2>&1; then
    iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns" && rm -rf build/AppIcon.iconset
fi

# Code signing
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "SecShot Local Signing"; then
        SIGN_IDENTITY="SecShot Local Signing"
    else
        SIGN_IDENTITY="-"
        echo "⚠️  Ad-hoc signature: macOS will ask for the screen permission again after every build."
        echo "    Run scripts/create-signing-cert.sh once to avoid it."
    fi
fi
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID")
if [[ "$SIGN_IDENTITY" == Developer\ ID\ Application* ]]; then
    SIGN_FLAGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --strict "$APP"
echo "✅ $APP  (v$VERSION, signature: $SIGN_IDENTITY, arch: $(lipo -archs "$APP/Contents/MacOS/SecShot"))"
