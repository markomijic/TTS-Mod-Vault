# Benchmark tooling

The tools behind `docs/v3-rewrite-plan.md` section 10. Everything here is
Windows PowerShell 5.1 compatible or plain Dart; nothing needs the app to be
built except `bench.ps1 -Mode cold|warm`, which measures a release exe.

| Tool | What it does | Writes |
| --- | --- | --- |
| `bench.ps1 -Mode cold\|warm` | Cold / warm start of a **release build** on the real library | the app's own cache only |
| `bench.ps1 -Mode memory` | Samples the working set of a running `tts_mod_vault` process while you drive a GUI operation by hand | nothing |
| `op_bench.ps1` / `op_bench.dart` | Headless operation benchmark: refresh, backup-one, backup-all, import, cleanup, check-urls with wall time and peak RSS | the given data folder, backups folder, sandbox library |
| `make_sandbox.ps1` | Copies a few mods and their cached assets out of the real library into a sandbox | the sandbox folder only |
| `../stress_library.dart` | Generates a 2,000-mod library from the real Workshop JSONs (plan 10.4) | the output folder only |
| `list_assets.dart` | Prints the asset file keys of a mod JSON (used by `make_sandbox.ps1`) | nothing |
| `parse_probe.dart`, `db_probe.dart` | Diagnostic probes for the parse and database costs of the refresh | scratch files only |

Tests: `flutter test test/tool` covers the stress generator and every
non-network `op_bench` scenario on a tiny generated library.

## Safety rules (short form of plan section 10.2, binding)

- The real library under `Documents\My Games\Tabletop Simulator` is never
  modified. `bench.ps1` only reads it (through the app) and refuses an `-Exe`
  path inside it; `op_bench` refuses `import` and a non-dry-run `cleanup`
  against a library inside `Documents` and refuses a data or backups folder
  there; `stress_library.dart` and `make_sandbox.ps1` refuse an output folder
  inside `Documents` or inside their source. Nothing in the real library is
  ever a cleanup / delete / import target.
- Any benchmark that writes into a library uses a sandbox copy under
  `D:\tmp\ttsmv-bench\` (`make_sandbox.ps1`); backup output goes to
  `D:\tmp\ttsmv-bench\backups\`; sandbox plus scratch stays under 20 GB
  (`make_sandbox.ps1` prints the estimate first and aborts past `-MaxGB` or
  when the drive would drop below `-MinFreeGB`); the scratch is deleted after
  each session. No symlinks or junctions into the real folders.
- `bench.ps1 -Mode cold` deletes nothing except the app's own cache files
  listed below. Before a session, copy the app's cache folder somewhere under
  `D:\tmp\ttsmv-bench\` and restore it byte for byte afterwards (verify sizes
  and hashes), because cold runs rebuild the cache and v2 also compacts
  `appdata.hive` on open.
- Release builds only for the start-up numbers; a debug-build number is never
  recorded. `op_bench` numbers are JIT numbers (see below) and are recorded as
  such.
- The bulk URL check is the one network scenario; it only reads.

## Start-up harness (`bench.ps1 -Mode cold|warm`)

Measures cold and warm start of a release build of TTS Mod Vault (v2 or v3)
on the real library.

```powershell
# v2 (2.1.0 release build kept at D:\tmp\ttsmv-bench\v2-release\)
.\bench.ps1 -Exe D:\tmp\ttsmv-bench\v2-release\tts_mod_vault.exe -Mode cold -Runs 3 -App v2
.\bench.ps1 -Exe D:\tmp\ttsmv-bench\v2-release\tts_mod_vault.exe -Mode warm -Runs 3 -App v2

