######################################################################
# Update Windows Store Apps (Parameterized for Tanium)
#
# Tanium package command:
#   cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Update-StoreApps.ps1 "$1" "$2"
#
# $1  Apps           Package name(s), comma separated. Each entry is either:
#                      Name                 report the version before and after
#                      Name=MinimumVersion  also verify the app reached that version
#                    Example: Microsoft.Paint=11.2605.91.0,Microsoft.WindowsCalculator
#                    Use the package Name (Name column of Get-AppxPackage), not PackageFullName.
#                    Wildcards are not allowed.
# $2  Wait Minutes   How long to wait for updates to finish, 1 to 30. Blank = 10.
#
# How it works:
#   Triggers a Microsoft Store update scan through the MDM WMI bridge, which requires SYSTEM.
#   The scan updates every Store app that has an update available, not only the apps in $1.
#   $1 decides what is verified and reported. The Store must be reachable from SYSTEM context.
#   Apps that are not installed are not installed by this package.
#
# Exit codes:
#   0  Every app with a minimum version meets it (or nothing needed updating)
#   1  One or more apps are still below the minimum version after waiting
#   2  Invalid parameters
#   3  Store update scan could not be triggered (MDM bridge error or InstallService disabled)
#   4  Microsoft Store is blocked by policy, nothing done
#   5  Not running as SYSTEM, nothing done
#   6  Minimum version met, but an older version is still installed for at least one user
#      (the old WindowsApps folder stays, so a vulnerability scan can still flag it)
######################################################################

param(
    [string]$Apps = "",
    [string]$WaitMinutes = ""
)

# The Appx cmdlets do not work reliably from 32-bit PowerShell, so restart as 64-bit.
# The raw (still URL-encoded) values are passed on, so they are decoded only once.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($Apps)        { $argList += @('-Apps', $Apps) }
    if ($WaitMinutes) { $argList += @('-WaitMinutes', $WaitMinutes) }
    & $ps64 @argList
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'

