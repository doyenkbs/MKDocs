---
tags:
  - Tanium
  - Microsoft Defender
  - Vulnerability Remediation
  - PowerShell
  - Packages
---

# Defender Vulnerability Remediation

A Windows machine is remediated for the 2026 Defender CVEs when its Defender platform is **4.18.26040.7 or later** and its engine is **1.1.26040.8 or later**. That applies even when another antivirus (for example CrowdStrike Falcon) is the active protection, because the scanner checks Defender's files, not whether Defender is protecting the machine.

This page covers how to find every affected machine with Tanium, which scenario each one is in, and the fix for each scenario.

!!! note "Test status"
    The questions on this page were run in a lab Tanium environment with Windows Server 2016, 2019, 2022, and 2025, Windows 10, and Windows 11 endpoints. Both packages were run locally on Windows 11 Pro to confirm their safety stops (exit code `2`). Neither package has been run through a Tanium action against a server yet. Test on one server before deploying wider.

---

## Fix levels

| CVE | Type | Component | Fixed in |
|---|---|---|---|
| CVE-2026-33825 | Elevation of privilege (CISA KEV) | Antimalware Platform | 4.18.26030.3011 |
| CVE-2026-45498 | Denial of service (CISA KEV) | Antimalware Platform | 4.18.26040.7 |
| CVE-2026-41091 | Elevation of privilege (CISA KEV) | Malware Protection Engine | 1.1.26040.8 |
| CVE-2026-45584 | Remote code execution | Malware Protection Engine | 1.1.26040.8 |