# v3 (build first: cd v3; flutter build windows --release)
.\bench.ps1 -Exe ..\..\build\windows\x64\runner\Release\tts_mod_vault.exe -Mode cold -Runs 3 -App v3
.\bench.ps1 -Exe ..\..\build\windows\x64\runner\Release\tts_mod_vault.exe -Mode warm -Runs 3 -App v3
```

| Parameter | Meaning |
| --- | --- |
| `-Exe` | Full path to the release exe. Debug/Profile build paths are refused. |
| `-Mode cold\|warm` | `cold` deletes the app's own cache before every run, `warm` changes nothing. |
| `-Runs` | Number of runs, default 3. Run cold first so warm has a cache to use. |
| `-App v2\|v3` | Selects the detection method and the cache location (below). |
| `-TimeoutSec` | Per-run timeout, default 600. |
| `-Csv <path>` | Appends one row per run (header written if the file is new). |
| `-KeepLogs` | Keeps the per-run stdout/stderr captures in `%TEMP%\ttsmv-bench\`. |

The app is launched with stdout/stderr redirected, killed with `Stop-Process`
after each run, and the script waits 2 s before the next run. CPU load
(`\Processor(_Total)\% Processor Time`, 1 s sample) is printed before every
launch so an unusually busy machine shows up in the record.

### What is measured

Two numbers per run:

- **wall**: OS process start time (`Process.StartTime`) to the "library loaded"
  event below. Includes engine start-up, window creation, settings load and the
  library load. This is the number section 10.3 calls "cold start"/"warm start".
- **in-app**: the duration the app itself reports for its library load only.

Both are in milliseconds; the summary prints every run and the median
(middle value for odd N, mean of the two middle values for even N).

### v2 detection

The 2.1.0 release exe prints its `debugPrint` lines to stdout when stdout is
redirected (verified on Windows). The script waits for

```
loadModsData END: 2026-10-17 15:50:19.548912
loadModsData total time: 0:00:00.882850
```

in `lib/src/state/mods/mods.dart`. Wall = END timestamp minus process start;
in-app = the `total time` Duration. Caveats:

- v2 pads `loadModsData` to a **minimum of 500 ms** ("artificial delay to ensure
  at least 500ms of visual refresh indicator"), so an in-app value of ~500 ms
  means "faster than 500 ms", not 500 ms of work.
- If `checkForUpdatesOnStart` is enabled in the user's settings, v2 awaits a
  GitHub request **before** `loadModsData`, which adds network latency to wall
  (and a blocking dialog if a newer release exists). The user's live settings
  have it disabled (visible in the captured `initializeSettings` line).

Cache: `%USERPROFILE%\Documents\TTS Mod Vault\`. Cold mode deletes only
`modurls*`, `modmetadata*` and `backupcache*` (Hive box + lock). `appdata*`
(settings, folder paths) is never touched.

### v3 detection

Watches `%APPDATA%\io.github.markomijic\TTS Mod Vault\vault.log` for lines
appended after launch. Lines have the shape
`[yyyy-MM-dd HH:mm:ss.SSS] [LEVEL] [source] message key=value ...`.

- **wall** = the `Library refresh finished` line's leading timestamp minus
  process start (the file sink flushes on a 500 ms timer, so the timestamp,
  not the moment the harness sees the line, is what counts).
- **in-app** = that line's `durationMs=<n>` token (fallbacks: `<n> ms`,
  `duration=`/`elapsed=`/`took`).
- Also printed per run and as medians: `Bootstrap finished: ... totalMs=`
  (the `bootstrap()` duration with its per-step splits), `First frame
  rendered: sinceMainMs=` and `Refreshing library: sinceMainMs=` (both
  measured from `main()` entry), and the refresh's per-phase `<phase>Ms=`
  splits from the finished line.

A `Library refresh failed` line marks the run as failed. Cold mode deletes
`vault.sqlite` only (a warning is printed if `-wal`/`-shm` sidecars exist).

## GUI memory sampling (`bench.ps1 -Mode memory`)

For the plan 10.3 "peak memory" rows measured in the GUI (Task Manager peak
working set), this mode samples a running app instead of eyeballing Task
Manager:

```powershell
# start the app, select the mod, then:
.\bench.ps1 -Mode memory -Seconds 60              # start the backup in the app now
.\bench.ps1 -Mode memory -Pid 12345 -Seconds 0    # until the process exits (Ctrl-C to stop)
.\bench.ps1 -Mode memory -Seconds 60 -IntervalMs 100 -Csv D:\tmp\ttsmv-bench\memory.csv
```

Samples `WorkingSet64` and `PrivateMemorySize64` of the `tts_mod_vault`
process (or `-Pid`) every `-IntervalMs` (default 250) for `-Seconds` (default
30, `0` = until exit) and prints min / max / avg of both plus the OS-tracked
`PeakWorkingSet64` of the whole process lifetime. It launches, kills and
deletes nothing; `-Exe` and `-App` are not needed. Start sampling first, then
trigger the operation in the app, so the baseline is in the samples too. With
one `tts_mod_vault` running `-Pid` can be omitted; use a profile build for
DevTools inspection and label the number as such (plan 10.3).

## Headless operation benchmark (`op_bench`)

`tool/bench/op_bench.dart` bootstraps the application layer in a
`ProviderContainer` without any widget: `appDatabaseProvider` ->
`AppDatabase.open(<data>/vault.sqlite)`, `keyValueStoreProvider` ->
`DriftKeyValueStore`, `appLogProvider` -> `AppLog` with a store and the
rotating file sink into `<data>/vault.log`, `directoriesProvider` -> a
controller answering the given library folders, `legacyImporterProvider` ->
null, the real worker pool, file system and `Dio`. It then runs one scenario
through the same operations and services the UI calls and reports wall time
and peak RSS.

### Host: `flutter test`, not `dart run`

The provider layer imports `hooks_riverpod`, and through it Flutter
(`material_ui`, `flutter_localizations` for the refresh phase labels), so the
stand-alone Dart VM cannot compile the file: `dart run` stops with
`Error: Dart library 'dart:ui' is not available on this platform`. The headless
Flutter test engine (`flutter_tester`) has `dart:ui`, opens no window and
needs no `WidgetsFlutterBinding`: a plain `ProviderContainer` with
`Notifier`/`AsyncNotifier`/`Provider` providers works in it unchanged, the
worker isolates spawn, drift's background isolate runs, and `dart:io`
networking is real because no `TestWidgetsFlutterBinding` (which installs the
HTTP-blocking `HttpOverrides`) is ever created. `op_bench.dart` therefore
wraps its work in one `test(..., timeout: Timeout.none)` when
`FLUTTER_TEST=true` and takes its options from `--dart-define=OPB_<NAME>` or
the environment variable `OPB_<NAME>` (its `main` must take no arguments; the
test runner refuses a `main(List<String>)`).

`op_bench.ps1` does the plumbing:

```powershell
.\op_bench.ps1 -Library <TTS dir> -Data <data dir> -Scenario <name>
    [-Backups <dir>] [-Ttsmod <path>] [-Mod <id>] [-Concurrency 5] [-Workers n]
    [-Cold] [-DryRun] [-Json] [-Out <file.json>]
