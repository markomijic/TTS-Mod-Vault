<#
.SYNOPSIS
  Runs tool/bench/op_bench.dart (the headless operation benchmark) inside
  the headless Flutter test engine and passes the options through.

.DESCRIPTION
  op_bench.dart needs dart:ui (the provider layer imports Flutter), so it
  cannot run with `dart run`; `flutter test` hosts it in flutter_tester
  (no window, no WidgetsFlutterBinding). This wrapper sets the OPB_*
  environment variables op_bench.dart reads and starts that run from the
  v3 project folder. See tool/bench/README.md for the scenarios and the
  safety rules (plan section 10.2).

.EXAMPLE
  .\op_bench.ps1 -Library D:\tmp\ttsmv-bench\stress -Data D:\tmp\ttsmv-bench\data -Scenario refresh -Cold
  .\op_bench.ps1 -Library D:\tmp\ttsmv-bench\sandbox -Data D:\tmp\ttsmv-bench\data -Scenario backup-one -Mod 3781830124 -Backups D:\tmp\ttsmv-bench\backups -Json -Out D:\tmp\ttsmv-bench\backup-one.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Library,
    [Parameter(Mandatory = $true)] [string] $Data,
    [Parameter(Mandatory = $true)]
    [ValidateSet('refresh', 'backup-one', 'backup-all', 'import', 'cleanup', 'check-urls')]
    [string] $Scenario,
    [string] $Backups = '',
    [string] $Ttsmod = '',
    [string] $Mod = '',
    [int] $Concurrency = 0,
    [int] $Workers = 0,
    [switch] $Cold,
    [switch] $DryRun,
    [switch] $Json,
    [string] $Out = ''
)

$ErrorActionPreference = 'Stop'
$v3 = Resolve-Path (Join-Path $PSScriptRoot '..\..')

$env:OPB_LIBRARY = $Library
$env:OPB_DATA = $Data
$env:OPB_SCENARIO = $Scenario
$env:OPB_BACKUPS = $Backups
$env:OPB_TTSMOD = $Ttsmod
$env:OPB_MOD = $Mod
$env:OPB_CONCURRENCY = if ($Concurrency -gt 0) { "$Concurrency" } else { '' }
$env:OPB_WORKERS = if ($Workers -gt 0) { "$Workers" } else { '' }
$env:OPB_COLD = if ($Cold) { '1' } else { '' }
$env:OPB_DRY_RUN = if ($DryRun) { '1' } else { '' }
$env:OPB_JSON = if ($Json) { '1' } else { '' }
$env:OPB_OUT = $Out

Push-Location $v3
try {
    # flutter_tester prefixes print() output with "Shell: " when stdout is
    # not a console; strip it so the lines read the same either way.
    & flutter test tool/bench/op_bench.dart --reporter expanded 2>&1 |
        ForEach-Object { "$_" -replace '^Shell: ', '' }
    $code = $LASTEXITCODE
}
finally {
    Pop-Location
    foreach ($name in 'LIBRARY', 'DATA', 'SCENARIO', 'BACKUPS', 'TTSMOD', 'MOD',
        'CONCURRENCY', 'WORKERS', 'COLD', 'DRY_RUN', 'JSON', 'OUT') {
        Remove-Item -Path "Env:OPB_$name" -ErrorAction SilentlyContinue
    }
}
exit $code
