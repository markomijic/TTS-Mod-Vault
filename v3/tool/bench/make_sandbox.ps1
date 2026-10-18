<#
.SYNOPSIS
  Builds a sandbox copy of a few mods out of the real TTS library for the
  benchmarks that write (plan section 10.2 / 10.3).

.DESCRIPTION
  Copies ONLY the listed Workshop mod JSONs (plus their sibling PNGs) and
  the cached asset files they reference into -Out, which gets the usual
  TTS layout (Mods\Workshop, Mods\<asset folders>, Saves\Saved Objects).
  The asset file keys come from `dart run tool/bench/list_assets.dart`;
  files are matched in Mods\<folder>\ by case-insensitive basename (without
  extension), with the legacy Steam Cloud prefix mapped to the current host
  the way the app's index does.

  Before anything is copied the total size is printed and the script
  aborts when it exceeds -MaxGB (default 15) or when the free space on the
  target drive would drop below -MinFreeGB (default 20). -DryRun stops
  after the estimate. The source is only read: nothing in it is ever
  deleted, moved or written. -Out may not be inside the source or inside
  the user's Documents folder.

  -SeedOrphans N additionally writes N 1 KB files `orphan<i>.png` into
  Out\Mods\Images that no mod references, for the cleanup scenario.

.EXAMPLE
  .\make_sandbox.ps1 -Source "$env:USERPROFILE\Documents\My Games\Tabletop Simulator" `
      -Mods 3781830124,2857317092 -Out D:\tmp\ttsmv-bench\sandbox -SeedOrphans 500
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Source,
    [Parameter(Mandatory = $true)] [string[]] $Mods,
    [string] $Out = 'D:\tmp\ttsmv-bench\sandbox',
    [double] $MaxGB = 15,
    [double] $MinFreeGB = 20,
    [int] $SeedOrphans = 0,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$inv = [System.Globalization.CultureInfo]::InvariantCulture

# Mods may arrive as one comma-separated string.
$Mods = @($Mods | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Mods.Count -eq 0) { throw '-Mods is empty' }

function Normalize-Path([string] $path) {
    return [System.IO.Path]::GetFullPath($path).TrimEnd('\').ToLowerInvariant()
}

function Test-Inside([string] $path, [string] $root) {
    $a = Normalize-Path $path
    $b = Normalize-Path $root
    return ($a -eq $b) -or $a.StartsWith($b + '\')
}

# ---------------------------------------------------------------- safety ----
$sourceMods = Join-Path $Source 'Mods'
$sourceWorkshop = Join-Path $sourceMods 'Workshop'
if (-not (Test-Path -LiteralPath $sourceWorkshop -PathType Container)) {
    throw "Source has no Mods\Workshop folder: $Source"
}
if (Test-Inside $Out $Source) { throw "Refusing: -Out ($Out) is inside the source ($Source)." }
$documents = Join-Path $env:USERPROFILE 'Documents'
if (Test-Inside $Out $documents) {
    throw "Refusing: -Out ($Out) is inside $documents (plan 10.2: sandboxes live under D:\tmp\ttsmv-bench)."
}

$v3 = Resolve-Path (Join-Path $PSScriptRoot '..\..')

# --------------------------------------------------------- locate the mods ----
Write-Host "sandbox: source=$Source out=$Out mods=$($Mods -join ', ')"
$plan = New-Object System.Collections.Generic.List[object]   # objects with Source, Target, Length
$jsonPaths = @()
foreach ($id in $Mods) {
    $found = @(Get-ChildItem -LiteralPath $sourceWorkshop -Recurse -File -Filter "$id.json" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq "$id.json" })
    if ($found.Count -eq 0) { throw "Mod $id.json not found under $sourceWorkshop" }
    if ($found.Count -gt 1) {
        Write-Warning "Mod $id.json exists $($found.Count) times; taking $($found[0].FullName)"
    }
    $json = $found[0]
    $jsonPaths += $json.FullName
    $relDir = $json.DirectoryName.Substring($sourceMods.TrimEnd('\').Length).TrimStart('\')
    $plan.Add([pscustomobject]@{ Source = $json.FullName; Target = Join-Path (Join-Path $Out 'Mods') (Join-Path $relDir $json.Name); Length = $json.Length })
    foreach ($png in @((Join-Path $json.DirectoryName "$id.png"), (Join-Path $json.DirectoryName "Thumbnails\$id.png"))) {
        if (Test-Path -LiteralPath $png -PathType Leaf) {
            $item = Get-Item -LiteralPath $png
            $rel = $item.FullName.Substring($sourceMods.TrimEnd('\').Length).TrimStart('\')
            $plan.Add([pscustomobject]@{ Source = $item.FullName; Target = Join-Path (Join-Path $Out 'Mods') $rel; Length = $item.Length })
        }
    }
    Write-Host ("  {0}: {1} ({2:N1} MB)" -f $id, $json.FullName, ($json.Length / 1MB))
}

# ------------------------------------------------- asset keys (list_assets) ----
Write-Host 'listing asset keys (dart run tool/bench/list_assets.dart)...'
$keyLines = @()
Push-Location $v3
try {
    # `dart run` prints "Running build hooks..." to stderr, which PowerShell
    # 5.1 would turn into a NativeCommandError under -ErrorAction Stop; let
    # cmd drop stderr before it reaches PowerShell.
    $cmdline = 'dart run tool/bench/list_assets.dart ' +
        (($jsonPaths | ForEach-Object { '--json "' + $_ + '"' }) -join ' ') + ' 2>nul'
    $keyLines = @(& cmd /c $cmdline | Where-Object { $_ -match '^[^\t]+\t[^\t]+$' })
    if ($LASTEXITCODE -ne 0) { throw "list_assets.dart failed (exit $LASTEXITCODE)" }
}
finally { Pop-Location }
Write-Host "  $($keyLines.Count) distinct asset keys"

# The index maps a legacy-host file name to its current-host key.
$oldPrefix = 'httpcloud3steamusercontentcom'
$newPrefix = 'httpssteamusercontentaakamaihdnet'
function Get-FileKey([string] $baseName) {
    $k = $baseName.ToLowerInvariant()
    if ($k.StartsWith($oldPrefix)) { $k = $newPrefix + $k.Substring($oldPrefix.Length) }
    return $k
}

$folderIndex = @{}   # folder -> hashtable key -> [FileInfo[]]
function Get-FolderIndex([string] $folder) {
    if ($folderIndex.ContainsKey($folder)) { return $folderIndex[$folder] }
    $dir = Join-Path $sourceMods $folder
    $index = @{}
    if (Test-Path -LiteralPath $dir -PathType Container) {
        foreach ($f in Get-ChildItem -LiteralPath $dir -File) {
            $k = Get-FileKey ([System.IO.Path]::GetFileNameWithoutExtension($f.Name))
            if (-not $index.ContainsKey($k)) { $index[$k] = New-Object System.Collections.Generic.List[object] }
            $index[$k].Add($f)
        }
    }
    else {
        Write-Warning "asset folder missing in source: $dir"
    }
    $folderIndex[$folder] = $index
    return $index
}

$missing = 0
$perFolder = @{}
foreach ($line in $keyLines) {
    $parts = $line -split "`t"
    $folder = $parts[0]; $key = $parts[1].ToLowerInvariant()
    $index = Get-FolderIndex $folder
    if ($index.ContainsKey($key)) {
        foreach ($f in $index[$key]) {
            $plan.Add([pscustomobject]@{ Source = $f.FullName; Target = Join-Path (Join-Path (Join-Path $Out 'Mods') $folder) $f.Name; Length = $f.Length })
            $perFolder[$folder] = 1 + $(if ($perFolder.ContainsKey($folder)) { $perFolder[$folder] } else { 0 })
        }
    }
    else {
        $missing++
    }
}

