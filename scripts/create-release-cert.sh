#!/bin/zsh
# SecShot — security evidence capture tool for macOS.
# Copyright (C) 2026 JahazielLem
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Made by AI
#
# Generates a self-signed code-signing certificate for GitHub release builds.
#
# Signing every release with the SAME certificate keeps the code signature requirement stable,
# so macOS preserves the Screen Recording permission when users update SecShot. It does NOT
# remove the Gatekeeper warning on first launch; that requires an Apple Developer ID.
#
# Nothing is added to your keychain. The files are written to ./release-signing/ (git-ignored).
# Keep the .p12 private and backed up: losing it means users re-grant the permission once.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="SecShot Release Signing"
OUT=release-signing
if [[ -e "$OUT/secshot-release.p12" ]]; then
    echo "⚠️  $OUT/secshot-release.p12 already exists. Delete it first to create a new one."
    exit 1
fi
mkdir -p "$OUT"
chmod 700 "$OUT"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CFG

/usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -config "$TMP/cfg" \
    -keyout "$TMP/key.pem" -out "$OUT/secshot-release.cer" 2>/dev/null
PASS=$(/usr/bin/openssl rand -hex 24)
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$OUT/secshot-release.cer" \
    -name "$NAME" -out "$OUT/secshot-release.p12" -passout "pass:$PASS"
base64 -i "$OUT/secshot-release.p12" > "$OUT/MACOS_CERT_P12.txt"
printf '%s' "$PASS" > "$OUT/MACOS_CERT_PASSWORD.txt"
chmod 600 "$OUT"/*

cat <<MSG
✅ Release certificate created in $OUT/

Add these repository secrets (Settings → Secrets and variables → Actions):
  MACOS_CERT_P12        contents of $OUT/MACOS_CERT_P12.txt
  MACOS_CERT_PASSWORD   contents of $OUT/MACOS_CERT_PASSWORD.txt
  MACOS_SIGN_IDENTITY   $NAME

With the GitHub CLI:
  gh secret set MACOS_CERT_P12 < $OUT/MACOS_CERT_P12.txt
  gh secret set MACOS_CERT_PASSWORD < $OUT/MACOS_CERT_PASSWORD.txt
  gh secret set MACOS_SIGN_IDENTITY --body "$NAME"

Then store $OUT/ somewhere safe (e.g. your password manager) and delete it from this folder.
MSG
