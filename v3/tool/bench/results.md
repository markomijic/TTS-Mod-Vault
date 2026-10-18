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

## v3 Phase 6 (2026-10-18)

Operation benchmarks of plan section 10.3 and the stress library of 10.4.
Source: `v3-rewrite` at commit `5f6a81e`, Flutter 3.47.7 / Dart 3.13.5. GUI
numbers come from the release exe `build\windows\x64\runner\Release\tts_mod_vault.exe`
through `bench.ps1`; every `op_bench` number is a **JIT number** (headless
`flutter_tester`, see README "JIT, not release") and is never put next to the
release start-up rows. For `op_bench` the comparable figure is the RSS
**delta** over the baseline (the baseline of ~200-215 MB is the flutter_tester
engine plus the loaded library); `maxRss at end` is the OS peak of the whole
process including the setup refresh. No v2 counterpart exists for these rows
(v2 has no headless path and the v2 GUI rows were not measured), so Phase 6
records v3 only. Same machine as Phase 1 (Ryzen 7 5700X3D, 14 worker
isolates), nothing else heavy running, CPU 0-6 % before each GUI launch.

### Safety record

Plan 10.2 was followed: the real library under `Documents\My Games\Tabletop
Simulator` was only read (sandbox copy, stress templates, the stopped URL
check); nothing was written, deleted, imported or cleaned there. The 2.x data
folder was not touched. All output went under `D:\tmp\ttsmv-bench\`; the
combined footprint peaked at ~17.4 GB (during the sandbox `backup-all`, free
space on D dropped from 146.5 GB to 129.1 GB) and is 9.41 GB after the session
(`sandbox` 7.92 GB and `stress` 1.44 GB kept, everything else deleted; free
space on D 136.7 GB). Verification at the end of the session:

- real library: 20,446 files / 38.91 GB, every path, size and mtime identical
  to the inventory taken before the session;
- `Documents\TTS Mod Vault` (2.x): unchanged, SHA256 identical;
- v3 data folder `%APPDATA%\io.github.markomijic\TTS Mod Vault` (`vault.sqlite`
  16,605,184 bytes, `vault.log` 59,845 bytes): copied to
  `D:\tmp\ttsmv-bench\v3-data-backup\` before the stress GUI runs, restored
  byte for byte afterwards, SHA256 of both files identical to the pre-session
  snapshot (`1D7EAD84...DDD8D6` / `BC4FD097...E880`).

### Sandbox (`make_sandbox.ps1`)

`3781830124` (the plan's "large mod") has 1,576 referenced assets but only
**4** of them are cached in the real library (0.01 GB), so a sandbox picked by
JSON size alone (the five largest JSONs) would have carried 1.0 GB of assets
and the "multi-GB import" row would have been meaningless. A read-only survey
of cached bytes per Workshop mod (`list_assets.dart` per JSON, matched against
the asset folders) chose the mods instead:

| Mod | JSON | Assets cached / referenced | Cached size |
| --- | --- | --- | --- |
| `3781830124` Lord of the Rings LCG [Scripted] | 64.9 MB | 4 / 1,576 | 0.01 GB |
| `3775466398` Lands of Evershade | 3.5 MB | 677 / 677 | 2.95 GB |
| `3720241537` Zombicide - White Death (`Queued/`) | 4.4 MB | 638 / 645 | 2.41 GB |
| `3756707253` Cozy Stickerville (`Queued/`) | 1.2 MB | 397 / 415 | 1.27 GB |
| `2912738329` Marvel Zombies - A Zombicide Game (`Queued/`) | 2.8 MB | 300 / 618 | 1.23 GB |

Dry run then copy: 2,016 files, 7.92 GB (8,501,641,801 bytes; Images 1,931,
Models 41, PDF 27, Assetbundles 6, Audio 1; 1,939 referenced assets are not
cached in the source and so are "missing" in the sandbox too), plus 500 x 1 KB
`orphan<i>.png` in `Mods\Images`. `3775466398` doubles as the multi-GB case
for the backup and import rows.

### Peak memory, one-mod backup (`op_bench backup-one`, JIT)

| Mod | Run | Elapsed | Archive | RSS baseline | peak | delta |
| --- | --- | --- | --- | --- | --- | --- |
| `3781830124` (68 MB JSON, 4 assets) | 1 | 903 ms | 14,768,500 B | 312.0 MB (first run, compile) | 328.3 MB | 16.3 MB |
| | 2 | 863 ms | same | 214.5 MB | 233.2 MB | 18.7 MB |
| | 3 | 886 ms | same | 215.2 MB | 232.8 MB | 17.6 MB |
| | **median** | **886 ms** | **14.8 MB** | | | **17.6 MB** |
| `3775466398` (677 assets) | 1 | 71,497 ms | 3,028,124,043 B | 214.8 MB | 285.9 MB | 71.1 MB |
| | 2 | 62,979 ms | same | 215.0 MB | 271.5 MB | 56.5 MB |
| | 3 | 63,620 ms | same | 215.3 MB | 267.7 MB | 52.4 MB |
| | **median** | **63,620 ms** | **3.03 GB** | | | **56.5 MB** |

The 68 MB JSON compresses to 14.8 MB; the 3.03 GB archive is written at ~48
MB/s (deflate-bound) with a peak delta of 1.9 % of its size.

### Peak memory, full-library backup (`op_bench backup-all`, JIT)

Run on the **sandbox**, not the real library: the real `Mods` folder is 39.8
GB, so a full archive set would not fit the 20 GB budget (plan 10.2), and
`op_bench` has no mod-count limit for `backup-all`. 5 mods, replace
behaviour, output `D:\tmp\ttsmv-bench\backups-all\` (deleted after the runs).

| Run | Elapsed | Archives | RSS baseline | peak | delta |
| --- | --- | --- | --- | --- | --- |
| 1 | 170,417 ms | 5 / 8,208,598,650 B | 216.7 MB | 292.7 MB | 76.0 MB |
| 2 | 167,575 ms | same | 215.7 MB | 295.6 MB | 79.9 MB |
| 3 | 167,145 ms | same | 214.8 MB | 295.2 MB | 80.4 MB |
| **median** | **167,575 ms** | **8.21 GB** | | | **79.9 MB** |

Archive sizes: Lands of Evershade 3,028,124,043; Zombicide - White Death
2,560,534,848; Cozy Stickerville 1,334,598,486; Marvel Zombies 1,270,572,773;
Lord of the Rings 14,768,500 bytes. 0 skipped, 0 failed.

### Peak memory, multi-GB import (`op_bench import`, JIT)

Into `D:\tmp\ttsmv-bench\sandbox-import\`, an empty TTS-shaped folder that was
wiped and recreated before every run (fresh data folder too), so every run is
a first import with nothing to skip.

| Archive | Run | Elapsed | Extracted | RSS baseline | peak | delta |
| --- | --- | --- | --- | --- | --- | --- |
| `3775466398` 3.03 GB | 1 | 6,362 ms | 677 assets + JSON | 205.3 MB | 261.9 MB | 56.6 MB |
| | 2 | 6,460 ms | same | 205.3 MB | 254.7 MB | 49.4 MB |
| | 3 | 6,679 ms | same | 205.3 MB | 256.5 MB | 51.3 MB |
| | **median** | **6,460 ms** | | | | **51.3 MB (1.7 % of the archive)** |
| `3781830124` 14.8 MB | 1 | 869 ms | 4 assets + 68 MB JSON | 205.6 MB | 481.3 MB | 275.8 MB |
| | 2 | 854 ms | same | 205.5 MB | 468.3 MB | 262.8 MB |
| | 3 | 823 ms | same | 205.4 MB | 468.3 MB | 262.9 MB |
| | **median** | **854 ms** | | | | **262.9 MB** |

The import memory is flat with respect to the archive: 3.03 GB of assets are
streamed through in 6.5 s with a 51 MB peak delta (470 MB/s, stored entries).
The 14.8 MB archive shows the opposite ratio (17.8x its size) because the cost
is the 68 MB mod JSON being decoded and parsed after extraction (the string
alone is ~136 MB in Dart), not the archive; the same JSON costs the refresh the
same amount on every cold start. This is a per-mod-JSON cost, bounded by the
largest JSON in the library, not by the archive size.

### Cleanup (`op_bench cleanup`, JIT, sandbox with 500 seeded orphans)

| Run | Scan | Candidates | Delete | Deleted | RSS delta |
| --- | --- | --- | --- | --- | --- |
| dry-run 1 | 427 ms | 500 / 512,000 B | - | - | 6.1 MB |
| dry-run 2 | 430 ms | 500 | - | - | 2.8 MB |
| dry-run 3 | 430 ms | 500 | - | - | 6.0 MB |
| delete 1 | 426 ms | 500 | 375 ms | 500 / 512,000 B | 12.5 MB |
| delete 2 (re-seeded) | 430 ms | 500 | 345 ms | 500 | 12.6 MB |
| delete 3 (re-seeded) | 434 ms | 500 | 372 ms | 500 | 13.7 MB |
| **median** | **430 ms** | | **372 ms** | | |

Exactly the 500 seeded files were flagged each time (nothing else in the
2,016-file sandbox), 0 failed, 0 warnings. The orphans were re-seeded between
the delete runs with the same 1 KB files `make_sandbox.ps1` writes.

### Bulk URL check (`op_bench check-urls`, concurrency 5, JIT)

Real library (read-only, `D:\tmp\ttsmv-bench\data-real`): 101 mods, started
10:06:22, **stopped after 26 min 20 s** at 75 / 101 mods and 12,865 URLs
checked (~8 URLs/s; the mods are checked one after another with 5 workers
inside each, and the slow part is non-Steam hosts such as Dropbox links that
run into the 15 s connect timeout). The full ~18.9k URLs would have taken ~39
min, over the ~20 min cap, so the scenario was repeated on the sandbox as the
brief allows; only the four `flutter_tester`/`dart` processes of that job were
stopped.

| Library | Run | Elapsed | Mods | URLs checked / total | Unreachable | RSS delta |
| --- | --- | --- | --- | --- | --- | --- |
| real (stopped) | 1 | >26 min 20 s | 75 / 101 | 12,865 / ~18.9k | partial | - |
| sandbox | 1 | 167,606 ms | 5 / 5 | 3,912 / 3,912 | 14 | 38.1 MB |
| sandbox | 2 | 62,225 ms | 5 / 5 | 3,912 / 3,912 | 14 | 37.0 MB |

Both sandbox runs have equal result counts (3,912 checked, 14 unreachable), so
they are comparable in the plan's sense, and they differ by 2.7x purely on the
network side (second-pass CDN/DNS/TLS warmth; run 2 overlapped for ~1 min with
the first, aborted, stress refresh attempt, which cannot explain 105 s). The
elapsed time of this row is a network number; the counts are the stable part.
v2 baseline: not available.

### Stress library (plan 10.4)

`dart run tool\stress_library.dart --source "<real>\Mods" --out D:\tmp\ttsmv-bench\stress --mods 1000 --present-fraction 0.6 --max-template-mb 10`:
97 templates (the 4 JSONs over 10 MB skipped so the copies stay small; the
estimate before writing was 97 x 1.36 MB avg x 1000 = 1.33 GB of JSON), 1,000
mods, 153,636 rewritten URLs (62 not rewritable, shared), 92,178 placeholder
files, 1,547,003,964 bytes written in 119 s. 10x the mods and 8x the asset rows
of the real library (153.6k vs 18.9k `mod_assets`).

#### Headless refresh (`op_bench refresh`, JIT)

| | Run | Elapsed | In-app `durationMs` | Phases | RSS baseline / peak / delta |
| --- | --- | --- | --- | --- | --- |
| cold (`-Cold`) | 1 | 5,551 ms | 5,183 ms | scan 226, parse 1056, upsert 3211 (work 4074, 3 transactions), summary 550 | 199.0 / 507.1 / 308.1 MB |
| | 2 | 5,645 ms | 5,242 ms | scan 219, parse 1093, upsert 3255 (work 4140), summary 538 | 199.2 / 531.4 / 332.2 MB |
| | 3 | 5,558 ms | 5,188 ms | scan 217, parse 1072, upsert 3217 (work 4085), summary 541 | 197.0 / 514.6 / 317.6 MB |
| | **median** | **5,558 ms** | **5,188 ms** | | **delta 317.6 MB** |
| warm | 1 | 1,461 ms | 1,404 ms | scan 217, diff 36, indexFiles 494, summary 555 | 198.8 / 307.7 / 108.8 MB |
| | 2 | 1,448 ms | 1,391 ms | scan 220, diff 30, indexFiles 478, summary 560 | 197.1 / 307.9 / 110.8 MB |
| | 3 | 1,445 ms | 1,387 ms | scan 220, diff 29, indexFiles 478, summary 557 | 198.8 / 308.6 / 109.8 MB |
| | **median** | **1,448 ms** | **1,391 ms** | | **delta 109.8 MB** |

An earlier cold run that overlapped with the sandbox URL check measured 5,896
ms / 5,496 ms; its warm partner failed before starting because two concurrent
`flutter test` runs fight over `build\native_assets\windows\sqlite3.dll`
(op_bench runs must not overlap). The series above was taken afterwards with
nothing else running.

#### GUI start-up, release build (`bench.ps1 -App v3`)

The GUI was pointed at the stress library by editing the `directories` row of
the `kv` table in a copy of the user's `vault.sqlite` (`modsDir`/`savesDir` ->
`D:\tmp\ttsmv-bench\stress\Mods|Saves`, `backupsDir` -> an empty folder) with
Python's sqlite3. Because the directories live in `vault.sqlite`, the harness'
cold mode (delete `vault.sqlite`) would have fallen back to the default
folders, i.e. the real library. Cold runs were therefore made with a **seed
database** installed before each run: that copy with the `mods`, `mod_assets`,
`existing_files` and `backups` tables emptied and `VACUUM`ed (kv rows kept,
schema present), launched through `bench.ps1 -Mode warm -Runs 1` which deletes
nothing. The difference to a true "no file" cold start is the schema creation
(`dbOpenMs=0` in every bootstrap line, so negligible). Warm runs used the
database the last cold run left behind. The user's data folder was restored
and hash-verified afterwards (see the safety record).

| Mode | Run | Wall | In-app | Phases (ms) | bootstrap / first frame / refresh requested (since `main()`) |
| --- | --- | --- | --- | --- | --- |
| cold | 1 | 5,826 ms | 4,472 ms | scan 79, diff 10, parse 928, upsert 2930 (work 3751), summary 524 | 22 / 40 / 50 |
| | 2 | 5,667 ms | 4,404 ms | scan 75, parse 903, upsert 2900 (work 3702), summary 524 | 9 / 25 / 32 |
| | 3 | 5,805 ms | 4,533 ms | scan 77, diff 19, parse 1042, upsert 2831 (work 3769), summary 539 | 9 / 25 / 31 |
| | **median** | **5,805 ms** | **4,472 ms** | | 9 / 25 / 32 |
| warm | 1 | 2,548 ms | 1,166 ms | scan 75, diff 22, indexFiles 511, summary 557 | 9 / 25 / 137 |
| | 2 | 2,554 ms | 1,170 ms | scan 73, diff 9, indexFiles 522, summary 564 | 9 / 25 / 140 |
| | 3 | 2,562 ms | 1,177 ms | scan 76, diff 24, indexFiles 516, summary 559 | 10 / 25 / 142 |
| | **median** | **2,554 ms** | **1,170 ms** | | 9 / 25 / 140 |
| after one change | 1 | 2,549 ms | 1,150 ms | scan 77, parse 24, upsert 16, indexFiles 498, summary 529 | 9 / 25 / 154 |
| | 2 | 2,516 ms | 1,139 ms | scan 77, parse 3, upsert 1, indexFiles 513, summary 528 | 9 / 25 / 136 |
| | 3 | 2,562 ms | 1,184 ms | scan 78, parse 7, upsert 6, indexFiles 502, summary 562 | 9 / 27 / 141 |
| | **median** | **2,549 ms** | **1,150 ms** | | |

"After one change" = the mtime of one stress JSON (`9000000000..2.json`, a
different one per run) set to now before the launch: only that mod is
re-parsed and upserted (3-24 ms), the rest is the warm path. Release-build
observations against the JIT refresh: parse 903-1042 vs ~1070 ms (the parse
workers are mostly I/O and regex, little JIT gain), upsert 2831-2930 vs ~3217
ms, summary ~524-564 ms in both. The warm start on 1,000 mods is dominated by
`indexFilesMs` (~515 ms for 92k placeholder files in the asset folders) and
`summaryMs` (~560 ms for the 153.6k-row join), and the ~1.3 s before `main()`
is unchanged from the real library. `refresh requested` moves from ~48 ms
(real library) to ~140 ms on the stress library; the first frame is unchanged
at 25 ms.

#### GUI memory during a stress cold start (release build)

One extra cold start (same seed database) sampled every 100 ms from process
start until 5 s after `Library refresh finished` (in-app 4,466 ms: parse 1039,
upsert 2769, summary 524): working set min 72.5 MB, max sampled 405.4 MB,
average 212.2 MB; private bytes max 954.0 MB; OS `PeakWorkingSet64` for the
process lifetime **453.2 MB**; peak paged memory 1,028 MB. The private-bytes
spike is the 14 parse isolates' heaps while 1,000 JSON texts (1.47 GB) are
decoded; the working set settles around 200 MB after the refresh.

### Deviations from the plan and the brief

- The sandbox mods were chosen by cached asset bytes, not JSON size (see
  above); `3781830124` is in it as required but is not a multi-GB case.
- `backup-all` ran on the sandbox (5 mods, 8.21 GB), not the real library,
  for the budget reason given above.
- The real-library URL check was stopped at 26 min 20 s and the row recorded
  from the sandbox (3,912 URLs); the partial real-library progress is given.
- The stress GUI cold starts used a seeded database instead of
  `bench.ps1 -Mode cold`; the "start after one change" row was measured on
  the stress library (the plan's "touch a copy").
- "Select large mod" (click to asset list frame) was not measured in Phase 6;
  it needs an interactive GUI measurement.
- One `op_bench` pair was lost to the concurrent-`flutter test` conflict noted
  above and re-run.
- Not from this session: ten `flutter_tester.exe` processes from test runs on
  2026-10-17 (19:30-19:40) were still alive on the machine and were left
  alone.

Raw rows: `D:\tmp\ttsmv-bench\*.json` (one per `op_bench` run),
`stress-gui-runs.csv`, `stress-gui-onechange.csv`.
