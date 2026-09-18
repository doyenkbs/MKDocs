---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Microsoft Edge
  - AppX
  - Patch Management
---

# Edge MSI Standardization

!!! note "Test status"
    Verified on Windows test machines: the MSI install on a device with no Edge, AppX removal by both the all-users and per-user routes, sign-in re-registration of a staged package, the deprovisioned-marker cleanup, the version-floor guard, the missing-MSI exit, and a clean idempotent second run. Not yet verified: the non-removable unlock path, which has not triggered on any test machine. Run it on a test machine matching your own image before any wider deployment.

A Tanium package that makes the Enterprise MSI the thing that owns Microsoft Edge on an endpoint, and clears leftover Microsoft Store (AppX) registrations, including ones marked non-removable.

It takes no parameters. The package contents are the configuration: the script plus the Enterprise MSI.

## The problem this solves

Windows ships an in-box copy of Edge that registers as an AppX package named `Microsoft.MicrosoftEdge.Stable`. If an image was built without the Enterprise MSI, the endpoint ends up with that in-box copy and no `EdgeUpdate` service, so the browser has no way to update itself and sits on whatever version the image was captured with. Vulnerability scanners keep reporting the old AppX version even after the MSI is pushed, because the old registration is still there.

Three things have to happen, in this order:

1. The Enterprise MSI has to own Edge on the endpoint.
2. That has to be verified before anything is removed.
3. Only then can the leftover AppX registrations and their registry entries be cleaned up.

Getting the order wrong is how endpoints end up with no browser at all.

---

## The MSI in the package decides everything

There is no version threshold to set and no parameter to keep up to date. The script reads the installed MSI Edge version from the registry and treats that as the line: any AppX registration older than it is a leftover, and anything at or above it is left alone.

More than one registration can exist at once. A real test VM carried three:

| Item | Version | Outcome |
|---|---|---|
| MSI Edge | `153.0.4234.32` | The line everything is measured against. |
| AppX installed | `144.0.3719.104` | Older than the MSI. Removed. |
| AppX installed | `152.0.4191.53` | Older than the MSI. Removed. |
| AppX installed | `153.0.4234.32` | Matches the MSI. Kept. |
| AppX provisioned | `153.0.4234.32` | Matches the MSI. Kept. |

What is left is the registration the MSI owns and nothing else.

To move the fleet to a newer Edge, stage a newer MSI in the package. Nothing else changes.

### Two safety adjustments

If the registry says MSI Edge is on one version but `msedge.exe` on disk is older, the script uses the lower of the two. A registration matching the binary that is actually running is never removed on the strength of a registry value that disagrees with it.

This guard fires on real machines. One observed case: MSI Edge registered as `153.0.4234.48` while `msedge.exe` on disk was still `153.0.4234.32`, minutes after `EdgeUpdate` had updated the registration but before the binary caught up. The floor stayed at `.32`, so the matching AppX registration was left alone. Had the floor followed the registry to `.48`, that registration would have been targeted for removal on an endpoint that needed no work at all.

---

## The end state is no Store registration

On an endpoint where the only AppX registration is the in-box one and the MSI has taken over, the script removes that registration and nothing replaces it. `EdgeUpdate` and the MSI do not create AppX registrations, so the endpoint ends with none.

That is the intended outcome. The Store registration was never what made Edge work: the browser is the Win32 install under `C:\Program Files (x86)\Microsoft\Edge\Application`, and the MSI creates its own all-users Start menu shortcut pointing straight at `msedge.exe`.

```
C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk
  target: C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe
```

Because `EdgeUpdate` moves the MSI version ahead of any AppX registration over time, most endpoints eventually reach this state. An endpoint whose image carries a matching or newer registration keeps it.

!!! warning "Verify this suits your environment"
    What else in Windows keys off the Edge AppX package identity has not been fully established: the app execution alias, the default-apps page, and on Windows 11 the search and widget surfaces are candidates. Edge itself runs regardless. On the first endpoint you remediate, check that Edge opens from the Start menu, that Settings, Default apps still lets you set it, and that a link clicked in another application opens it.

---

## Staged packages and sign-in