# -------------------------------------------------------------- estimate ----
$totalBytes = ($plan | Measure-Object -Property Length -Sum).Sum
if (-not $totalBytes) { $totalBytes = 0 }
$totalBytes += [long]$SeedOrphans * 1024
Write-Host ''
Write-Host ("estimate: {0} files, {1:N2} GB ({2:N0} bytes); {3} referenced assets not cached in the source" -f $plan.Count, ($totalBytes / 1GB), $totalBytes, $missing)
foreach ($folder in ($perFolder.Keys | Sort-Object)) { Write-Host ("  {0,-14} {1,6} files" -f $folder, $perFolder[$folder]) }
if ($SeedOrphans -gt 0) { Write-Host "  + $SeedOrphans orphan placeholder files in Mods\Images" }

$outRoot = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Out))
$drive = New-Object System.IO.DriveInfo($outRoot)
$free = $drive.AvailableFreeSpace
Write-Host ("free space on {0} {1:N2} GB; after copy {2:N2} GB" -f $outRoot, ($free / 1GB), (($free - $totalBytes) / 1GB))
if ($totalBytes -gt $MaxGB * 1GB) {
    throw ("Aborting: {0:N2} GB exceeds -MaxGB {1}." -f ($totalBytes / 1GB), $MaxGB)
}
if (($free - $totalBytes) -lt $MinFreeGB * 1GB) {
    throw ("Aborting: free space would drop below -MinFreeGB {0} GB." -f $MinFreeGB)
}
if ($DryRun) { Write-Host 'dry run: nothing copied.'; return }

# ------------------------------------------------------------------- copy ----
foreach ($dir in @('Mods\Workshop', 'Mods\Assetbundles', 'Mods\Audio', 'Mods\Images', 'Mods\Images Raw',
        'Mods\Models', 'Mods\Models Raw', 'Mods\PDF', 'Saves\Saved Objects')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Out $dir) | Out-Null
}
$i = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($item in $plan) {
    $targetDir = Split-Path $item.Target
    if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
    Copy-Item -LiteralPath $item.Source -Destination $item.Target -Force
    $i++
    if ($i % 200 -eq 0) { Write-Host ("  copied {0}/{1} ({2}s)" -f $i, $plan.Count, [int]$sw.Elapsed.TotalSeconds) }
}
$orphanBytes = New-Object byte[] 1024
for ($k = 1; $k -le $SeedOrphans; $k++) {
    [System.IO.File]::WriteAllBytes((Join-Path (Join-Path $Out 'Mods\Images') ("orphan{0}.png" -f $k)), $orphanBytes)
}
Write-Host ("done: {0} files copied, {1} orphans seeded, {2:N2} GB in {3}s -> {4}" -f $plan.Count, $SeedOrphans, ($totalBytes / 1GB), [int]$sw.Elapsed.TotalSeconds, $Out)
Write-Host "point the app / op_bench at: $Out (Mods = $(Join-Path $Out 'Mods'), Saves = $(Join-Path $Out 'Saves'))"
