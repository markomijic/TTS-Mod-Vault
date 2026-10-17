# Benchmark results

All numbers from `bench.ps1` (see README.md), release builds only, median of 3.

## v2 2.1.0 baseline (2026-10-17)

### Build

- Source: git commit `ba4f677` ("Regenerate macOS files, added packaging script"),
  the 2.1.0 release state, built from a clean detached worktree (no uncommitted
  changes from the working tree).
- Toolchain: Flutter 3.47.7 stable (abaf9c5237), Dart 3.13.5, `enable-native-assets: true`.
  The commit's `.fvmrc` pins **3.44.4**, which is what the published 2.1.0 was
  built with; fvm is not installed on this machine, so the global SDK was used.
- Dependency deviation: `pdfrx_engine` 0.4.3 (locked at `ba4f677`) does not
  compile on Dart 3.13.5 (null-safety errors in `pdf_file_cache.dart`), so it was
  upgraded in the build worktree only to 0.4.7 (`flutter pub upgrade pdfrx_engine`;
  `pdfium_dart` stayed at 0.2.5). `flutter pub get` also moved 5 transitive
  packages within their constraints (characters, matcher, material_color_utilities,
  test_api, vector_math). PDF thumbnail rendering is not on the start-up path.
- Exe: `D:\tmp\ttsmv-bench\v2-release\tts_mod_vault.exe` (16 files, 41,529,661 bytes
  incl. `pdfium.dll`), a copy of `build\windows\x64\runner\Release`.

### Library

Plan section 10.1, measured 2026-10-17: `C:\Users\Marko\Documents\My Games\Tabletop Simulator`
on an ADATA SU630 SATA SSD. 99 Workshop JSONs (33 top level, incl. `Queued/` and
`Save trading/`), 11 Saves, 6 Saved Objects; v2 reports "Processing 102 files".
Assets: Images 7,779 files / 19.6 GB, Images Raw 3,509 / 7.4 GB, PDF 155 / 4.6 GB,
Models 167 / 64 MB, Models Raw 92 / 12 MB, Audio 9 / 97 MB, Assetbundles 41 / 112 MB;
`Mods` total 39.8 GB. Largest mod `3781830124.json` 68 MB.

v2 settings in effect (from the captured `initializeSettings` line):
`checkForUpdatesOnStart: false`, `ignoreAudioAssets: true`, `showPdfThumbnails: true`,
`showSavedObjects: false`, `ignoredSubfolders: []`, `ignoredDomains: []`.
Backups folder had 41 existing backups (cold run: "0 cache hits, 41 cache misses").

### Conditions

Windows 11 Pro 10.0.26300, nothing of the user's closed. CPU load before each
launch (1 s sample): cold 10.9 / 9.3 / 12.1 % (the previous run had been killed
2 s earlier), warm 3.0 / 0.0 / 2.3 %. Each run: fresh process, killed with
`Stop-Process` after detection.

### Cold start (cache `modurls*`, `modmetadata*`, `backupcache*` deleted before each run)

| Run | Wall (process start to `loadModsData END`) | In-app (`loadModsData total time`) |
| --- | --- | --- |
| 1 | 2261 ms | 883 ms |
| 2 | 2249 ms | 889 ms |
| 3 | 2279 ms | 929 ms |
| **median** | **2261 ms** | **889 ms** |

Within the in-app time: `loadExistingAssetsLists` ~56 ms, `getInitialMods`
(102 files, 13 chunks, 14 isolates) ~15 ms, asset processing in 6 isolates
~780 ms, "Applying 102 storage updates" ~17 ms.

### Warm start (nothing changed between runs)

| Run | Wall | In-app |
| --- | --- | --- |
| 1 | 1848 ms | 502 ms |
| 2 | 1843 ms | 502 ms |
| 3 | 1845 ms | 502 ms |
| **median** | **1845 ms** | **502 ms** (floor, see note) |

