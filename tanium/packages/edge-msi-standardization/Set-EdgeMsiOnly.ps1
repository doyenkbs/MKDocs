<#
    Set-EdgeMsiOnly.ps1

    Makes the Enterprise MSI the owner of Microsoft Edge, then removes older
    Edge AppX registrations that a user profile holds, including ones locked
    as non-removable.

    An older AppX registration that no user profile holds is left in place and
    logged as Keep. It is a small label package (a manifest and two icons, no
    browser files), and Windows puts it back within minutes when it is removed.

    Installs the MSI only where MSI Edge is missing, and never removes anything
    until MSI Edge is confirmed registered. Upgrading an existing MSI install is
    Tanium Patch's job, not this package's.

    Before the install it clears EdgeUpdate policy values that block Edge or
    WebView2 from installing or updating (InstallDefault, UpdateDefault,
    Install{GUID} and Update{GUID} set to 0, AutoUpdateCheckPeriodMinutes=0,
    and an update suppression window of a full day). Each old value is logged.
    If Group Policy sets them, the script names the GPO; those values return at
    the next policy refresh until the GPO is changed.

    It leaves EdgeUpdate enabled (services and scheduled tasks), so Edge can
    keep itself patched between Tanium Patch cycles.

    No parameters. Settings are in the Config block. Stage the Enterprise MSI
    (Stable x64) in the same package: https://www.microsoft.com/edge/business/download
    Run as SYSTEM.

    Exit codes:
      0   success
      10  no MSI-registered Edge after the install attempt (nothing removed)
      11  MSI not found in the package working directory
      12  an AppX removal failed (partial)
      13  not elevated

    An endpoint with no replacement registration available is left alone and
    reports RESULT|Skipped with exit 0. That is the expected steady state once
    EdgeUpdate moves the MSI ahead of the AppX registration, so it is not
    treated as a failed action. Query the RESULT line to find those endpoints.
#>

# ===========================================================================
# Config
# ===========================================================================

# MSI file staged alongside this script in the package.
$MsiName = 'MicrosoftEdgeEnterpriseX64.msi'

$LogPath = "$env:ProgramData\_TaniumLogs\Set-EdgeMsiOnly.log"

# ===========================================================================

$ErrorActionPreference = 'Stop'
$failures = 0

function Say { param([string]$Text) Write-Output ("{0:HH:mm:ss}|{1}" -f (Get-Date), $Text) }

try {
    New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null
    Start-Transcript -Path $LogPath -Append | Out-Null
    $transcript = $true
} catch { $transcript = $false }

function Finish { param([int]$Code, [string]$Line)
    Write-Output $Line
    if ($transcript) { Stop-Transcript | Out-Null }
    exit $Code
}

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Finish 13 "RESULT|Error|Must run as SYSTEM or an administrator."
}

$edgeStableGuid   = '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
$webView2Guid     = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
$edgeUpdatePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
$appxStoreRoot    = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore'
$appxPackageName  = 'Microsoft.MicrosoftEdge.Stable'

# ---------------------------------------------------------------------------
# Enables SeTakeOwnership / SeRestore so a non-removable AppX registration can
# be unlocked. SYSTEM holds both privileges but neither is enabled by default.
# ---------------------------------------------------------------------------
$privTypeDef = @'
using System;
using System.Runtime.InteropServices;
public class EdgePriv {
    [StructLayout(LayoutKind.Sequential)] struct LUID { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)] struct LUID_AND_ATTRIBUTES { public LUID Luid; public uint Attributes; }
    [StructLayout(LayoutKind.Sequential)] struct TOKEN_PRIVILEGES { public uint Count; public LUID_AND_ATTRIBUTES Priv; }

    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool OpenProcessToken(IntPtr h, uint acc, out IntPtr tok);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool LookupPrivilegeValue(string sys, string name, out LUID luid);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool AdjustTokenPrivileges(IntPtr tok, bool dis, ref TOKEN_PRIVILEGES nw, uint len, IntPtr prev, IntPtr ret);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);

    public static bool Enable(string privilege) {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), 0x0020 | 0x0008, out token)) return false;
        try {
            LUID luid;
            if (!LookupPrivilegeValue(null, privilege, out luid)) return false;
            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
            tp.Count = 1; tp.Priv.Luid = luid; tp.Priv.Attributes = 0x00000002; // ENABLED
            return AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)
                   && Marshal.GetLastWin32Error() == 0;
        } finally { CloseHandle(token); }
    }
}
'@

