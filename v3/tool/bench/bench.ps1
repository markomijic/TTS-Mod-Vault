<#
.SYNOPSIS
  Cold / warm start benchmark for TTS Mod Vault (v2 and v3), release builds only.

.DESCRIPTION
  Launches the given exe N times, detects "library loaded" for the chosen app,
  reports every run and the median, and kills the app after each run.

  v2 detection: the release exe prints its debugPrint lines to stdout when stdout
  is redirected. The script captures stdout and waits for
      loadModsData END: <yyyy-MM-dd HH:mm:ss.ffffff>
      loadModsData total time: <h:mm:ss.ffffff>
  Wall time   = END timestamp - OS process start time.
  In-app time = the "total time" Duration (START line -> END line inside the app).
  Cold mode deletes only modurls*, modmetadata* and backupcache* in
  %USERPROFILE%\Documents\TTS Mod Vault (never appdata*, which holds settings).

  v3 detection: watches %APPDATA%\io.github.markomijic\TTS Mod Vault\vault.log
  for a NEW line (appended after launch) containing "Library refresh finished".
  Wall time   = that line's leading timestamp (yyyy-MM-dd HH:mm:ss.SSS) - process start.
  In-app time = first "<n>ms" / "<n> ms" / "duration=<n>" / "elapsed=<n>" token
                on that line, if present (reported as n/a otherwise).
  Cold mode deletes vault.sqlite only.

  Safety (docs/v3-rewrite-plan.md section 10.2): this script never writes under
  Documents\My Games\Tabletop Simulator and refuses an -Exe path inside it.
  It touches only the app's own cache files listed above.

  Memory mode (-Mode memory): samples WorkingSet64 / PrivateMemorySize64 of
  an already running tts_mod_vault process (or -Pid) every -IntervalMs for
  -Seconds and prints min / max / avg, so a GUI operation started by hand
  can be measured. Launches, kills and deletes nothing.

.PARAMETER Exe      Full path to the release exe (cold / warm).
.PARAMETER Mode     cold | warm | memory
.PARAMETER Runs     Number of runs (default 3).
.PARAMETER App      v2 | v3 (cold / warm)
.PARAMETER TimeoutSec  Per-run timeout in seconds (default 600).
.PARAMETER Csv      Optional path; one row per run is appended (header written if new).
.PARAMETER KeepLogs Keep per-run stdout/stderr captures (default: deleted). They are
                    written to $env:TEMP\ttsmv-bench\ either way.
.PARAMETER ProcessId  (-Pid) memory mode: process to sample; default: the one tts_mod_vault.
.PARAMETER Seconds  memory mode: sampling duration, 0 = until the process exits (default 30).
.PARAMETER IntervalMs  memory mode: sampling interval (default 250).

.EXAMPLE
  .\bench.ps1 -Exe D:\tmp\ttsmv-bench\v2-release\tts_mod_vault.exe -Mode cold -Runs 3 -App v2
  .\bench.ps1 -Exe D:\Dev\TTS-Mod-Vault\v3\build\windows\x64\runner\Release\tts_mod_vault.exe -Mode warm -App v3
  .\bench.ps1 -Mode memory -Seconds 60            # then start the backup in the app
  .\bench.ps1 -Mode memory -Pid 12345 -Seconds 0 -Csv D:\tmp\ttsmv-bench\memory.csv
#>
[CmdletBinding()]
param(
    [string] $Exe = '',
    [Parameter(Mandatory = $true)] [ValidateSet('cold', 'warm', 'memory')] [string] $Mode,
    [int] $Runs = 3,
    [string] $App = '',
    [int] $TimeoutSec = 600,
    [string] $Csv = '',
    [switch] $KeepLogs,
    # -Mode memory only: the process to sample (default: the one running
    # tts_mod_vault), how long (0 = until it exits or Ctrl-C) and how often.
    [Alias('Pid')] [int] $ProcessId = 0,
    [int] $Seconds = 30,
    [int] $IntervalMs = 250
)

$ErrorActionPreference = 'Stop'
$inv = [System.Globalization.CultureInfo]::InvariantCulture