```

which is the same as

```powershell
cd v3
flutter test tool/bench/op_bench.dart --reporter expanded `
    --dart-define=OPB_LIBRARY=<TTS dir> --dart-define=OPB_DATA=<data dir> `
    --dart-define=OPB_SCENARIO=<name> [--dart-define=OPB_BACKUPS=<dir>] ...
```

| Option | Meaning |
| --- | --- |
| `-Library` / `OPB_LIBRARY` | The TTS folder (contains `Mods\` and `Saves\`): a sandbox, the stress library, or for the read-only scenarios the real one (a warning is printed). |
| `-Data` / `OPB_DATA` | Folder for `vault.sqlite` and `vault.log`; never the app's own `%APPDATA%` folder, never inside `Documents`. |
| `-Scenario` / `OPB_SCENARIO` | `refresh`, `backup-one`, `backup-all`, `import`, `cleanup`, `check-urls`. |
| `-Backups` / `OPB_BACKUPS` | Backups folder (required by the backup scenarios; indexed by the refresh when given). |
| `-Ttsmod` / `OPB_TTSMOD` | Archive to import. |
| `-Mod` / `OPB_MOD` | Mod id for `backup-one` (default: the mod with the most assets). |
| `-Concurrency` / `OPB_CONCURRENCY` | URL-check workers (default 5, the app default); persisted in the data folder's kv store. |
| `-Workers` / `OPB_WORKERS` | Worker pool size (default: processors - 2). |
| `-Cold` / `OPB_COLD=1` | Delete `vault.sqlite` (+ `-wal`/`-shm`) before the run. |
| `-DryRun` / `OPB_DRY_RUN=1` | `cleanup` only scans. |
| `-Json` / `OPB_JSON=1` | Also print the result as one JSON line. |
| `-Out` / `OPB_OUT` | Write that JSON to a file as well. |

Every scenario except `refresh` first loads the library (a refresh, reported
as `setup refresh`, warm when the data folder already has a database) and
then runs the operation under measurement:

| Scenario | Runs | Details reported |
| --- | --- | --- |
| `refresh` | `LibraryController.refresh()`; `-Cold` deletes the database first, a second run without it is the warm case | `durationMs` and every `<phase>Ms=` split of the `Library refresh finished` line, counts |
| `backup-one` | `CreateBackupOperation` for `-Mod` into `-Backups` through the `OperationRunner` | mod, assets present / total, archive path and size |
| `backup-all` | `BulkBackupOperation(behavior: replace)` over every mod into `-Backups` | backed up, skipped, failed, total archive bytes |
| `import` | `ImportBackupOperation` of `-Ttsmod`, answering `useBackup` on a date conflict | assets extracted, failed, JSON path |
| `cleanup` | `CleanupService.scanOrphans()` then `deleteCandidates()` (`-DryRun`: scan only) | `scanMs`, `deleteMs`, candidates, bytes, deleted |
| `check-urls` | `BulkCheckUrlsOperation` over every mod, real network | mods / URLs checked, unreachable URLs, concurrency |

Memory: `ProcessInfo.currentRss` is sampled every 50 ms on a timer while the
operation runs; the result carries the baseline before the start, the peak
and the delta, plus `ProcessInfo.maxRss` at the end (the OS peak of the whole
process, setup refresh included). The baseline includes the flutter_tester
engine (~200-250 MB on this machine); the **delta** and its shape (flat vs.
proportional to the archive size) are the numbers to compare, as plan 10.3
asks for the import row.

### JIT, not release

`flutter test` runs the Dart code on the JIT, exactly like `dart run` would;
the tool prints a banner saying so. Absolute `op_bench` timings are not
release numbers and are never put next to the release-build start-up numbers.
What they are good for: the memory shape, relative timings between
scenarios, and scaling (sandbox vs. stress library). For a release-mode
measurement of the same operations use the GUI with `bench.ps1 -Mode memory`.

`--aot`: an AOT build of `op_bench` is not possible, since `dart compile exe`
cannot compile Flutter imports either (the same `dart:ui` error). For the
pure-Dart probes it was tried on this Dart (3.13.5):
`dart compile exe tool/bench/db_probe.dart -o <scratch>\db_probe.exe` compiles
("Running build hooks..." runs the sqlite3 build hook) but the exe fails at
start with `Couldn't resolve native function 'sqlite3_initialize' ... No
available native assets` - the native asset is not bundled into the exe. So
`db_probe` stays on `dart run` as well; `parse_probe.dart` (no native assets)
compiles and runs as an exe. `stress_library.dart` and `list_assets.dart` are
pure Dart and compile too, though `dart run` is fast enough for both.

## Sandbox builder (`make_sandbox.ps1`)

Builds the sandbox library the writing scenarios run against: only the
listed mods, their sibling PNGs and the cached asset files they reference,
not the whole 40 GB.

```powershell
.\make_sandbox.ps1 -Source "$env:USERPROFILE\Documents\My Games\Tabletop Simulator" `
    -Mods 3781830124,2857317092,<id3>,<id4>,<id5> `
    -Out D:\tmp\ttsmv-bench\sandbox -SeedOrphans 500 [-MaxGB 15] [-MinFreeGB 20] [-DryRun]