Platform 4.18.26040.7 covers both platform CVEs. Engine 1.1.26040.8 covers both engine CVEs. When a new Defender CVE is published, update this table and rerun [Find the scope](#find-the-scope).

---

## Why machines with another antivirus still get flagged

Installing a third-party antivirus does not uninstall Defender. Defender switches to passive or turns off, but its files stay on disk:

| Location | What is there |
|---|---|
| `C:\Program Files\Windows Defender\` | The copy that ships with Windows |
| `C:\ProgramData\Microsoft\Windows Defender\Platform\<version>\` | One folder per platform update |
| `C:\ProgramData\Microsoft\Windows Defender\Definition Updates\` | Engine and signatures |

When the `WinDefend` service is stopped, Defender stops updating and stops cleaning up its old platform folders. The files fall behind and match the CVE ranges.

In the lab, every machine with `WinDefend` running was on a fixed platform and kept only two or three recent `Platform` folders. Every machine with `WinDefend` stopped was on an old platform and was vulnerable:

| OS | WinDefend | Startup | Platform | Result |
|---|---|---|---|---|
| Windows Server 2019 | Running | Auto | 4.18.26080.4 | Fixed |
| Windows Server 2022 | Running | Auto | 4.18.26090.9 | Fixed |
| Windows Server 2022 | Stopped | Manual | 4.18.25110.6 (3 old folders) | Vulnerable |
| Windows Server 2016 | Stopped | Manual | Built-in copy only, no `Platform` folder | Vulnerable |
| Windows 11 | Stopped | Manual | 4.18.24080.9 (3 old folders) | Vulnerable |

---

## Sensors used on this page

| Sensor | What it answers |
|---|---|
| Microsoft Defender AntiMalware Details (built-in) | Engine Version, Product Version (platform), Service Enabled, Service State. Reads versions even when the service is stopped |
| Service Details (built-in) | Service Status and Startup Mode for `WinDefend` |
| Folder Contents[path] (built-in) | Which platform version folders exist on disk |
| File Exists[path] (built-in) | Whether `MsMpEng.exe` exists at a given path |
| Registry Value Data[key,value] (built-in) | Whether Defender is turned off by policy |
| Operating System (built-in) | Separates servers from workstations. The fix is different |
| [Defender - Computer Status](../sensors/defender-computer-status.md) (custom) | Running mode, protection state, tamper protection, signature age. Only answers when `WinDefend` is running |

---

## Find the scope

Build the target list from Tanium, not from the scanner ticket. Scanners miss machines that were offline, out of scope, or failing credentialed scans, and those machines are just as vulnerable.

Run these in **Interact**, in the question bar.

### 1. Versions and service state

```
Get Computer Name and Operating System and Microsoft Defender AntiMalware Details from all machines with Operating System contains Windows
```

Any row with Product Version below `4.18.26040.7`, or Engine Version below `1.1.26040.8`, is in scope.

An Engine Version of `0.0.0.0` usually means the service is not running, not that the engine is missing. An Operating System of Server 2016 with Product Version `0.0.0.0` usually means the built-in copy is still there but has never been updated.

### 2. Service status and startup mode

```
Get Computer Name and Operating System and Service Details from all machines with Service Details contains WinDefend
```

If the results include every service on each machine, type `WinDefend` in the **Filter by text** box above the results grid.

### 3. What is on disk

```
Get Computer Name and Operating System and Folder Contents[C:\ProgramData\Microsoft\Windows Defender\Platform] and File Exists[C:\Program Files\Windows Defender\MsMpEng.exe] from all machines with Operating System contains Windows
```

`MsMpEng.exe` is never directly in `C:\ProgramData\Microsoft\Windows Defender\`. Check `C:\Program Files\Windows Defender\MsMpEng.exe`, or a specific version folder such as `C:\ProgramData\Microsoft\Windows Defender\Platform\4.18.25110.6-0\MsMpEng.exe`.

### 4. Defender turned off by policy

```
Get Computer Name and Registry Value Data[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender,DisableAntiSpyware] from all machines with Operating System contains Windows
```

The sensor takes two parameters, Registry Key and Registry Value. The key works in full form (`HKEY_LOCAL_MACHINE\...`) or short form (`HKLM\...`). Use `(Default)` as the value name to read a key's default value.

It returns five columns (User, Data, Type, Architecture, KeyPath) and two rows per machine, one for the 32-bit registry view and one for the 64-bit view. Read the **64-bit** row.

| User column | Data column | What it means |
|---|---|---|
| Key/Value not found | (empty) | Policy is not set. Defender is not turned off by this policy |
| N/A | `0` | Policy is set but does not turn Defender off |
| N/A | `1` | Defender is turned off by policy (Group Policy, Intune, or a local setting) |
| N/A on Linux | (empty) | Not a Windows machine. Ignore it |

Keep the `with Operating System contains Windows` filter. Without it, Linux machines come back as `N/A on Linux` rows.

### 5. Protection state

```
Get Computer Name and Defender - Computer Status from all machines with Operating System contains Windows
```

Use the results of questions 1 to 4 to place each machine in a scenario below.

---

## Scenarios

The `WinDefend` service status decides the fix. Match each machine to one row, then follow the fix with that letter.

| # | WinDefend | Startup | Other signs | What it means | Fix |
|---|---|---|---|---|---|
| 1 | Running | Auto | Running Mode `Normal`, versions at or above fix level | Defender is active and updating | None. Compliant |
| 2 | Running | Auto | Running Mode `Passive` or `EDR Block Mode`, versions at or above fix level | Another antivirus is primary, Defender is onboarded to Defender for Endpoint and still updating | None. Compliant |
| 3 | Running | Auto | Normal or Passive, platform or engine below fix level | Defender is running but its updates are failing or blocked | [A](#fix-a-update-defender) |
| 4 | Running | Auto | Platform at fix level, engine below `1.1.26040.8` | Security intelligence updates are failing. The engine ships with them | [A](#fix-a-update-defender) |
| 5 | Running | Auto | Server 2016, no `Platform` folder, `MsMpEng.exe` only in `C:\Program Files\Windows Defender\` | Built-in copy that never received a platform update | [A](#fix-a-update-defender) |
| 6 | Stopped | Manual | Windows 10 or 11, another antivirus installed | Windows turned Defender off when the other antivirus registered. Updates stopped | [B](#fix-b-workstation-with-defender-turned-off) |
| 7 | Stopped | Manual | Windows Server | Defender turned off on a server. Updates stopped | [C](#fix-c-remove-defender-from-a-server), then [D](#fix-d-delete-leftover-platform-folders) if folders remain |
| 8 | Stopped | Disabled | Any, often with `DisableAntiSpyware` set to `1` | Defender turned off by policy or by hand. Updates stopped | Server: [C](#fix-c-remove-defender-from-a-server) then [D](#fix-d-delete-leftover-platform-folders). Workstation: [B](#fix-b-workstation-with-defender-turned-off) |
| 9 | Not present | (none) | No `WinDefend` service, but folders remain under `C:\ProgramData\Microsoft\Windows Defender\Platform\` | Feature was removed, old files left behind | [D](#fix-d-delete-leftover-platform-folders) |
| 10 | Not present | (none) | No `WinDefend` service, no `MsMpEng.exe`, no `Platform` folder | Defender is gone. The scanner is matching something else | [E](#fix-e-scanner-flag-with-no-defender-files) |
| 11 | Any | Any | Custom sensor returns `Error:`, versions show `0.0.0.0` | Defender can't be read, usually because the service is stopped | Recheck with questions 1 to 3, then use row 6, 7, or 8 |

If a machine has `DisableAntiSpyware` set to `1`, find and change the source of that policy before trying Fix A or B, or the setting comes back at the next policy refresh.

---

## Fixes

!!! warning "Removing Defender is a policy decision"
    Get approval from your security team before running Fix C or Fix D on any server.

### Fix A: Update Defender

Defender is running, so it can take updates. The update path is what is broken.

1. Check the update source. If machines use WSUS or another patch tool, confirm these are approved:
    - **Microsoft Defender Antivirus** platform update (KB4052623)
    - **Definition Updates** for Microsoft Defender Antivirus. These carry the engine
2. Force an engine and signature update with a package that runs:
    ```
    "%ProgramFiles%\Windows Defender\MpCmdRun.exe" -SignatureUpdate
    ```
3. If the platform is still behind, download the KB4052623 x64 platform installer from the Microsoft Update Catalog and deploy it as a package. Confirm the installer name and any switches from the catalog entry before building the package.
4. Rerun [question 1](#1-versions-and-service-state). Product Version should be at or above `4.18.26040.7` and Engine Version at or above `1.1.26040.8`.

### Fix B: Workstation with Defender turned off

`Uninstall-WindowsFeature` only exists on Windows Server. Defender can't be removed from Windows 10 or 11, so the files have to be updated instead.

1. Test the KB4052623 platform installer as a package on one workstation. A platform update may not install while `WinDefend` is stopped, so confirm it on one machine first.
2. Rerun [question 1](#1-versions-and-service-state) and [question 3](#3-what-is-on-disk) on that machine. A new `4.18.26xxx` folder and a Product Version at or above `4.18.26040.7` mean it worked.
3. If the platform update does not install, there are two options. Both need security team approval:
    - Onboard the machine to Defender for Endpoint so Defender runs in passive mode and updates itself (scenario 2).
    - Document a risk exception: the other antivirus is active, `WinDefend` is stopped, and Defender can't be removed from the OS.
4. The engine CVEs (CVE-2026-41091 and CVE-2026-45584) usually stay open until Defender is running again, because the engine updates through the service.

### Fix C: Remove Defender from a server

1. Get approval from the security team.
2. Confirm the other antivirus is running, so the server is not left with no protection. For CrowdStrike Falcon:
    ```
    Get Computer Name and Running Service from all machines with Running Service contains CSFalcon
    ```
    Every target server must come back. If one does not, fix the antivirus first.
3. [Create the Remove Windows Defender package](#create-the-packages).
4. Deploy it to one server first (see [Deploy a package](#deploy-a-package)).
5. Restart the server in a maintenance window. The script does not restart it.
6. After the restart, rerun [question 3](#3-what-is-on-disk). `C:\Program Files\Windows Defender\MsMpEng.exe` should return **File does not exist**.
7. If folders remain under `C:\ProgramData\Microsoft\Windows Defender\Platform\`, run [Fix D](#fix-d-delete-leftover-platform-folders).
8. Repeat on the remaining servers.

While waiting for approval, you can try the platform installer from Fix B step 1 to close the platform CVEs. The engine CVEs stay open until removal.

### Fix D: Delete leftover platform folders

Use only when the `WinDefend` service no longer exists (scenario 9, or after Fix C and a restart).

1. [Create the Remove Defender Platform Leftovers package](#create-the-packages).
2. Deploy it to one machine first. The script stops with exit code `2` if `WinDefend` still exists, so it can't break an installed Defender.
3. Rerun [question 3](#3-what-is-on-disk). The `Platform` folder should return **Folder does not exist**.

### Fix E: Scanner flag with no Defender files

1. Open the finding in the vulnerability scanner and copy its evidence field (the file path and version it matched).
2. Ask Tanium for that exact path:
    ```
    Get Computer Name and File Exists[<path from the scanner evidence>] from all machines with Computer Name contains "<hostname>"
    ```
3. If the file does not exist, send the Tanium result to the security team and request a rescan or closure of the finding.

---

## Packages

| Package | Used in | Exit codes |
|---|---|---|
| Remove Windows Defender | Fix C | `0` removed or nothing to remove, `3010` removed and restart required, `1` failed, `2` not a server |
| Remove Defender Platform Leftovers | Fix D | `0` removed or nothing to remove, `1` failed, `2` `WinDefend` still exists |

Neither script restarts the machine. Both restart themselves as 64-bit PowerShell if the Tanium client starts them as 32-bit.

In Action History, exit codes other than `0` can show as **Failed**. For `3010`, the removal worked and the server needs a restart. For `2`, the script stopped on purpose before changing anything.

### Create the packages

Menu labels can differ slightly between Tanium versions. Repeat these steps for each package.

1. Save the script from [Scripts](#scripts) with the file name in the table below.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package**.
4. Fill in the fields from the table below. **Content Set** is the content set your team uses for custom content.
5. Under **Files**, click **Add**, choose **Local File**, and upload the script.
6. Leave **Parameters** empty. These packages have no parameters.
7. Click **Save**.

| Field | Remove Windows Defender | Remove Defender Platform Leftovers |
|---|---|---|
| Package Display Name | `Remove Windows Defender` | `Remove Defender Platform Leftovers` |
| File | `Remove-WindowsDefender.ps1` | `Remove-DefenderPlatformLeftovers.ps1` |
| Command | `cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-WindowsDefender.ps1` | `cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-DefenderPlatformLeftovers.ps1` |
| Command Timeout | `30` minutes. Feature removal can take several minutes on a busy server | `10` minutes |

### Deploy a package

1. In **Interact**, ask a question that returns the target servers. Example:
    ```
    Get Computer Name and Operating System from all machines with Computer Name contains "<hostname>"
    ```
2. Select the servers in the results grid.
3. Click **Deploy Action**.
4. In **Deployment Package**, search for and select the package.
5. Leave the schedule as a one-time action.
6. Click **Show preview to continue**, review the targets, then click **Deploy Action**.

### View the results

Open the action from **Administration** > **Actions** > **Action History**, select an endpoint, and open its action log. The script output appears between the `Command Line` line and the `Completed` line.

Removal that needs a restart (illustrative):

```
2026-10-08 20:38:40 [INFO] Operating system: Microsoft Windows Server 2022 Datacenter
2026-10-08 20:38:41 [INFO] Removing: Windows-Defender
2026-10-08 20:40:12 [INFO] Removal succeeded. Restart required to finish.
```

Safety stop on a workstation:

```
2026-10-08 20:38:40 [INFO] Operating system: Microsoft Windows 11 Pro
2026-10-08 20:38:40 [ERROR] Workstation OS detected. Uninstall-WindowsFeature only exists on Windows Server. Nothing done.
```

Safety stop when Defender is still installed:

```
2026-10-08 20:38:41 [INFO] Target folder: 'C:\ProgramData\Microsoft\Windows Defender\Platform'
2026-10-08 20:38:41 [ERROR] WinDefend service still exists. Remove the Defender feature and restart first. Nothing deleted.
```

For many endpoints, ask the built-in **Tanium Action Log** sensor with the action ID from the top of the log:

```
Get Tanium Action Log[12345] from all machines
```

### Scripts

=== "Remove-WindowsDefender.ps1"

    ```powershell
    --8<-- "tanium/packages/remove-windows-defender/Remove-WindowsDefender.ps1"
    ```

=== "Remove-DefenderPlatformLeftovers.ps1"

    ```powershell
    --8<-- "tanium/packages/remove-defender-platform-leftovers/Remove-DefenderPlatformLeftovers.ps1"
    ```

---

## Verify and close

A machine is done when Tanium shows it in scenario 1, 2, or 10, or the scanner closes the finding after a rescan.

1. Rerun [question 1](#1-versions-and-service-state) and [question 3](#3-what-is-on-disk) against every machine you remediated.
2. Confirm each machine shows one of these:
    - Product Version at or above `4.18.26040.7` and Engine Version at or above `1.1.26040.8`.
    - `C:\Program Files\Windows Defender\MsMpEng.exe` returns **File does not exist** and the `Platform` folder returns **Folder does not exist**.
3. Request a rescan of those machines from the vulnerability scanner.
4. Compare the scanner's open findings with your Tanium list. A machine Tanium shows as vulnerable that the scanner does not list is a coverage gap. Check its last scan date and whether its credentialed scan succeeded.

---

## Sources

- [UpGuard: CVE-2026-33825](https://www.upguard.com/vulnerabilities/cve-2026-33825)
- [CIRCL: CVE-2026-33825](https://cve.circl.lu/cve/CVE-2026-33825)
- [Vulert: CVE-2026-41091 and CVE-2026-45498](https://vulert.com/blog/microsoft-defender-cve-2026-41091-cve-2026-45498/)
- [Penligent: CVE-2026-41091 fixed versions](https://www.penligent.ai/hackinglabs/?p=5347)
