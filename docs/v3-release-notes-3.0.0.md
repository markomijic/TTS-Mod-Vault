# TTS Mod Vault 3.0.0

TTS Mod Vault 3.0 is a complete rewrite of the app: a new storage engine, a much faster library index, one library page with tabs, a log panel that tells you why something failed, and theming. Everything you could do in 2.x is still here, and `.ttsmod` backups remain fully compatible in both directions (TTS Mod Vault 2.x, 3.0 and TTS Mod Backup all read each other's files).

## Downloads

| OS | File |
| --- | --- |
| Windows | `Windows.TTS.Mod.Vault.3.0.0.zip` – extract and run `tts_mod_vault.exe` |
| Linux | `TTS_Mod_Vault-x86_64.AppImage` – `chmod +x`, then run; `Linux.TTS.Mod.Vault.3.0.0.zip` is the raw build folder for systems the AppImage does not suit |
| macOS (Apple Silicon) | `macOS.TTS.Mod.Vault.3.0.0.zip` – contains the `.dmg`; see the first-launch note below |

Also on [Nexus Mods](https://www.nexusmods.com/tabletopsimulator/mods/426).

## What to expect on the first start

- **Your settings come along.** Folders, URL presets and every other option from TTS Mod Vault 2.x are imported once, on the first start. The log shows "Imported settings from TTS Mod Vault 2.x" when it happens.
- **2.x is left untouched.** 3.0 keeps its own data in a new place (below) and never modifies or deletes the 2.x folder `Documents/TTS Mod Vault/`. You can keep running 2.x next to 3.0, or delete that folder yourself once you no longer need 2.x.
- **The library is indexed again.** Caches from 2.x are not imported, so the first load reads every mod file once and takes a moment longer than usual. Every later start only re-reads files that changed, so it is faster than 2.x from then on.
- **Where the data and the log file are.** The index (`vault.sqlite`) and the log file (`vault.log`) live in the app-data folder; attach `vault.log` to bug reports (the log panel header and Help → About both open it):
  - Windows: `%APPDATA%\io.github.markomijic\TTS Mod Vault\`
  - macOS: `~/Library/Application Support/io.github.markomijic.ttsModVault/`
  - Linux: `~/.local/share/tts_mod_vault/`

### ⚠️ macOS users — first launch
This app isn't notarized (no paid Apple Developer account), so macOS blocks it on
first open. After dragging it to Applications, run this once in Terminal:

    xattr -dr com.apple.quarantine "/Applications/TTS Mod Vault.app"

## Features

- Complete rewrite with a new storage engine and a faster library index
- One library page: Mods, Saves, Saved Objects and Backups are tabs above the list; sort, filter, search and bulk actions adapt to the tab
- Instant start: the library appears right away and refreshes in the background
- Log panel under the list with contextual failure messages, filters by level and source, search, jump to the mod an entry is about, copy, clear and one-click access to the log file
- Theming: light, dark and system mode, colour presets (including the Classic 2.x look) and a custom seed colour
- Help, Changelog and About in one dialog with a manual update check
- Settings dialog with an Appearance section; every 2.x option is kept
- Keyboard shortcuts: `Ctrl+F` search, `F5` refresh, `Esc` clear selection, `Delete` remove the selected mod or backup (with confirmation)
- "Copy missing URLs" for the selected mod
- Every operation, including the cleanup scan, can be cancelled from the progress bar
- Languages: English, Croatian (Hrvatski), Brazilian Portuguese (Português), Russian (Русский), Spanish (Español), Korean (한국어), Simplified Chinese (简体中文) and German (Deutsch), chosen in Settings → Interface → Language
- Domain reachability: URL checks first test whether each domain can be reached, and URLs on a domain that is down or blocked on your network are no longer marked invalid
- After a download, the files still missing are checked and a "Download check results" dialog lists unreachable domains and dead URLs (Settings → Network → "Check missing files after downloads", on by default)
- Settings → Network → "Check all Mods and Saves domains"
- Cards show "N missing, N invalid" when some missing files have URLs a check found dead

## Changes

- Settings and folders are imported from TTS Mod Vault 2.x on the first start; the 2.x files stay where they are
- Caches from 2.x are not imported; the library is indexed again on the first start
- App data moved from `Documents/TTS Mod Vault/` to the app-data folder listed above
- The sidebar no longer expands when the mouse crosses it; the chevron at the top toggles labels and the choice is remembered
- Checking a single URL from the asset menu now runs like the per-mod check (progress bar, cancel) and records the result, so an invalid URL stays marked
- URL checks skip audio URLs that are hidden by the audio setting, matching the asset list
- Importing a backup of a save or saved object now registers it in the library right away (2.x extracted the files without indexing them)
- Update from Workshop is unavailable for mods whose file name is not a Workshop id, instead of failing
- Backup tooltips show the mod's save date next to the backup date
- Fixed: renaming a mod whose name contains escaped quotes no longer truncates or corrupts the name
- Fixed: `.wav` and `.ogg` files were sometimes detected with the wrong extension
- Fixed: mods with the same file name in different folders no longer overwrite each other in the library

## Known limitations

- The macOS build is ad-hoc signed; the first-launch step above is needed after every update.
- The Linux AppImage needs glibc 2.35 or newer (Ubuntu 22.04 and later, or equivalents).
- Settings import reads 2.x data only once. If you want to redo it, delete 3.0's `vault.sqlite` while the app is closed (the index is rebuilt anyway) and start the app again while the 2.x folder still exists.

## Thanks

Bug reports and feature requests: [GitHub issues](https://github.com/markomijic/TTS-Mod-Vault/issues) or the Nexus Mods page. If the app saves you time, consider a coffee on [Ko-fi](https://ko-fi.com/ttsmodvault).
