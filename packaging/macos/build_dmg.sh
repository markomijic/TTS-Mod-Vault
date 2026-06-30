#!/usr/bin/env bash
#
# Build a TTS Mod Vault macOS release: a .app, a .dmg, and a .zip-containing-the-dmg
# matching the format hosted on GitHub Releases (e.g. macOS.TTS.Mod.Vault.2.1.0.zip).
# Run this ON macOS (Apple Silicon):  bash packaging/macos/build_dmg.sh
#
# WHY A CLEAN BUILD: incremental Flutter macOS builds can leave the outer .app's
# code-signature seal stale ("nested code is modified or invalid"), which makes a
# downloaded/quarantined copy fail to launch on another Mac. This script always
# does `flutter clean` first (set SKIP_CLEAN=1 to override) and then verifies the
# signature, so a broken seal fails the build instead of shipping.
#
# NOTE ON GATEKEEPER: the app is ad-hoc signed, NOT notarized (no paid Apple
# Developer ID). macOS will quarantine it on download and Gatekeeper will block
# it ("Apple could not verify ... free of malware"). Users remove the quarantine
# flag once with:
#   xattr -dr com.apple.quarantine "/Applications/TTS Mod Vault.app"
# This is documented in the README and should be in each release's notes.
#
# Prerequisites on the build machine:
#   - Flutter with macOS desktop enabled (run `flutter doctor` to confirm)
#   - Xcode + command line tools
#   - This repo uses FVM; the script calls `fvm flutter` if fvm is available,
#     otherwise falls back to plain `flutter`.

set -euo pipefail

APP_NAME="TTS Mod Vault"          # bundle/display name (Contents/MacOS/<APP_NAME>)
VOL_NAME="TTS Mod Vault"          # mounted DMG volume name
DMG_NAME="TTSModVault.dmg"        # dmg filename (matches existing releases)

# Resolve repo root robustly, regardless of where this script is invoked from.
ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "$ROOT"

# Prefer fvm so the pinned Flutter version is used, like local dev.
if command -v fvm >/dev/null 2>&1; then
  FLUTTER="fvm flutter"
else
  FLUTTER="flutter"
fi

# Version (e.g. 2.1.0) from pubspec, dropping the +build suffix.
VERSION="$(grep '^version:' pubspec.yaml | head -1 | sed 's/version:[[:space:]]*//' | cut -d'+' -f1)"
[ -n "$VERSION" ] || { echo "ERROR: could not read version from pubspec.yaml"; exit 1; }
ZIP_NAME="macOS.TTS.Mod.Vault.${VERSION}.zip"

echo "==> building TTS Mod Vault $VERSION for macOS"

if [ "${SKIP_CLEAN:-0}" != "1" ]; then
  echo "==> flutter clean (set SKIP_CLEAN=1 to skip)"
  $FLUTTER clean >/dev/null
fi

echo "==> flutter build macos --release"
$FLUTTER build macos --release

APP="build/macos/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP" ] || { echo "ERROR: built app not found at $APP"; exit 1; }

# Sanity: the pdfium native asset must be bundled, or the app crashes at startup.
[ -e "$APP/Contents/Frameworks/pdfium.framework/pdfium" ] || {
  echo "ERROR: pdfium.framework missing from the app bundle — release would crash at launch"; exit 1; }

echo "==> verifying code signature (must be valid or downloads won't launch)"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "    signature OK"

# ---- assemble a staging folder for the DMG ---------------------------------
# IMPORTANT: never modify the .app after this point — touching the bundle breaks
# the signature. We only copy it and add an Applications symlink for drag-install.
WORK="build/macos/dmg"
STAGE="$WORK/stage"
rm -rf "$WORK"
mkdir -p "$STAGE"
echo "==> staging app + /Applications shortcut"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# ---- create the DMG --------------------------------------------------------
OUT_DMG="build/$DMG_NAME"
rm -f "$OUT_DMG"
echo "==> creating $OUT_DMG"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$OUT_DMG" >/dev/null

# ---- zip the DMG (matches the GitHub release format) -----------------------
OUT_ZIP="build/$ZIP_NAME"
rm -f "$OUT_ZIP"
echo "==> zipping -> $OUT_ZIP"
# -j: store just the dmg filename (no build/ path).  -X: no macOS extra
# attributes, so no __MACOSX cruft inside the zip.
( cd build && zip -j -X -q "$ZIP_NAME" "$DMG_NAME" )

echo ""
echo "==> done:"
echo "    app:  $APP"
echo "    dmg:  $OUT_DMG"
echo "    zip:  $OUT_ZIP   <- upload this to GitHub Releases"
echo ""
echo "    Reminder: app is ad-hoc signed (not notarized). Add to the release notes:"
echo "      xattr -dr com.apple.quarantine \"/Applications/${APP_NAME}.app\""
