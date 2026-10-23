# v3 cut-over checklist: from `v3/` on `v3-rewrite` to the released 3.0.0 on `main`

> **Status 2026-10-23:** (a) and (b1)-(b5) are done on `v3-rewrite` (commit `c3aa352`; the root project is now v3). (b6) merge/tag/push and (c)/(d) are ON HOLD by the user's decision; do not merge into `main` until told. `main` since gained `051741c` (2.x download validation), merged into `v3-rewrite` as `6629c9e`; its port is tracked in `docs/v3-download-validation-port.md`.

Ordered steps with a verification after each. Commands are for Git Bash from
the repo root unless marked PowerShell. Nothing here is automated: releases
are manual, there is no CI, and the app only notifies about updates.

Facts the steps rely on (checked 2026-10-18 at `3ef5788`):

- `v3/pubspec.yaml` is `3.0.0+1`; root `pubspec.yaml` is `2.1.0+1`.
- The update check reads `tag_name` of the latest GitHub release and strips a
  leading `v`, so the tag is `v3.0.0` like every tag before it (`v2.1.0`, ...).
- `CLAUDE.md`, `.claude/`, `graphify-out/` and `*.iml` are git-ignored: they are
  not tracked and are not touched by any `git rm` below.
- The packaging scripts already default `PROJECT_DIR` to `.`; only their
  comments and READMEs still mention `PROJECT_DIR=v3`.
- The AppStream metainfo has no `<releases>` list, so nothing to bump there.

## (a) Pre-flight (on `v3-rewrite`, before touching the tree)

1. **Clean tree, latest `main` merged in.** `main` may have 2.x hotfixes.
   ```sh
   git switch v3-rewrite
   git status --porcelain            # must print nothing
   git merge main                    # resolve conflicts if any; usually "Already up to date"
   ```
2. **Version and texts final.**
   - `grep '^version:' v3/pubspec.yaml` prints `version: 3.0.0+1`.
   - `v3/assets/text/changelog.md` starts with `# v3.0.0` and the section is final
     (it is shown in the in-app Changelog tab and copied into the release notes).
   - `v3/assets/text/help.md` matches the shipped UI (Troubleshooting names the log panel and `vault.log`).
   - `v3/windows/runner/Runner.rc` copyright year is current.
3. **Tests and analysis.** From `v3/`:
   ```sh
   cd v3
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   flutter gen-l10n
   flutter analyze                   # "No issues found!"
   flutter test                      # all green (1015+ tests)
   cd ..
   ```
4. **Release builds on all three OSes with `PROJECT_DIR=v3`.** Each script
   checks the native-assets flag and that pdfium + sqlite3 are in the bundle.
   ```powershell
   # Windows (PowerShell)
   powershell -ExecutionPolicy Bypass -File packaging\windows\build_zip.ps1 -PROJECT_DIR v3
   # -> v3\build\Windows.TTS.Mod.Vault.3.0.0.zip
   ```
   ```sh
   # Linux (Ubuntu VM; for a public build use the ubuntu:22.04 container, see packaging/appimage/README.md)
   PROJECT_DIR=v3 bash packaging/appimage/build_appimage.sh
   # -> v3/build/TTS_Mod_Vault-x86_64.AppImage
   # macOS (Apple Silicon)
   PROJECT_DIR=v3 bash packaging/macos/build_dmg.sh
   # -> v3/build/TTSModVault.dmg, v3/build/macOS.TTS.Mod.Vault.3.0.0.zip
   ```