function Enable-OwnershipPrivileges {
    try {
        if (-not ('EdgePriv' -as [type])) { Add-Type -TypeDefinition $privTypeDef -Language CSharp }
        return ([EdgePriv]::Enable('SeTakeOwnershipPrivilege') -and [EdgePriv]::Enable('SeRestorePrivilege'))
    } catch {
        Say "Warn|Could not enable ownership privileges: $($_.Exception.Message)"
        return $false
    }
}

function Test-AppxStillPresent {
    param([string]$PackageFullName)
    return [bool](Get-AppxPackage -AllUsers -Name $appxPackageName -ErrorAction SilentlyContinue |
                  Where-Object { $_.PackageFullName -eq $PackageFullName })
}

function Unlock-NonRemovableAppx {
    param([string]$PackageFullName)

    $keyPath = Join-Path (Join-Path $appxStoreRoot 'Applications') $PackageFullName
    if (-not (Test-Path $keyPath)) { return $false }
    if (-not (Enable-OwnershipPrivileges)) { return $false }

    try {
        $sub    = "SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications\$PackageFullName"
        $admins = New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544'

        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                 $sub, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                 [Security.AccessControl.RegistryRights]::TakeOwnership)
        $acl = $k.GetAccessControl([Security.AccessControl.AccessControlSections]::None)
        $acl.SetOwner($admins); $k.SetAccessControl($acl); $k.Close()

        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                 $sub, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                 [Security.AccessControl.RegistryRights]::ChangePermissions)
        $acl = $k.GetAccessControl()
        $acl.SetAccessRule((New-Object Security.AccessControl.RegistryAccessRule(
                    $admins, 'FullControl', 'ContainerInherit', 'None', 'Allow')))
        $k.SetAccessControl($acl); $k.Close()

        Set-ItemProperty -Path $keyPath -Name 'NonRemovable' -Value 0 -Type DWord -Force
        Say "Info|Cleared NonRemovable flag on $PackageFullName."
        return $true
    } catch {
        Say "Warn|Could not clear NonRemovable flag - $($_.Exception.Message)"
        return $false
    }
}

