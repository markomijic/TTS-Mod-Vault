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

## v3

Pending (Phase 1 adds the `Library refresh finished` log line, then run the
`-App v3` branch of `bench.ps1`).