Note: v2 pads `loadModsData` to a minimum of 500 ms (`mods.dart`, "Artificial
delay to ensure at least 500ms of visual refresh indicator"). In the warm runs
all isolates completed ~115 ms after START, so the real warm load is roughly
115 ms and the remaining ~390 ms is the artificial wait. Wall time contains it too.

### Other observations

- The release exe prints `debugPrint` output to stdout when launched with
  redirected stdout; stderr only has the Impeller banner
  (`Using the Impeller rendering backend (OpenGLESSDF)`).
- Wall minus in-app is a constant ~1.35 s: engine start, `windowManager`
  init, Hive init, `pdfrxInitialize`, the splash's 100 ms maximize workaround,
  storage/settings init. This part is independent of the cache state.
- No update check or dialog happened (`checkForUpdatesOnStart` is off). If it
  were on, the GitHub request is awaited before `loadModsData` (`splash_page.dart`)
  and a newer release would show a blocking dialog. GitHub latest release on the
  day: `v2.1.0`, so no dialog would appear even with the setting on.
- Rebuilt cache after a cold run: `modurls.hive` 2,295,945 bytes vs 3,908,528 in
  the user's live file (Hive append-log growth), `appdata.hive` compacted from
  6,291 to 825 bytes on open. The live folder was restored from the pre-session
  backup byte for byte (8 files, SHA256 verified).
- No errors in any run.

## v3 Phase 1 (2026-10-17)

### Build and conditions

- Source: the `v3-rewrite` working tree after commit `ad127db` ("v3 Phase 1:
  domain, store, parsing, scanners, library pipeline, startup") with the
  Phase 1 optimisations below (uncommitted at measurement time).
- Toolchain: Flutter 3.47.7 stable, Dart 3.13.5, `flutter build windows
  --release`; exe `build\windows\x64\runner\Release\tts_mod_vault.exe`
  (`app.so` 7.3 MB, bundle otherwise equivalent to v2's).
- Same machine (AMD Ryzen 7 5700X3D, 16 threads -> 14 worker isolates) and the
  same library as the v2 baseline (section 10.1: 99 Workshop JSONs / 272 MB,
  7,779 images, 155 PDFs; 102 mods indexed, 18,839 `mod_assets` rows, 8,151
  `existing_files` rows). No backups folder configured, so the backups phase
  is empty in every run. CPU load before each launch 0-5 %.
- Cold = `vault.sqlite` deleted before each run (the `-wal`/`-shm` sidecars of
  the previous run are left; SQLite discards a WAL whose salt does not match
  the new file). Warm = nothing changed.

### Harness correction

The first v3 numbers taken with `bench.ps1` (2979 ms cold) were an artefact:
the v3 log line starts with `[timestamp]`, which the old timestamp regex did
not match, so the harness fell back to the moment it *saw* the line, i.e.
after the file sink's 500 ms flush timer, and it did not read `durationMs=`.
Both are fixed; every number below uses the line's own timestamp.

### Where the time goes

`bootstrap()` (bindings, window manager, pdfium, paths, database handle,
package info, window show) takes 6-9 ms in total; the first frame is rendered
~25 ms after `main()` and the first library refresh is requested ~70 ms (cold,
includes creating the database) / ~48 ms (warm) after `main()`. Wall minus
in-app minus those offsets leaves ~1.2 s before `main()` runs: Flutter engine
and Dart VM start, identical runner to v2. The same ~1.2 s is inside v2's
1.35 s fixed overhead, so the start-up outside the refresh was never the gap.

Instrumented baseline (before any optimisation), medians of 3:

| | Wall | In-app | Phases (cold run 1) |
| --- | --- | --- | --- |
| Cold | 2446 ms | 1178 ms | scan 7, parse 656, upsert 406, indexFiles 70, summary 27 |
| Warm | 1387 ms | 154 ms | scan 8, indexFiles 92-121, summary 28 |

Attribution with the probes (`tool/bench/parse_probe.dart`, AOT, and
`tool/bench/db_probe.dart`, JIT):

- The parse phase was bounded by the 68 MB `3781830124.json` on one worker:
  `readAsBytes` 26 ms, `utf8.decode` 170 ms, regex URL extraction 445 ms,
  `readFull` 616-651 ms.
- Writing 18.8k `mod_assets` rows cost ~235 ms in SQLite alone (in-memory 120
  ms, with no indexes at all 165 ms: row volume, ~4.7 MB of text per refresh)
  and every commit past 4 MB of WAL ran an auto-checkpoint (~90 ms of file
  copy and fsync inside the measured window).
- `existing_files` was deleted and re-inserted on every refresh (8k rows,
  90-120 ms warm, 10 MB of WAL per run).
- The summary query is ~20 ms of which the `mod_assets x existing_files` join
  is ~9.4 ms; a per-(mod, type) aggregate joined in Dart was no faster
  (21 ms), so it was left alone.

### Optimisations and their effect

Builds were measured after groups of changes (a release build and six runs
per group); per-item effects come from the probes where noted.

| Step | Change | Cold wall / in-app | Warm wall / in-app |
| --- | --- | --- | --- |
| 0 | Instrumented baseline (harness fixed) | 2446 / 1178 | 1387 / 154 |
| 1 | Byte-scanner URL extraction + header from a decoded prefix (`readFull` on the 68 MB mod 650 -> 102 ms, probe); asset index and backups scan concurrent with scan+parse; per-batch upserts; batch target 16 MB, largest batch first; `existing_files` synced as a diff in SQL; asset rows via `json_each` | 2082 / 746 | 1386 / 127 |
| 2 | WAL auto-checkpoint deferred during the refresh, one passive checkpoint afterwards; parse batches finishing during a write are coalesced into the next transaction (3-4 transactions instead of ~13; `upsertWorkMs` 613 -> 420) | 1904 / 544 | 1415 / 121 |
| 3 | Multi-row `INSERT ... VALUES` (995/999 parameters per statement) instead of `json_each` for `mod_assets` and `existing_files` (probe: 234 -> 179 ms for 18.8k rows; `upsertWorkMs` 420 -> 314, warm `indexFilesMs` 76 -> 55) | **1722 / 437** | **1354 / 95** |

Step 1 is a group because the byte scanner, the pipeline reordering and the
store changes were built together; the probe numbers isolate the scanner.

### Final cold start (step 3 build)

| Run | Wall | In-app | Phases |
| --- | --- | --- | --- |
| 1 | 1832 ms | 437 ms | scan 11, parse 209, upsert 186 (work 312), indexFiles 0, summary 29 |
| 2 | 1722 ms | 437 ms | scan 8, parse 215, upsert 185 (work 315), indexFiles 0, summary 27 |
| 3 | 1722 ms | 443 ms | scan 9, parse 213, upsert 193 (work 314), indexFiles 0, summary 27 |
| **median** | **1722 ms** | **437 ms** | bootstrap 8, first frame 25, refresh requested 71 (since `main()`) |

`upsertMs` is the part of the store write still exposed after the last parse
batch returns; `indexFiles 0` means the asset-folder listing and
`existing_files` sync finished entirely under the parse phase.

### Final warm start (step 3 build)

| Run | Wall | In-app | Phases |
| --- | --- | --- | --- |
| 1 | 1354 ms | 95 ms | scan 10, indexFiles 55, summary 28 |
| 2 | 1346 ms | 93 ms | scan 9, indexFiles 54, summary 28 |
| 3 | 1355 ms | 96 ms | scan 9, indexFiles 56, summary 29 |
| **median** | **1354 ms** | **95 ms** | bootstrap 8, first frame 25, refresh requested 48 (since `main()`) |

### Against v2

| | v2 wall | v2 in-app | v3 wall | v3 in-app |
| --- | --- | --- | --- | --- |
| Cold | 2261 ms | 889 ms | 1722 ms (-24 %) | 437 ms |
| Warm | 1845 ms (incl. 500 ms pad) | 502 ms (~115 ms real) | 1354 ms | 95 ms |

### Tried and dropped

- `json_each` bulk inserts: as fast as drift's per-row batch, slower than
  multi-row `VALUES` (SQLite's JSON parsing of ~5 MB costs more than binding).
- Inserting `mod_assets` sorted by primary key: no gain (238 vs 236 ms).
- Dropping the `mod_assets_type` / `mod_assets_file_key` indexes: 236 -> 192
  ms in the probe, i.e. the indexes are not the main cost; schema left as is.
- `PRAGMA synchronous = OFF`: 236 -> 180 ms, rejected (durability of the kv
  table shares the file).
- Alternative summary query shapes: no gain (see above).

### Not implemented

- Fingerprinting the asset folders by directory mtime + entry count to skip
  the listing and the `existing_files` sync when nothing changed (warm
  `indexFilesMs` 55 -> ~0; ~4 % of warm wall).
- Computing `file_key` and de-duplicating URLs on the parse workers instead
  of the UI isolate (a few tens of ms of the exposed upsert tail).
- Dropping the low-cardinality `mod_assets_type` index (~2 % of cold wall).
- The ~1.2 s before `main()` is the Flutter Windows engine start and is the
  same for v2; nothing in the Dart code affects it.
