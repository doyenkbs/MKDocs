######################################################################
# Remove Windows Store Apps (Parameterized for Tanium)
#
# Tanium package command:
#   cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-StoreApps.ps1 "$1" "$2" "$3"
#
# $1  Apps           Package name(s), comma separated: Microsoft.XboxApp,Microsoft.BingNews
#                    Use the package Name (Name column of Get-AppxPackage), not PackageFullName.
#                    Wildcards are not allowed.
# $2  Option         None (or blank), or DisableReinstall
# $3  Confirm Count  Number of apps listed in $1 (2 for the example above)
#
# Exit codes:
#   0  Every requested app was removed or was not present
#   1  One or more apps, or a DisableReinstall setting, failed
#   2  Invalid parameters
#   3  Confirm Count did not match, nothing removed
#   4  A protected app was requested, nothing removed
#   5  Not running as SYSTEM or an administrator, nothing removed
######################################################################

param(
    [string]$Apps = "",
    [string]$Option = "",
    [string]$ConfirmCount = ""
)

# The Appx cmdlets do not work reliably from 32-bit PowerShell, so restart as 64-bit.
# The raw (still URL-encoded) values are passed on, so they are decoded only once.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($Apps)         { $argList += @('-Apps', $Apps) }
    if ($Option)       { $argList += @('-Option', $Option) }
    if ($ConfirmCount) { $argList += @('-ConfirmCount', $ConfirmCount) }
    & $ps64 @argList
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'
$script:Failures = 0

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

function Set-RegDword {
    param ([string]$Path, [string]$Name, [int]$Value)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
        Write-Log ("Set {0}\{1} = {2}" -f $Path, $Name, $Value)
    } catch {
        Write-Log ("Failed to set {0}\{1}. {2}" -f $Path, $Name, $_.Exception.Message) 'ERROR'
        $script:Failures++
    }
}

$appsRaw = ConvertFrom-TaniumParam $Apps
$option  = ConvertFrom-TaniumParam $Option
$confirm = ConvertFrom-TaniumParam $ConfirmCount

Write-Log "Apps parameter: '$appsRaw'"
Write-Log "Option parameter: '$option'"
Write-Log "Confirm Count parameter: '$confirm'"

# --- Validate parameters ------------------------------------------------------
if (-not $appsRaw) {
    Write-Log "No Store app specified. Example: Microsoft.XboxApp,Microsoft.BingNews" 'ERROR'
    exit 2
}

# Package names are not case sensitive, so drop duplicates without regard to case
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$appList = @($appsRaw.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $seen.Add($_) })

$badNames = @($appList | Where-Object { $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9.\-]*$' })
if ($badNames.Count -gt 0) {
    Write-Log ("Invalid app name(s): {0}. Use the package Name only (letters, numbers, periods, hyphens). No wildcards or PackageFullName." -f ($badNames -join ', ')) 'ERROR'
    exit 2
}

if ($option -eq 'None') { $option = '' }   # drop-down lists that cannot hold a blank value
if ($option -and $option -ne 'DisableReinstall') {
    Write-Log "Unknown Option '$option'. Use None (or leave it blank), or DisableReinstall." 'ERROR'
    exit 2
}

Write-Log ("Apps requested for removal ({0}):" -f $appList.Count)
$appList | ForEach-Object { Write-Log "  - $_" }

# --- Protected apps -----------------------------------------------------------
# Removing these breaks the Store, winget, Windows Security, the Start menu, sign-in, or other apps' dependencies
$protectedPatterns = @(
    'Microsoft.WindowsStore'
    'Microsoft.StorePurchaseApp'
    'Microsoft.DesktopAppInstaller'
    'Microsoft.SecHealthUI'
    'Microsoft.Windows.ShellExperienceHost'
    'Microsoft.Windows.StartMenuExperienceHost'
    'Microsoft.Windows.CloudExperienceHost'
    'Microsoft.Windows.Search'
    'Microsoft.AAD.BrokerPlugin'
    'Microsoft.AccountsControl'
    'Microsoft.LockApp'
    'Microsoft.Win32WebViewHost'
    'Microsoft.Services.Store.Engagement'
    'windows.immersivecontrolpanel'
    'Microsoft.VCLibs*'
    'Microsoft.NET.Native*'
    'Microsoft.UI.Xaml*'
    'Microsoft.WindowsAppRuntime*'
    'MicrosoftCorporationII.WinAppRuntime*'
    'Microsoft.WidgetsPlatformRuntime'
    'Microsoft.Winget.Source'
    'MicrosoftWindows.Client.*'
)

$protectedHits = @(foreach ($app in $appList) {
    foreach ($pattern in $protectedPatterns) {
        if ($app -like $pattern) { $app; break }
    }
})
if ($protectedHits.Count -gt 0) {
    Write-Log ("Protected app(s) requested: {0}. Removing these breaks Windows components. Nothing removed." -f ($protectedHits -join ', ')) 'ERROR'
    exit 4
}

# --- Confirmation (friction layer) --------------------------------------------
$confirmNumber = 0
if (-not [int]::TryParse($confirm, [ref]$confirmNumber) -or $confirmNumber -ne $appList.Count) {
    Write-Log ("Confirm Count '{0}' does not match the number of apps requested ({1}). Nothing removed." -f $confirm, $appList.Count) 'ERROR'
    exit 3
}
Write-Log ("Confirm Count matched ({0})." -f $appList.Count)

# --- Elevation check ----------------------------------------------------------
# Without admin rights, Get-AppxPackage -AllUsers returns nothing, which would look like "Not present"
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Not running as SYSTEM or an administrator. Store apps for all users cannot be read or removed. Nothing removed." 'ERROR'
    exit 5
}