5. **Smoke on each OS** with a real TTS library, from the extracted/mounted artefact, not from `flutter run`:
   - First start: library appears, "Imported settings from TTS Mod Vault 2.x" in the log when a 2.x folder exists; folders and URL presets carried over; `Documents/TTS Mod Vault/` still intact afterwards (`ls`).
   - Second start: warm start, no re-parse (log shows only changed files parsed).
   - Select the largest mod; open a PDF thumbnail; open an image in the images viewer (pdfium works).
   - Create a backup to a scratch folder, import it into a sandbox copy (`D:\tmp\ttsmv-bench\`, never the real library).
   - Download one missing asset; check URLs for one mod; cancel a bulk URL check mid-flight.
   - Log panel: expand, filter, "Open log file" opens `vault.log`.
   - Settings: switch theme mode and preset; Reset to defaults; Save.
   - Window title reads "TTS Mod Vault 3.0.0".
   - macOS only: copy the app to `/Applications`, add the quarantine attribute, confirm `xattr -dr` lets it launch (packaging/macos/README.md "Verifying a release").
6. **Benchmark table complete.** `docs/v3-rewrite-plan.md` section 10.3 has every
   row of the 10.3 metric table filled (cold/warm start are there; backup/import
   memory, cleanup scan, bulk URL check and the stress library were still open at
   `3ef5788`), with `v3/tool/bench/results.md` holding the raw numbers.
7. **Docs ready for the swap.** `docs/README-v3.md` (future root README),
   `docs/v3-release-notes-3.0.0.md`, `packaging/windows/` exist on the branch.
   Screenshots: replace the 2.x images in `docs/README-v3.md` (the TODO comment
   marks them) with 3.0 screenshots, or accept the old ones for now.
8. **Commit** anything from steps 2 and 7: `git add -A && git commit -m "v3: pre-cut-over docs"`.

## (b) Git sequence

Everything below happens in one working session on `v3-rewrite`, ending in one
commit, then a merge into `main`. If anything goes wrong before the commit,
`git reset --hard HEAD && git clean -fd -e .claude -e CLAUDE.md -e graphify-out` restores the branch.

### b1. Remove the 2.x project at the root

The tracked root files that belong to 2.x (from `git ls-files | grep -v '^v3/'`):

```
.fvmrc  .metadata  README.md  analysis_options.yaml  devtools_options.yaml  l10n.yaml
pubspec.yaml  pubspec.lock
assets/   (icon only)
lib/      (123 files: main.dart + src/)
linux/    (12 files)
macos/    (28 files)
windows/  (18 files)
```

Kept at the root: `.gitattributes`, `.gitignore` (merged in b3), `LICENSE`,
`docs/`, `packaging/`. Not tracked, so not affected: `tts_mod_vault.iml`
(`*.iml` ignored), `graphify-out/`, `.claude/`, `CLAUDE.md`.

```sh
git rm -r -q lib windows linux macos assets \
  pubspec.yaml pubspec.lock analysis_options.yaml l10n.yaml devtools_options.yaml \
  .fvmrc .metadata README.md
```

Verify: only the keepers and `v3/` remain tracked.

```sh
git ls-files | grep -v '^v3/'
# expected exactly:
# .gitattributes
# .gitignore
# LICENSE
# docs/...  packaging/...
```

### b2. Clear untracked leftovers so `git mv` cannot nest into them

`git rm` leaves ignored build output behind (`build/`, `.dart_tool/`,
`windows/flutter/ephemeral/`, `macos/Flutter/ephemeral/`, ...). If a directory
named `lib` or `windows` still exists, `git mv v3/lib lib` would move *into* it.

```sh
git status --short --ignored -- . ':!v3'      # lists the leftovers; keep .claude/, CLAUDE.md, graphify-out/
rm -rf lib windows linux macos assets build .dart_tool .fvm .flutter-plugins-dependencies tts_mod_vault.iml
for d in lib windows linux macos assets build .dart_tool; do [ -e "$d" ] && echo "STILL THERE: $d"; done
```

Verify: the loop prints nothing.

### b3. Move `v3/` to the root

Move each tracked top-level entry explicitly (a bare `git mv v3/* .` would
fail on the untracked `v3/build`, `v3/.dart_tool`, `v3/.fvm` and would stop
half way; `git mv v3/.* .` matches `.` and `..`).

```sh
git mv v3/.fvmrc .fvmrc
git mv v3/.metadata .metadata
git mv v3/README.md docs/developing.md          # developer notes; the user README comes from docs/README-v3.md
for p in $(git ls-files v3 | cut -d/ -f2 | sort -u | grep -v -E '^(\.gitignore|\.fvmrc|\.metadata|README\.md)$'); do
  git mv "v3/$p" "$p"
done
# -> analysis_options.yaml build.yaml l10n.yaml pubspec.yaml pubspec.lock assets/ lib/ linux/ macos/ test/ tool/ windows/
```

Merge the two `.gitignore` files by editing the root one:

- Add from `v3/.gitignore`: `/coverage/`, `.widget_preview/`, and the generated-code block
  (`*.g.dart`, `*.freezed.dart`, `lib/l10n/generated/` with its comment).
- Remove from the root: the "v3 rewrite project" block (`v3/build/`, `v3/.fvm/`).
- Keep the root-only rules: `.vscode/`, `.env`, `.claude/`, `graphify-out/`, `CLAUDE.md`, `.flutter-plugins`, `.fvm/`.

```sh
git rm -q v3/.gitignore
git mv docs/README-v3.md README.md
```

Verify:

```sh
git ls-files v3                    # prints nothing
ls -A v3                           # only ignored leftovers (build, .dart_tool, .fvm, maybe tts_mod_vault.iml)
rm -rf v3 && [ ! -e v3 ] && echo "v3 gone"
git diff --cached --stat | tail -1 # renames, not add+delete, for lib/ etc.
grep -n -E 'g\.dart|freezed|l10n/generated|v3/' .gitignore   # generated rules present, no v3/ rule
```

### b4. Fix references that assumed `v3/`

- `packaging/appimage/build_appimage.sh`, `packaging/macos/build_dmg.sh`,
  `packaging/windows/build_zip.ps1`: `PROJECT_DIR` already defaults to `.`; delete
  the "While the v3 rewrite lives in v3/ ..." comment lines.
- `packaging/appimage/README.md`, `packaging/macos/README.md`,
  `packaging/windows/README.md`: drop the `PROJECT_DIR=v3` / `-PROJECT_DIR v3`
  example lines and the "`<project>` is ... `v3/`" sentences.
- `docs/developing.md` (ex `v3/README.md`): rewrite the intro (it no longer
  "lives in `v3/`"), drop `PROJECT_DIR=v3` from "Release builds" and point the
  Windows line at `packaging/windows/build_zip.ps1`; the "Layout" block says
  `domain/, data/... arrive in Phase 1+`, which is stale.
- `CLAUDE.md` (local, ignored) and `.claude/`: fix any `v3/` paths, then
  `graphify update .` so `graphify-out/` indexes the root project.

Verify:

```sh
grep -rn 'v3/' README.md packaging docs/developing.md .fvmrc l10n.yaml build.yaml   # nothing
grep -rn 'PROJECT_DIR=v3\|-PROJECT_DIR v3' packaging                               # nothing
```

(`docs/v3-rewrite-plan.md`, `docs/v3-parity-audit.md` and this file keep their
historical `v3/` paths.)

### b5. Prove the moved tree builds from the root

```sh
fvm use                              # or make sure `flutter --version` says 3.47.7
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
flutter analyze                      # No issues found!
flutter test                         # all green
git status --short | grep -E '\.g\.dart|\.freezed\.dart|l10n/generated'   # nothing: the merged .gitignore works
```

Then one release build from the root with the default `PROJECT_DIR`:

```powershell
powershell -ExecutionPolicy Bypass -File packaging\windows\build_zip.ps1   # -> build\Windows.TTS.Mod.Vault.3.0.0.zip
```

Start the exe from the extracted zip once (title "TTS Mod Vault 3.0.0").

### b6. Commit and merge

```sh
git add -A
git status --short                   # review: R (renames) for lib/ etc., D for 2.x files, M for packaging/docs
git commit -m "v3.0.0: replace the 2.x app with the v3 rewrite

Move v3/ to the repo root, delete the 2.x project, merge .gitignore,
promote docs/README-v3.md to README.md, drop PROJECT_DIR=v3 from the
packaging docs."
git switch main
git merge --no-ff v3-rewrite -m "Merge branch 'v3-rewrite': TTS Mod Vault 3.0.0"
```

Verify, then tag and push:

```sh
git diff v3-rewrite main --stat                   # prints nothing
git ls-files | grep -c '^v3/'                     # 0
grep '^version:' pubspec.yaml                     # version: 3.0.0+1
flutter analyze && flutter test                   # once more on main
git tag -a v3.0.0 -m "TTS Mod Vault 3.0.0"
git push origin main v3.0.0
git push origin v3-rewrite                        # keep the branch for the record; delete later if wanted
```

## (c) Release

Build the artefacts from `main` at the tag, not from the pre-flight builds
(those came from `v3/` before the move):

```sh
git switch --detach v3.0.0           # on each build machine
```

| OS | Command (from the repo root) | Artefact to upload |
| --- | --- | --- |
| Windows | `powershell -ExecutionPolicy Bypass -File packaging\windows\build_zip.ps1` | `build\Windows.TTS.Mod.Vault.3.0.0.zip` |
| Linux | `bash packaging/appimage/build_appimage.sh` (inside the `ubuntu:22.04` container for the public build) | `build/TTS_Mod_Vault-x86_64.AppImage` |
| Linux raw bundle | `(cd build/linux/x64/release/bundle && zip -r -X ../../../../Linux.TTS.Mod.Vault.3.0.0.zip .)` after the AppImage build | `build/Linux.TTS.Mod.Vault.3.0.0.zip` (check the 2.1.0 release page and keep whatever name the 2.x Linux zip used) |
| macOS | `bash packaging/macos/build_dmg.sh` | `build/macOS.TTS.Mod.Vault.3.0.0.zip` (contains `TTSModVault.dmg`) |

Verify each before uploading:

- Windows: extract to a new folder, run `tts_mod_vault.exe`, check `pdfium.dll` and `sqlite3.dll` are in the folder.
- Linux: `chmod +x build/TTS_Mod_Vault-x86_64.AppImage && ./build/TTS_Mod_Vault-x86_64.AppImage`; `./build/TTS_Mod_Vault-x86_64.AppImage --appimage-extract >/dev/null && ls squashfs-root/usr/bin/lib | grep -E 'libpdfium|libsqlite3'`; on the 22.04 build, `objdump -T squashfs-root/usr/bin/tts_mod_vault | grep -o 'GLIBC_2\.[0-9]*' | sort -V | tail -1` is at most `GLIBC_2.35`.
- macOS: the "Verifying a release before uploading" block in `packaging/macos/README.md` (`codesign --verify --deep --strict` exits 0).

GitHub release:

1. https://github.com/markomijic/TTS-Mod-Vault/releases/new, tag `v3.0.0`, title `TTS Mod Vault 3.0.0`.
2. Body: `docs/v3-release-notes-3.0.0.md` (it already contains the 3.0.0 changelog section and the macOS first-launch block the macOS README requires in every release).
3. Attach the four artefacts. Publish as a normal release, **not** a pre-release or draft: the in-app update check (2.x and 3.0) reads `releases/latest`, so publishing is what notifies 2.x users.
4. Verify: `curl -s https://api.github.com/repos/markomijic/TTS-Mod-Vault/releases/latest | grep tag_name` prints `v3.0.0`; a 2.x install with "check for updates on start" shows the update dialog with working Nexus/GitHub links.

Nexus Mods (https://www.nexusmods.com/tabletopsimulator/mods/426):

1. Files: add one main file per OS with the same four artefacts and set the version to `3.0.0`; archive the 2.1.0 files as old versions (keep them downloadable for a while: 3.0 leaves 2.x data alone, so users can go back).
2. Description: paste the release notes (Nexus BBCode: headings become `[size]`/`[b]`, code blocks `[code]`); add the macOS block; refresh the screenshots with 3.0 ones.
3. Change log tab: paste the `# v3.0.0` section of `assets/text/changelog.md`.
4. Verify: the mod page's "Files" tab lists 3.0.0 for all three OSes and the download links resolve.

## (d) Post-release

- **2.x data stays.** Per decision D4 the importer never deletes `Documents/TTS Mod Vault/`; 3.0 reads it once. Do not add a cleanup step to 3.0.x; if removal is ever wanted, make it an explicit user action in a later release.
- **3.1: drop `hive_ce_flutter`.** It exists only for `lib/data/legacy/hive_settings_importer.dart`. Removing it also removes the importer (keep `tool/legacy/restore_v2_appdata.dart` or delete it with the importer; it rebuilds a 2.x box from the 3.x store and was only needed for the 2026-10-18 incident). Also consider removing the duplicate `library.options`/`network.options` persistence noted in the plan's resume notes.
- Update `docs/v3-rewrite-plan.md` "Resume notes" with the release date and tag; record the final benchmark numbers in 10.3 if any were produced on the released build.
- Watch the first bug reports for first-start problems (settings import, folder detection, the native libraries); the log file users should attach is named in the release notes.
- Optional housekeeping: `git branch -d v3-rewrite` locally and on the remote once `main` has shipped; update the `release-distribution-model` memory note (Windows zip script now exists).
