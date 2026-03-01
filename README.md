# TTS Mod Vault

![Downloads](https://img.shields.io/github/downloads/markomijic/TTS-Mod-Vault/total?color=red&label=Total+downloads&style=for-the-badge)
![Latest Downloads](https://img.shields.io/github/downloads/markomijic/TTS-Mod-Vault/latest/total?color=blue&label=Latest+release+downloads&style=for-the-badge)
![Version](https://img.shields.io/github/v/release/markomijic/TTS-Mod-Vault?label=Latest+release&style=for-the-badge)

A cross-platform mod backup and download tool for Tabletop Simulator on Windows, Linux, and macOS. Download assets, create backups, manage URLs, and keep your mods, saves, and saved objects safe.

## Alternative to TTS Mod Backup

TTS Mod Vault is an actively maintained alternative to [TTS Mod Backup](https://www.nexusmods.com/tabletopsimulator/mods/263), which is no longer updated. TTS Mod Vault imports .ttsmod files created by either tool, runs on all major platforms (not just Windows), and includes additional features like images viewing, backups tab and more.

## Download

- [GitHub Releases](https://github.com/markomijic/TTS-Mod-Vault/releases)
- [NexusMods](https://www.nexusmods.com/tabletopsimulator/mods/426)

## Features

### Backup, Download & Update

- **Download** – Download all assets to the local cache used by Tabletop Simulator
- **Backup** – Create backups in the .ttsmod file format
- **Backups tab** – Browse and manage all your backup files
- **Import Backups** – Import .ttsmod files created by TTS Mod Vault or TTS Mod Backup
- **JSON Import** – Import mod JSON files directly
- **Backup state** – See which mods have a backup file and whether it is out of date or up to date
- **Download Workshop Mods by ID** – Download either with single or multiple IDs
- **Mod updates from Steam Workshop** – Check for and apply mod updates

### Bulk Actions

- Download, backup, update mods, delete assets, update URLs
- **Multi-select** – Select multiple mods for bulk actions

### URL Management

- **Automatic URL handling** – Handles files using old URL format (`http://cloud-3.steamusercontent.com/` → `https://steamusercontent-a.akamaihd.net/`)
- **Replace URL** – Replace a asset URL with a new one
- **Update URLs** – Replace prefixes or entire URLs, either for a single item or as a bulk action
- **Update URL presets** – Save and reuse URL replacement presets in Settings
- **Check for shared asset URLs** – Detect assets shared across mods
- **Check for invalid asset URLs** – Find broken or invalid asset links

### Sort, Filter & Browse

- Sort by A-Z, newest, missing assets, or recently updated
- Filter by folders, backup state, asset status, and asset type
- Filter mods by backup asset count mismatch
- **Search assets** – Search through assets of a selected mod
- **View Images** – View all downloaded images of a specific mod in one place
- **Open Files** – Open Audio, Images, and PDF files directly

### Mod & Asset Management

- **Mod and asset file deletion** – Delete mod and asset files directly from the app
- **Per-mod audio asset handling** – Configure audio handling on a per-mod basis

### Cache & Cleanup

- Remove unused cached files that aren't part of your installed mods, saves, or saved objects
- **Mod and Backup information caching** – Faster loading times with cached mod and backup data

### Settings & Configuration

- Separately set paths for your Mods folder and Saves folder
- Custom Asset URL font size
- Exclude audio, subfolders, and domains

## Installation

### Windows

Download the latest `.zip` from [GitHub Releases](https://github.com/markomijic/TTS-Mod-Vault/releases), extract it, and run the `.exe` file.

### Linux

Download the latest `.zip` from [GitHub Releases](https://github.com/markomijic/TTS-Mod-Vault/releases), extract it, and run the executable.

### macOS (Apple Silicon)

Download the latest `.dmg` from [GitHub Releases](https://github.com/markomijic/TTS-Mod-Vault/releases), open it, and drag the application to your Applications folder.

## Screenshots

![Mod options](https://staticdelivery.nexusmods.com/mods/461/images/426/426-1754210010-1826631811.png)
![Asset options](https://staticdelivery.nexusmods.com/mods/461/images/426/426-1754210030-494217467.png)
![Backup](https://staticdelivery.nexusmods.com/mods/461/images/426/426-1754210208-2068770182.png)
![Download all](https://staticdelivery.nexusmods.com/mods/461/images/426/426-1754210165-484744119.png)
![List](https://staticdelivery.nexusmods.com/mods/461/images/426/426-1754210080-95374435.png)
![Filters](https://staticdelivery.nexusmods.com/mods/461/images/426/426-1754210284-1979467777.png)
![View images](https://i.imgur.com/JoUQd4K.jpeg)
![Replace URL](https://i.imgur.com/Wbd33S1.jpeg)

## Building from Source

Created using Flutter 3.38.10. To build the app, follow the official Flutter documentation to get started: https://docs.flutter.dev/get-started/install