```

1. Finds each `<id>.json` under `Mods\Workshop` (recursively; the first match
   wins with a warning when there are several) plus `<id>.png` and
   `Thumbnails\<id>.png` next to it.
2. Runs `dart run tool/bench/list_assets.dart --json <path> ...` which prints
   one `<asset folder><TAB><file key>` line per referenced asset
   (`fileKeyFromUrl`: host normalised, non-alphanumerics stripped,
   lower-cased).
3. Lists each `Mods\<folder>\` once and matches files by case-insensitive
   basename without extension, mapping the legacy
   `httpcloud3steamusercontentcom` prefix to `httpssteamusercontentaakamaihdnet`
   the way the app's index does; every file sharing a key (`x.png` and
   `x.jpg`) is taken.
4. Prints the file count, total size, per-folder counts, how many referenced
   assets are not cached in the source and the free space on the target
   drive before and after; aborts when the total exceeds `-MaxGB` or the
   free space would drop below `-MinFreeGB`. `-DryRun` stops here.
5. Creates `Mods\Workshop`, the five asset folders, the two raw folders and
   `Saves\Saved Objects` under `-Out`, copies the files (mtimes preserved) and
   writes `-SeedOrphans` 1 KB `orphan<i>.png` files into `Mods\Images` for the
   cleanup scenario.

It never deletes, moves or writes anything in `-Source`; `-Out` may not lie
inside `-Source` or inside `Documents`. Point the app's folder settings or
`op_bench -Library` at `-Out`.

## Stress library (`tool/stress_library.dart`, plan 10.4)

```powershell
cd v3
dart run tool/stress_library.dart --source "$env:USERPROFILE\Documents\My Games\Tabletop Simulator\Mods" `
    --out D:\tmp\ttsmv-bench\stress --mods 2000 --present-fraction 0.6 [--seed 1] [--max-template-mb 0]
```

