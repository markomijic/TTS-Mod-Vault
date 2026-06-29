# Linux packaging — AppImage

This directory builds the Linux release of TTS Mod Vault as an
[AppImage](https://appimage.org/): a single self-contained file the user
downloads, marks executable, and runs. It fits the app's "you're notified of an
update, download the new version, replace the old file" model — updating is just
replacing one `.AppImage`.

## Build

Run on **Linux** (Flutter cannot build Linux targets on Windows/macOS):

```bash
bash packaging/appimage/build_appimage.sh
```

Output: `build/TTS_Mod_Vault-x86_64.AppImage`

Test it:

```bash
chmod +x build/TTS_Mod_Vault-x86_64.AppImage
./build/TTS_Mod_Vault-x86_64.AppImage
```

### Prerequisites

- Flutter with Linux desktop enabled (`flutter doctor` should be clean for Linux)
- Build toolchain: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev`
- `curl` (the script downloads `appimagetool` automatically into `build/appimage/`)

FUSE is **not** required: the script invokes appimagetool with
`--appimage-extract-and-run`, so you don't need `libfuse2`/`libfuse2t64`.

## ⚠️ The most important rule: where you build sets the glibc floor

An AppImage bundles the app's libraries but **not glibc** (glibc can't be
practically bundled — it includes the dynamic loader and is tied to the kernel).
glibc is **forward-compatible only**, so an AppImage built on a given distro
requires *at least* that distro's glibc at runtime.

- Built on **Ubuntu 26.04** → runs only on ~26.04-and-newer systems. Fine for
  local testing, **bad for public releases**.
- Built on **Ubuntu 22.04** (glibc 2.35) → runs on the large majority of distros
  from the last several years. **This is what you want for releases.**

Since there's no GitHub Actions in use, the recommended way to get an old glibc
without a second VM is a container:

```bash
# from the repo root, on any Linux host with Docker/Podman
docker run --rm -v "$PWD":/src -w /src ubuntu:22.04 bash -c '
  apt-get update &&
  apt-get install -y curl git unzip xz-utils clang cmake ninja-build \
    pkg-config libgtk-3-dev &&
  # install Flutter inside the container, then:
  bash packaging/appimage/build_appimage.sh
'
```

(Bundling GTK with `linuxdeploy-plugin-gtk` is a *separate*, optional refinement
for distros lacking GTK3 — it does **not** remove the glibc requirement. Don't
confuse the two.)

## Files involved

| File | Role |
| --- | --- |
| `packaging/appimage/build_appimage.sh` | Builds the bundle, assembles the AppDir, runs appimagetool |
| `linux/io.github.markomijic.tts_mod_vault.desktop` | Desktop entry (single source of truth) |
| `linux/io.github.markomijic.tts_mod_vault.metainfo.xml` | AppStream metadata |
| `assets/icon/tts_mod_vault_icon.png` | App icon (from `pubspec.yaml`) |

The app id is `io.github.markomijic.tts_mod_vault` — it must stay consistent
across the desktop file name, the metainfo `<id>`, `APPLICATION_ID` in
`linux/CMakeLists.txt`, and `StartupWMClass`.

## Quirk: `.metainfo.xml` vs `.appdata.xml`

The repo keeps the metadata under the **modern** name
`io.github.markomijic.tts_mod_vault.metainfo.xml` (correct for Flathub/software
centers). But `appimagetool`'s presence-check only recognizes the **legacy**
`.appdata.xml` name, so the build script installs it *into the AppImage* as
`io.github.markomijic.tts_mod_vault.appdata.xml`. Both are valid AppStream
filenames; only one copy is installed to avoid duplicate-component warnings.

## The icon, and why it isn't automatic on Linux

The icon **is** embedded in the AppImage (`appimagetool` logs
`Creating .DirIcon ...`). But:

- **GNOME Files shows a generic cog for the AppImage file** — it does not render
  an AppImage's embedded icon as the file's icon. This is normal; ignore it.
- **The running window / taskbar icon** on Wayland (Ubuntu's default) comes
  *only* from a **system-installed** `.desktop` + themed icon whose name/
  `StartupWMClass` matches the window's `app_id`. There is no runtime API to set
  a window icon on Wayland — which is why an older `gtk_window_set_icon_from_file`
  approach silently did nothing.

To make the icon appear in the app menu and taskbar, the AppImage must be
**integrated** (it won't happen automatically for a loose file):

- Use **Gear Lever** (Flathub) or **AppImageLauncher** — "add" the AppImage and
  it installs the `.desktop` + icon into `~/.local/share`.

The window's confirmed `app_id` is `io.github.markomijic.tts_mod_vault`, and
`StartupWMClass` in the desktop file is set to match it.

## Fallback: the raw bundle

Every `flutter build linux` also produces a plain bundle at
`build/linux/x64/release/bundle/` (exe + `data/` + `lib/`, kept together). You
can zip/tar that as a no-frills fallback for users the AppImage doesn't suit. It
shares the same glibc floor and also relies on the host having GTK3, but has no
icon/menu integration unless the user installs the `.desktop` manually.