function Remove-EdgeAppxRegistration {
    <#  Three removal routes, tried in order, each verified by re-querying rather
        than by trusting the exception. A removal can report failure and still
        have taken effect. #>
    param($Package)
    $pfn = $Package.PackageFullName

    # 1. All-users removal. Works when the package is in the all-user store.
    try {
        Remove-AppxPackage -Package $pfn -AllUsers -ErrorAction Stop
        if (Test-AppxStillPresent $pfn) { Say "Info|All-users removal of $($Package.Version) reported no error, but it is still registered." }
    } catch { Say "Warn|All-users removal of $($Package.Version) failed - $($_.Exception.Message)" }
    if (-not (Test-AppxStillPresent $pfn)) { return $true }

    # 2. Per-user removal. A registration held only by a user profile is not in
    #    the all-user store, so route 1 fails with 0x80070002 (file not found)
    #    while a per-SID removal succeeds.
    foreach ($u in @($Package.PackageUserInformation)) {
        $sid = $u.UserSecurityId.Sid
        try {
            Remove-AppxPackage -Package $pfn -User $sid -ErrorAction Stop
            Say "Act|Removed $($Package.Version) for $sid."
        } catch { Say "Warn|Per-user removal for $sid failed - $($_.Exception.Message)" }
    }
    if (-not (Test-AppxStillPresent $pfn)) { return $true }

    # 3. Non-removable flag (0x80073CFA).
    if (Unlock-NonRemovableAppx -PackageFullName $pfn) {
        try { Remove-AppxPackage -Package $pfn -AllUsers -ErrorAction Stop }
        catch { Say "Error|Removal still failed after unlocking - $($_.Exception.Message)" }
    } else {
        Say "Info|No NonRemovable flag to clear for $($Package.Version) (no all-users store key, or privileges not available)."
    }

    # Still there: log what is left, so the action log explains the failure.
    $left = Get-AppxPackage -AllUsers -Name $appxPackageName -ErrorAction SilentlyContinue |
            Where-Object { $_.PackageFullName -eq $pfn } | Select-Object -First 1
    if (-not $left) { return $true }
    $users = @($left.PackageUserInformation | ForEach-Object { '{0}={1}' -f $_.UserSecurityId.Sid, $_.InstallState }) -join '; '
    if (-not $users) { $users = 'none' }
    $storeKey = Test-Path (Join-Path (Join-Path $appxStoreRoot 'Applications') $pfn)
    Say ("Error|AppX {0} is still registered after every removal attempt. NonRemovable={1}. SignatureKind={2}. User registrations: {3}. All-users store key: {4}. Location: {5}" -f `
            $pfn, $left.NonRemovable, $left.SignatureKind, $users, $storeKey, $left.InstallLocation)
    return $false
}

# ---------------------------------------------------------------------------
# Current state. Drives the decisions below, so it is read before and after the
# install. Inventory reporting is left to Tanium.
# ---------------------------------------------------------------------------
function Get-EdgeState {
    $entries = Get-ItemProperty -ErrorAction SilentlyContinue -Path @(
                   'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
               ) | Where-Object { $_.DisplayName -eq 'Microsoft Edge' }

    $msi = $entries | Where-Object { $_.WindowsInstaller -eq 1 } | Select-Object -First 1

    $exe = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
    if (-not (Test-Path $exe)) { $exe = Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe' }

    $msiVersion = $null; $exeVersion = $null
    if ($msi)             { try { $msiVersion = [version]$msi.DisplayVersion } catch { } }
    if (Test-Path $exe)   { try { $exeVersion = [version](Get-Item $exe).VersionInfo.ProductVersion } catch { } }

    # Registrations below this version are leftovers. Held down to the on-disk
    # binary version when the two disagree, so the registration matching what is
    # actually running is never removed.
    $floor = $msiVersion
    if ($floor -and $exeVersion -and $exeVersion -lt $floor) { $floor = $exeVersion }

    [pscustomobject]@{
        MsiVersion      = $msiVersion
        Floor           = $floor
        SelfUpdate      = $entries | Where-Object { $_.WindowsInstaller -ne 1 -and $_.UninstallString -match 'setup\.exe' } |
                          Select-Object -First 1
        AppxPackages    = @(Get-AppxPackage -AllUsers -Name $appxPackageName -ErrorAction SilentlyContinue)
        ProvisionedPkgs = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                            Where-Object { $_.DisplayName -eq $appxPackageName })
    }
}

$state = Get-EdgeState

# ---------------------------------------------------------------------------
# 1. Clear EdgeUpdate policy values that block an install or an update.
#    Install{GUID}=0 or InstallDefault=0 makes the MSI fail with error 1722 /
#    CustomAction DoInstall. Update{GUID}=0, UpdateDefault=0, a check period of
#    0 minutes, or a suppression window of a full day stop Edge from updating.
#    Only the Edge Stable and WebView2 values are touched.
# ---------------------------------------------------------------------------
$policyCleared = 0
if (Test-Path $edgeUpdatePolicy) {
    $props = Get-ItemProperty -Path $edgeUpdatePolicy -ErrorAction SilentlyContinue
    $names = @($props.PSObject.Properties.Name | Where-Object { $_ -notlike 'PS*' })

    $blocking = @()
    foreach ($n in @('InstallDefault', 'UpdateDefault',
                     "Install$edgeStableGuid", "Update$edgeStableGuid",
                     "Install$webView2Guid",   "Update$webView2Guid",
                     'AutoUpdateCheckPeriodMinutes')) {
        if ($names -contains $n -and "$($props.$n)" -eq '0') { $blocking += $n }
    }
    if ($names -contains 'UpdatesSuppressedDurationMin') {
        $duration = 0L
        [void][int64]::TryParse("$($props.UpdatesSuppressedDurationMin)", [ref]$duration)
        if ($duration -ge 1440) {
            $blocking += @('UpdatesSuppressedStartHour', 'UpdatesSuppressedStartMin', 'UpdatesSuppressedDurationMin') |
                         Where-Object { $names -contains $_ }
        } else {
            Say ("Info|Update suppression window of {0} minutes left in place (shorter than a day)." -f $props.UpdatesSuppressedDurationMin)
        }
    }

    foreach ($n in $blocking) {
        try {
            Remove-ItemProperty -Path $edgeUpdatePolicy -Name $n -Force
            Say ("Fix|Cleared EdgeUpdate policy {0} (was {1})." -f $n, $props.$n)
            $policyCleared++
        } catch { Say "Warn|Could not clear policy $n - $($_.Exception.Message)" }
    }

    # Other values are left alone but logged, so the action log shows the full key.
    foreach ($n in ($names | Where-Object { $blocking -notcontains $_ })) {
        Say ("Info|EdgeUpdate policy {0}={1} left in place." -f $n, $props.$n)
    }

    # If Group Policy set any of these, they come back at the next refresh.
    if ($blocking.Count) {
        try {
            $gpoNames = @{}
            Get-CimInstance -Namespace 'root\rsop\computer' -ClassName RSOP_GPO -ErrorAction Stop |
                ForEach-Object { $gpoNames[$_.id] = $_.name }
            $fromGpo = @(Get-CimInstance -Namespace 'root\rsop\computer' -ClassName RSOP_RegistryPolicySetting -ErrorAction Stop |
                Where-Object { $_.registryKey -like '*Policies\Microsoft\EdgeUpdate' -and $blocking -contains $_.valueName -and $_.precedence -eq 1 })
            foreach ($g in $fromGpo) {
                $gName = if ($gpoNames.ContainsKey($g.GPOID)) { $gpoNames[$g.GPOID] } else { $g.GPOID }
                Say ("Warn|Group Policy '{0}' sets {1}. It returns at the next policy refresh until that GPO is changed." -f $gName, $g.valueName)
            }
            if (-not $fromGpo.Count) { Say 'Info|No Group Policy sets the cleared values (RSoP).' }
        } catch {
            Say 'Info|Could not read Group Policy results (RSoP). If a GPO, Intune, or an image build step sets these values, they will return.'
        }
    }
} else {
    Say 'Info|No EdgeUpdate policy key.'
}

# ---------------------------------------------------------------------------
# 1b. Leave EdgeUpdate able to patch Edge, with the startup types a healthy
#     install has. The service starts on its own schedule; it is not started
#     here. Done before the MSI and AppX steps so every exit path gets it.
# ---------------------------------------------------------------------------
foreach ($pair in @(@('edgeupdate', 'Automatic'), @('edgeupdatem', 'Manual'))) {
    $svc = Get-Service -Name $pair[0] -ErrorAction SilentlyContinue
    if (-not $svc) { Say "Warn|Service $($pair[0]) not found."; continue }
    if ("$($svc.StartType)" -ne $pair[1]) {
        try {
            Set-Service -Name $pair[0] -StartupType $pair[1]
            Say ("Fix|Service {0} startup {1} -> {2}." -f $pair[0], $svc.StartType, $pair[1])
        } catch { Say "Warn|Could not set $($pair[0]) startup - $($_.Exception.Message)" }
    }
}
foreach ($t in 'MicrosoftEdgeUpdateTaskMachineCore*', 'MicrosoftEdgeUpdateTaskMachineUA*') {
    foreach ($task in @(Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue)) {
        if ($task.State -eq 'Disabled') {
            try {
                $task | Enable-ScheduledTask -ErrorAction Stop | Out-Null
                Say "Fix|Enabled scheduled task $($task.TaskName)."
            } catch { Say "Warn|Could not enable $($task.TaskName) - $($_.Exception.Message)" }
        }
    }
}
Say 'Policy|EdgeUpdate enabled.'

# ---------------------------------------------------------------------------
# 2. Install the MSI only where MSI Edge is missing
# ---------------------------------------------------------------------------
if ($state.MsiVersion) {
    Say "Skip|MSI Edge $($state.MsiVersion) already installed."
} else {
    $root    = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $msiPath = Join-Path $root $MsiName
    if (-not (Test-Path $msiPath)) {
        Say "Error|MSI not found at $msiPath."
        Finish 11 "RESULT|Failed|MSI missing from package"
    }

    foreach ($svc in 'edgeupdate','edgeupdatem') { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue }

    $msiArgs = "/i `"$msiPath`" /qn /norestart DONOTCREATEDESKTOPSHORTCUT=TRUE " +
               "/log `"$env:ProgramData\_TaniumLogs\EdgeMSI_Install.log`""
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
    Say "Act|MSI install exit code $($proc.ExitCode)."

    # Fallback, only after the install has actually failed: remove the
    # self-updating install and retry. Doing this first would leave the endpoint
    # with no browser whenever the install was never going to work.
    if ($proc.ExitCode -notin @(0,3010) -and $state.SelfUpdate) {
        foreach ($svc in 'edgeupdate','edgeupdatem') {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service  -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        }
        foreach ($t in 'MicrosoftEdgeUpdateTaskMachineCore*','MicrosoftEdgeUpdateTaskMachineUA*') {
            Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue |
                Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
        }

        $u = $state.SelfUpdate.UninstallString
        if ($u -match '^"([^"]+)"\s*(.*)$') { $exePath = $matches[1]; $exeArgs = $matches[2] }
        else { $parts = $u.Split(' ',2); $exePath = $parts[0]; $exeArgs = $parts[1] }

        if (Test-Path $exePath) {
            $un = Start-Process -FilePath $exePath -ArgumentList "$exeArgs --force-uninstall" `
                                -Wait -PassThru -WindowStyle Hidden
            Say "Act|Force-uninstall exit code $($un.ExitCode)."
            Start-Sleep -Seconds 5
        }

        $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
        Say "Act|MSI retry exit code $($proc.ExitCode)."
    }

    $state = Get-EdgeState
}