Reads the Workshop JSONs under `--source\Workshop` (recursively, skipping
`WorkshopFileInfos.json` / `SaveFileInfos.json`) as templates and writes
`--mods` copies round-robin as `Mods\Workshop\9000000000.json`,
`9000000001.json`, ... Every asset URL `extractAssetUrlsTyped` finds is
rewritten in the text with a per-copy query parameter (`?c17` / `&c17`), so
each copy has its own file keys; scheme-less values and values with literal
`\r\n` inside stay as they are and are counted as `urlsNotRewritten` (they are
then shared between copies, like real shared assets). For exactly
`round(urls * fraction)` of each copy's URLs (chosen with `--seed`) a 1 KB
placeholder is written to `Mods\<asset folder>\<fileNameFromUrl><ext>` with
the type's default extension (`.png`, `.mp3`, `.obj`, `.PDF`, `.unity3d`), so
the "present" and "missing" paths both exist. `Saves\` and
`Saves\Saved Objects\` are created empty, as are the raw folders. The summary
prints templates, mods, URLs, placeholder files, bytes written and the
elapsed time; progress every 100 mods.

Size: the JSON copies are the bulk (2,000 copies of the reference library's
~2.7 MB average is ~5.5 GB; the 68 MB template alone contributes ~1.4 GB).
`--max-template-mb 20` skips the giants when the budget is tight; the
estimate is printed before writing. The output folder may not be inside
`Documents` or the source. The generator is pure Dart (`dart run`, or
`dart compile exe` for a faster run).

## Plan 10.3 scenarios, step by step

All paths under `D:\tmp\ttsmv-bench\`; delete the folder after the session.
Run every measurement three times and record the median in `results.md`.

```powershell
cd D:\Dev\TTS-Mod-Vault\v3\tool\bench
$tts = "$env:USERPROFILE\Documents\My Games\Tabletop Simulator"
$b = 'D:\tmp\ttsmv-bench'

# 0. sandbox: the large mod plus four others, 500 orphans for the cleanup row
.\make_sandbox.ps1 -Source $tts -Mods 3781830124,<id2>,<id3>,<id4>,<id5> -Out $b\sandbox -SeedOrphans 500 -DryRun
.\make_sandbox.ps1 -Source $tts -Mods 3781830124,<id2>,<id3>,<id4>,<id5> -Out $b\sandbox -SeedOrphans 500

