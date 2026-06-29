#!/usr/bin/env bash
#
# Build a TTS Mod Vault AppImage from a Flutter Linux release build.
# Run this ON LINUX (e.g. your Ubuntu VM):  bash packaging/appimage/build_appimage.sh
#
# NOTE ON COMPATIBILITY: an AppImage bundles app libraries but NOT glibc, so the
# resulting file's minimum glibc is whatever THIS build machine ships. Built on
# Ubuntu 26.04 it will only run on similarly-new distros. For broad compatibility
# later, build on an older LTS (e.g. inside an ubuntu:22.04 container).
#
# Prerequisites on the build machine:
#   - Flutter with Linux desktop enabled (run `flutter doctor` to confirm)
#   - Linux toolchain: sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
#   - curl (to fetch appimagetool)

set -euo pipefail

APP_ID="io.github.markomijic.tts_mod_vault"
BIN_NAME="tts_mod_vault"
ICON_SRC="assets/icon/tts_mod_vault_icon.png"
OUT_NAME="TTS_Mod_Vault-x86_64.AppImage"

# Resolve repo root robustly, regardless of where this script is invoked from.
ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "$ROOT"

[ -f "$ICON_SRC" ] || { echo "ERROR: icon not found at $ICON_SRC"; exit 1; }

echo "==> flutter build linux --release"
flutter build linux --release

BUNDLE="build/linux/x64/release/bundle"
[ -d "$BUNDLE" ] || { echo "ERROR: build bundle not found at $BUNDLE"; exit 1; }

echo "==> assembling AppDir"
WORK="build/appimage"
APPDIR="$WORK/AppDir"
rm -rf "$WORK"
mkdir -p "$APPDIR/usr/bin"

# The Flutter executable expects data/ and lib/ to sit next to it, so copy the
# whole bundle (exe + data/ + lib/) together into usr/bin.
cp -r "$BUNDLE/." "$APPDIR/usr/bin/"

# Icon: required at the AppDir root (named after the app id), plus a themed copy.
cp "$ICON_SRC" "$APPDIR/${APP_ID}.png"
mkdir -p "$APPDIR/usr/share/icons/hicolor/512x512/apps"
cp "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/512x512/apps/${APP_ID}.png"

# Desktop entry: single source of truth lives at linux/<app-id>.desktop.
# Copy it both to the AppDir root (required by appimagetool) and the standard
# applications dir.
DESKTOP_SRC="linux/${APP_ID}.desktop"
[ -f "$DESKTOP_SRC" ] || { echo "ERROR: desktop file not found at $DESKTOP_SRC"; exit 1; }
mkdir -p "$APPDIR/usr/share/applications"
cp "$DESKTOP_SRC" "$APPDIR/usr/share/applications/${APP_ID}.desktop"
cp "$DESKTOP_SRC" "$APPDIR/${APP_ID}.desktop"   # required at AppDir root too

# AppStream metainfo (silences appimagetool's warning; enables Flathub/AppImageHub).
METAINFO_SRC="linux/${APP_ID}.metainfo.xml"
if [ -f "$METAINFO_SRC" ]; then
  mkdir -p "$APPDIR/usr/share/metainfo"
  cp "$METAINFO_SRC" "$APPDIR/usr/share/metainfo/${APP_ID}.metainfo.xml"
fi

# AppRun: launches the bundled executable.
cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "${0}")")"
export LD_LIBRARY_PATH="${HERE}/usr/bin/lib:${LD_LIBRARY_PATH:-}"
exec "${HERE}/usr/bin/tts_mod_vault" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# Fetch appimagetool if we don't already have it.
TOOL="$WORK/appimagetool-x86_64.AppImage"
if [ ! -f "$TOOL" ]; then
  echo "==> downloading appimagetool"
  curl -fL -o "$TOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
  chmod +x "$TOOL"
fi

echo "==> packaging AppImage"
# --appimage-extract-and-run avoids needing FUSE (libfuse2) on the host.
ARCH=x86_64 "$TOOL" --appimage-extract-and-run "$APPDIR" "build/$OUT_NAME"

echo ""
echo "==> done:  build/$OUT_NAME"
echo "    test it:  chmod +x build/$OUT_NAME && ./build/$OUT_NAME"
