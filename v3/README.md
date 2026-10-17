# TTS Mod Vault v3

The v3 rewrite of [TTS Mod Vault](https://github.com/markomijic/TTS-Mod-Vault).
It lives in `v3/` next to the 2.x app until it reaches feature parity, then it
replaces the root project (see `docs/v3-rewrite-plan.md`).

## Toolchain

| | |
| --- | --- |
| Flutter | 3.47.7 (pinned in `.fvmrc`; `fvm use` picks it up) |
| Dart | 3.13 (`sdk: ^3.13.0`) |
| UI | `package:material_ui` (import `package:material_ui/material_ui.dart`, never `flutter/material.dart`) |
| State | `hooks_riverpod` 3 + `riverpod_generator` |
| Store | `drift` 2.35 on `sqlite3` 3.x (native assets, no `sqlite3_flutter_libs`) |
| PDF | `pdfrx_engine` (pdfium via native assets) |

### One-time machine setup

```sh
flutter config --enable-native-assets
```

pdfium and sqlite3 are delivered as Dart native assets. Without this flag the
build succeeds but the app crashes at launch with a missing library. The
packaging scripts check the flag and refuse to build without it.

## Working on the code

```sh
fvm flutter pub get                                    # or: flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift / freezed / riverpod codegen
flutter gen-l10n                                       # lib/l10n/generated/ from lib/l10n/app_en.arb
flutter analyze
flutter test                                           # all tests; or e.g. flutter test test/data
flutter run -d windows                                 # or macos / linux
```

Generated code (`*.g.dart`, `*.freezed.dart`, `lib/l10n/generated/`) is not
committed; run the two generation commands after a fresh clone or after
editing an annotated class or the ARB file. `dart run build_runner watch`
regenerates on save while developing. (build_runner 2.17 ignores
`--delete-conflicting-outputs` with a warning; it is kept so the command also
works with older build_runner versions.)

Code generation is also the first thing the release scripts do, so a release
build never depends on stale local output.

Lints: `flutter_lints` plus `always_use_package_imports`, `prefer_single_quotes`,
`require_trailing_commas`, `prefer_final_locals`, `unawaited_futures` and the
Riverpod lints (`analysis_options.yaml`). Imports inside `lib/` are always
`package:tts_mod_vault/...`.

## Where the app keeps its data

The database and the log file live in the platform's application-support
directory (`lib/bootstrap/app_paths.dart`):

| OS | Directory |
| --- | --- |
| Windows | `%APPDATA%\io.github.markomijic\TTS Mod Vault\` |
| macOS | `~/Library/Application Support/io.github.markomijic.ttsModVault/` |
| Linux | `~/.local/share/tts_mod_vault/` |

Files: `vault.sqlite` (drift database, schema in `lib/data/db/app_database.dart`)
and `vault.log` (rotating log). Deleting the folder resets the app; the mod
index is rebuilt on the next start. Settings from TTS Mod Vault 2.x are
imported once from `~/Documents/TTS Mod Vault/` (Phase 5).

## Release builds

From the repo root, with `PROJECT_DIR=v3` until the cut-over:

```sh
PROJECT_DIR=v3 bash packaging/appimage/build_appimage.sh   # Linux AppImage
PROJECT_DIR=v3 bash packaging/macos/build_dmg.sh           # macOS DMG + zip
flutter build windows --release                            # Windows, from v3/
```

Each script runs `pub get`, code generation and `gen-l10n` before the build and
verifies that both native libraries (pdfium, sqlite3) are in the bundle. See the
README next to each script.

## Layout

```
lib/
  main.dart        awaits bootstrap(), runs ProviderScope(retry: disabled) + App
  bootstrap/       window, pdfium module path, database open, data directory
  app/             App widget, theme, shell, dialog/menu primitives
  core/            Result, CancellationToken, WorkerPool, AppLog, KeyValueStore
  data/db/         drift AppDatabase + DriftKeyValueStore
  domain/, data/fs|net|pdf, features/   arrive in Phase 1+
  l10n/            app_en.arb (generated output is git-ignored)
test/              mirrors lib/
```