# ---------------------------------------------------------- memory mode ----
# Samples WorkingSet64 / PrivateMemorySize64 of a running app so a GUI
# operation started by hand (a backup, an import) can be measured too.
# Nothing is launched, killed or deleted in this mode.
if ($Mode -eq 'memory') {
    if ($ProcessId -gt 0) {
        $proc = Get-Process -Id $ProcessId -ErrorAction Stop
    }
    else {
        $procs = @(Get-Process -Name 'tts_mod_vault' -ErrorAction SilentlyContinue)
        if ($procs.Count -eq 0) { throw 'No tts_mod_vault process is running; start the app or pass -Pid.' }
        if ($procs.Count -gt 1) { throw "Several tts_mod_vault processes are running ($($procs.Id -join ', ')); pass -Pid." }
        $proc = $procs[0]
    }
    $forText = if ($Seconds -gt 0) { "for $Seconds s" } else { 'until it exits (Ctrl-C to stop)' }
    Write-Host "memory: sampling '$($proc.ProcessName)' (pid $($proc.Id)) every $IntervalMs ms $forText"
    Write-Host "  exe: $($proc.Path)"
    $ws = New-Object System.Collections.Generic.List[double]
    $private = New-Object System.Collections.Generic.List[double]
    $deadline = (Get-Date).AddSeconds($Seconds)
    $started = Get-Date
    $exited = $false
    while ($Seconds -le 0 -or (Get-Date) -lt $deadline) {
        try { $proc.Refresh() } catch { $exited = $true; break }
        if ($proc.HasExited) { $exited = $true; break }
        $ws.Add($proc.WorkingSet64 / 1MB)
        $private.Add($proc.PrivateMemorySize64 / 1MB)
        Start-Sleep -Milliseconds $IntervalMs
    }
    $elapsed = ((Get-Date) - $started).TotalSeconds
    if ($ws.Count -eq 0) { throw 'No samples taken (did the process exit immediately?).' }
    $wsStats = $ws | Measure-Object -Minimum -Maximum -Average
    $pbStats = $private | Measure-Object -Minimum -Maximum -Average
    $peakWs = $null
    try { if (-not $exited) { $peakWs = [math]::Round($proc.PeakWorkingSet64 / 1MB, 1) } } catch { }
    Write-Host ("  samples      : {0} over {1:N1} s{2}" -f $ws.Count, $elapsed, $(if ($exited) { ' (process exited)' } else { '' }))
    Write-Host ("  working set  : min {0,8:N1} MB   max {1,8:N1} MB   avg {2,8:N1} MB" -f $wsStats.Minimum, $wsStats.Maximum, $wsStats.Average)
    Write-Host ("  private bytes: min {0,8:N1} MB   max {1,8:N1} MB   avg {2,8:N1} MB" -f $pbStats.Minimum, $pbStats.Maximum, $pbStats.Average)
    if ($null -ne $peakWs) { Write-Host ("  peak working set (OS, whole lifetime): {0:N1} MB" -f $peakWs) }
    $row = [pscustomobject]@{
        Mode = 'memory'; ProcessId = $proc.Id; ProcessName = $proc.ProcessName
        Samples = $ws.Count; Seconds = [math]::Round($elapsed, 1); IntervalMs = $IntervalMs
        WorkingSetMinMB = [math]::Round($wsStats.Minimum, 1); WorkingSetMaxMB = [math]::Round($wsStats.Maximum, 1); WorkingSetAvgMB = [math]::Round($wsStats.Average, 1)
        PrivateMinMB = [math]::Round($pbStats.Minimum, 1); PrivateMaxMB = [math]::Round($pbStats.Maximum, 1); PrivateAvgMB = [math]::Round($pbStats.Average, 1)
        PeakWorkingSetMB = $peakWs
        Timestamp = $started.ToString('yyyy-MM-dd HH:mm:ss', $inv)
        Exe = $proc.Path
    }
    if ($Csv) {
        $row | Export-Csv -LiteralPath $Csv -Append -NoTypeInformation -Encoding UTF8
        Write-Host "  csv: $Csv"
    }
    return $row
}

if (-not $Exe) { throw "-Exe is required for -Mode $Mode." }
if ($App -ne 'v2' -and $App -ne 'v3') { throw "-App v2|v3 is required for -Mode $Mode." }

# ---------------------------------------------------------------- safety ----
$libraryRoot = Join-Path $env:USERPROFILE 'Documents\My Games\Tabletop Simulator'
if ($Exe.ToLowerInvariant().StartsWith($libraryRoot.ToLowerInvariant())) {
    throw "Refusing: -Exe is inside the real TTS library ($libraryRoot)."
}
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
    throw "Exe not found: $Exe"
}
if ($Exe -match '\\build\\windows\\x64\\runner\\(Debug|Profile)\\') {
    throw "Refusing: '$Exe' is a Debug/Profile build. Section 10.3: release builds only."
}
if ($Runs -lt 1) { throw "-Runs must be >= 1" }

