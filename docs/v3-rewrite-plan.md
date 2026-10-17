# TTS Mod Vault v3 Rewrite Plan

Status: proposal, 2026-10-17. Written against the current `main` (2.1.0 + uncommitted `material_ui` import swap), Flutter 3.47.7 / Dart 3.13.5 installed locally.

## 1. Goals and non-goals

Goals (from the brief):

- Rebuild on the current Flutter stable and current package majors, most importantly Riverpod 3.x.
- Better organised code, standardised UI, modern practices, measurably better performance, cleaner architecture.
- Lives next to the current app until it reaches feature parity, then the old app is deleted.
- No compatibility with v2 caches when dropping it buys a better design.
- Targets Windows, macOS, Linux. Manual releases, no CI, no auto-update (unchanged from v2).

Non-goals:

- Keeping the v2 Hive cache or the v2 Hive settings box format (see decision D4 for the one exception).
- Changing the `.ttsmod` zip layout. Backups made by v2 and by TTS Mod Backup must still import, and v3 backups must still import into v2.
- Changing TTS on-disk conventions (asset filename = URL with non-alphanumerics stripped, `Mods/<Type>/` folders, `Workshop/<id>.json`, etc.).

## 2. What v2 does today (inventory)

22.5k lines of Dart, no tests. Everything lives under `lib/src/`.

| Area | v2 implementation | Notes |
| --- | --- | --- |
| State | `hooks_riverpod` 2.6, 15 `StateNotifier`s + 1 `AsyncNotifier`, one 358-line `provider.dart` hub | `StateNotifier`/`StateProvider` are legacy in Riverpod 3 |
| Models | Hand-written immutable classes, `Mod` has 17 fields and is re-constructed field by field in 8 places | `copyWith` cannot clear `backup` to null, so code avoids it |
| Cache | 4 Hive CE boxes: mod URLs, mod metadata (string-suffix keys), app data/settings, backup asset counts | Whole boxes in memory, every "shared asset" question rebuilds an inverted index over all mods inside an isolate |
| Load pipeline | `getJsonFilesInDirectory` -> `processInitialModsInIsolate` (reads head of every JSON for SaveName/EpochTime on every start) -> adaptive batches -> N isolates each receiving copies of all 5 existing-asset maps | Good parallelism, but heavy copying and one full read pass over all JSONs each start |
| URL extraction | Single regex over the raw JSON text, handles Lua-embedded escaped JSON, `{en}...{fr}...` multi-language values, old cloud URL rewrite | Battle-tested, must be ported verbatim with tests |
| Downloads | Dio, hand-rolled worker pool, retry with backoff, Steam trailing-slash fallback, HTML error page detection, MIME-based extension | Keep the logic |
| URL check | HEAD then ranged GET, text/html = dead | Keep |
| Workshop | Steam `GetPublishedFileDetails`, BSON -> JSON via `bson`, EpochTime injection, preview image resize | Keep; simplify image path |
| Backups | Zip via `archive` in a spawned isolate with progress port; existing backups indexed by custom zip central-directory reader + Hive count cache | Central-directory reader is a keeper |
| Import | `ZipDecoder().decodeBytes(readAsBytes())` | Loads the entire .ttsmod into RAM |
| Bulk actions | 9 operations, each drives UI by calling `setSelectedMod` per mod, sticky `cancelled` booleans, `BuildContext` passed into notifiers, dialogs shown from notifiers | Main architectural pain point |
| Progress UI | 4 progress bar widgets + 6 state classes with their own status enums | Should be one |
| UI | Dark theme only, hard-coded `Colors.white`/font sizes, custom hover sidebar, 24 dialogs with `BackdropFilter`, `utils.dart` (1347 lines) holds theme + dialogs + context menus + helpers | |
| l10n | ARB scaffold with 1 string; every user-facing string hard-coded | |
| Platform | window_manager, pdfrx_engine (pdfium via native assets), macOS pdfium module-path fix in `main.dart`, custom Linux header bar title, Windows `Runner.rc` product name | Must carry over |

Known smells and bugs the rewrite should fix (not a complete list):

- `File(...).existsSync()` inside `ModsGridCard.build` (sync IO on the UI thread per card, per rebuild).
- `SelectedModView` list: filtered items return `SizedBox.shrink()` instead of being removed, and `isFirstHeader` is O(n^2).
- Every grid card watches the whole `multiModsProvider` set, so one selection change rebuilds every card.
- `createdAtTimestamp` is seconds from `stat.changed` (ctime, not creation time on Linux); `lastModifiedTimestamp` is `microseconds ~/ 1000` (milliseconds). Mixed units.
- Directory paths built with `'$modsDir/Workshop'` string concatenation rather than `path.join`.
- Artificial 500 ms delay in `loadModsData`; `Future.delayed(kThemeChangeDuration)` hacks after dialogs.
- Success detection by string prefix (`result.startsWith('Mod saved to:')`) and error classification by `e.toString().contains("NoSuchMethod")`.
- `http` and `dio` both used for HTTP.
- Workshop preview image is PNG-encoded at level 0, re-read, re-decoded, then resized and encoded again.
- Bulk actions import widgets (`BulkUrlCheckResultsDialog`) and call `showDialog`: a layering violation that also makes them untestable.

## 3. Decisions (recommended defaults; override any of these)

