<#
.SYNOPSIS
    Build the Windows release of TTS Mod Vault and zip it the way GitHub
    Releases expects (Windows.TTS.Mod.Vault.<version>.zip).

.DESCRIPTION
    Windows counterpart of packaging/appimage/build_appimage.sh and
    packaging/macos/build_dmg.sh. Runs, in order: the native-assets check,
    (optional) flutter clean, flutter pub get, dart run build_runner build,
    flutter gen-l10n, flutter build windows --release, copies the Visual C++
    runtime DLLs next to the exe, verifies that they and the native libraries
    pdfium.dll and sqlite3.dll are in the Release folder, and zips that
    folder's contents into build\Windows.TTS.Mod.Vault.<version>.zip.

    Every missing piece stops the script with a non-zero exit code.

    Run it ON WINDOWS, from any directory, in Windows PowerShell 5.1 or newer:

        powershell -ExecutionPolicy Bypass -File packaging\windows\build_zip.ps1

.PARAMETER PROJECT_DIR
    Which Flutter project in the repo to build, relative to the repo root.
    Defaults to the repo root ("."). All paths below (pubspec.yaml, build\) are
    relative to that project.

.PARAMETER Clean
    Run `flutter clean` before building (the macOS script always does; on
    Windows an incremental build is normally fine).

.NOTES
    Prerequisites on the build machine:
      - Flutter with Windows desktop enabled (`flutter doctor` clean for Windows),
        which means Visual Studio with the "Desktop development with C++" workload.
      - Dart native assets enabled once per machine: flutter config --enable-native-assets
        (pdfium and sqlite3 ship as native assets; the script refuses to build without it).
      - FVM is optional: the script calls `fvm flutter` when fvm is on PATH so the
        version pinned in .fvmrc is used, otherwise plain `flutter`.
    No Windows Developer Mode is needed for a release build.