The registration matching the MSI is often `Staged` and held only by `SYSTEM`, while an older registration is the one a user profile actually holds `Installed`. Removing the older one first would leave the profile with nothing, so the script tries to promote the newer one before removing anything.

`Add-AppxPackage -Register ... -AllUsers` does that in one step, but the `-AllUsers` parameter does not exist on every Windows build. The script checks for it with `(Get-Command Add-AppxPackage).Parameters.ContainsKey('AllUsers')` rather than assuming, because calling it where it is absent raises a parameter-binding error, not a deployment error.

Where the parameter is missing, the script relies on the package being provisioned. Windows registers a provisioned package for a profile at sign-in. Verified on a test VM:

| When | Registration state |
|---|---|
| Before the run | `152.0.4191.53` Installed for the user, `153.0.4234.32` Staged for SYSTEM |
| Immediately after | `153.0.4234.32` Staged for SYSTEM only |
| After sign out and sign in | `153.0.4234.32` Installed for the user |

Edge remained usable throughout, because the browser is the Win32 MSI install and does not depend on the AppX registration to run.

---

## What it does

| Step | Action |
|---|---|
| 1 | Clears `EdgeUpdate` policy values that block installs (`InstallDefault=0`, `Install{GUID}=0`). |
| 2 | If MSI Edge is already installed, keeps it and installs nothing. If it is not, installs the MSI staged in the package. |
| 3 | If that install fails, and only then, force-uninstalls the self-updating install and retries. |
| 4 | Confirms MSI Edge is registered. If it is not, stops. Nothing is removed. |
| 5 | Promotes a newer staged registration where one exists, so no profile is left between two packages. |
| 6 | Removes AppX registrations older than the installed MSI version. |
| 7 | Removes narrowly scoped stale registry entries. |
| 8 | Leaves `EdgeUpdate` enabled or disabled, per the Config section. |

This package installs Edge where it is missing. It does not upgrade an existing MSI install. Patching machines that already have MSI Edge is Tanium Patch's job, or `EdgeUpdate`'s.

The script reads endpoint state twice, before and after the install, because that state drives its decisions. It does not report that state back. Inventory questions about Edge and AppX belong in Interact, not in an action log.

---

## Who owns patching afterward

`$KeepEdgeUpdate = $true` (the default) leaves the `EdgeUpdate` service and its scheduled tasks running, so Edge can self-patch between Tanium cycles.

`$KeepEdgeUpdate = $false` stops and disables the service, disables the update tasks, and writes `Update{GUID}=0` under `HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate`. Tanium then becomes the only path by which Edge gets patched.

The second option is a real choice with a real cost. An endpoint with no update service is exactly the condition that leaves machines stranded on an old build when a patch cycle is missed. Pick it only if Edge patch compliance is something you actively monitor.

---

## What it deliberately does not delete

Cleanup scripts for Edge circulating online remove these:

```
C:\Program Files (x86)\Microsoft\Edge
C:\ProgramData\Microsoft\EdgeUpdate
HKLM:\SOFTWARE\Microsoft\Edge
HKLM:\SOFTWARE\WOW6432Node\Microsoft\Edge
HKLM:\SOFTWARE\Microsoft\EdgeUpdate
HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate
```

That list is for wiping Edge off a machine entirely before a clean reinstall. Run it after the MSI is installed and it deletes the browser you just installed, along with its policy configuration. This script does not touch any of those paths.

What it does remove:

| Target | Condition |
|---|---|
| `...\Uninstall\Microsoft Edge` | Only when it is a non-MSI entry whose `setup.exe` no longer exists on disk. |
| `...\AppxAllUserStore\Applications\<PackageFullName>` | Only for packages it successfully removed. |
| `...\AppxAllUserStore\Deprovisioned\Microsoft.MicrosoftEdge.Stable*` | Always, after a provisioned removal. |

That last one matters. Removing a provisioned package writes a deprovisioned marker, and that marker would stop the MSI's own current AppX registration from provisioning later.

---

## Three removal routes

`Remove-AppxPackage` fails in more than one way, so the script tries three routes in order and checks the result of each by re-querying rather than by trusting whether an error was raised. A removal can report failure and still have taken effect, which was observed during testing.