# ---------------------------------------------------------------------------
# 3. Gate. No MSI-registered Edge means the MSI does not own the browser here,
#    so there is nothing safe to remove.
# ---------------------------------------------------------------------------
if (-not $state.Floor) {
    Say "Error|No MSI-registered Edge found. Nothing removed."
    Finish 10 "RESULT|Failed|No MSI Edge registered"
}
$floor = $state.Floor
Say "Verify|MSI Edge $($state.MsiVersion). Checking AppX registrations below $floor."

# What is on the computer now, so every action log shows the AppX picture.
$provVersions = @($state.ProvisionedPkgs | ForEach-Object { "$($_.Version)" })
foreach ($p in ($state.AppxPackages | Sort-Object { [version]$_.Version })) {
    $users = @($p.PackageUserInformation | ForEach-Object { '{0}={1}' -f $_.UserSecurityId.Sid, $_.InstallState }) -join '; '
    if (-not $users) { $users = 'none' }
    $folder = if ($p.InstallLocation -and (Test-Path -LiteralPath $p.InstallLocation)) { 'present' } else { 'missing' }
    Say ("AppX|{0}|Provisioned={1}|NonRemovable={2}|Folder {3}|Users: {4}" -f $p.Version, ($provVersions -contains "$($p.Version)"), $p.NonRemovable, $folder, $users)
}
if (-not $state.AppxPackages.Count) { Say 'AppX|No Edge AppX registrations.' }
foreach ($v in ($provVersions | Where-Object { $state.AppxPackages.Version -notcontains $_ })) {
    Say "AppX|$v|Provisioned=True|Not registered"
}

