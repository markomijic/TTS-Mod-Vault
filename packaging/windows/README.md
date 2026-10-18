# Windows packaging — zip

This directory builds the Windows release of TTS Mod Vault as a plain `.zip`
of the Flutter release folder, the format hosted on GitHub Releases and Nexus
Mods since 1.0 (e.g. `Windows.TTS.Mod.Vault.2.1.0.zip`). The user extracts it
anywhere and runs `tts_mod_vault.exe`; updating means extracting the new zip
over (or next to) the old folder. There is no installer and no auto-update.

## Build

Run on **Windows** (Flutter cannot build Windows targets on Linux/macOS), from
any directory, in Windows PowerShell 5.1 or newer:

```powershell
powershell -ExecutionPolicy Bypass -File packaging\windows\build_zip.ps1                  # builds the project at the repo root
```

Add `-Clean` to run `flutter clean` first.

The script runs, in order: the native-assets check, `flutter pub get`,
`dart run build_runner build` (drift / freezed / riverpod code generation;
generated `*.g.dart` files are not committed), `flutter gen-l10n`,
`flutter build windows --release`, then checks that the runner, the engine,
`data\` and both native assets (`pdfium.dll`, `sqlite3.dll`) are in the
release folder before zipping. It uses `fvm flutter` when FVM is installed
(`.fvmrc` pins the Flutter version), otherwise plain `flutter`. Every missing
piece ends the script with a non-zero exit code.

Output (in `build\`):

| File | Use |
| --- | --- |
| `Windows.TTS.Mod.Vault.<version>.zip` | **Upload this to GitHub Releases and Nexus Mods.** Contents of the release folder at the top level, forward-slash entry names. |
| `build\windows\x64\runner\Release\` | The raw release folder, if you need it. |

The version is read automatically from `pubspec.yaml` (`3.0.0+1` becomes `3.0.0`).

Test it: extract the zip to a folder outside the repo and run
`tts_mod_vault.exe` from there. A build that crashes on launch with a missing
DLL means the native-assets flag was off (the script should have caught this).

### Prerequisites

- Flutter with Windows desktop enabled (`flutter doctor` clean for Windows),
  which means Visual Studio 2022 with the "Desktop development with C++"
  workload. Windows Developer Mode is **not** needed for a release build.
- Dart native assets enabled, once per machine: `flutter config --enable-native-assets`.
  pdfium (`pdfrx_engine`) and sqlite3 (`sqlite3` 3.x, used by drift) are both
  shipped this way. The script refuses to build when the flag is off, because
  the resulting app would start and immediately crash with a missing library.
- [FVM](https://fvm.app/) is optional; with it, `.fvmrc` decides the Flutter version.
- Nothing else: the zip is written with .NET's `System.IO.Compression`, which
  is part of Windows.

## Why not `Compress-Archive`

Under Windows PowerShell 5.1 both `Compress-Archive` and
`ZipFile.CreateFromDirectory` write nested entry names with backslashes
(`data\icudtl.dat`), which 7-Zip and Windows Explorer accept but some unzip
tools on other platforms keep as literal file names. The script therefore adds
each file itself with a forward-slash name through `ZipArchive`, which also has
no 2 GB limit. It then reopens the finished zip and checks that
`tts_mod_vault.exe`, `pdfium.dll` and `sqlite3.dll` are top-level entries, that
the entry count matches the file count, and that no entry contains a backslash.

## Files involved

| File | Role |
| --- | --- |
| `packaging/windows/build_zip.ps1` | Runs codegen + build, verifies the bundle, writes the zip |
| `windows/runner/Runner.rc` | Product strings (`CompanyName` `io.github.markomijic`, `ProductName` `TTS Mod Vault`); these also name the app-data folder `%APPDATA%\io.github.markomijic\TTS Mod Vault\` |
| `windows/CMakeLists.txt` | `BINARY_NAME` `tts_mod_vault` (the exe name the script checks for) |
| `windows/runner/resources/app_icon.ico` | App icon |