$procName = [System.IO.Path]::GetFileNameWithoutExtension($Exe)
if (Get-Process -Name $procName -ErrorAction SilentlyContinue) {
    throw "A '$procName' process is already running. Close it before benchmarking."
}

# ------------------------------------------------------------ app config ----
if ($App -eq 'v2') {
    $cacheDir = Join-Path $env:USERPROFILE 'Documents\TTS Mod Vault'
    $coldDeletePatterns = @('modurls*', 'modmetadata*', 'backupcache*')
    $v3LogFile = $null
}
else {
    $cacheDir = Join-Path $env:APPDATA 'io.github.markomijic\TTS Mod Vault'
    $coldDeletePatterns = @('vault.sqlite')
    $v3LogFile = Join-Path $cacheDir 'vault.log'
}

$captureDir = Join-Path $env:TEMP 'ttsmv-bench'
New-Item -ItemType Directory -Force -Path $captureDir | Out-Null

# --------------------------------------------------------------- helpers ----
function Get-CpuLoad {
    try {
        $v = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop).CounterSamples[0].CookedValue
        return [math]::Round($v, 1)
    }
    catch {
        try { return (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average }
        catch { return -1 }
    }
}

function Get-Median([double[]] $values) {
    if ($values.Count -eq 0) { return [double]::NaN }
    $s = $values | Sort-Object
    $n = $s.Count
    if ($n % 2 -eq 1) { return $s[[int][math]::Floor($n / 2)] }
    return ($s[$n / 2 - 1] + $s[$n / 2]) / 2
}

function Remove-ColdCache {
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        Write-Host "  cache dir does not exist yet: $cacheDir"
        return
    }
    foreach ($pat in $coldDeletePatterns) {
        $files = Get-ChildItem -LiteralPath $cacheDir -File -Filter $pat -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            Write-Host "  deleting $($f.Name) ($($f.Length) bytes)"
            Remove-Item -LiteralPath $f.FullName -Force -Confirm:$false
        }
    }
    if ($App -eq 'v3') {
        $side = Get-ChildItem -LiteralPath $cacheDir -File -Filter 'vault.sqlite-*' -ErrorAction SilentlyContinue
        if ($side) {
            Write-Warning "vault.sqlite-wal/-shm sidecars left in place ($($side.Count)); cold mode deletes vault.sqlite only."
        }
    }
}

function Stop-App([System.Diagnostics.Process] $p) {
    if ($p -and -not $p.HasExited) {
        Stop-Process -Id $p.Id -Force -Confirm:$false -ErrorAction SilentlyContinue
        try { $p.WaitForExit(10000) | Out-Null } catch { }
    }
    # catch any helper processes the app may have spawned under the same name
    Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false -ErrorAction SilentlyContinue
}

function Read-SharedText([string] $path) {
    # Start-Process keeps the redirect file open for writing; open with full sharing.
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        $sr = New-Object System.IO.StreamReader($fs)
        $t = $sr.ReadToEnd()
        $sr.Dispose(); $fs = $null
        return $t
    }
    catch { return '' }
    finally { if ($fs) { $fs.Dispose() } }
}

function Parse-DartDateTime([string] $s) {
    # Dart DateTime.toString(): 2026-10-17 15:47:20.489314 (6 fractional digits)
    # v3 LogEntry: 2026-10-17 15:47:20.489 (3 fractional digits)
    return [DateTime]::Parse($s.Trim(), $inv)
}

function Wait-V2Loaded([System.Diagnostics.Process] $p, [string] $stdoutPath, [string] $stderrPath) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 50
        $text = Read-SharedText $stdoutPath
        if ($text -match 'loadModsData END: (\S+ \S+)') {
            $endTs = Parse-DartDateTime $Matches[1]
            $inApp = [double]::NaN
            if ($text -match 'loadModsData total time: (\S+)') {
                $inApp = [TimeSpan]::Parse($Matches[1], $inv).TotalMilliseconds
            }
            $err = ''
            if ($text -match 'loadModsData error: (.*)') { $err = $Matches[1] }
            return @{ Ok = $true; EndTime = $endTs; InAppMs = $inApp; Error = $err }
        }
        if ($text -match 'loadModsData error: (.*)') {
            return @{ Ok = $false; Error = $Matches[1] }
        }
        if ($p.HasExited) {
            return @{ Ok = $false; Error = "process exited early (code $($p.ExitCode))" }
        }
    }
    return @{ Ok = $false; Error = "timeout after ${TimeoutSec}s" }
}