# 1. peak memory, one-mod backup (the archive is what step 3 imports)
.\op_bench.ps1 -Library $b\sandbox -Data $b\data -Scenario backup-one -Mod 3781830124 -Backups $b\backups -Json -Out $b\backup-one.json

# 2. peak memory, full-library backup (sandbox: 5 mods; real library: read-only, allowed, output several GB)
.\op_bench.ps1 -Library $b\sandbox -Data $b\data -Scenario backup-all -Backups $b\backups -Json -Out $b\backup-all.json
.\op_bench.ps1 -Library $tts      -Data $b\data-real -Scenario backup-all -Backups $b\backups-real -Json -Out $b\backup-all-real.json

# 3. peak memory, multi-GB import: the archive from step 1 back into the sandbox
.\op_bench.ps1 -Library $b\sandbox -Data $b\data -Scenario import -Ttsmod "$b\backups\<name> (3781830124).ttsmod" -Json -Out $b\import.json

# 4. cleanup scan, then delete (the 500 seeded orphans)
.\op_bench.ps1 -Library $b\sandbox -Data $b\data -Scenario cleanup -DryRun -Json -Out $b\cleanup-scan.json
.\op_bench.ps1 -Library $b\sandbox -Data $b\data -Scenario cleanup -Json -Out $b\cleanup.json

# 5. bulk URL check, concurrency 5 (read-only; the real library is allowed; run twice the same day,
#    compare only runs with equal result counts)
.\op_bench.ps1 -Library $tts -Data $b\data-real -Scenario check-urls -Concurrency 5 -Json -Out $b\check-urls.json

# 6. stress library: cold and warm refresh (plan 10.4), then the GUI start-up rows with bench.ps1
cd ..\..
dart run tool\stress_library.dart --source "$tts\Mods" --out $b\stress --mods 2000 --present-fraction 0.6
cd tool\bench
.\op_bench.ps1 -Library $b\stress -Data $b\data-stress -Scenario refresh -Cold
.\op_bench.ps1 -Library $b\stress -Data $b\data-stress -Scenario refresh
.\op_bench.ps1 -Library $b\stress -Data $b\data-stress -Scenario cleanup -DryRun

# GUI counterpart of 1-3 in a release build: start the app on the sandbox, then
.\bench.ps1 -Mode memory -Seconds 120    # and trigger the operation in the app
```

The same GUI operation in v2 is measured with `bench.ps1 -Mode memory` as
well (v2 has no headless path); point v2 at the sandbox through its folder
settings only.

## Diagnostic probes

Two stand-alone programs attribute the start-up cost to its parts; they only
read the paths they are given.

- `parse_probe.dart` times the pieces of `JsonModReader.readFull` on one mod
  JSON (read bytes, UTF-8 decode, regex extraction, byte-scanner extraction,
  full `readFull`). Compile it to measure AOT numbers:
  `dart compile exe tool/bench/parse_probe.dart -o <scratch>\parse_probe.exe`
  then `parse_probe.exe "<library>\Mods\Workshop\3781830124.json" 3`.
- `db_probe.dart` times the pipeline's bulk writes (`upsertMods`,
  `replaceAll`), the summary query shapes and several insert variants
  (sync off, sorted, fewer indexes, WAL auto-checkpoint off, in-memory) on a
  file database on drift's background isolate with synthetic data shaped like
  the reference library. It needs the `sqlite3` native asset, which
  `dart compile exe` does not bundle (see above), so run it with the JIT:
  `dart run tool/bench/db_probe.dart <scratch dir> 3` (numbers are relative,
  not release numbers).

## Recording results

Raw numbers, medians, the exact build (commit, Flutter version, dependency
deviations), date and machine notes go into `results.md` in this folder. The
medians are then copied into the results table at the end of
`docs/v3-rewrite-plan.md` section 10.3. Use `-Csv` (`bench.ps1`) and `-Out`
(`op_bench.ps1`) to keep the raw rows; label every `op_bench` number as JIT.