| # | Decision | Recommendation | Why |
| --- | --- | --- | --- |
| D1 | Where the new app lives | Confirmed. `D:\Dev\TTS-Mod-Vault\v3\` (repo root is `D:\Dev\TTS-Mod-Vault`), a second Flutter project inside the same git repo. Same `name: tts_mod_vault`, same org `io.github.markomijic`, version `3.0.0+1`. At cut-over: delete the old root project, `git mv v3/* .`. | Keeps repo history, GitHub releases and the update-check URL. Same package name keeps `package:tts_mod_vault/...` imports and the `tts_mod_vault` binary name that the AppImage/desktop/metainfo files expect. |
| D2 | State management | `hooks_riverpod` 3.4 + `riverpod_annotation` 4 + `riverpod_generator` 4 + `riverpod_lint`. `Notifier`/`AsyncNotifier` only, no `legacy.dart` imports. Keep `flutter_hooks` for ephemeral widget-local state only. | Code generation removes provider boilerplate and the lint catches the Riverpod 3 traps (`ref` after `await`, missing `ref.mounted`). |
| D3 | Local store | SQLite via `drift` 2.35 (+ `drift_dev`, `sqlite3` 3.x) replacing Hive. Database runs on drift's background isolate. | Shared-asset lookups, cleanup, delete-assets and "which mods reference file X" become indexed queries instead of rebuilding maps in isolates. Stat-based (mtime+size) change detection means unchanged JSON files are never opened at startup. `sqlite3` 3.x ships its native library through Dart native assets, the same mechanism pdfium already requires. |
| D4 | v2 data carry-over | Confirmed. Caches: dropped. Settings + chosen folders + URL presets: one-shot importer that reads the v2 Hive `AppData` box on first run, writes to the new store, then deletes the v2 Hive files. Remove the importer and the `hive_ce` dependency one release later. See 3.1 for the details. | Defaults re-detect the TTS folders anyway, but losing URL presets and a custom backup folder is a bad first impression for existing users. The importer is ~60 lines. |
| D5 | UI toolkit | `package:material_ui` (official, flutter.dev publisher, needs Flutter >= 3.47) from day one, Material 3, `ColorScheme.fromSeed`, dark and light theme, all colours/typography from the theme. User theming is a first-class setting from the start, see 4.7. | You already started this swap in the working tree. `flutter/material.dart` is being moved out of the SDK into this package. |
| D6 | Navigation | No router package. An `AppShell` with a `NavigationRail` for destinations (Mods, Backups, Log) and plain `Navigator` pushes for the images viewer and dialogs. The rail never expands on hover; it expands only via a persisted toggle. See 4.6. | Three top-level destinations do not justify go_router. Hover expansion fires for anyone whose OS taskbar sits on the left edge. |
| D7 | Strings | All user-facing text through ARB (`flutter gen-l10n`), English only for now. | Retrofitting l10n later means touching every widget again. The scaffold already exists in v2. |
| D8 | Lints | `flutter_lints` 6 + `riverpod_lint` 3.1 (installed as an `analysis_server_plugin` via the `plugins:` key in `analysis_options.yaml`, not through pubspec; `custom_lint` is no longer involved), plus an explicit extra rule set (`always_use_package_imports`, `prefer_single_quotes`, `unawaited_futures`, `avoid_dynamic_calls`, `require_trailing_commas`, `prefer_final_locals`) and strict casts/inference/raw types. | Stricter than v2 without `very_good_analysis` noise (doc comments on everything). |
| D9 | Flutter version | Pin with FVM: `.fvmrc` -> 3.47.7 in `v3/`. SDK constraint `^3.13.0`. | material_ui needs >= 3.47.0, pdfrx_engine 0.6 needs Dart >= 3.13. |
| D10 | Tests | Unit tests for every pure domain function and for the data layer using `package:file` `MemoryFileSystem`; widget tests for the shell, mod list, selected-mod view and the operation progress bar. No golden tests. | v2 has zero tests; the URL extraction regex alone has a dozen documented edge cases that should never regress silently. |
| D11 | Background work | One `WorkerPool` (persistent isolates, `Platform.numberOfProcessors - 2`, min 2) with sealed task/result classes, replacing ad-hoc `Isolate.run` and `compute` calls. Workers do file IO and parsing only; all DB writes happen on the main isolate via drift. | Removes per-call isolate spawn cost and the repeated copying of large maps. |

### 3.1 Store location, first run, and why SQLite over Hive

Where the data lives:

| | v2 (Hive) | v3 (SQLite) |
| --- | --- | --- |
| Windows | `%USERPROFILE%\Documents\TTS Mod Vault\*.hive` | `%APPDATA%\io.github.markomijic\TTS Mod Vault\vault.sqlite` |
| macOS | `~/Documents/TTS Mod Vault/` | `~/Library/Application Support/io.github.markomijic.ttsModVault/vault.sqlite` |
| Linux | `~/Documents/TTS Mod Vault/` (XDG documents) | `~/.local/share/tts_mod_vault/vault.sqlite` |

v3 uses `path_provider`'s application-support directory, which is the conventional place for app-private data; v2 used the Documents folder because that is what `Hive.initFlutter` defaults to. The log file (section 4.8) sits next to the database. On Windows the folder names come from `CompanyName` and `ProductName` in `Runner.rc`, which v3 copies from v2.

First run:

1. Open (create) `vault.sqlite`, run migrations.
2. If the v2 folder exists and contains `AppData.hive`: read the `TTSModVaultSettings` JSON, `ModsDir`, `SavesDir`, `BackupsDir`, write them to `kv`, then delete the whole v2 folder. Log one info line ("Imported settings from TTS Mod Vault 2.x").
3. If it does not exist (fresh install, or v3 already ran once): nothing happens. Settings fall back to `Settings.defaults()`, directories to the per-OS TTS defaults, and if those folders are missing the existing "select your Mods and Saves folders" screen appears exactly as in v2.

Either way the mod index is built from scratch on the first start, the same as "Refresh with clear cache" in v2.

Why SQLite. Hive is a log-structured key-value store: the whole box is read into memory when opened, every read is a map lookup, there are no indexes and no queries. SQLite is not faster at "give me the value for this key"; for settings the two are equivalent. The gain is in what v2 spends most of its time doing:

- **Derived lookups.** Shared-asset detection, cleanup, delete-assets scans and "refresh mods that use the files I just downloaded" all need the inverse mapping file -> mods. v2 rebuilds that map from the full URL box every time, inside an isolate, and ships the inputs across the isolate boundary (a copy). With a `file_key` index it is one query, no copy, no rebuild.
- **Startup.** Hive reads and replays the entire box file on open, on the main isolate. With tens of thousands of URL entries that is a measurable blocking stall before the UI can do anything. SQLite opens instantly and reads pages on demand.
- **Change detection.** Storing `mtime + size` per mod turns "has this JSON changed" into a `stat` call; v2 opens and reads the head of every JSON every start because its cache key is a value inside the file.
- **Memory.** Only the rows the UI needs are materialised. v2 holds every URL of every mod in memory for the lifetime of the app and additionally copies the five existing-asset maps into each worker isolate.
- **Integrity and migrations.** Transactions, foreign keys with cascade (delete a mod, its asset rows go), and a numbered schema migration path instead of string-suffixed keys.

Costs, stated plainly: SQLite adds a native library (bundled via Dart native assets, the same mechanism pdfium already requires), drift adds code generation (which freezed and riverpod_generator add anyway), and single-row writes are slower than Hive unless batched, so all bulk writes go through transactions. If any of this proves troublesome in Phase 0 or 1, the fallback is `hive_ce` with a cleaner schema and the same repository interface; the rest of the architecture does not change.

## 4. Target architecture

### 4.1 Layers and folders

```
v3/
  lib/
    main.dart                      bootstrap only (window, pdfium path, ProviderScope, observers)
    app/                           App widget, theme, AppShell, dialogs/menus primitives
    core/                          Result/Failure types, CancellationToken, WorkerPool, logging,
                                   extensions, constants (Steam URLs, TTS folder names)
    domain/
      models/                      freezed: Mod, Asset, AssetType, ModType, Backup, Settings, Directories,
                                   OperationProgress, ...
      rules/                       pure functions: url_extraction, asset_filename, backup_filename,
                                   asset_extension, version_compare, tts_paths
    data/
      db/                          drift database, tables, DAOs, migrations
      fs/                          FileSystem abstraction (package:file), directory scanners,
                                   json metadata reader, zip reader/writer, file ops
      net/                         DioClient, AssetDownloader, UrlChecker, SteamWorkshopClient,
                                   GitHubReleasesClient
      pdf/                         PdfThumbnailRenderer
      legacy/                      HiveSettingsImporter (temporary)
    features/
      startup/                     splash, directory validation/selection, legacy import
      library/                     mods/saves/saved objects: index refresh, list/grid, sort/filter/search,
                                   selection, context menus, rename, delete, save-as-mod
      asset_detail/                selected-mod view, asset list, filters, replace URL, update URLs,
                                   audio visibility, PDF thumbnails, images viewer
      operations/                  OperationRunner + progress model + progress bar + cancellation
      downloads/                   asset downloads, URL checks (use operations)
      workshop/                    download by id, update from Workshop
      backups/                     create, index, status, backups page, import .ttsmod, import JSON
      bulk/                        multi-select + bulk operations (compose operations)
      cleanup/                     orphaned asset scan/delete, delete mod assets (shared analysis)
      settings/                    settings dialog and persistence, theme settings
      logs/                        collapsible log panel, structured log store, file sink
      about/                       help, changelog, update notification
    l10n/                          app_en.arb
  test/                            mirrors lib/
```

Dependency rule: `features/*/presentation` -> `features/*/application` -> `domain` + `data`. `data` and `domain` never import from `features`. No `BuildContext` below presentation. Notifiers never call `showDialog`; they expose state or return values and the widget decides.

### 4.2 Domain model (freezed)

- `ModRef { ModType type; String jsonPath; String id /* basename without .json */ }`
- `Mod { ModRef ref; String saveName; String folder; int? epochTime; DateTime modified; int sizeBytes; String? imagePath; AudioVisibility audio; AssetSummary summary; BackupStatus backupStatus; Backup? backup }`
- `AssetSummary { int total; int present; bool hasAudio; Map<AssetType,int> byType }` (counts only; the full asset list is loaded on selection, not for every mod)
- `Asset { String url; AssetType type; String fileKey; String? path; bool invalid }`
- `Backup { String path; String fileName; String folder; DateTime modified; int sizeBytes; int assetCount; String? matchingModPath }`
- `Settings` (same fields as v2, json_serializable), `Directories` (derived paths via `path.join`)
- `OperationProgress { String label; int done; int total; double? fraction; bool cancelRequested }`

Every timestamp is a `DateTime`; every size is bytes. `copyWith` from freezed handles nullable resets, which removes the 8 copies of the 17-field constructor.

### 4.3 Store schema (drift)

```
mods           (id TEXT PK, type INT, json_path TEXT UNIQUE, folder TEXT, save_name TEXT,
                epoch_time INT NULL, mtime_ms INT, size_bytes INT, image_path TEXT NULL,
                audio_visibility INT, invalid_urls_json TEXT NULL)