function Wait-V3Loaded([System.Diagnostics.Process] $p, [long] $startLength) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 50
        if (Test-Path -LiteralPath $v3LogFile) {
            $fs = $null
            try {
                $fs = [System.IO.File]::Open($v3LogFile, 'Open', 'Read', 'ReadWrite')
                if ($fs.Length -gt $startLength) {
                    $fs.Position = $startLength
                    $sr = New-Object System.IO.StreamReader($fs)
                    $new = $sr.ReadToEnd()
                    $sr.Dispose(); $fs = $null
                    # Lines look like: [yyyy-MM-dd HH:mm:ss.SSS] [INFO] [library] message key=value ...
                    $bootstrapMs = $null
                    $bootstrapSplits = ''
                    $firstFrameMs = $null
                    $refreshRequestedMs = $null
                    foreach ($line in ($new -split "`r?`n")) {
                        if ($line -match 'Bootstrap finished: (.*)$') {
                            $bootstrapSplits = $Matches[1]
                            if ($bootstrapSplits -match 'totalMs=(\d+)') { $bootstrapMs = [int]$Matches[1] }
                        }
                        elseif ($line -match 'First frame rendered: sinceMainMs=(\d+)') { $firstFrameMs = [int]$Matches[1] }
                        elseif ($line -match 'Refreshing library: sinceMainMs=(\d+)') { $refreshRequestedMs = [int]$Matches[1] }
                        if ($line -match 'Library refresh finished') {
                            $endTs = $null
                            if ($line -match '^\[?(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)\]?') {
                                $endTs = Parse-DartDateTime $Matches[1]
                            }
                            $inApp = [double]::NaN
                            if ($line -match 'durationMs=(\d+(?:\.\d+)?)') { $inApp = [double]::Parse($Matches[1], $inv) }
                            elseif ($line -match '(\d+(?:\.\d+)?)\s*ms\b') { $inApp = [double]::Parse($Matches[1], $inv) }
                            elseif ($line -match '(?:duration|elapsed|took)\s*[=:]\s*(\d+(?:\.\d+)?)') { $inApp = [double]::Parse($Matches[1], $inv) }
                            # Per-phase splits: every <name>Ms=<n> token except durationMs itself.
                            $phases = @()
                            foreach ($m in [regex]::Matches($line, '(\w+Ms)=(\d+)')) {
                                if ($m.Groups[1].Value -ne 'durationMs') { $phases += "$($m.Groups[1].Value)=$($m.Groups[2].Value)" }
                            }
                            return @{
                                Ok = $true; EndTime = $endTs; InAppMs = $inApp; Error = ''; Line = $line
                                BootstrapMs = $bootstrapMs; BootstrapSplits = $bootstrapSplits
                                FirstFrameMs = $firstFrameMs; RefreshRequestedMs = $refreshRequestedMs
                                Phases = ($phases -join ' ')
                            }
                        }
                        if ($line -match 'Library refresh failed') {
                            return @{ Ok = $false; Error = $line }
                        }
                    }
                }
            }
            finally {
                if ($fs) { $fs.Dispose() }
            }
        }
        if ($p.HasExited) {
            return @{ Ok = $false; Error = "process exited early (code $($p.ExitCode))" }
        }
    }
    return @{ Ok = $false; Error = "timeout after ${TimeoutSec}s" }
}

# ------------------------------------------------------------------ main ----
Write-Host "bench: app=$App mode=$Mode runs=$Runs"
Write-Host "  exe   : $Exe"
Write-Host "  cache : $cacheDir"
if ($Mode -eq 'cold') { Write-Host "  cold deletes: $($coldDeletePatterns -join ', ')" }
Write-Host ""

