# v3.0.0

The Vault cache is rebuilt on the first start, so the first library load takes a moment longer than usual.

## Features

· Complete rewrite with a new storage engine and a faster library index
· One library page: Mods, Saves, Saved Objects and Backups are tabs above the list
· Instant start: the library appears right away and refreshes in the background
· Log panel under the list with contextual failure messages, filters, search and one-click access to the log file
· Theming: light, dark and system mode, colour presets (including the Classic 2.x look) and a custom seed colour
· Help, Changelog and About in one dialog with a manual update check
· Settings dialog with an Appearance section; every 2.x option is kept
· Copy missing URLs of the selected mod
· Every operation, including the cleanup scan, can be cancelled from the progress bar
· Languages: English, Croatian (Hrvatski) and Brazilian Portuguese (Português), chosen in Settings → Interface → Language
· Domain reachability: URL checks first test whether each domain can be reached, and URLs on unreachable domains are no longer marked invalid
· After a download, the files still missing are checked and a "Download check results" dialog lists unreachable domains and invalid URLs
· Settings → Network: Check all Mods and Saves domains
· Cards show "N missing, N invalid" when some missing files have URLs a check found dead

## Changes

· Settings and folders are imported from TTS Mod Vault 2.x on the first start; the 2.x files are left untouched
· Caches from 2.x are not imported; the library is indexed again on the first start
· App data moved from Documents/TTS Mod Vault to the app data folder (see Help → Troubleshooting)
· Keyboard shortcuts: Ctrl+F search, F5 refresh, Esc clear selection, Delete remove the selected mod or backup
· The sidebar no longer expands on hover; the chevron at the top toggles labels and the choice is remembered
· Checking a single URL from the asset menu runs like the per-mod check and records the result
· URL checks skip audio URLs hidden by the audio setting
· Importing a backup of a save or saved object registers it in the library right away
· Update from Workshop is unavailable for mods whose file name is not a Workshop id
· Backup tooltips show the mod's save date next to the backup date
· Fixed renaming of mods whose name contains escaped quotes
· Fixed .wav and .ogg files being detected with the wrong extension
· Fixed mods with the same file name in different folders overwriting each other in the library

# v2.1.0

It is recommended to clear the cache on the first run due to the new detection of embedded URLs
(Refresh → Clear Vault cache)

## Features

· Detection of embedded URLs
· PDF thumbnail previews
· Setting for the default PDF view (thumbnails or URLs)
· Save as Mod option in the Saves context menu
· Bulk action to check all URLs for validity
· Rename mod, save or saved object

## Changes

· Improved asset download and URL-checking queues
· Added a Download option to the mod context menu
· Bulk Actions button now shows the number of affected mods based on the current search and/or filters
· Updated backup import for existing mods to check JSON file dates
· Added an option to set the backup folder as the default when creating a backup without a preset folder
· Action buttons are now shown for mods without assets
· Fixed an issue where some files were not recognized because of file extension case sensitivity
· Fixed URL validation not covering text/html cases
· Fixed an issue where URLs without a domain were ignored
· Fixed opening URLs without a scheme

# v2.0.0

It is recommended to clear the cache on the first run
(Refresh → Clear Vault cache)

BREAKING CHANGE
Saved object backup file naming has been changed to "Filename (saved object).ttsmod"
Backups of saved objects made with previous versions will not be detected until renamed

## Features

· Updated UI layout with sidebar
· Backups tab
· Backup information caching for faster loading times
· Check for shared asset URLs
· Check for invalid asset URLs
· Mod and asset file deletion
· Multi-select support for bulk actions
· Searching assets of selected mod
· Sorting by missing assets and recently updated
· Filtering by asset status and type
· Filtering mods by backup asset count mismatch
· New setting for Asset URL font size
· New setting for custom Saves folder path
· New settings for excluding audio, subfolders and domains
· Per-mod audio asset handling
· JSON import support
· Update URL presets in Settings
· Mod updates from Steam Workshop

## Changes

· Updated saved object backup naming
· Clear cache moved to Refresh and renamed to Clear Vault cache
· Removed setting to show or hide URL replacement features
· Various UI updates and refinements
· General bug fixes and improvements

# v1.3.0

Due to asset URL bug fixes in this version, it is recommended to clear the cache on the first run
The new URL replacement features are disabled by default and can be enabled in Settings

## Features

· Clear cache - available under Tools
· Update URLs - lets you replace prefixes or entire URLs, either for a single item or as a bulk action

## Changes

· New Setting - Force JSON filename inclusion in backup filename for all cases
· Last selected asset URL now stays highlighted after closing the context menu
· Removed the tool for renaming old backups
· Fixed Steam CDN URLs not downloading when a trailing / was missing
· Fixed URLs with spaces breaking UI and cache checks
· Fixed URLs with '\r' or '\n' suffixes breaking cache checks and downloads
· Fixed 'Download Workshop Mod by ID' failing to create a JSON file in cases where BsonBinary exists within JSON data

# v1.2.1

## Changes

· Fixed URL replacement not working with the old URL format (http://cloud-3.steamusercontent.com/)
· Fixed loading failures caused by backup file names containing Unicode characters
· Added support for an additional date format in mod JSON files
· Reduced memory usage when creating a backup
· Reduced loading times for backup files

# v1.2.0

· Backup filename format changed
Version 1.2.0 updates the backup file naming format to match TTS Mod Backup
Backups created with TTS Mod Vault versions 1.0.0 to 1.1.0 must be renamed to work with the new Backup State feature.

A renaming tool is available under:
Tools → Rename old backups

## Features

· Backup State
· Sort & Filter
· Bulk actions:
    Download All
    Backup All
    Download & Backup All
· Download Workshop Mod by ID

## Changes

· UI updates
· New settings options
· General improvements and fixes

# v1.1.0

## Features

· Search
· Viewing images
· Support for Saves and Saved Objects
· Separate selection of Mods and Saves folders
· Opening audio, image and pdf files
· URL replacement tool

## Changes

· Reworked loading system for faster load times
· Replaced storage solution with faster alternative for improved performance
· General improvements and fixes

# v1.0.2

## Changes

· Fixed mods not appearing if they were in a folder within the Workshop folder
· Fixed issue where downloading files from Dropbox links, where files were deleted, incorrectly marked them as downloaded

# v1.0.1

## Changes

· Fixed asset lists not updating due to incorrect reading of last time mod was updated
· Added Download from GitHub button to "Check for updates" dialog
· Performance improvements when opening file explorer

# v1.0.0

## Features

· Download - Download all mod assets locally
· Backup - Create backups of your mods
· Import Backup - Restore existing ttsmod files backups
· Cleanup - Remove unused cached files that aren't part of your installed mods
