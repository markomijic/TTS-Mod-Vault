#!/usr/bin/env bash
#
# Build a TTS Mod Vault macOS release: a .app, a .dmg, and a .zip-containing-the-dmg
# matching the format hosted on GitHub Releases (e.g. macOS.TTS.Mod.Vault.2.1.0.zip).
# Run this ON macOS (Apple Silicon):  bash packaging/macos/build_dmg.sh
#
# PROJECT_DIR selects which Flutter project in the repo is built. It defaults
# to the repo root (".").
# All paths below (pubspec.yaml, build/) are relative to that project.
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
#   - Dart native assets enabled once per machine: flutter config --enable-native-assets
#     (pdfium and sqlite3 are shipped as native assets; the script checks this)
#   - Xcode + command line tools
#   - This repo uses FVM; the script calls `fvm flutter` if fvm is available,
#     otherwise falls back to plain `flutter`.

set -euo pipefail

APP_NAME="TTS Mod Vault"          # bundle/display name (Contents/MacOS/<APP_NAME>)
VOL_NAME="TTS Mod Vault"          # mounted DMG volume name
DMG_NAME="TTSModVault.dmg"        # dmg filename (matches existing releases)

# Resolve repo root robustly, regardless of where this script is invoked from,
# then enter the Flutter project (the repo root by default).
ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
PROJECT_DIR="${PROJECT_DIR:-.}"
cd "$ROOT/$PROJECT_DIR"
[ -f pubspec.yaml ] || { echo "ERROR: no pubspec.yaml in $PWD (PROJECT_DIR=$PROJECT_DIR)"; exit 1; }
echo "==> project: $PWD"

# Prefer fvm so the pinned Flutter version (.fvmrc) is used, like local dev.
if command -v fvm >/dev/null 2>&1; then
  FLUTTER="fvm flutter"; DART="fvm dart"
else
  FLUTTER="flutter"; DART="dart"
fi

# pdfium (pdfrx_engine) and sqlite3 are delivered as Dart native assets. Without
# this flag the build silently omits them and the app crashes at startup.
if ! $FLUTTER config --list 2>/dev/null | grep -q 'enable-native-assets: true'; then
  echo "ERROR: Dart native assets are disabled for this Flutter install."
  echo "       pdfium and sqlite3 ship as native assets. Run once on this machine:"
  echo "         $FLUTTER config --enable-native-assets"
  exit 1
fi

# Version (e.g. 3.0.0) from pubspec, dropping the +build suffix.
VERSION="$(grep '^version:' pubspec.yaml | head -1 | sed 's/version:[[:space:]]*//' | cut -d'+' -f1)"
[ -n "$VERSION" ] || { echo "ERROR: could not read version from pubspec.yaml"; exit 1; }
ZIP_NAME="macOS.TTS.Mod.Vault.${VERSION}.zip"

echo "==> building TTS Mod Vault $VERSION for macOS"

if [ "${SKIP_CLEAN:-0}" != "1" ]; then
  echo "==> flutter clean (set SKIP_CLEAN=1 to skip)"
  $FLUTTER clean >/dev/null
fi

echo "==> flutter pub get"
$FLUTTER pub get

echo "==> dart run build_runner build (drift / freezed / riverpod codegen)"
$DART run build_runner build --delete-conflicting-outputs

echo "==> flutter gen-l10n"
$FLUTTER gen-l10n

echo "==> flutter build macos --release"
$FLUTTER build macos --release

APP="build/macos/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP" ] || { echo "ERROR: built app not found at $APP"; exit 1; }

# Sanity: both native assets must be bundled, or the app crashes at startup.
# Flutter wraps each native-asset dylib in a framework under Contents/Frameworks.
FRAMEWORKS="$APP/Contents/Frameworks"
[ -e "$FRAMEWORKS/pdfium.framework/pdfium" ] || {
  echo "ERROR: pdfium.framework missing from the app bundle — release would crash at launch"; exit 1; }
[ -e "$FRAMEWORKS/sqlite3.framework/sqlite3" ] || [ -e "$FRAMEWORKS/libsqlite3.dylib" ] || {
  echo "ERROR: sqlite3 native library missing from $FRAMEWORKS — release would crash at launch"
  echo "       (expected sqlite3.framework/sqlite3; is 'flutter config --enable-native-assets' set?)"; exit 1; }
echo "    native assets OK: pdfium, sqlite3"

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
echo "==> done (paths relative to $PWD):"
echo "    app:  $APP"
echo "    dmg:  $OUT_DMG"
echo "    zip:  $OUT_ZIP   <- upload this to GitHub Releases"
echo ""
echo "    Reminder: app is ad-hoc signed (not notarized). Add to the release notes:"
echo "      xattr -dr com.apple.quarantine \"/Applications/${APP_NAME}.app\""