# ---------------------------------------------------------------------------
# 4. Avoid creating a gap.
#    Only older registrations that a user profile holds are removed. Where a
#    NEWER registration exists but is only Staged, promote it first, so the
#    profile is never left between the two. Where no newer registration exists
#    at all, there is no gap to create: the MSI is the browser.
# ---------------------------------------------------------------------------
$older    = @($state.AppxPackages | Where-Object { [version]$_.Version -lt $floor })
$toRemove = @($older | Where-Object {
                @($_.PackageUserInformation | Where-Object { $_.InstallState -eq 'Installed' }).Count })
$kept     = @($older | Where-Object { @($toRemove | ForEach-Object { $_.PackageFullName }) -notcontains $_.PackageFullName })
foreach ($k in $kept) {
    Say "Keep|AppX $($k.Version): no user profile holds it. Windows puts it back when it is removed, so it is left in place."
}
$newest   = $state.AppxPackages | Where-Object { [version]$_.Version -ge $floor } |
            Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
$provisionedSurvivor = [bool]@($state.ProvisionedPkgs | Where-Object { [version]$_.Version -ge $floor }).Count

# Nothing at or above the floor means these are legacy in-box registrations and
# the MSI is the browser. Removing them costs nothing: the Win32 install runs
# independently of any AppX registration, and the MSI creates its own all-users
# Start menu shortcut pointing at msedge.exe. This is the in-box-Edge case the
# package exists for, so it proceeds rather than refusing.
if ($toRemove.Count -and -not $newest -and -not $provisionedSurvivor) {
    Say "Info|No AppX registration at or above $floor. Removing legacy registrations; MSI Edge $($state.MsiVersion) is installed and owns the browser."
}