mod_assets     (mod_id TEXT REFERENCES mods ON DELETE CASCADE, url TEXT, asset_key TEXT,
                asset_type INT, file_key TEXT,  PRIMARY KEY(mod_id, url))
                INDEX mod_assets_file_key (file_key), INDEX mod_assets_type (asset_type)
existing_files (asset_type INT, file_key TEXT, path TEXT, PRIMARY KEY(asset_type, file_key))
backups        (path TEXT PK, mtime_ms INT, size_bytes INT, asset_count INT)
kv             (key TEXT PK, value TEXT)          settings json, directories, schema version
```

`file_key` is the TTS asset filename (URL stripped of non-alphanumerics), lower-cased, with the old `cloud-3` host already rewritten. With this:

- Mod summary = `mod_assets LEFT JOIN existing_files` grouped by mod. One query, no map copies.
- Shared assets of mod X = `SELECT mod_id FROM mod_assets WHERE file_key IN (...) AND mod_id != X`.
- Cleanup candidates = `existing_files LEFT JOIN mod_assets WHERE mod_assets.file_key IS NULL`.
- "Which mods do I need to refresh after downloading these files" = same index.
- `mods.mtime_ms + size_bytes` vs `stat` decides whether a JSON must be re-read at all.

### 4.4 Library refresh pipeline

1. `DirectoryScanner` (worker) lists `Workshop/`, `Saves/`, optional `Saves/Saved Objects/` recursively, honouring ignored subfolders and the two `*FileInfos.json` exclusions. Returns `(path, mtime, size)` tuples.
2. Diff against `mods`: unchanged rows are skipped entirely. New/changed paths are chunked to the `WorkerPool`, which reads each file once and returns `saveName`, `epochTime`, extracted URL map, sibling image path. Deleted paths are removed (cascade).
3. `existing_files` is rebuilt per asset type from one `Directory.list` each (workers), bulk-inserted in a transaction.
4. Backups: list `.ttsmod` files, reuse `backups` rows whose mtime+size match, count assets for the rest with the central-directory reader (workers).
5. One summary query produces the `List<Mod>` for the UI. Backup status is computed in Dart from `epoch_time`, backup `mtime`, counts (same rules as v2 `getModBackupStatus`).

Expected effect: first run is comparable to v2 (one full read), every later start reads only changed JSONs and does no per-mod file reads. UI shows a determinate progress (files scanned / files parsed) instead of free-text messages.

Phase 1 implementation notes (measured against the reference library, section 10.3):

- Steps 3 and 4 run concurrently with steps 1 and 2: the asset-folder listings and the backups scan are dispatched right after the mod-folder scan and collected after parsing, so on a cold start the whole `existing_files` rebuild is hidden behind the parse phase. Progress is still reported in pipeline order through a gate that publishes each phase's latest snapshot when its turn comes.
- Step 2 reads each JSON as bytes and extracts URLs with a byte scanner that reproduces the regex exactly (same keys, whitespace set and match semantics, including failing the file on malformed UTF-8); only the file head is decoded for `SaveName`/`EpochTime`, the whole file only when they are not there. The 68 MB mod drops from ~650 ms to ~100 ms on its worker.
- Step 2 writes parsed batches to the store while the remaining batches still parse (one write at a time, batches that finish meanwhile are coalesced into the next transaction), and batches are dispatched largest first so the biggest file bounds the phase; the batch byte target is 16 MB so the reference library yields about as many batches as workers.
- Bulk writes use multi-row `INSERT ... VALUES` statements (995/999 bound parameters each); on ~19k asset rows that is ~25 % faster than both drift's per-row batch and a `json_each` expansion of one JSON array, because the cost is SQLite's row and index writes.
- Step 3 syncs `existing_files` as a diff inside SQLite (delete stale keys, insert new, update changed paths) instead of delete-and-reinsert, so an unchanged cache folder costs index lookups only and does not grow the WAL.
- WAL auto-checkpoints are deferred for the duration of a refresh and one passive checkpoint runs after the result is published, keeping the checkpoint's file copy and fsync off the critical path.

### 4.5 Operations engine

A single `OperationRunner` (AsyncNotifier) owns "is anything running" (today's `actionInProgressProvider` plus 6 status enums), the current `OperationProgress`, and one `CancellationToken`. An operation is a plain class:

```dart
abstract class Operation<T> {
  String get label;
  Future<T> run(OperationContext ctx); // ctx.report(progress), ctx.token, ctx.log
}
```

Downloads, URL checks, backup creation, import, cleanup, delete-assets, Workshop update, bulk variants are all `Operation`s. Bulk operations compose per-mod operations with a shared token; they never touch selection. Progress bar = one widget bound to the runner. Cancellation = token checked at every await boundary and forwarded to Dio `CancelToken`s and worker tasks. Results dialogs are shown by the widget that awaited the operation.

Riverpod 3 specifics applied here: `retry` disabled on the root `ProviderScope` (automatic retry would re-run a failed file scan in a loop), `ref.mounted` checks after awaits, `ProviderObserver(ProviderObserverContext)` feeding the in-app log in debug builds, `select` for per-card subscriptions.

### 4.6 UI standardisation

- One `AppTheme` built from `ThemeSettings` (4.7). No literal `Colors.*` or `TextStyle(fontSize:)` in features; spacing via a small `Gaps`/`Insets` constant set. Semantic colours (asset present / missing / invalid, backup up-to-date / out-of-date / mismatch) come from a `VaultColors` `ThemeExtension`, so they follow the scheme and can be themed too.
- Shell: a custom `VaultSidebar` keeps every v2 sidebar item in the sidebar (decided: no move to page toolbars). It is not a Material `NavigationRail`, because rails are destination-only; it is a themed column built from M3 parts (`IconButton`/`FilledTonalButton`, `Tooltip`, `Divider`) so it still follows the colour scheme and typography. No hover behaviour at all: collapsed by default (icons with tooltips), a chevron at the top toggles the labelled wide form, and that choice is persisted. Users with a left-side OS taskbar can mouse across it freely.
  - ~~Section 1 (destinations, highlighted when active): Mods, Backups.~~ Superseded 2026-10-17 (see decisions log): there is one library page; Backups is a tab in the type selector (Mods | Saves | Saved Objects | Backups), shown only when a backups folder is set. The sidebar carries actions only.
  - Section 2: Refresh, Cleanup.
  - Section 3: Import backups, Import JSON, Download Workshop mods.
  - Bottom: Help, Settings.
  - Items disable while an operation runs, as in v2. The log is a collapsible panel docked under the mod/backup list (4.8), not a sidebar item.
  - Actions that are not destinations (Refresh, Cleanup, Import backups, Import JSON, Download Workshop mods) move to the page toolbar: Refresh as a button, the rest under a Tools menu next to Sort/Filter/Bulk. This matches M3 guidance (rails hold destinations) and shortens the rail.
- Dialog primitives: `AppDialog` (title, content, actions, optional blur) and `ConfirmDialog`, `ChoiceDialog<T>`, `ResultsDialog` for the 24 ad-hoc dialogs.
- Context menus: one `AppContextMenu` helper over `MenuAnchor` with typed `MenuAction` items; menus for mod, asset, backup are declared as lists of actions.
- Lists: `GridView.builder`/`ListView.builder` with real item counts, `Image.file(cacheWidth: ...)` for thumbnails, `ResizeImage`, no sync IO in `build`.
- Keyboard: Ctrl/Cmd-click multi-select kept, add Ctrl+F (search), F5 (refresh), Esc (clear selection), Delete (delete mod with confirm).
- Window: keep `window_manager` (min size, title with version, maximise on first launch).

### 4.7 Theming (confirmed: M3 seed palette by default)

`ThemeSettings { ThemeMode mode; int seedColor; DynamicSchemeVariant variant; double contrast; String? presetId }`, persisted in `kv` and exposed by a `themeProvider`. `AppTheme.build(settings, brightness)` does `ColorScheme.fromSeed(seedColor, brightness, dynamicSchemeVariant, contrastLevel)` and derives `ThemeData` plus the `VaultColors` extension from it. Because every widget reads colours from the theme, user theming is a settings UI problem, not a widget problem. Rollout:

- 3.0: Mode (system / light / dark), seed colour picker with a row of presets, and a "Classic" preset that reproduces the v2 near-black look as a seed + variant choice.
- Later, without touching widgets: scheme variant selector (tonal spot, vibrant, monochrome, fidelity), contrast slider, per-semantic-colour overrides in `VaultColors`, import/export of a theme as JSON, and optionally sharing presets.

### 4.8 Log page (new feature)

v2 has a `LogNotifier` and a debug console, but both are commented out; users have no way to see why something failed. v3 makes logging a product feature:

- **Structured entries.** `LogEntry { DateTime time; LogLevel level; LogSource source; String message; String? details; ModRef? mod; String? url; String? operationId }`. Levels: info, success, warning, error. Sources: library, download, urlCheck, workshop, backup, import, cleanup, settings, app.
- **Every failure site logs with context.** A 404 reads "Download failed (404 Not Found): https://... Mod: X, type: Images", not a `debugPrint`. Retries, skips (ignored domain, already present), cancellations and summaries ("Downloaded 42/45 files, 3 failed") are logged too. `OperationContext.log` makes this the path of least resistance inside operations.
- **Log panel**, docked under the mod grid/list (and under the backups list on the Backups page), sharing the bottom slot with the operation progress bar. Collapsed state is a one-line header: expand chevron, "Log", counts of warnings and errors since last expanded (red badge), the last message as a one-line preview, and an "Open log file" icon button. Expanded state is a resizable (drag handle, height persisted) virtualised list: newest at the bottom with follow-tail, filter chips by level and source, text search, click an entry to select its mod, copy entry, copy all visible, clear. State (collapsed/expanded, height, filters) is persisted in settings. An error while the panel is collapsed flashes the header once and increments the badge; it never auto-expands.
- **File access.** The header's "Open log file" button opens `vault.log` in the OS default viewer; its menu also offers "Open log folder" and "Copy log file path". The same entries are in Help under "Troubleshooting". The file lives next to the database (3.1) with size-based rotation (for example 5 MB x 3), so a user can attach it to a bug report in two clicks.
- **Debug extras** (debug builds only): `ProviderObserver` events and `debugPrint` captured into the same store with a `debug` source hidden behind a toggle.
- Memory bound: keep the last 10,000 entries in memory (v2's limit), the file keeps the rest.

## 5. Dependency plan

Versions are the pub.dev latest as of 2026-10-17.

| Package | v2 | v3 | Breaking changes to handle |
| --- | --- | --- | --- |
| Flutter SDK | 3.44.4 (fvm) | 3.47.7 | `flutter/material.dart` -> `material_ui`; run `dart fix --apply --code=migrate_design_widgets` on any template code |
| hooks_riverpod | 2.6.1 | 3.4.3 | StateNotifier/StateProvider legacy; `Ref` has no type param; `FamilyNotifier` gone (arg via constructor); auto retry; out-of-view pausing; `ProviderException` wrapping; observer signature |
| riverpod_annotation / generator / lint | none | 4.0.7 / 4.0.9 / 3.1.9 | new; riverpod_generator 4 needs `build` 4.x, which pins `build_runner` to 2.16.x (2.17 requires `build` 5) |
| drift / drift_dev / sqlite3 (resolved) | | 2.35.2 / 2.35.1 / 3.7.1 | `drift_flutter` skipped: it still depends on the EOL `sqlite3_flutter_libs`; we open `NativeDatabase` directly |
| flutter_hooks | 0.21.2 | 0.21.3+1 | none |
| material_ui | WIP | 1.7.0 | `MaterialUiCompatibilityBridge` for third-party widgets still importing `flutter/material.dart` |
| freezed / freezed_annotation / json_serializable | none | 4.0.2 / 3.1.0 / 6.14.1 | new |
| build_runner | none | 2.17.1 | new |
| drift / drift_dev / sqlite3 | none (hive_ce_flutter 2.3.1) | 2.35.2 / 2.35.1 / 3.7.1 | new; `sqlite3_flutter_libs` is EOL, `sqlite3` 3.x bundles natively via native assets |
| dio | 5.7 | 5.11.1 | none expected |
| http | 1.2 | removed | use dio everywhere |
| file_picker | 10.1 | 13.1.0 | static API; `pickFiles` returns `List<PlatformFile>`; `lockParentWindow` moved to `WindowsOptions`/`LinuxOptions`; `saveFile` needs `fileName` + `bytes` |
| archive | 4.0.5 | 4.5.2 | use streaming `InputFileStream`/`OutputFileStream` APIs for import/backup |
| pdfrx_engine | 0.4.6 | 0.6.1 | Dart >= 3.13; verify `Pdfrx.pdfiumModulePath` still exists for the macOS fix |
| image | 4.5 | 4.12.0 | none expected |
| bson / fixnum | 5.0.7 / 1.1.1 | 5.0.8 / 1.1.1 | none |
| window_manager | 0.5.1 | 0.5.2 | none |
| package_info_plus | 9.0 | 10.2.2 | check changelog |
| url_launcher | 6.3.1 | 6.3.3 | none |
| open_filex | 4.7 | 5.0.0 | check changelog (major) |
| mime | 2.0 | 2.1.0 | none |
| intl | 0.20.2 | 0.20.3 | none |
| path_provider | transitive | 2.1.6 | direct (DB and legacy import location) |
| file | none | latest | `FileSystem` abstraction for tests |
| mocktail | none | 1.0.5 | tests |
| flutter_lints / custom_lint | 6.0.0 / none | 6.0.0 / 0.8.1 | |
| icons_launcher | 3.0.1 | latest | regenerate icons |
| hive_ce_flutter | 2.3.1 | temporary, legacy import only | removed in 3.1 |

Optional later: `desktop_drop` 0.9.1 (drag a `.ttsmod`/`.json` onto the window to import), `Directory.watch` based incremental refresh.

Machine prerequisite that stays: `flutter config --enable-native-assets` on every build machine (pdfium and now sqlite3).

## 6. Phases and milestones

Each phase ends with `flutter analyze` clean, tests green, and a Windows release build that runs against your real TTS library. Linux and macOS builds are checked at the end of phases 1, 3, 5, 6.

### Phase 0: Scaffold (small)

- `flutter create v3 --platforms=windows,macos,linux --org io.github.markomijic --project-name tts_mod_vault`, FVM pin, pubspec with the table above, `build.yaml`, `analysis_options.yaml`, `l10n.yaml`.
- Root `.gitignore`: add `v3/build/`, `v3/.fvm/`. Keep `.dart_tool/` rule (already recursive).
- Carry over platform customisations: Windows `Runner.rc` product strings and icon, Linux header-bar title and `.desktop`/`.metainfo.xml`, macOS bundle id `io.github.markomijic.ttsModVault`, entitlements (sandbox off, network), pdfium module-path fix.
- `core/`: `Result`, `CancellationToken`, `WorkerPool`, `AppLog` (structured store + file sink from day one so every later phase logs properly). `app/`: `ThemeSettings`/`AppTheme`/`VaultColors`, `AppShell` with the toggle-extended rail and empty pages, dialog/menu primitives.
- Build scripts: parametrise `packaging/appimage/build_appimage.sh` and `packaging/macos/build_dmg.sh` with a `PROJECT_DIR` (default `.`, set to `v3` until cut-over).

Milestone: empty shell runs on Windows with M3 theme, native assets bundle (pdfium + sqlite), analyzer clean.

**Status: done 2026-10-17** on branch `v3-rewrite` (uncommitted). `flutter analyze` clean, 120 tests green (core 79, app 31, data 10), Windows release build 37 MB with `pdfium.dll` and `sqlite3.dll` in the bundle; the exe starts, titles itself "TTS Mod Vault 3.0.0", creates `vault.sqlite` and `vault.log` under `%APPDATA%\io.github.markomijic\TTS Mod Vault\`. Visual check of the shell is pending (no interactive desktop in the build session). Notes from the work: riverpod_lint 3.1 is installed through `analysis_options.yaml` (`plugins:`), build_runner is held at 2.16.x by riverpod_generator, `material_ui` needs its own `GlobalMaterialLocalizations.delegates` (handled in `App`), `MaterialUiCompatibilityBridge` is not needed yet. Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/generated/`) are git-ignored; the packaging scripts run codegen and gen-l10n themselves and take `PROJECT_DIR=v3` until cut-over.