function Write-Log {
    param ([string]$Message, [string]$Level = 'INFO')
    Write-Output ("{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

# Tanium URL-encodes parameter values. Decode, then strip stray whitespace and quotes.
function ConvertFrom-TaniumParam {
    param ([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return ([Uri]::UnescapeDataString($Value)).Trim().Trim('"').Trim()
}

# Returns every version of an app installed for any user, or $null if none
function Get-AppState {
    param ([string]$Name)
    $pkgs = @(Get-AppxPackage -AllUsers -Name $Name -ErrorAction SilentlyContinue)
    if ($pkgs.Count -eq 0) { return $null }
    $versions = @($pkgs | ForEach-Object { [version]$_.Version } | Sort-Object -Unique)
    return [pscustomobject]@{
        Highest  = $versions[-1]
        Versions = $versions
    }
}

$appsRaw = ConvertFrom-TaniumParam $Apps
$waitRaw = ConvertFrom-TaniumParam $WaitMinutes

Write-Log "Apps parameter: '$appsRaw'"
Write-Log "Wait Minutes parameter: '$waitRaw'"

# --- Validate parameters ------------------------------------------------------
if (-not $appsRaw) {
    Write-Log "No Store app specified. Example: Microsoft.Paint=11.2605.91.0,Microsoft.WindowsCalculator" 'ERROR'
    exit 2
}

# Package names are not case sensitive, so track duplicates without regard to case
$seen     = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$targets  = [ordered]@{}   # Name -> minimum [version], or $null when no minimum was given
$badItems = @()

foreach ($entry in $appsRaw.Split(',')) {
    $e = $entry.Trim()
    if (-not $e) { continue }

    $parts = $e -split '=', 2
    $name  = $parts[0].Trim()
    if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9.\-]*$') { $badItems += $e; continue }

    $min = $null
    if ($parts.Count -gt 1) {
        $parsed = $null
        if (-not [version]::TryParse($parts[1].Trim(), [ref]$parsed)) { $badItems += $e; continue }
        $min = $parsed
    }

    if (-not $seen.Add($name)) {
        Write-Log "Duplicate entry '$e' ignored. The first entry for $name is used." 'WARN'
        continue
    }
    $targets[$name] = $min
}

if ($badItems.Count -gt 0) {
    Write-Log ("Invalid entr(ies): {0}. Use Name or Name=Version (example: Microsoft.Paint=11.2605.91.0). No wildcards or PackageFullName." -f ($badItems -join ', ')) 'ERROR'
    exit 2
}
if ($targets.Count -eq 0) {
    Write-Log "No valid app names found in the Apps parameter." 'ERROR'
    exit 2
}

$wait = 10
if ($waitRaw) {
    $parsedWait = 0
    if (-not [int]::TryParse($waitRaw, [ref]$parsedWait) -or $parsedWait -lt 1 -or $parsedWait -gt 30) {
        Write-Log "Wait Minutes '$waitRaw' is not a whole number from 1 to 30." 'ERROR'
        exit 2
    }
    $wait = $parsedWait
}

Write-Log ("Apps to verify ({0}):" -f $targets.Count)
foreach ($name in $targets.Keys) {
    if ($targets[$name]) { Write-Log ("  - {0} (minimum {1})" -f $name, $targets[$name]) }
    else                 { Write-Log ("  - {0} (no minimum, report only)" -f $name) }
}

# --- SYSTEM check -------------------------------------------------------------
# The MDM WMI bridge only accepts calls from SYSTEM. An administrator account is not enough.
$currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($currentSid -ne 'S-1-5-18') {
    Write-Log "Running as $currentSid, not SYSTEM. The Store update scan requires SYSTEM. Nothing done." 'ERROR'
    exit 5
}

# --- Store policy and service checks ------------------------------------------
$storePolicy = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' -ErrorAction SilentlyContinue
if ($storePolicy) {
    if ($storePolicy.RemoveWindowsStore -eq 1) {
        Write-Log "Policy RemoveWindowsStore = 1. The Microsoft Store is blocked, so it cannot deliver updates. Nothing done." 'ERROR'
        exit 4
    }
    if ($storePolicy.DisableStoreApps -eq 1) {
        Write-Log "Policy DisableStoreApps = 1. Store apps are disabled on this machine. Nothing done." 'ERROR'
        exit 4
    }
    if ($storePolicy.AutoDownload -eq 2) {
        Write-Log "Policy AutoDownload = 2 (automatic Store updates turned off). The triggered scan may still be blocked by this policy." 'WARN'
    }
}

$installService = Get-Service -Name 'InstallService' -ErrorAction SilentlyContinue
if (-not $installService) {
    Write-Log "Microsoft Store Install Service (InstallService) was not found. The scan will likely fail." 'WARN'
} elseif ($installService.StartType -eq 'Disabled') {
    Write-Log "Microsoft Store Install Service (InstallService) is disabled. Store updates cannot install. Nothing done." 'ERROR'
    exit 3
}

# --- Baseline -----------------------------------------------------------------
$baseline = @{}
$pending  = New-Object 'System.Collections.Generic.List[string]'

foreach ($name in $targets.Keys) {
    $state = Get-AppState $name
    $baseline[$name] = $state
    $min = $targets[$name]

    if (-not $state) {
        Write-Log "Before: $name is not installed for any user. Store updates do not install apps, so it is skipped."
        continue
    }

    Write-Log ("Before: {0} installed version(s): {1}" -f $name, ($state.Versions -join ', '))

    if ($min -and $state.Highest -ge $min) {
        Write-Log ("  {0} already meets minimum {1}." -f $name, $min)
    } else {
        $pending.Add($name)
    }
}

# --- Trigger the Store update scan --------------------------------------------
if ($pending.Count -eq 0) {
    Write-Log "No app needs an update. Store update scan not triggered."
} else {
    try {
        $mdm = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' -ErrorAction Stop |
            Select-Object -First 1
        if (-not $mdm) { throw "MDM_EnterpriseModernAppManagement_AppManagement01 returned no instance." }
        $scan = $mdm | Invoke-CimMethod -MethodName 'UpdateScanMethod' -ErrorAction Stop
        Write-Log ("Store update scan triggered. ReturnValue: {0}" -f $scan.ReturnValue)
        if ($null -ne $scan.ReturnValue -and $scan.ReturnValue -ne 0) {
            Write-Log "UpdateScanMethod returned a non-zero value. Continuing, the version check below decides the result." 'WARN'
        }
    } catch {
        Write-Log ("Could not trigger the Store update scan. {0}" -f $_.Exception.Message) 'ERROR'
        exit 3
    }

    # --- Wait for updates to land ---------------------------------------------
    Write-Log ("Waiting up to {0} minute(s) for: {1}" -f $wait, ($pending -join ', '))
    $deadline = (Get-Date).AddMinutes($wait)

    while ($pending.Count -gt 0 -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 30
        foreach ($name in @($pending)) {
            $state = Get-AppState $name
            if (-not $state) { continue }
            $min  = $targets[$name]
            $base = $baseline[$name].Highest
            if (($min -and $state.Highest -ge $min) -or (-not $min -and $state.Highest -gt $base)) {
                Write-Log ("  {0} updated: {1} -> {2}" -f $name, $base, $state.Highest)
                [void]$pending.Remove($name)
            }
        }
    }

    if ($pending.Count -gt 0) {
        Write-Log ("Wait ended. No version change seen for: {0}" -f ($pending -join ', ')) 'WARN'
    }
}

# --- Final check and summary --------------------------------------------------
$belowMin   = 0
$oldRemains = 0
$results    = [ordered]@{}

foreach ($name in $targets.Keys) {
    $state = Get-AppState $name
    $min   = $targets[$name]
    $base  = if ($baseline[$name]) { $baseline[$name].Highest } else { $null }

    if (-not $state) {
        $results[$name] = 'Not installed (skipped)'
        continue
    }

    $older = @($state.Versions | Where-Object { $_ -lt $state.Highest })
    $olderText = if ($older.Count -gt 0) { " Older version(s) still installed for a user: {0}." -f ($older -join ', ') } else { "" }

    if ($min) {
        if ($state.Highest -lt $min) {
            $results[$name] = "BELOW MINIMUM: {0} (needs {1})" -f $state.Highest, $min
            $belowMin++
        } else {
            $results[$name] = ("OK: {0} (minimum {1}).{2}" -f $state.Highest, $min, $olderText)
            if ($older.Count -gt 0) { $oldRemains++ }
        }
    } else {
        if ($base -and $state.Highest -gt $base) {
            $results[$name] = ("Updated: {0} -> {1}.{2}" -f $base, $state.Highest, $olderText)
            if ($older.Count -gt 0) { $oldRemains++ }
        } else {
            $results[$name] = "No change: {0} (no update found, or it did not finish within {1} minute(s))" -f $state.Highest, $wait
        }
    }
}

Write-Log "Summary:"
foreach ($key in $results.Keys) {
    Write-Log ("  {0}: {1}" -f $key, $results[$key])
}

if ($belowMin -gt 0) {
    Write-Log ("{0} app(s) still below the minimum version." -f $belowMin) 'ERROR'
    exit 1
}
if ($oldRemains -gt 0) {
    Write-Log ("{0} app(s) updated, but an older version is still installed for at least one user. A vulnerability scan can still flag this machine until the older version is gone." -f $oldRemains) 'WARN'
    exit 6
}

Write-Log "Completed."
exit 0
