# Start-up benchmark harness

`bench.ps1` measures cold and warm start of a **release build** of TTS Mod Vault
(v2 or v3) on the real library, as defined in `docs/v3-rewrite-plan.md`
section 10. It is Windows PowerShell 5.1 compatible.

## Usage

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

## What is measured

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

Watches `%APPDATA%\io.github.markomijic\TTS Mod Vault\vault.log` for a line
appended after launch that contains `Library refresh finished`. Wall = the
line's leading `yyyy-MM-dd HH:mm:ss.SSS` timestamp minus process start; in-app
= the first `<n>ms` / `<n> ms` / `duration=<n>` / `elapsed=<n>` / `took <n>` token on
that line (reported as n/a when absent). A `Library refresh failed` line marks
the run as failed. Cold mode deletes `vault.sqlite` only (a warning is printed if
`-wal`/`-shm` sidecars exist). v3 does not emit the line yet; the branch is in
place so Phase 1 only has to add the log line.

## Safety rules (short form of plan section 10.2, binding)

- The real library under `Documents\My Games\Tabletop Simulator` is never
  modified. This script only reads it (through the app) and refuses an `-Exe`
  path inside it. Nothing in it is ever a cleanup/delete/import target.
- The script deletes nothing except the app's own cache files listed above, and
  only in `cold` mode.
- Before a session, copy the app's cache folder somewhere under
  `D:\tmp\ttsmv-bench\` and restore it byte for byte afterwards (verify sizes
  and hashes), because cold runs rebuild the cache and v2 also compacts
  `appdata.hive` on open.
- Any benchmark that writes into a library uses a sandbox copy under
  `D:\tmp\ttsmv-bench\`, backup output goes to `D:\tmp\ttsmv-bench\backups\`,
  sandbox plus scratch stays under 20 GB, and the scratch is deleted after each
  session. No symlinks or junctions into the real folders.
- Release builds only; a debug-build number is never recorded.

## Recording results

Raw numbers, medians, the exact build (commit, Flutter version, dependency
deviations), date and machine notes go into `results.md` in this folder. The
medians are then copied into the results table at the end of
`docs/v3-rewrite-plan.md` section 10.3. Use `-Csv` to keep the raw rows.