### Phase 1: Domain, store, library index (large)

- Port `domain/rules`: URL extraction (incl. Lua-embedded, `{lang}` prefixes, scheme-less domains, `file:/` skip, old-host rewrite), asset type mapping from JSON keys, `fileKey`, backup filename rules, extension-by-MIME, version compare, default TTS directories per OS (incl. Steam snap path). Each with unit tests built from the comments and edge cases in v2.
- drift schema + DAOs + migration framework.
- `data/fs`: directory scanner, JSON metadata reader (streamed head read for SaveName/Nickname/EpochTime/Date, full read for URL extraction), existing-files indexer, `.ttsmod` central-directory reader (port verbatim).
- `features/library`: refresh pipeline (4.4), `Mod` summaries, sort/filter/search providers (same options as v2: A-Z, newest, recently updated, missing assets; folder, backup state, asset status/type, has-audio filters), grid and list views, Mods/Saves/Saved Objects selector, selection (single + Ctrl-click multi).
- `features/startup`: splash, directory detection/validation/selection, "loading x of y" progress.

Milestone: v3 lists your mods/saves/saved objects with correct asset counts and backup status. Measure cold and warm start against v2 on the same library and record the numbers in this document.

**Status: done 2026-10-17** on `v3-rewrite`. 470 tests green, analyzer clean. Delivered: freezed models and enums with stable db values; parsing rules ported verbatim plus a byte-level URL scanner equivalent to the regex (68 MB mod parses in ~100 ms instead of 650); SQLite schema keyed by json path with multi-row inserts, SQL diff sync for `existing_files`, and deferred WAL checkpoints; worker-pool scanners and zip central-directory reader; refresh pipeline with stat-based change detection, largest-first parse batches, concurrent asset/backup indexing and streaming upserts; startup flow with directory selection; Mods page with grid/list, badges, toolbar, context menu (copy, open in explorer, Workshop page live; the rest stubbed for Phases 2-5) and Refresh dialog. Fixes found along the way: escaped quotes in SaveName no longer truncate or corrupt on rename; `.wav`/`.ogg` extension detection corrected; same-basename JSONs in different folders no longer collide. Numbers in section 10.3.

