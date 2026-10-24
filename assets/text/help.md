# Getting started

TTS Mod Vault reads the Tabletop Simulator `Mods` and `Saves` folders, shows every mod, save and saved object with the state of its asset files, and lets you download missing files, create `.ttsmod` backups and restore them.

- Set the folders in Settings → Folders. A backups folder is optional but required for the backup state to be remembered between starts.
- The library is indexed on start; press Refresh in the sidebar after changing files outside the app. "Clear Vault cache" re-reads every JSON file.
- Mods, Saves, Saved Objects and Backups are tabs above the list. Saved Objects appear when enabled in Settings → Features, Backups when a backups folder is set.

# Library

- Left-click a mod to see its assets and actions
- Right-click a mod for more actions (download, backup, open folder, rename, delete, ...)
- Ctrl-click (Cmd-click on macOS) to select several mods for bulk actions
- Hover the backup icon on a mod to see its backup date and asset count
- Hover the type selector to see how many mods, saves and saved objects there are
- Search, sort and filter with the toolbar; bulk actions respect the search text and filters
- Keyboard: Ctrl+F focuses the search, F5 refreshes, Esc clears the selection, Delete removes the selected mod after a confirmation

# Selected mod

The right panel lists the assets of the selected mod grouped by type. URL colours:

- Red: the asset file is missing
- Green: the asset file is downloaded
- Orange: a URL check flagged the URL as invalid
- Highlighted: the URL you clicked last

Actions:

- Left- or right-click a URL for options (open, copy, download, replace, delete the file)
- Double-click a PDF thumbnail to open the file
- Download all: download every missing asset file. Files still missing afterwards are checked: a "Download check results" dialog lists domains that could not be reached and URLs that are dead. Turn this off with Settings → Network → Check missing files after downloads
- "3 missing, 2 invalid" on a card: 3 files are missing and a URL check found 2 of their URLs dead, so those cannot be downloaded
- Backup: create a backup from the downloaded asset files
- Audio assets can be excluded globally in Settings → Features and overridden per mod from the mod's context menu

# Backups

- Backups are `.ttsmod` archives containing the mod JSON, its image and every downloaded asset file.
- Backup state compares the backup with the mod: up to date, out of date (the JSON changed after the backup) or asset count mismatch.
- Import backups from the sidebar to restore archives into the Mods folder. Import JSON adds a mod from a JSON file.
- Bulk backup offers skip, replace and replace-if-out-of-date, with optional deletion of the mod afterwards.

# Update URLs

The Update URLs feature works by replacing the beginning of URLs, or even entire URLs, of "Old prefix" with "New prefix".

You can enter multiple old prefixes by separating them with the `|` pipe symbol. In Settings → Update URL presets you can create presets which are then offered in the Update URLs dialog.

Using a single old prefix:

- Old prefix: `http://pastebin.com/raw.php?i=`
- New prefix: `https://pastebin.com/raw/`

If your mod contains `http://pastebin.com/raw.php?i=1234` and `http://pastebin.com/raw.php?i=example`, they will be updated to `https://pastebin.com/raw/1234` and `https://pastebin.com/raw/example`.

Using multiple old prefixes:

- Old prefixes: `http://pastebin.com/raw.php?i=|http://pastebin.com/raw/|http://pastebin.com/`
- New prefix: `https://pastebin.com/raw/`

If your mod contains `http://pastebin.com/raw.php?i=abcd`, `http://pastebin.com/raw/5678` and `http://pastebin.com/example2`, they will be updated to `https://pastebin.com/raw/abcd`, `https://pastebin.com/raw/5678` and `https://pastebin.com/raw/example2`.

# Workshop

- Download Workshop mods by Steam Workshop id or URL from the sidebar; several ids can be entered at once.
- Update from Workshop re-downloads the JSON of a mod that already exists. The force option overwrites a newer local file.

# Troubleshooting

- The log panel under the list records every operation with its failures; expand it to filter by level and source, search, copy entries or clear it. Click an entry to select its mod.
- The log file `vault.log` lives next to the database. Open it from the log panel header or from the About tab; attach it to bug reports.
- Nothing shows up after a folder change? Press Refresh. Still nothing? Check the folder paths in Settings → Folders and the excluded subfolders.
- Downloads of working URLs fail when many run at once? Lower the concurrent downloads in Settings → Network.
- URL checks and the check after a download first test whether each domain can be reached at all. URLs on a domain that cannot be reached (it is down, or blocked on your network) are not marked invalid, and a URL check with such a domain is not saved. Settings → Network → Check all Mods and Saves domains tests every domain your Mods and Saves use.
