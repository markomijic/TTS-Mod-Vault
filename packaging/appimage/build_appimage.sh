#!/usr/bin/env bash
#
# Build a TTS Mod Vault AppImage from a Flutter Linux release build.
# Run this ON LINUX (e.g. your Ubuntu VM):  bash packaging/appimage/build_appimage.sh
#
# PROJECT_DIR selects which Flutter project in the repo is built. It defaults
# to the repo root (".").
# All paths below (icon, linux/, build/) are relative to that project.
#
# NOTE ON COMPATIBILITY: an AppImage bundles app libraries but NOT glibc, so the
# resulting file's minimum glibc is whatever THIS build machine ships. Built on
# Ubuntu 26.04 it will only run on similarly-new distros. Public releases are
# built inside an ubuntu:22.04 container (the GitHub Actions Build workflow does
# this). The script fails when any bundled binary needs a glibc newer than
# MAX_GLIBC (default 2.35); set MAX_GLIBC=none for a local test build on a newer
# distro.
#
# Prerequisites on the build machine:
#   - Flutter with Linux desktop enabled (run `flutter doctor` to confirm)
#   - Dart native assets enabled once per machine: flutter config --enable-native-assets
#     (pdfium and sqlite3 are shipped as native assets; the script checks this)
#   - Linux toolchain: sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
#   - curl (to fetch appimagetool), zip, binutils (objdump, for the glibc check)

set -euo pipefail

APP_ID="io.github.markomijic.tts_mod_vault"
BIN_NAME="tts_mod_vault"
ICON_SRC="assets/icon/tts_mod_vault_icon.png"
OUT_NAME="TTS_Mod_Vault-x86_64.AppImage"
MAX_GLIBC="${MAX_GLIBC:-2.35}"

# appimagetool is pinned to one release and checked against its SHA-256, so a
# new upstream build can never change a release unnoticed. To upgrade: pick a
# release on https://github.com/AppImage/appimagetool/releases, update both
# lines, and run the script once.
APPIMAGETOOL_VERSION="1.9.1"
APPIMAGETOOL_SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"

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

[ -f "$ICON_SRC" ] || { echo "ERROR: icon not found at $ICON_SRC"; exit 1; }

# Version (e.g. 3.0.0) from pubspec, dropping the +build suffix.
VERSION="$(grep '^version:' pubspec.yaml | head -1 | sed 's/version:[[:space:]]*//' | cut -d'+' -f1)"
[ -n "$VERSION" ] || { echo "ERROR: could not read version from pubspec.yaml"; exit 1; }
ZIP_NAME="Linux.TTS.Mod.Vault.${VERSION}.zip"
echo "==> building TTS Mod Vault $VERSION for Linux"

echo "==> flutter pub get"
$FLUTTER pub get

echo "==> dart run build_runner build (drift / freezed / riverpod codegen)"
$DART run build_runner build --delete-conflicting-outputs

echo "==> flutter gen-l10n"
$FLUTTER gen-l10n

echo "==> flutter build linux --release"
$FLUTTER build linux --release

BUNDLE="build/linux/x64/release/bundle"
[ -d "$BUNDLE" ] || { echo "ERROR: build bundle not found at $BUNDLE"; exit 1; }

# Sanity: both native assets must be in lib/ next to the Flutter .so files, or
# the app dies at startup ("Failed to lookup symbol" / "Failed to load dynamic library").
for lib in libpdfium.so libsqlite3.so; do
  [ -e "$BUNDLE/lib/$lib" ] || {
    echo "ERROR: $lib missing from $BUNDLE/lib — release would crash at launch"
    echo "       (is 'flutter config --enable-native-assets' set and the hook build succeeding?)"
    exit 1; }
done
echo "    native assets OK: libpdfium.so, libsqlite3.so"

# glibc floor: the highest GLIBC_x.y symbol version any bundled binary needs is
# the oldest glibc the release runs on.
need="0"
for bin in "$BUNDLE/$BIN_NAME" "$BUNDLE"/lib/*.so; do
  v="$(objdump -T "$bin" | grep -o 'GLIBC_2\.[0-9]*' | sed 's/GLIBC_//' | sort -V | tail -1 || true)"
  [ -n "$v" ] || continue
  need="$(printf '%s\n%s\n' "$need" "$v" | sort -V | tail -1)"
  if [ "$MAX_GLIBC" != "none" ] && [ "$(printf '%s\n%s\n' "$v" "$MAX_GLIBC" | sort -V | tail -1)" != "$MAX_GLIBC" ]; then
    echo "ERROR: $bin needs glibc $v, newer than MAX_GLIBC=$MAX_GLIBC"
    echo "       build inside ubuntu:22.04 (see packaging/appimage/README.md), or MAX_GLIBC=none for a local test build"
    exit 1
  fi
done
echo "    glibc floor: $need (limit: $MAX_GLIBC)"

# Raw bundle zip: the fallback download for systems the AppImage does not suit
# (same name as the 2.x Linux release). -y keeps symlinks, -X drops extra attributes.
rm -f "build/$ZIP_NAME"
echo "==> zipping the bundle -> build/$ZIP_NAME"
( cd "$BUNDLE" && zip -r -y -X -q "$OLDPWD/build/$ZIP_NAME" . )

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

# AppStream metainfo. Repo keeps the modern .metainfo.xml name, but appimagetool's
# presence-check only recognizes the legacy .appdata.xml name, so install it under
# that name inside the AppImage (still a valid AppStream filename). Only one copy,
# to avoid duplicate-component warnings.
METAINFO_SRC="linux/${APP_ID}.metainfo.xml"
if [ -f "$METAINFO_SRC" ]; then
  mkdir -p "$APPDIR/usr/share/metainfo"
  cp "$METAINFO_SRC" "$APPDIR/usr/share/metainfo/${APP_ID}.appdata.xml"
fi

# AppRun: launches the bundled executable.
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "${0}")")"
export LD_LIBRARY_PATH="${HERE}/usr/bin/lib:${LD_LIBRARY_PATH:-}"
exec "${HERE}/usr/bin/tts_mod_vault" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# Fetch the pinned appimagetool ($WORK is recreated above, so this runs every
# build) and refuse to run it unless the checksum matches.
TOOL="$WORK/appimagetool-x86_64.AppImage"
echo "==> downloading appimagetool $APPIMAGETOOL_VERSION"
curl -fsSL -o "$TOOL" \
  "https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_VERSION}/appimagetool-x86_64.AppImage"
echo "$APPIMAGETOOL_SHA256  $TOOL" | sha256sum -c --quiet - || {
  echo "ERROR: appimagetool checksum mismatch (expected $APPIMAGETOOL_SHA256)"; exit 1; }
chmod +x "$TOOL"

echo "==> packaging AppImage"
# --appimage-extract-and-run avoids needing FUSE (libfuse2) on the host.
ARCH=x86_64 "$TOOL" --appimage-extract-and-run "$APPDIR" "build/$OUT_NAME"

echo ""
echo "==> done:"
echo "    AppImage:  $PWD/build/$OUT_NAME"
echo "    zip:       $PWD/build/$ZIP_NAME"
echo "    test it:  chmod +x build/$OUT_NAME && ./build/$OUT_NAME"