### Phase 2: Selected mod and assets (medium)

- Selected-mod view: grouped asset list with type/status/invalid/search filters, URL font size setting, asset context menu (open file, open URL, copy, open in file explorer, replace URL, delete file, shared-with list), audio visibility override, PDF thumbnails (serialised renderer, same DPI as v2) with URL/thumbnail toggle, images viewer page.
- Mod context menu: download, view images, open in explorer, Workshop page, copy name/filename, rename (SaveName rewrite + optional backup rename), delete, save-as-mod (saves only), backup sub-actions.
- Help tooltip texts and the info tooltip moved to ARB.

Milestone: everything you can do to one mod in v2 without network works in v3.

**Status: done 2026-10-17** (`df23fb3`). Selected-mod panel with filters, audio override, asset context menu, Replace URL, Shared with, Delete file, PDF thumbnails, images viewer, rename/delete/save-as dialogs. v2 bug fixed: escaped quotes in SaveName.

### Phase 3: Operations, downloads, Workshop (medium)

- `OperationRunner`, progress model, single progress bar, cancellation.
- `AssetDownloader` (Dio pool, retry/backoff, trailing-slash fallback, HTML page detection, MIME extension, ignored domains, concurrency setting), download single/type/all; `existing_files` and summaries updated incrementally; mods sharing downloaded files refreshed via the index.
- `UrlChecker` (HEAD then ranged GET, html = dead), per-mod check with invalid-URL persistence.
- `SteamWorkshopClient`: file details, BSON -> JSON with EpochTime, title override, preview image (decode, resize once, encode once), creation-time-preserving write; download by id(s); update check (60 s tolerance) and update; result model with typed statuses instead of string prefixes.
- GitHub release check and update dialog.