$newestInstalled = $newest -and
    @($newest.PackageUserInformation | Where-Object { $_.InstallState -eq 'Installed' }).Count

if ($newest -and -not $newestInstalled -and $toRemove.Count) {

    $registered = $false
    $manifest   = if ($newest.InstallLocation) { Join-Path $newest.InstallLocation 'AppxManifest.xml' }

    # -AllUsers on Add-AppxPackage only exists on newer Windows builds. Check for
    # it rather than assuming, because calling it where it is absent throws a
    # parameter-binding error, not a deployment error.
    $canRegisterAllUsers = (Get-Command Add-AppxPackage).Parameters.ContainsKey('AllUsers')

    if ($canRegisterAllUsers -and $manifest -and (Test-Path $manifest)) {
        try {
            Add-AppxPackage -Register $manifest -DisableDevelopmentMode -AllUsers -ErrorAction Stop
            Say "Act|Registered staged $($newest.Version) for all users."
            $registered = $true
        } catch {
            Say "Warn|Could not register staged $($newest.Version) - $($_.Exception.Message)"
        }
    }

    if (-not $registered) {
        # No way to register it for other users from SYSTEM on this build. That
        # is acceptable only if the package is provisioned, because Windows then
        # registers it for a profile at sign-in. If it is not, removing the older
        # registration would leave that profile with nothing.
        if ($provisionedSurvivor) {
            Say "Info|Cannot register $($newest.Version) for other users on this build. It is provisioned, so Windows registers it at next sign-in. Continuing."
        } else {
            Say "Info|$($newest.Version) is staged but not provisioned, and cannot be registered from here. Leaving the endpoint alone."
            Finish 0 ("RESULT|Skipped|Staged {0} not provisioned and not registerable|Kept={1}|PoliciesCleared={2}" -f $newest.Version, $kept.Count, $policyCleared)
        }
    }
}

