# TTS Mod Vault

![Downloads](https://img.shields.io/github/downloads/markomijic/TTS-Mod-Vault/total?color=red&label=Total+downloads&style=for-the-badge)
![Latest Downloads](https://img.shields.io/github/downloads/markomijic/TTS-Mod-Vault/latest/total?color=blue&label=Latest+release+downloads&style=for-the-badge)
![Version](https://img.shields.io/github/v/release/markomijic/TTS-Mod-Vault?label=Latest+release&style=for-the-badge)

A cross-platform mod backup and download tool for Tabletop Simulator on Windows, Linux, and macOS. Download assets, create backups, manage URLs, and keep your mods, saves, and saved objects safe.

## Alternative to TTS Mod Backup

TTS Mod Vault is an actively maintained alternative to [TTS Mod Backup](https://www.nexusmods.com/tabletopsimulator/mods/263), which is no longer updated. TTS Mod Vault imports .ttsmod files created by either tool, runs on all major platforms (not just Windows), and includes additional features like images viewing, a Backups tab, a log panel, theming and more.

## Download

- [GitHub Releases](https://github.com/markomijic/TTS-Mod-Vault/releases)
- [NexusMods](https://www.nexusmods.com/tabletopsimulator/mods/426)

Upgrading from 2.x: your settings, folders and URL presets are imported on the first start, and the library is indexed again (the first load takes a moment longer). Your 2.x installation and its data are left untouched. See the [3.0.0 release notes](https://github.com/markomijic/TTS-Mod-Vault/releases/tag/v3.0.0) for details.

## Features

### One library

- **Mods, Saves, Saved Objects and Backups** – Tabs above one list; the toolbar (sort, filter, search, bulk actions) adapts to the tab
- **Instant start** – The library appears right away and refreshes in the background; later starts only re-read files that changed
- **Grid and list views** – With optional titles on cards
- **Sort** – A-Z, newest, recently updated, missing assets; backups by name, size or date
- **Filter** – Folders, backup state, asset status, asset type, backup asset count mismatch
- **Search** – Mods by name, assets of the selected mod, backups by file name
- **Keyboard** – `Ctrl+F` search, `F5` refresh, `Esc` clear selection, `Delete` remove the selected mod (with confirmation), `Ctrl`/`Cmd`-click multi-select

### Backup, Download & Update

- **Download** – Download missing assets (one file, one type or the whole mod) to the local cache used by Tabletop Simulator
- **Backup** – Create backups in the .ttsmod file format, with a default backup folder
- **Backups tab** – Browse, sort, filter, search, import, open and delete all your backup files
- **Backup state** – See which mods have a backup file and whether it is up to date, out of date or has a different asset count
- **Import Backups** – Import .ttsmod files created by TTS Mod Vault or TTS Mod Backup, with a date check for existing mods
- **JSON Import** – Import mod JSON files (plus the PNG) directly
- **Download Workshop Mods by ID** – One or many Steam Workshop ids or URLs at a time
- **Mod updates from Steam Workshop** – Check for and apply mod updates, single or in bulk

### Bulk Actions

- Download, backup, download & backup, update from Workshop, delete assets, check URLs, update URLs, import backups
- **Multi-select** – Select several mods, or act on everything the current search and filters show
- **Cancel** – Every operation can be cancelled from the progress bar

### URL Management

- **Automatic URL handling** – Handles files using the old URL format (`http://cloud-3.steamusercontent.com/` → `https://steamusercontent-a.akamaihd.net/`)
- **Replace URL** – Replace an asset URL with a new one, optionally renaming the cached file
- **Update URLs** – Replace prefixes or entire URLs, for a single item or as a bulk action
- **Update URL presets** – Save and reuse URL replacement presets in Settings
- **Shared assets** – See which other mods use an asset
- **Invalid URLs** – Check the URLs of a mod (or of many mods at once) and keep the broken ones marked

### Mod & Asset Management

- **View Images** – All downloaded images of a mod in one place
- **PDF thumbnails** – Thumbnails of downloaded PDFs, switchable to the URL list
- **Open Files** – Open audio, image and PDF files, or show them in the file explorer
- **Rename** – Rename a mod, save or saved object (and its backup); Save as Mod for saves
- **Deletion** – Delete mods, single asset files, or all assets of a mod with a report of files shared with other mods
- **Per-mod audio asset handling** – Ignore audio globally and override it per mod

### Cleanup, Log & Appearance

- **Cleanup** – Remove cached files that are not part of any installed mod, save or saved object
- **Log panel** – Under the list: what every operation did and why something failed, with filters, search and one-click access to the log file
- **Theming** – Light, dark or system mode, colour presets (including the Classic 2.x look) and a custom seed colour
- **Settings** – Mods, Saves and Backups folders, ignored subfolders and domains, concurrent downloads, backup file naming, update check on start, asset URL font size and more. Settings from 2.x are imported on the first start.

## Installation

### Windows

Download the latest `Windows.TTS.Mod.Vault.<version>.zip` from [GitHub Releases](https://github.com/markomijic/TTS-Mod-Vault/releases), extract it, and run `tts_mod_vault.exe`.

### Linux

Download the latest `TTS_Mod_Vault-x86_64.AppImage` from [GitHub Releases](https://github.com/markomijic/TTS-Mod-Vault/releases), make it executable, and run it:

```sh
chmod +x TTS_Mod_Vault-x86_64.AppImage
./TTS_Mod_Vault-x86_64.AppImage
```

For an app-menu entry and a taskbar icon, add the AppImage with [Gear Lever](https://flathub.org/apps/it.mijorus.gearlever) or AppImageLauncher. A plain `Linux.TTS.Mod.Vault.<version>.zip` (the raw build folder: extract and run `tts_mod_vault`) is also attached to each release for systems the AppImage does not suit; it needs GTK 3 installed.

### macOS (Apple Silicon)

Download the latest `.dmg` from [GitHub Releases](https://github.com/markomijic/TTS-Mod-Vault/releases), open it, and drag the application to your Applications folder.

#### "Apple could not verify… free of malware" / the app won't open

TTS Mod Vault is an open-source app that is **not** signed with a paid Apple Developer ID, so macOS quarantines it after download and Gatekeeper blocks it. You may see a message like _"'TTS Mod Vault' Not Opened — Apple could not verify…"_, or the icon may bounce and then quit with no window.

After dragging the app to **Applications**, open the **Terminal** app and run this command to remove the quarantine flag, then launch the app normally:

```sh
xattr -dr com.apple.quarantine "/Applications/TTS Mod Vault.app"
```

This only needs to be done once (and again after each update). The app is otherwise fully functional — this step is purely Apple's Gatekeeper check for apps distributed outside the App Store without a paid developer certificate.

## Screenshots

<!-- TODO before the 3.0.0 release: replace with 3.0 screenshots (library with tabs, selected mod, backups tab, log panel, settings with Appearance, images viewer). The 2.x images below show the old UI. -->

![Mod options](https://staticdelivery.nexusmods.com/mods/461/images/426/426-1754210010-1826631811.png)
![Asset options](https://staticdelivery.nexusmods.com/mods/461/images/426/426-1754210030-494217467.png)
![Backup](https://staticdelivery.nexusmods.com/mods/461/images/426/426-1754210208-2068770182.png)
![Download all](https://staticdelivery.nexusmods.com/mods/461/images/426/426-1754210165-484744119.png)
![List](https://staticdelivery.nexusmods.com/mods/461/images/426/426-1754210080-95374435.png)
![Filters](https://staticdelivery.nexusmods.com/mods/461/images/426/426-1754210284-1979467777.png)
![View images](https://i.imgur.com/JoUQd4K.jpeg)
![Replace URL](https://i.imgur.com/Wbd33S1.jpeg)

## Building from Source

Built with Flutter 3.47.7 (pinned in `.fvmrc`; `fvm use` picks it up). To set up Flutter, follow the official documentation: https://docs.flutter.dev/get-started/install

One-time setup on every build machine: pdfium (PDF thumbnails) and sqlite3 (the library index) are delivered as Dart native assets, which must be enabled or the app builds but crashes at launch with a missing library.

```sh
flutter config --enable-native-assets
```

Generated code is not committed, so run the two generators after cloning or after editing an annotated class or the ARB file, then build or run as usual:

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift / freezed / riverpod
flutter gen-l10n                                           # lib/l10n/generated/
flutter run -d windows                                     # or macos / linux
```

Release artefacts are built with the scripts under `packaging/`, each of which runs the steps above, builds in release mode and verifies that both native libraries made it into the bundle (see the README next to each script):

| OS | Script | Output |
| --- | --- | --- |
| Windows | `powershell -ExecutionPolicy Bypass -File packaging\windows\build_zip.ps1` | `build\Windows.TTS.Mod.Vault.<version>.zip` |
| Linux | `bash packaging/appimage/build_appimage.sh` | `build/TTS_Mod_Vault-x86_64.AppImage` (plus the raw bundle in `build/linux/x64/release/bundle/`) |
| macOS | `bash packaging/macos/build_dmg.sh` | `build/TTSModVault.dmg` and `build/macOS.TTS.Mod.Vault.<version>.zip` |

### Where the app keeps its data

The library index (`vault.sqlite`) and the log file (`vault.log`, rotated at 5 MB, three files kept) live in the platform's application-support folder. Deleting the folder resets the app; the index is rebuilt on the next start.

| OS | Folder |
| --- | --- |
| Windows | `%APPDATA%\io.github.markomijic\TTS Mod Vault\` |
| macOS | `~/Library/Application Support/io.github.markomijic.ttsModVault/` |
| Linux | `~/.local/share/tts_mod_vault/` |

TTS Mod Vault 2.x kept its data in `Documents/TTS Mod Vault/`; 3.0 reads the settings from there once and leaves that folder alone.

## License

GPL-3.0-only. See [LICENSE](LICENSE).