Milestone: download/URL-check/Workshop flows at parity, cancel works mid-flight everywhere.

**Status: done 2026-10-18** (`57a05b3`, `f9fe695`). One `OperationRunner`, one progress bar with cancel, streaming downloader tested against a loopback server, typed Workshop statuses, update notice. Deliberate change: URL checks skip audio URLs hidden by the audio setting, matching the asset list.

### Phase 4: Backups, import, deletion, cleanup (medium)

- Create backup: streaming zip in a worker, same entry layout (`Mods/...`, `Saves/...`), progress, "replace / select folder" behaviour, optional set-as-default folder, `forceBackupJsonFilename` setting.
- Backups page: grid/list, sort (name/size/date), filters (folder, has matching mod), search, context menu (import, open, copy name, delete), rename on mod rename.
- Import `.ttsmod`: streaming extraction (no whole-file read), JSON target folder resolution (explicit > single matching mod > stored path), date-conflict dialog (keep current / use backup / cancel), asset index update. Import JSON (+ optional PNG).
- Delete mod, delete mod assets (non-shared / all) with shared-asset report from the index, cleanup of orphaned files (incl. `Images Raw`, `Models Raw`, old-host duplicate detection, `file*` raw exclusions).

Milestone: backups and imports interoperate with v2 and TTS Mod Backup files; memory stays flat while importing a multi-GB `.ttsmod`.

**Status: application layer done 2026-10-18** (`f9fe695`): progress-reporting zip isolates (write to `.part` then rename; streamed extraction with zip-slip guard), backup creation with v2 entry layout, import with target resolution and date-conflict callback, JSON import, delete/rename backup, delete-assets scan with shared details, cleanup incl. raw folders and legacy duplicates. UI wiring in progress. Import now also indexes save/saved-object backups (v2 extracted them without registering the mod).

### Phase 5: Bulk, URL updates, settings, logs, legacy import (medium)

- Multi-select view and bulk operations: download, backup (skip/replace/replace-if-out-of-date, post-backup deletion), download+backup, delete assets, check URLs (results dialog), update URL prefixes (presets, `|`-separated old prefixes, optional file rename), update from Workshop (force option), import many backups. Bulk button shows affected count under current search/filters.
- Settings dialog (Features, Interface, Folders, Network, Update URL presets, Appearance) with the same options plus theme mode, seed colour and presets (4.7); settings persisted in `kv`.
- Log panel (4.8): collapsible/resizable dock under the lists, filters, search, jump-to-mod, copy, clear, error badge, open log file/folder; audit every operation for missing or context-free log lines.
- `HiveSettingsImporter` first-run migration (D4).
- Help and changelog dialogs with content in assets, not Dart strings.

Milestone: full feature parity checklist (section 7) ticked.

### Phase 6: Polish, measurement, cut-over (small to medium)