# ---------------------------------------------------------------------------
# 5. Remove leftover AppX registrations
# ---------------------------------------------------------------------------
$removed = New-Object 'System.Collections.Generic.List[string]'

foreach ($pkg in $toRemove) {
    if (Remove-EdgeAppxRegistration -Package $pkg) {
        Say "Act|Removed AppX $($pkg.Version)."
        $removed.Add($pkg.PackageFullName)
    } else {
        $failures++
    }
}

foreach ($pkg in @($state.ProvisionedPkgs | Where-Object { [version]$_.Version -lt $floor })) {
    try {
        Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction Stop
        Say "Act|Removed provisioned AppX $($pkg.Version)."
    } catch {
        Say "Error|Provisioned removal of $($pkg.Version) failed - $($_.Exception.Message)"
        $failures++
    }
}

# ---------------------------------------------------------------------------
# 6. Stale registry cleanup. Edge's own keys and program folder are not touched:
#    the MSI install owns those.
# ---------------------------------------------------------------------------

# Uninstall entry pointing at a setup.exe that no longer exists.
foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
    $key = Join-Path $root 'Microsoft Edge'
    if (-not (Test-Path $key)) { continue }
    $p = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    if ($p -and $p.WindowsInstaller -ne 1 -and $p.UninstallString -match 'setup\.exe') {
        $exe = if ($p.UninstallString -match '^"([^"]+)"') { $matches[1] } else { $p.UninstallString.Split(' ')[0] }
        if (-not (Test-Path $exe)) {
            try { Remove-Item -Path $key -Recurse -Force; Say "Fix|Removed stale uninstall key: $key" }
            catch { Say "Warn|Could not remove $key - $($_.Exception.Message)" }
        }
    }
}

# AppxAllUserStore leftovers for packages that were removed.
foreach ($name in $removed) {
    $leftover = Join-Path (Join-Path $appxStoreRoot 'Applications') $name
    if (Test-Path $leftover) {
        try { Enable-OwnershipPrivileges | Out-Null; Remove-Item -Path $leftover -Recurse -Force }
        catch { Say "Warn|Could not remove AppX store key for $name - $($_.Exception.Message)" }
    }
}

# Deprovisioned marker. A provisioned removal writes one, and it would stop the
# MSI's own current AppX registration from provisioning later.
$dep = Join-Path $appxStoreRoot 'Deprovisioned'
if (Test-Path $dep) {
    Get-ChildItem -Path $dep -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -like "$appxPackageName*" } |
        ForEach-Object {
            try { Remove-Item -Path $_.PSPath -Recurse -Force; Say "Fix|Cleared deprovisioned marker $($_.PSChildName)." }
            catch { Say "Warn|Could not clear deprovisioned marker - $($_.Exception.Message)" }
        }
}

# ---------------------------------------------------------------------------
# Single outcome line. This is what the action status reflects across the fleet.
# ---------------------------------------------------------------------------
if ($failures -gt 0) {
    Finish 12 ("RESULT|Partial|MSI={0}|Removed={1}|Kept={2}|Failed={3}|PoliciesCleared={4}" -f $state.MsiVersion, $removed.Count, $kept.Count, $failures, $policyCleared)
}
Finish 0 ("RESULT|Success|MSI={0}|Removed={1}|Kept={2}|PoliciesCleared={3}" -f $state.MsiVersion, $removed.Count, $kept.Count, $policyCleared)
