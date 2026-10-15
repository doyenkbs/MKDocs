<#
.SYNOPSIS
    Checks the two WMI calls the Tanium Client Core Health sensor depends on,
    and optionally salvages the WMI repository. Built for a Tanium package.

.DESCRIPTION
    Tanium package command:
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Repair-WmiHealth.ps1 "$1"

    $1  Mode   Check (default) or Repair

    Checks, matching the sensor:
      1. root\default StdRegProv: EnumValues on HKLM\SYSTEM returns 0
      2. root\cimv2: Select ProductType from Win32_OperatingSystem returns a value

    Check mode only reports. Repair mode runs winmgmt /salvagerepository when a
    check fails, then checks again. Salvage rebuilds the repository only if it
    is inconsistent and keeps whatever it can read. /resetrepository is never run.

    Exit codes:
      0  Both checks pass (before or after repair)
      1  Repair ran and a check still fails
      2  A check failed in Check mode. Nothing changed
      3  Invalid Mode value
#>
param ([string]$Mode = "")

# Run as 64-bit so winmgmt.exe and WMI are the native versions.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($Mode) { $argList += @('-Mode', $Mode) }
    & $ps64 @argList
    exit $LASTEXITCODE
}

function Write-Log {
    param ([string]$Message, [string]$Level = 'INFO')
    Write-Output ("{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

$Mode = ([Uri]::UnescapeDataString($Mode)).Trim().Trim('"').Trim()
if (-not $Mode) { $Mode = 'Check' }
if ($Mode -notin 'Check', 'Repair') {
    Write-Log "Mode must be Check or Repair, got '$Mode'." 'ERROR'
    exit 3
}
Write-Log "Mode: $Mode"

$winmgmt = Join-Path $env:SystemRoot 'System32\wbem\winmgmt.exe'

# Sets $script:wmiOk instead of returning it. Write-Log writes to the output
# stream, so a return value would be mixed in with the log lines.
function Test-Wmi {
    $ok = $true

    try {
        $r = Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName EnumValues `
            -Arguments @{ hDefKey = [uint32]2147483650; sSubKeyName = 'SYSTEM' } -OperationTimeoutSec 60 -ErrorAction Stop
        if ($r.ReturnValue -eq 0) {
            Write-Log 'StdRegProv (root\default): OK'
        } else {
            Write-Log "StdRegProv (root\default): EnumValues returned $($r.ReturnValue)" 'ERROR'
            $ok = $false
        }
    } catch {
        Write-Log "StdRegProv (root\default): $($_.Exception.Message)" 'ERROR'
        $ok = $false
    }

    try {
        $os = Get-CimInstance -Query 'Select ProductType from Win32_OperatingSystem' -OperationTimeoutSec 60 -ErrorAction Stop
        if ($null -ne $os.ProductType) {
            Write-Log "Win32_OperatingSystem (root\cimv2): OK, ProductType $($os.ProductType)"
        } else {
            Write-Log 'Win32_OperatingSystem (root\cimv2): no ProductType returned' 'ERROR'
            $ok = $false
        }
    } catch {
        Write-Log "Win32_OperatingSystem (root\cimv2): $($_.Exception.Message)" 'ERROR'
        $ok = $false
    }

    $script:wmiOk = $ok
}

function Write-VerifyResult {
    $out = & $winmgmt /verifyrepository 2>&1
    Write-Log ("winmgmt /verifyrepository (exit {0}): {1}" -f $LASTEXITCODE, (($out | Where-Object { "$_".Trim() }) -join ' | '))
}

$svc = Get-Service -Name Winmgmt -ErrorAction SilentlyContinue
Write-Log ("Winmgmt service: {0}, startup {1}" -f $svc.Status, $svc.StartType)
Write-VerifyResult

Test-Wmi
if ($script:wmiOk) {
    Write-Log 'WMI checks passed. Nothing to do.'
    exit 0
}

if ($Mode -eq 'Check') {
    Write-Log 'WMI checks failed. Check mode, nothing changed. Run again with Mode Repair.' 'WARN'
    exit 2
}

Write-Log 'Running winmgmt /salvagerepository.'
$out = & $winmgmt /salvagerepository 2>&1
Write-Log ("winmgmt /salvagerepository (exit {0}): {1}" -f $LASTEXITCODE, (($out | Where-Object { "$_".Trim() }) -join ' | '))

Start-Sleep -Seconds 15
Write-VerifyResult

Test-Wmi
if ($script:wmiOk) {
    Write-Log 'WMI checks pass after salvage.'
    exit 0
}

Write-Log 'WMI checks still fail after salvage. This needs hands-on troubleshooting.' 'ERROR'
exit 1