- Performance pass with DevTools against your library: startup, grid scroll, selection latency, memory during import/backup. Fix regressions, record numbers.
- Accessibility/keyboard pass, light theme pass, window edge cases (min size, HiDPI).
- Build on all three OSes with the parametrised scripts; verify pdfium + sqlite bundling in each artifact; macOS codesign verify.
- Update README (install, build, `--enable-native-assets`), write 3.0.0 changelog (note: cache rebuilt on first start, settings migrated).
- Cut-over commit: delete old root project files, move `v3/` contents to root, drop `PROJECT_DIR` defaults, `graphify update .`, tag `v3.0.0`.

## 7. Feature parity checklist

Taken from the README and the code. Every item must be reachable in v3 before cut-over.

- [ ] Mods / Saves / Saved Objects (setting) tabs with counts tooltip
- [ ] Grid and list views (settings), title-on-cards setting
- [ ] Sort: A-Z, newest, recently updated, missing assets; default sort setting (mods and backups)
- [ ] Filters: folders, backup state, complete/missing, audio/image/model/PDF/asset bundle presence
- [ ] Search mods by name; search assets of selected mod
- [ ] Single and Ctrl/Cmd multi-select
- [ ] Selected mod: grouped assets, type chips, downloaded/missing filter, invalid filter, PDF thumbnails toggle + default setting, images viewer, open files (audio/image/PDF), open in file explorer
- [ ] Asset actions: open URL, copy URL, replace URL (with optional file rename), delete file, shared-with info
- [ ] Per-mod audio visibility override + global ignore-audio setting
- [ ] Download missing assets (single asset, per type, whole mod); concurrency setting; ignored domains
- [ ] Check URLs for a mod, persist invalid URLs; bulk check with results dialog
- [ ] Download Workshop mods by one or many ids; update from Workshop (single, bulk, force)
- [ ] Backup create (folder picker, default folder, set-as-default), replace prompt, progress
- [ ] Backup status: none / up to date / out of date / asset count mismatch, with tooltip times
- [ ] Backups tab: browse, sort, filter, search, import, open, copy filename, delete
- [ ] Import `.ttsmod` (ours and TTS Mod Backup), conflict dialog on older backup JSON; import JSON (+PNG)
- [ ] Rename mod/save/saved object (+ rename backup); Save as Mod; delete mod (+ image + cache)
- [ ] Delete mod assets (non-shared / all) with shared report; bulk delete assets
- [ ] Update URLs (prefix or whole URL, `|` multi old prefixes, presets from settings, rename files) single and bulk
- [ ] Cleanup unused cached files
- [ ] Bulk: download, backup, download+backup, with skip/replace rules and post-backup deletion; cancel for every bulk op
- [ ] Refresh with optional clear cache
- [ ] Settings: folders (mods, saves, backups, custom saves folder), ignored subfolders, ignored domains, force JSON filename in backup names, check updates on start, asset URL font size, concurrent downloads, show saved objects, show backup state
- [ ] Update check against GitHub releases with Nexus/GitHub links; Help; Changelog; Ko-fi/Steam links
- [ ] Collapsible log panel under the mod/backup lists with level/source filters, search, jump to mod, copy, clear, error badge, one-click open of the rotating log file (new in 3.0)
- [ ] Appearance settings: theme mode, seed colour, presets incl. Classic (new in 3.0)
- [ ] Window: min size 854x480, maximise on first show, title with version
- [ ] macOS pdfium module path fix; Linux header bar title; Windows product strings; AppImage and DMG scripts

## 8. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| material_ui is new (1.x) and third-party widgets may still import `flutter/material.dart` | Wrap with `MaterialUiCompatibilityBridge`; keep the dependency list short; the only Material-dependent plugins are window_manager and file_picker (no widgets) |
| URL extraction regressions | Port the regexes verbatim and encode every v2 comment as a test case; run v2 and v3 extraction over your real library and diff the results before Phase 1 ends |
| Riverpod 3 auto-retry re-running failed IO | Disable `retry` globally; errors surface through `AsyncValue.error` as before |
| SQLite adds a native dependency | Same native-assets mechanism already required for pdfium; verify bundling in Phase 0 on all three OSes |
| Two Flutter projects in one repo confuse IDE/analyzer | Open `v3/` as the workspace folder during the rewrite; the root project stays buildable for hotfix releases of 2.x |
| Scope creep from "while we're here" features | New features (drag-drop import, file watching, light theme polish) are listed as optional and scheduled after parity |

## 9. Decisions log

Resolved 2026-10-17:

- D1 `v3/` in-repo: confirmed. All v3 work happens on the `v3-rewrite` branch (created from `main` at `ba4f677` plus the uncommitted `material_ui` swap). `main` stays releasable for 2.x hotfixes; merge `main` into `v3-rewrite` when needed. At cut-over (Phase 6) the branch is merged into `main` in one go.
- D4 one-shot settings import, caches dropped: confirmed. Behaviour with nothing to import documented in 3.1.
- Theme: M3 seed palette by default, user theming planned from the start (4.7). Classic preset keeps the v2 look available.
- Navigation: no hover expansion; collapsed rail with labels, explicit persisted toggle to extend (4.6).
- New feature: collapsible log panel under the mod/backup lists with contextual failure messages and one-click access to the log file (4.8). Not a sidebar item.
- Sidebar: all v2 sidebar items stay in the sidebar; custom `VaultSidebar`, no hover, persisted toggle (4.6).
- Benchmark: the real library at `C:\Users\Marko\Documents\My Games\Tabletop Simulator` plus a generated stress library; protocol and safety rules in section 10.

Resolved 2026-10-17 (evening, after trying the Phase 2 build):

- **One library page, no Mods/Backups destinations.** The type selector becomes Mods | Saves | Saved Objects (setting) | Backups (only when a backups folder is set). The toolbar adapts per tab: backups get their own sort (name/size/date), filters (folder, has matching mod), search and view toggle; the right panel shows backup details and actions. Sidebar = actions only (Refresh, Cleanup | Import backups, Import JSON, Download Workshop mods | Help, Settings). Phase 4's "Backups page" becomes the Backups tab.
- **No splash in the common case.** The library loads in well under a second, so when the folders are valid the shell renders immediately and the refresh runs behind it; a loading indicator appears only if the first refresh is still running after ~400 ms. Directory selection and failure screens stay.

Nothing open.

### Resume notes (keep current)