$results = @()
for ($i = 1; $i -le $Runs; $i++) {
    Write-Host "run $i/$Runs"
    if ($Mode -eq 'cold') { Remove-ColdCache }

    $cpu = Get-CpuLoad
    Write-Host "  cpu before launch: $cpu%"

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outPath = Join-Path $captureDir "$App-$Mode-$i-$stamp.stdout.txt"
    $errPath = Join-Path $captureDir "$App-$Mode-$i-$stamp.stderr.txt"
    Remove-Item -LiteralPath $outPath, $errPath -Force -ErrorAction SilentlyContinue

    $startLength = 0
    if ($App -eq 'v3' -and (Test-Path -LiteralPath $v3LogFile)) {
        $startLength = (Get-Item -LiteralPath $v3LogFile).Length
    }

    $p = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe) `
        -RedirectStandardOutput $outPath -RedirectStandardError $errPath -PassThru
    $launchedAt = Get-Date
    $procStart = $null
    try { $procStart = $p.StartTime } catch { $procStart = $launchedAt }

    try {
        if ($App -eq 'v2') { $r = Wait-V2Loaded $p $outPath $errPath }
        else { $r = Wait-V3Loaded $p $startLength }
        $detectedAt = Get-Date
    }
    finally {
        Stop-App $p
    }
    Start-Sleep -Seconds 2

    $wallMs = [double]::NaN
    if ($r.Ok) {
        if ($r.EndTime) { $wallMs = ($r.EndTime - $procStart).TotalMilliseconds }
        else { $wallMs = ($detectedAt - $procStart).TotalMilliseconds }
    }

    $row = [pscustomobject]@{
        App       = $App
        Mode      = $Mode
        Run       = $i
        Ok        = $r.Ok
        WallMs    = if ($r.Ok) { [math]::Round($wallMs) } else { $null }
        InAppMs   = if ($r.Ok -and -not [double]::IsNaN($r.InAppMs)) { [math]::Round($r.InAppMs) } else { $null }
        # v3 only (null for v2): bootstrap() duration, main()->first frame,
        # main()->refresh requested, and the refresh's per-phase splits.
        BootstrapMs        = if ($r.Ok) { $r.BootstrapMs } else { $null }
        FirstFrameMs       = if ($r.Ok) { $r.FirstFrameMs } else { $null }
        RefreshRequestedMs = if ($r.Ok) { $r.RefreshRequestedMs } else { $null }
        Phases             = if ($r.Ok) { $r.Phases } else { $null }
        BootstrapSplits    = if ($r.Ok) { $r.BootstrapSplits } else { $null }
        CpuBefore = $cpu
        Error     = $r.Error
        Timestamp = $procStart.ToString('yyyy-MM-dd HH:mm:ss', $inv)
        Exe       = $Exe
    }
    $results += $row

    if ($r.Ok) {
        $inAppText = if ($null -ne $row.InAppMs) { "$($row.InAppMs) ms" } else { 'n/a' }
        Write-Host "  wall $($row.WallMs) ms   in-app $inAppText"
        if ($null -ne $row.BootstrapMs) {
            Write-Host "  bootstrap $($row.BootstrapMs) ms   first frame $($row.FirstFrameMs) ms   refresh requested $($row.RefreshRequestedMs) ms  (since main)"
            Write-Host "  bootstrap splits: $($row.BootstrapSplits)"
        }
        if ($row.Phases) { Write-Host "  phases: $($row.Phases)" }
    }
    else {
        Write-Host "  FAILED: $($r.Error)"
    }
    if ($r.Ok -and $r.Error) { Write-Host "  note: app reported: $($r.Error)" }

    if ($Csv) {
        $exists = Test-Path -LiteralPath $Csv
        $row | Export-Csv -LiteralPath $Csv -Append -NoTypeInformation -Encoding UTF8
        if (-not $exists) { Write-Host "  csv created: $Csv" }
    }
    if (-not $KeepLogs) {
        Remove-Item -LiteralPath $outPath, $errPath -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "summary ($App, $Mode)"
$ok = @($results | Where-Object { $_.Ok })
if ($ok.Count -gt 0) {
    $walls = @($ok | ForEach-Object { [double]$_.WallMs })
    Write-Host ("  wall   : runs = {0}   median = {1} ms" -f ($walls -join ', '), [math]::Round((Get-Median $walls)))
    $inapps = @($ok | Where-Object { $null -ne $_.InAppMs } | ForEach-Object { [double]$_.InAppMs })
    if ($inapps.Count -gt 0) {
        Write-Host ("  in-app : runs = {0}   median = {1} ms" -f ($inapps -join ', '), [math]::Round((Get-Median $inapps)))
    }
    else {
        Write-Host "  in-app : n/a"
    }
    foreach ($extra in @(
            @{ Name = 'BootstrapMs'; Label = 'bootstrap' },
            @{ Name = 'FirstFrameMs'; Label = 'first frame (since main)' },
            @{ Name = 'RefreshRequestedMs'; Label = 'refresh requested (since main)' })) {
        $vals = @($ok | Where-Object { $null -ne $_.($extra.Name) } | ForEach-Object { [double]$_.($extra.Name) })
        if ($vals.Count -gt 0) {
            Write-Host ("  {0,-31}: runs = {1}   median = {2} ms" -f $extra.Label, ($vals -join ', '), [math]::Round((Get-Median $vals)))
        }
    }
}
if ($ok.Count -lt $results.Count) {
    Write-Host "  failed runs: $($results.Count - $ok.Count)"
}
if ($KeepLogs) { Write-Host "  captures: $captureDir" }

$results