#>
[CmdletBinding()]
param(
    [string]$PROJECT_DIR = '.',
    [switch]$Clean
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

$ZipPrefix = 'Windows.TTS.Mod.Vault'      # 2.x release name: Windows.TTS.Mod.Vault.2.1.0.zip
$ExeName   = 'tts_mod_vault.exe'          # BINARY_NAME in windows\CMakeLists.txt
# The Visual C++ runtime the exe links against. Flutter does not bundle it;
# without these next to the exe the app does not start on a Windows install
# that never got the VC++ redistributable ("VCRUNTIME140.dll was not found").
$VcRuntimeDlls = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')

function Fail([string]$Message) {
    Write-Host ''
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# Runs a native command (first element = executable, rest = arguments) and
# fails loudly on a non-zero exit code. Output streams straight to the console.
function Invoke-Native([string[]]$Command) {
    $exe  = $Command[0]
    $rest = @($Command | Select-Object -Skip 1)
    & $exe @rest
    if ($LASTEXITCODE -ne 0) {
        Fail "'$($Command -join ' ')' exited with code $LASTEXITCODE"
    }
}

# Same as Invoke-Native but returns the command's output as one string.
function Invoke-Capture([string[]]$Command) {
    $exe  = $Command[0]
    $rest = @($Command | Select-Object -Skip 1)
    $out  = & $exe @rest
    if ($LASTEXITCODE -ne 0) {
        Fail "'$($Command -join ' ')' exited with code $LASTEXITCODE"
    }
    return ($out | Out-String)
}

# ---- locate the project -----------------------------------------------------
# Resolve the repo root regardless of where the script is invoked from, then
# enter the Flutter project (the repo root by default).
$root = $null
try {
    $root = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0) { $root = $null }
} catch {
    $root = $null
}
if (-not $root) {
    # Fallback when git is unavailable: packaging\windows\ is two levels below the root.
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$root = $root.Trim()

$projectPath = Join-Path $root $PROJECT_DIR
if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
    Fail "project directory not found: $projectPath (PROJECT_DIR=$PROJECT_DIR)"
}
$projectPath = (Resolve-Path -LiteralPath $projectPath).Path

Push-Location -LiteralPath $projectPath
try {
    if (-not (Test-Path -LiteralPath 'pubspec.yaml' -PathType Leaf)) {
        Fail "no pubspec.yaml in $projectPath (PROJECT_DIR=$PROJECT_DIR)"
    }
    Write-Host "==> project: $projectPath"

    # ---- toolchain -----------------------------------------------------------
    # Prefer fvm so the pinned Flutter version (.fvmrc) is used, like local dev.
    if (Get-Command fvm -ErrorAction SilentlyContinue) {
        $Flutter = @('fvm', 'flutter')
        $Dart    = @('fvm', 'dart')
        Write-Host '    using fvm (version from .fvmrc)'
    } else {
        if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
            Fail 'neither fvm nor flutter is on PATH'
        }
        $Flutter = @('flutter')
        $Dart    = @('dart')
    }

    # pdfium (pdfrx_engine) and sqlite3 are delivered as Dart native assets.
    # Without this flag the build silently omits them and the app crashes at startup.
    $configList = Invoke-Capture ($Flutter + @('config', '--list'))
    if ($configList -notmatch 'enable-native-assets:\s*true') {
        Write-Host 'ERROR: Dart native assets are disabled for this Flutter install.' -ForegroundColor Red
        Write-Host '       pdfium and sqlite3 ship as native assets. Run once on this machine:'
        Write-Host "         $($Flutter -join ' ') config --enable-native-assets"
        exit 1
    }

    # ---- version from pubspec.yaml (3.0.0+1 -> 3.0.0) --------------------------
    $versionLine = Get-Content -LiteralPath 'pubspec.yaml' |
        Where-Object { $_ -match '^version:' } |
        Select-Object -First 1
    if (-not $versionLine) { Fail 'could not read version from pubspec.yaml' }
    $version = (($versionLine -replace '^version:\s*', '').Split('+')[0]).Trim()
    if (-not $version) { Fail "could not parse the version from '$versionLine'" }
    $zipName = "$ZipPrefix.$version.zip"

    Write-Host "==> building TTS Mod Vault $version for Windows"

    # ---- build ---------------------------------------------------------------
    if ($Clean) {
        Step 'flutter clean'
        Invoke-Native ($Flutter + @('clean'))
    }

    Step 'flutter pub get'
    Invoke-Native ($Flutter + @('pub', 'get'))

    Step 'dart run build_runner build (drift / freezed / riverpod codegen)'
    Invoke-Native ($Dart + @('run', 'build_runner', 'build', '--delete-conflicting-outputs'))

    Step 'flutter gen-l10n'
    Invoke-Native ($Flutter + @('gen-l10n'))

    Step 'flutter build windows --release'
    Invoke-Native ($Flutter + @('build', 'windows', '--release'))

    # ---- verify the bundle ---------------------------------------------------
    $release = Join-Path $projectPath 'build\windows\x64\runner\Release'
    if (-not (Test-Path -LiteralPath $release -PathType Container)) {
        Fail "release folder not found at $release (Flutter writes x64 builds there; an arm64 host would need a different path)"
    }

    # ---- Visual C++ runtime -------------------------------------------------
    # Copied from the redist folder of the Visual Studio that built the app
    # (VC\Redist\MSVC\<version>\x64\Microsoft.VC14x.CRT\).
    Step 'copying the Visual C++ runtime DLLs'
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) { Fail "vswhere.exe not found at $vswhere (is Visual Studio installed?)" }
    $vsPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    if (-not $vsPath) { Fail 'no Visual Studio with the C++ x64 tools found (vswhere)' }
    $redistRoot = Join-Path $vsPath.Trim() 'VC\Redist\MSVC'
    $redistVersion = Get-ChildItem -LiteralPath $redistRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
    if (-not $redistVersion) { Fail "no versioned redist folder under $redistRoot" }
    $crt = Get-ChildItem -LiteralPath (Join-Path $redistVersion.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $crt) { Fail "no Microsoft.VC*.CRT folder under $($redistVersion.FullName)\x64" }
    foreach ($dll in $VcRuntimeDlls) {
        $src = Join-Path $crt.FullName $dll
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { Fail "$dll not found in $($crt.FullName)" }
        Copy-Item -LiteralPath $src -Destination $release -Force
    }
    Write-Host "    from $($crt.FullName)"

    # The runner, the engine and the asset folder must be there, plus both native
    # assets and the VC++ runtime, or the app dies at startup ("Failed to load
    # dynamic library", "VCRUNTIME140.dll was not found").
    $required = @($ExeName, 'flutter_windows.dll', 'pdfium.dll', 'sqlite3.dll') + $VcRuntimeDlls
    $missing = @()
    foreach ($name in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $release $name) -PathType Leaf)) { $missing += $name }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $release 'data') -PathType Container)) { $missing += 'data\' }
    if ($missing.Count -gt 0) {
        Write-Host "ERROR: missing from $release : $($missing -join ', ')" -ForegroundColor Red
        if ($missing -contains 'pdfium.dll' -or $missing -contains 'sqlite3.dll') {
            Write-Host "       release would crash at launch (is 'flutter config --enable-native-assets' set and the hook build succeeding?)"
        }
        exit 1
    }
    Write-Host "    native assets OK: pdfium.dll, sqlite3.dll; VC++ runtime OK: $($VcRuntimeDlls -join ', ')"

    # ---- zip the Release folder contents ------------------------------------
    # Entries are added one by one with forward-slash names. Under Windows
    # PowerShell 5.1 both Compress-Archive and ZipFile.CreateFromDirectory write
    # nested entries with backslashes (data\icudtl.dat), which some unzip tools on
    # other platforms keep as literal file names. The folder *contents* go at the
    # top level, so users extract and run tts_mod_vault.exe directly, as with the
    # 2.x releases.
    Add-Type -AssemblyName System.IO.Compression            # ZipArchive, ZipArchiveMode, CompressionLevel
    Add-Type -AssemblyName System.IO.Compression.FileSystem # ZipFile, ZipFileExtensions
    $buildDir = Join-Path $projectPath 'build'
    $zipPath  = Join-Path $buildDir $zipName
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

    Step "zipping -> build\$zipName"
    $files = @(Get-ChildItem -LiteralPath $release -Recurse -File)
    if ($files.Count -eq 0) { Fail "release folder $release is empty" }
    $archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $files) {
            $entryName = $file.FullName.Substring($release.Length).TrimStart('\', '/') -replace '\\', '/'
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $file.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally {
        $archive.Dispose()
    }

    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { Fail "zip was not created at $zipPath" }

    # Read the archive back: the exe and both native libraries must be top-level
    # entries, every file must be in, and no entry may carry a backslash.
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entryNames = @($zip.Entries | ForEach-Object { $_.FullName })
        foreach ($name in @($ExeName, 'pdfium.dll', 'sqlite3.dll') + $VcRuntimeDlls) {
            if ($entryNames -notcontains $name) { Fail "zip is missing top-level entry '$name'" }
        }
        if ($entryNames.Count -ne $files.Count) {
            Fail "zip has $($entryNames.Count) entries but the release folder has $($files.Count) files"
        }
        $backslashed = @($entryNames | Where-Object { $_ -like '*\*' })
        if ($backslashed.Count -gt 0) { Fail "zip entries with backslashes: $($backslashed -join ', ')" }
        $entryCount = $entryNames.Count
    } finally {
        $zip.Dispose()
    }
    $sizeMb = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1)

    Write-Host ''
    Write-Host '==> done:'
    Write-Host "    folder: $release"
    Write-Host "    zip:    $zipPath   ($sizeMb MB, $entryCount entries)   <- upload this to GitHub Releases and Nexus Mods"
    Write-Host "    test it: extract the zip somewhere else and run $ExeName from there"
} finally {
    Pop-Location
}