- 2026-10-18 01:30: committed through `f9fe695` (Phases 0-3 complete, Phase 4 application layer). **In progress, uncommitted:** (a) Phase 4 UI wiring agent (`lib/features/backups/presentation`, `lib/features/cleanup/presentation`, stub call sites in `mod_context_menu.dart`, `selected_mod_actions.dart`, `app_shell.dart`); (b) Phase 5 application agent (`lib/features/bulk`, `lib/features/url_updates`, `lib/features/settings`, `lib/features/logs` application folders, `lib/data/legacy`, one call added to `startup_controller.dart`). On resume: analyze + test those folders, fix or re-dispatch, commit, then dispatch Phase 5 UI (settings dialog with Appearance section, collapsible log panel in `bottomSlot`, bulk actions menu + multi-select view buttons, Update URLs dialog with presets, help/changelog dialogs from `assets/text/`), then Phase 6 polish (parity checklist audit, benchmarks incl. backup/import memory, Linux/macOS builds, README, cut-over).

## 10. Benchmark protocol

### 10.1 Reference library (measured 2026-10-17)

`C:\Users\Marko\Documents\My Games\Tabletop Simulator` on drive C (ADATA SU630 SSD, 113.8 GB free). Drive D (WD SN850X SSD, 147.3 GB free) hosts the repo and the scratch space.

| Folder | Files | Size |
| --- | --- | --- |
| `Mods/Workshop` (recursive, incl. `Queued/`, `Save trading/`) | 99 JSON (33 at top level) | 272 MB |
| `Saves` | 11 JSON | 3 MB |
| `Saves/Saved Objects` | 6 JSON | 1 MB |
| `Mods/Images` | 7,779 | 19.6 GB |
| `Mods/Images Raw` | 3,509 | 7.4 GB |
| `Mods/PDF` | 155 | 4.6 GB |
| `Mods/Models` | 167 | 64 MB |
| `Mods/Models Raw` | 92 | 12 MB |
| `Mods/Audio` | 9 | 97 MB |
| `Mods/Assetbundles` | 41 | 112 MB |
| `Mods` total | | 39.8 GB |

Largest mod JSONs: `3781830124.json` 68 MB, `Queued/2857317092.json` 37 MB, `Save trading/Dice Throne.json` 17 MB. "Large mod" in the measurements below means `3781830124`.

### 10.2 Safety rules (binding for every benchmark and test run)

- The real library is **never** modified or deleted by a benchmark. Nothing under `Documents\My Games\Tabletop Simulator` is a valid target for cleanup, delete, import or a `.ttsmod` extraction during measurement.
- Any measurement that writes into a library runs against a **sandbox copy** under `D:\tmp\ttsmv-bench\` (D has the free space). Copies are made with the asset files a scenario needs, not the whole 40 GB: for example the JSONs of five mods plus their referenced asset files.
- Disk budget: the sandbox plus scratch output stays under 20 GB. Before copying, a dry-run size estimate is printed and compared with free space, and the scratch folder is deleted after each session.
- Backup output goes to `D:\tmp\ttsmv-bench\backups\`, never into the real backups folder.
- Downloads are not benchmarked against live servers (network noise, and it would write into the library). The bulk URL check is benchmarked because it only reads.
- Both apps point at a library through their folder settings only; no symlinks or junctions into the real folders.

### 10.3 Measurements

Each number is the median of 3 runs, v2 (2.1.0 release build) vs v3 (release build), same machine, same library, nothing else heavy running. **Release builds only**: Flutter desktop debug builds (JIT, asset bundling, observatory) have historically differed from release builds by a large factor on cold and warm start, so a debug-build number is never recorded or compared. Profile builds are used only for DevTools memory inspection, and are labelled as such. Results are recorded in a table at the end of this section after Phase 1 and again in Phase 6.

| Metric | Library | Writes? | How |
| --- | --- | --- | --- |
| Cold start | real | cache only | Delete the app's own cache (v2 Hive folder / v3 `vault.sqlite`), launch, stopwatch from process start to mod grid rendered (`Timeline` event + log line) |
| Warm start | real | no | Second launch with nothing changed |
| Start after one change | real (touch a copy) | no | Edit the mtime of one JSON in the sandbox copy of the library; measures incremental path (v3 only has a fast path here) |
| Select large mod | real | no | Time from click on `3781830124` to asset list frame rendered |
| Peak memory, one-mod backup | real -> scratch output | scratch only | Back up `3781830124` to `D:\tmp\ttsmv-bench\backups\`; DevTools memory + Task Manager peak working set |
| Peak memory, full-library backup | real -> scratch output | scratch only | Bulk backup of all 99 mods to scratch; the output is several GB, check free space first; delete afterwards |
| Peak memory, multi-GB import | sandbox | sandbox only | Import the `3781830124.ttsmod` produced above into the sandbox library; v2 is expected to spike by the full archive size, v3 should stay flat |
| Cleanup scan | sandbox | sandbox only | Sandbox seeded with ~500 orphaned placeholder files; time to candidate list, then time to delete |
| Bulk URL check | real | cache only | Check all 99 mods with concurrency 5; time and number of requests; run twice on the same day and only compare runs with equal result counts |

**Results** (median of 3, harness `v3/tool/bench/bench.ps1`, details in `v3/tool/bench/results.md`). v2 = 2.1.0 at commit `ba4f677`, release build with Flutter 3.47.7 (the release used 3.44.4; `pdfrx_engine` bumped 0.4.3 -> 0.4.7 to compile), measured 2026-10-17. Wall = process start to the app's "library loaded" line; in-app = the load duration the app reports itself.

| Metric | v2 wall | v2 in-app | v3 wall | v3 in-app |
| --- | --- | --- | --- | --- |
| Cold start | 2261 ms | 889 ms | 1722 ms | 437 ms |
| Warm start | 1845 ms | 502 ms (v2 pads the load to a 500 ms minimum; real work ~115 ms) | 1354 ms | 95 ms |

v3 measured 2026-10-17 after the Phase 1 optimisations (v3 working tree on `v3-rewrite` after commit `ad127db`, Flutter 3.47.7, same machine and library). In both apps roughly 1.2 s of the wall time passes before `main()` runs (engine and VM start); v3's own bootstrap takes 8 ms and its first library refresh is requested ~70 ms (cold) / ~48 ms (warm) after `main()`. Before the optimisations the same v3 code measured 2446 ms / 1178 ms cold and 1387 ms / 154 ms warm (an earlier 2979 ms figure was a harness artefact: it timed the log file's 500 ms flush instead of the line's timestamp).

### 10.4 Stress library

99 mods is small for the architecture questions in section 4.4. A script (`v3/tool/stress_library.dart`) generates `D:\tmp\ttsmv-bench\stress\` with N copies of the real Workshop JSONs (default N gives ~2,000 mods), each copy with rewritten URLs so asset filenames are unique, and 1 KB placeholder asset files for a configurable fraction of them (so "missing" and "present" paths both exist). File count is what stresses the index, not bytes: 2,000 mods x ~150 assets x 4 KB clusters is roughly 1.2 GB. Cold start, warm start, select large mod and cleanup scan are repeated on this library.
