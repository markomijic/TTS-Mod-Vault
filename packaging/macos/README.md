# macOS packaging — DMG

This directory builds the macOS release of TTS Mod Vault as a `.dmg` (the user
opens it and drags the app to Applications) plus a `.zip` containing that DMG,
which is the format hosted on GitHub Releases (e.g.
`macOS.TTS.Mod.Vault.2.1.0.zip`).

## Build

Run on **macOS** (Apple Silicon — Flutter cannot build macOS targets on
Windows/Linux):

```bash
bash packaging/macos/build_dmg.sh
```

Output (in `build/`):

| File | Use |
| --- | --- |
| `TTSModVault.dmg` | The disk image (app + `Applications` shortcut). |
| `macOS.TTS.Mod.Vault.<version>.zip` | The DMG zipped — **upload this to GitHub Releases**. |
| `build/macos/Build/Products/Release/TTS Mod Vault.app` | The raw `.app`, if you need it. |

The version is read automatically from `pubspec.yaml`.

### Prerequisites

- Flutter with macOS desktop enabled (`flutter doctor` clean for macOS)
- Xcode + command line tools
- `hdiutil`, `codesign`, `zip` — all built into macOS, nothing to install
- The script uses `fvm flutter` if [FVM](https://fvm.app/) is installed (this
  repo pins a Flutter version via `.fvmrc`), otherwise plain `flutter`.

## Why the script always does a clean build

Incremental Flutter macOS builds can leave the outer `.app`'s **code-signature
seal stale** ("nested code is modified or invalid"). A locally-built app with a
stale seal still runs on the build machine, but a **downloaded** copy fails to
launch on another Mac. The script runs `flutter clean` first (override with
`SKIP_CLEAN=1`) and then runs `codesign --verify --deep --strict` — a broken
seal **fails the build** instead of shipping. It also checks that
`pdfium.framework` is bundled, since a missing pdfium native asset crashes the
app at startup.

It never modifies the `.app` after signing (it only copies it into a staging
folder and adds an `Applications` symlink) — touching a signed bundle is exactly
what breaks the signature.

## ⚠️ Gatekeeper: the app is not notarized

The app is **ad-hoc signed**, not signed with a paid Apple Developer ID and not
notarized (notarization requires a $99/yr Apple Developer account). On download,
macOS quarantines it and Gatekeeper blocks the first launch with *"Apple could
not verify 'TTS Mod Vault' is free of malware"* — or the icon bounces and the
app quits with no window.

This is **not a bug in the app** and cannot be fixed for free. Users clear it
once per install with:

```sh
xattr -dr com.apple.quarantine "/Applications/TTS Mod Vault.app"
```

This is documented in the main `README.md` (macOS install section). **Put it in
every release's notes**, e.g.:

```markdown
### ⚠️ macOS users — first launch
This app isn't notarized (no paid Apple Developer account), so macOS blocks it on
first open. After dragging it to Applications, run this once in Terminal:

    xattr -dr com.apple.quarantine "/Applications/TTS Mod Vault.app"
```

## Verifying a release before uploading

```bash
# unzip, mount, and check the app inside is signed & has the launch fix
unzip -o build/macOS.TTS.Mod.Vault.<version>.zip -d /tmp/ttscheck
hdiutil attach /tmp/ttscheck/TTSModVault.dmg -nobrowse
codesign --verify --deep --strict "/Volumes/TTS Mod Vault/TTS Mod Vault.app"   # exit 0
hdiutil detach "/Volumes/TTS Mod Vault"
```

To reproduce a *user's* experience (quarantine), copy the app to `/Applications`,
run `xattr -w com.apple.quarantine "0083;0;Safari;" "/Applications/TTS Mod Vault.app"`,
then verify the `xattr -dr` workaround above lets it launch.