1. **All-users removal.** Works when the package is in the all-user store.
2. **Per-user removal** for each SID in `PackageUserInformation`. A registration held only by a user profile is not in the all-user store, so route 1 fails with `0x80070002`, file not found, and the error text shows an empty source path (`... on Package ... from:` with nothing after it). A per-SID removal handles it.
3. **Clearing the non-removable flag**, for `0x80073CFA`, covered below.

If all three leave the package in place, that package is counted as a failure and the script continues with the rest, ending with exit 12.

### Clearing the non-removable flag

Where the package is marked as non-removable in the AppX store, the script:

1. Enabling `SeTakeOwnershipPrivilege` and `SeRestorePrivilege` in the process token. SYSTEM holds both, but neither is enabled by default.
2. Taking ownership of `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications\<PackageFullName>`.
3. Granting the local Administrators group full control of that key.
4. Setting `NonRemovable` to `0`.
5. Retrying the removal once.

If any of that fails, the script logs the reason, counts it as a failure, and carries on with the rest. It does not throw.

---

## Requirements

- Windows endpoints with PowerShell 5.1.
- The script runs as SYSTEM. It exits immediately if it is not elevated.
- The Microsoft Edge Enterprise MSI (Stable x64), staged in the same Tanium package. Download it from [https://www.microsoft.com/edge/business/download](https://www.microsoft.com/edge/business/download).

!!! info "No network access at run time"
    The script never downloads anything. It looks for `$MsiName` in the directory the action runs from, which is where Tanium extracts the package files, and calls `msiexec` against that local path. The download link above is for the person building the package, not for the endpoint.

    That makes it usable in air-gapped environments, and it avoids every endpoint pulling the same 150 MB installer across the WAN. The MSI moves once, through Tanium's own distribution, like any other package file.

---

## Configuration

Three settings, in the Config block at the top of the script. Edit them and repackage. Nothing is passed in at run time.

| Setting | Default | What it does |
|---|---|---|
| `$MsiName` | `MicrosoftEdgeEnterpriseX64.msi` | File name of the MSI staged in the package. Change this or rename the MSI to match. |
| `$KeepEdgeUpdate` | `$true` | Whether `EdgeUpdate` stays enabled after the run. See above. |
| `$LogPath` | `C:\ProgramData\_TaniumLogs\Set-EdgeMsiOnly.log` | Transcript location. |

---

## Output

Only decisions, actions, and failures are logged. The last line is always a single `RESULT`.

An in-box Edge endpoint, MSI installed by this run:

```
18:07:44|Act|MSI install exit code 0.
18:07:44|Verify|MSI Edge 153.0.4234.48. Removing AppX registrations below 153.0.4234.48.
18:27:25|Info|No AppX registration at or above 153.0.4234.48. Removing legacy registrations; MSI Edge 153.0.4234.48 is installed and owns the browser.
18:27:27|Act|Removed AppX 152.0.4191.66.
18:27:27|Fix|Cleared deprovisioned marker Microsoft.MicrosoftEdge.Stable_8wekyb3d8bbwe.
18:27:33|Policy|EdgeUpdate enabled.
RESULT|Success|MSI=153.0.4234.48|Removed=1
```

An endpoint where the matching registration was staged and provisioned:

```
17:35:35|Skip|MSI Edge 153.0.4234.32 already installed.
17:35:35|Verify|MSI Edge 153.0.4234.32. Removing AppX registrations below 153.0.4234.32.
17:35:36|Info|Cannot register 153.0.4234.32 for other users on this build. It is provisioned, so Windows registers it at next sign-in. Continuing.
17:35:37|Act|Removed AppX 152.0.4191.53.
17:35:42|Policy|EdgeUpdate enabled.
RESULT|Success|MSI=153.0.4234.32|Removed=1
```

A `Warn` line about an all-users removal failing is normal and not an error. It means route 1 did not apply and route 2 did the work.

The `RESULT` line and the exit code are what the action status reflects across the fleet, which is why they stay even though the same facts can be queried afterward. A failed action is visible immediately in Action History without running a question against every endpoint.

A full transcript is written to `C:\ProgramData\_TaniumLogs\Set-EdgeMsiOnly.log`, and the msiexec log to `C:\ProgramData\_TaniumLogs\EdgeMSI_Install.log`.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success. |
| 10 | No MSI-registered Edge after the install attempt. Nothing was removed. Investigate before retrying. |
| 11 | The MSI was not found in the package working directory. |
| 12 | MSI Edge is present, but one or more AppX removals failed. Partial success. |
| 13 | Not running as SYSTEM or an administrator. |

### `RESULT|Skipped` is not a failure

One narrow case returns `RESULT|Skipped` with **exit 0**: a newer registration exists but is only `Staged`, cannot be registered on that build, and is not provisioned. Removing the older registration there would strand the profile between two packages with nothing to restore it, so the script leaves the endpoint alone.

It returns exit 0 deliberately. A non-zero exit would mark the action failed in Tanium for an endpoint that is in a safe, deliberate state, and a wall of red across healthy endpoints trains people to ignore the exits that matter, 10 and 12. Find these endpoints by querying the `RESULT` line instead.

---

## Create the package

Menu labels can differ slightly between Tanium versions.

1. Save the script at the bottom of this page as `Set-EdgeMsiOnly.ps1`.
2. Download the Edge Enterprise MSI (Stable x64) and rename it to `MicrosoftEdgeEnterpriseX64.msi`, or change `$MsiName` in the script to match the file name you have.
3. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
4. Click **Create Package**.
5. Fill in the fields:
    - **Package Display Name:** `Edge MSI Standardization` (add your team's prefix if you use one).
    - **Content Set:** the content set your team uses for custom content.
    - **Command:**
      ```
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Set-EdgeMsiOnly.ps1
      ```
    - **Command Timeout:** `15` minutes.
6. Under **Files**, click **Add**, choose **Local File**, and upload both `Set-EdgeMsiOnly.ps1` and the MSI. Both must be in the same package, because the script looks for the MSI in the directory the action runs from.
7. Leave **Parameter Inputs** empty. This package takes none.
8. Click **Save**.

When a newer Edge build is needed, edit the package, replace the MSI file, and save. The script does not change.

---

## Deploy

1. Run against **one test VM** first, ideally one built from the same image as the endpoints you are targeting.
2. Confirm on that VM, in this order:
    - Edge opens and reports the expected version under `edge://settings/help`.
    - Only the MSI-matching registration is left:
      ```powershell
      Get-AppxPackage -AllUsers -Name Microsoft.MicrosoftEdge.Stable |
          Select-Object Version, @{n='Users';e={($_.PackageUserInformation | ForEach-Object { "$($_.UserSecurityId.Sid) [$($_.InstallState)]" }) -join '; '}}
      ```
    - The MSI is registered:
      ```powershell
      Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" |
          Where-Object { $_.DisplayName -eq "Microsoft Edge" } | Select-Object DisplayVersion, WindowsInstaller
      ```
3. **Sign out and sign back in, then run the registration query again.** Immediately after the run the surviving package may be `Staged` for `SYSTEM` only. It should come back `Installed` for the user SID. If it does not, stop and investigate before going further.
4. Expand to a pilot group, then the fleet, using **Distribute over** to spread the load. The MSI install is the expensive part.

To size the work before committing to a wide run, ask in Interact which endpoints have MSI Edge and which AppX versions are registered, and target from those results. The script does not report inventory back, because Interact already answers that better.

---

## Notes

- **Policy clearing is point in time.** If a GPO or Intune baseline sets `Install{GUID}=0` or `InstallDefault=0`, clearing it in the script only lasts until the next policy refresh. Raise it with whoever owns that policy if the failure recurs.
- **Fix the image, not just the endpoints.** If the golden image ships the in-box Store version instead of the Enterprise MSI, every newly recomposed machine comes back with the same gap. Updating the image is what stops this recurring.
- **Re-running is safe.** On an endpoint that is already correct, the script logs the state, finds nothing below the MSI version, and exits 0 without changing anything.

---

## Script

```powershell
<#
    Set-EdgeMsiOnly.ps1

    Makes the Enterprise MSI the owner of Microsoft Edge, then removes AppX
    registrations older than it, including ones locked as non-removable.

    Installs the MSI only where MSI Edge is missing, and never removes anything
    until MSI Edge is confirmed registered. Upgrading an existing MSI install is
    Tanium Patch's job, not this package's.

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

# $true  - EdgeUpdate keeps running, so Edge can self-patch between Tanium cycles.
# $false - EdgeUpdate is disabled and Tanium becomes the only patch path.
$KeepEdgeUpdate = $true

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
    try { Remove-AppxPackage -Package $pfn -AllUsers -ErrorAction Stop }
    catch { Say "Warn|All-users removal of $($Package.Version) failed - $($_.Exception.Message)" }
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
    }
    return (-not (Test-AppxStillPresent $pfn))
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
# 1. Clear EdgeUpdate policy values that block an install.
#    Install{GUID}=0 or InstallDefault=0 makes the MSI fail with error 1722 /
#    CustomAction DoInstall. If a GPO or Intune baseline sets these, clearing
#    them here only lasts until the next policy refresh.
# ---------------------------------------------------------------------------
if (Test-Path $edgeUpdatePolicy) {
    foreach ($name in @("Install$edgeStableGuid", 'InstallDefault')) {
        $props = Get-ItemProperty -Path $edgeUpdatePolicy -ErrorAction SilentlyContinue
        if ($props -and ($props.PSObject.Properties.Name -contains $name) -and ($props.$name -eq 0)) {
            try {
                Remove-ItemProperty -Path $edgeUpdatePolicy -Name $name -Force
                Say "Fix|Cleared blocking policy $name=0."
            } catch { Say "Warn|Could not clear policy $name - $($_.Exception.Message)" }
        }
    }
}

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
Say "Verify|MSI Edge $($state.MsiVersion). Removing AppX registrations below $floor."

# ---------------------------------------------------------------------------
# 4. Avoid creating a gap.
#    Where a NEWER registration exists but is only Staged, promote it before
#    removing the older one a user actually holds, so the profile is never left
#    between the two. Where no newer registration exists at all, there is no gap
#    to create: the older entries are legacy and the MSI is the browser.
# ---------------------------------------------------------------------------
$toRemove = @($state.AppxPackages | Where-Object { [version]$_.Version -lt $floor })
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

if ($newest -and
    -not (@($newest.PackageUserInformation | Where-Object { $_.InstallState -eq 'Installed' }).Count)) {

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
            Finish 0 ("RESULT|Skipped|Staged {0} not provisioned and not registerable" -f $newest.Version)
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
# 7. Who owns patching from here
# ---------------------------------------------------------------------------
if ($KeepEdgeUpdate) {
    foreach ($svc in 'edgeupdate','edgeupdatem') { Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue }
    Start-Service -Name 'edgeupdate' -ErrorAction SilentlyContinue
    foreach ($t in 'MicrosoftEdgeUpdateTaskMachineCore*','MicrosoftEdgeUpdateTaskMachineUA*') {
        Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
    }
} else {
    foreach ($svc in 'edgeupdate','edgeupdatem') {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service  -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
    }
    foreach ($t in 'MicrosoftEdgeUpdateTaskMachineCore*','MicrosoftEdgeUpdateTaskMachineUA*') {
        Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
    }
    New-Item -Path $edgeUpdatePolicy -Force | Out-Null
    New-ItemProperty -Path $edgeUpdatePolicy -Name "Update$edgeStableGuid" -PropertyType DWord -Value 0 -Force | Out-Null
}
Say ("Policy|EdgeUpdate {0}." -f $(if ($KeepEdgeUpdate) {'enabled'} else {'disabled'}))

# ---------------------------------------------------------------------------
# Single outcome line. This is what the action status reflects across the fleet.
# ---------------------------------------------------------------------------
if ($failures -gt 0) {
    Finish 12 ("RESULT|Partial|MSI={0}|Removed={1}|Failed={2}" -f $state.MsiVersion, $removed.Count, $failures)
}
Finish 0 ("RESULT|Success|MSI={0}|Removed={1}" -f $state.MsiVersion, $removed.Count)
```