# --- Remove apps --------------------------------------------------------------
try {
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
} catch {
    Write-Log ("Could not read provisioned packages. Provisioned copies will not be removed. {0}" -f $_.Exception.Message) 'ERROR'
    $provisioned = @()
    $script:Failures++
}

$results = [ordered]@{}

foreach ($app in $appList) {
    Write-Log "Processing $app"

    $installed = @(Get-AppxPackage -AllUsers -Name $app -ErrorAction SilentlyContinue)
    $prov      = @($provisioned | Where-Object { $_.DisplayName -eq $app })

    if ($installed.Count -eq 0 -and $prov.Count -eq 0) {
        Write-Log "  Not installed for any user and not provisioned."
        $results[$app] = 'Not present'
        continue
    }

    $systemPackage = $false
    foreach ($pkg in $installed) {
        if ($pkg.IsFramework -or $pkg.NonRemovable -or $pkg.SignatureKind -eq 'System') {
            Write-Log ("  {0} is a framework or system package. Windows does not allow removing it." -f $pkg.PackageFullName) 'WARN'
            $systemPackage = $true
            continue
        }
        try {
            # Pass PackageFullName explicitly. Piping AllUsers objects straight into Remove-AppxPackage is unreliable.
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            Write-Log ("  Removed for all users: {0}" -f $pkg.PackageFullName)
        } catch {
            Write-Log ("  Remove failed for {0}. {1}" -f $pkg.PackageFullName, $_.Exception.Message) 'ERROR'
        }
    }

    foreach ($p in $prov) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
            Write-Log ("  Removed provisioned package (new users): {0}" -f $p.PackageName)
        } catch {
            Write-Log ("  Provisioned remove failed for {0}. {1}" -f $p.PackageName, $_.Exception.Message) 'ERROR'
        }
    }

    # Verify instead of assuming success
    $left = @(Get-AppxPackage -AllUsers -Name $app -ErrorAction SilentlyContinue |
        Where-Object { -not ($_.IsFramework -or $_.NonRemovable -or $_.SignatureKind -eq 'System') })
    $leftProv = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $app })

    if ($left.Count -gt 0 -or $leftProv.Count -gt 0) {
        Write-Log ("  Still present after removal: {0} installed, {1} provisioned." -f $left.Count, $leftProv.Count) 'ERROR'
        $results[$app] = 'FAILED'
        $script:Failures++
    } elseif ($systemPackage) {
        $results[$app] = 'FAILED (system package, not removable)'
        $script:Failures++
    } else {
        $results[$app] = 'Removed'
    }
}

# --- Optional: DisableReinstall -----------------------------------------------
if ($option -eq 'DisableReinstall') {
    Write-Log "Applying DisableReinstall settings."

    # Consumer features (suggested app installs). Honored on Enterprise and Education editions.
    Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Value 1

    # SilentInstalledAppsEnabled is a per-user setting, so apply it to every loaded user hive
    $userHives = @(Get-ChildItem -Path 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$' })
    if ($userHives.Count -eq 0) {
        Write-Log "No user profiles are loaded. SilentInstalledAppsEnabled was not set for any user." 'WARN'
    }
    foreach ($hive in $userHives) {
        $cdm = "Registry::HKEY_USERS\{0}\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -f $hive.PSChildName
        Set-RegDword -Path $cdm -Name 'SilentInstalledAppsEnabled' -Value 0
    }
}

# --- Summary ------------------------------------------------------------------
Write-Log "Summary:"
foreach ($key in $results.Keys) {
    Write-Log ("  {0}: {1}" -f $key, $results[$key])
}

if ($script:Failures -gt 0) {
    Write-Log ("Completed with {0} failure(s)." -f $script:Failures) 'ERROR'
    exit 1
}

Write-Log "Completed. All requested apps removed or not present."
exit 0
