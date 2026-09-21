---
description: Running the Phase 1, 2, and 3 in-place upgrade packages in Tanium Deploy, and recovering endpoints that stall mid-upgrade.
tags:
  - Tanium
  - Deploy
  - Windows 11
  - In-Place Upgrade
  - Troubleshooting
---

# Windows In-Place Upgrade with Tanium Deploy

This page covers upgrading Windows 10 or Windows 11 endpoints to a newer Windows 11 feature release using the predefined in-place upgrade packages in Tanium Deploy, and what to do when endpoints get stuck.

The examples use Windows 11 23H2 to 25H2. The same process applies to Windows 10 22H2 to Windows 11, only the build numbers change.

!!! note "Placeholder values"
    Computer names, tags, and deployment names on this page are examples (`WS-EXAMPLE-01`, `IPU-Stuck`). Replace them with your own.

---

## 1. How the upgrade works

Deploy splits the upgrade into three predefined packages. Each one only becomes applicable when the one before it has finished.

| Package | What it does |
|---|---|
| **Phase 1 - Pre-Cache** | Copies the Windows installation media to the endpoint and runs a compatibility scan (`setup.exe /compat ScanOnly`). |
| **Phase 2 - Re-Scan** | Runs the compatibility scan again. Use it after you fix whatever failed the Phase 1 scan (disk space, an incompatible app, a driver). |
| **Phase 3 - Upgrade** | Runs Windows Setup to perform the actual upgrade and restart. Only endpoints that passed the compatibility scan are eligible. |

Deploy tracks where each endpoint is in this process through a registry value that the packages read and write:

```
HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Tanium\Tanium Client\OSD
    Status                  (REG_SZ)
    TargetedBuildVersion    (REG_SZ)
```

The `Status` values you will see:

| Status value | Meaning |
|---|---|
| `Ready to Install` | Set by Phase 1 at the start of the run, before the media is extracted. If an endpoint stays here, Phase 1 failed during extraction. |
| `WIM File Copied` | Media is staged. Ready for a compatibility scan. This is the value Tanium documents for forcing a re-scan. |
| `Compat Scan OK` | Compatibility scan passed. Phase 3 treats the endpoint as eligible. |
| `Upgrade In Progress` | Phase 3 started Windows Setup. If the endpoint stays here and the build never changes, the upgrade stalled. |

`TargetedBuildVersion` holds the build the endpoint was staged for (for 25H2, `26200`). It tells you what the endpoint was **targeted** for, not what it is **running**.

Each time Phase 1 runs, it renames the existing `OSD` key to `OSD.1` (then `OSD.2`, `OSD.3`, and so on) and creates a fresh `OSD` key. If you need to know what state an endpoint was in before a re-run, look at those backup keys:

```powershell
Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Tanium\Tanium Client' | Where-Object Name -match '\\OSD' | ForEach-Object { $_.Name; Get-ItemProperty $_.PSPath | Select-Object Status, TargetedBuildVersion }
```

The only reliable proof the upgrade finished is the OS build number:

```
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\CurrentBuildNumber
```

| Windows version | Build |
|---|---|
| Windows 10 22H2 (final Windows 10 release) | 19045 |
| Windows 11 22H2 | 22621 |
| Windows 11 23H2 | 22631 |
| Windows 11 24H2 | 26100 |
| Windows 11 25H2 | 26200 |

### Phase 3 install verification

To see the rule, go to **Modules > Deploy > Software >** *Phase 3 package* **> Edit > Install Verification**. The 25H2 package uses two branches joined by OR:

**Branch A: Setup is staged and waiting to finish**

```
OSD\Status                                   = "Upgrade In Progress"
AND File Version c:\$Windows.~BT\Sources\setupprep.exe >= 10.0.26100.1
AND File Version c:\$Windows.~BT\Sources\setupprep.exe <  10.0.26201
AND PROCESSOR_ARCHITECTURE                   = "AMD64"
AND ( OSD\TargetedBuildVersion (WOW6432Node) = "26200"
      OR OSD\TargetedBuildVersion (native)   = "26200" )
```

**Branch B: The OS is on the new build**

```
CurrentVersion\CurrentBuildNumber   = "26200"
AND CurrentBuildNumber              >= "10240"
AND CurrentVersion\InstallationType = "Client"
AND PROCESSOR_ARCHITECTURE          = "AMD64"
```

!!! warning "Why Phase 3 shows Complete when nothing upgraded"
    Branch A counts an endpoint as installed once Windows Setup has launched and staged 25H2 media in `C:\$Windows.~BT`, **before** the restart that actually performs the upgrade. That is by design: Setup finishes the job on the next reboot.

    If the restart never happens, or the upgrade is interrupted or rolls back and leaves `Status = Upgrade In Progress` behind, the endpoint still matches Branch A. Deploy reports it **Complete** and treats Phase 3 as already installed, so re-deploying Phase 3 does nothing.

    Do not use the Deploy Complete count as your success number. The real success number is Branch B: `CurrentBuildNumber = 26200`. The stuck population is exactly "matches Branch A, fails Branch B." Section 3 has the question that finds them, and section 4 covers the fix.

---

## 2. Running the deployment

### Import the packages

1. Go to **Modules > Deploy > Software > Predefined Package Gallery**.
2. Search for `InPlace Upgrade to Windows 11`.
3. Import the three packages for your target version: **Phase1 - Pre-Cache** (or **Phase1 - Direct-Cache**), **Phase2 - Re-Scan**, and **Phase3 - Upgrade**.

### Add the Windows installation ISO to Phase 1

The **Phase1 - Pre-Cache** package ships with only the wrapper script. You add the Windows media and a full 7-Zip installer to the package yourself.

**What the script accepts as media** (it checks in this order and uses the first match):

| Media you attach | How the script finds it |
|---|---|
| ISO file | Any `*.iso` larger than 2 GB. The file name does not matter. If there are several, it uses the largest. |
| Extracted ISO contents | An `install.wim` larger than 2 GB plus `setup.exe`. Both are required. |
| ESD file | An `*.esd` larger than 2 GB. If it has no matching `setup.exe`, the script builds the media with DISM, using the image name set in the script's `$ImageName` parameter. Make sure that matches your edition. |

The ISO is the simplest option.

**What else the package needs for an ISO:** a full 7-Zip installer. The Tanium Client's built-in `7za.exe` cannot open ISO files, so the script extracts `7z.exe` and `7z.dll` from a 7-Zip installer you attach, then uses those. The installer file name has to match the script's pattern, `7z` or `7zip`, optional version digits, optional `-x64`, ending in `.msi` or `.exe`. These all work: `7z2409-x64.msi`, `7z1900.exe`, `7zip.msi`.

**Steps**

1. Download the Windows 11 ISO for the target version, language, and edition from your licensed source (for example, the Microsoft 365 admin center or Volume Licensing Service Center).
2. Download the full 7-Zip installer from `https://www.7-zip.org` (for example `7z2409-x64.msi`). Do not rename it to something outside the pattern above.
3. Go to **Modules > Deploy > Software**.
4. Click the **InPlace Upgrade to Windows 11 Version 25H2 - Phase1 - Pre-Cache** package, then click **Edit**.
5. Expand **Package Files** and click **Add Package Files**.
6. Choose **Local File**, browse to the ISO, and click **Open**. For a large ISO, you can host it on an internal web server and use **Remote File** with that URL instead.
7. Click **Add Package Files** again and add the 7-Zip installer the same way. If the package already has a `7Zip.msi` entry that points to an external URL your endpoints cannot reach, delete it first.
8. Click **Save**.

**What Phase 1 does on the endpoint**

1. Backs up any existing `OSD` key (to `OSD.1`, `OSD.2`, ...), creates a new one, and sets `Status = Ready to Install`.
2. **Deletes** `C:\deploy\Tanium\OS` if it exists, recreates it, and locks the ACLs to SYSTEM and Administrators.
3. Extracts the media into `C:\deploy\Tanium\OS`.
4. Runs the compatibility scan.
5. Writes its transcript to `<Tanium Client>\Tools\SoftwareManagement\logs\WinIPU\Win_PreCache.txt`.

!!! warning "Before you deploy"
    - **Antivirus exclusion:** the script notes require an antivirus exclusion for `C:\deploy`. Without it, EDR can quarantine or lock extracted setup files and break extraction or Setup. Request it before the rollout.
    - **Disk space:** the endpoint holds the ISO in the Deploy download cache *and* the extracted copy in `C:\deploy\Tanium\OS`, then needs working space for Setup. Target endpoints with plenty of free space on `C:` (20 GB or more is a reasonable floor).
    - **Anything else in `C:\deploy\Tanium\OS` is deleted** every time Phase 1 runs.

If the log shows `Please attach 7zip download to Phase1 Package`, the 7-Zip installer is missing or its name does not match the pattern. If it shows `Missing Setup.Exe. Package must have *BOTH* Install.wim and Setup.exe`, you attached extracted media without `setup.exe`.

!!! note "Direct-Cache"
    The **Phase1 - Direct-Cache** variant gets the media a different way and is meant for endpoints that cannot peer (remote and VPN users). Check that package's **Package Files** after import to see whether it also expects an ISO.

### Deploy Phase 1

1. Go to **Modules > Deploy > Deployments > Create Deployment**.
2. Select the Phase 1 package and your target computer group.
3. Run it well ahead of the upgrade date. It downloads the full media, so give it time on remote and VPN endpoints.
4. Watch the results. Endpoints that fail the scan show as **Update Ineligible**.

### Fix and re-scan (Phase 2)

1. Find out why the scan failed using the **Deploy - Windows Upgrade Scan Results** sensor (some content versions name it **Deploy - Windows Upgrade Scan Details**; search Interact for `Windows Upgrade Scan` if neither name matches).
2. Fix the blocker (free disk space, remove the incompatible app, update the driver).
3. Deploy the **Phase2 - Re-Scan** package to those endpoints.

### Deploy Phase 3

1. Create a deployment with the **Phase3 - Upgrade** package.
2. Turn on **End User Notification** with a restart prompt so users know a long restart is coming and do not power off mid-upgrade.
3. Set the deployment to **Ongoing**, or set the **End Time** well past the notification window plus the install time. If the window is too short you get:
   `Deployment ended before completing. Previous sub-status was "Waiting for notification".`
4. After it finishes, confirm the build number in Interact. Do not rely on the Complete count:
   ```
   Get Computer Name and Registry Value Data["HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion","CurrentBuildNumber"] and Registry Value Data["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] and Registry Value Data["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","TargetedBuildVersion"] from all machines
   ```
   Endpoints showing `26200` in the `CurrentBuildNumber` column finished. Anything still on the old build did not, whatever Deploy reports.

---

## 3. Interact questions

Run these from **Interact** (main menu > **Interact**), paste the question into the question bar, and press Enter.

**Fleet overview: current build, OSD status, and targeted build**

```
Get Computer Name and Registry Value Data["HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion","CurrentBuildNumber"] and Registry Value Data["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] and Registry Value Data["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","TargetedBuildVersion"] from all machines
```

**Stuck endpoints: status says Upgrade In Progress**

```
Get Computer Name and Registry Value Data["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] and Registry Value Data["HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion","CurrentBuildNumber"] from all machines with Registry Value Data["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] contains "Upgrade In Progress"
```

Any row where `CurrentBuildNumber` is still the old build (for example `22631`) is stuck. Rows already showing `26200` finished the upgrade and only have a stale status value.

**Is Windows Setup still running?**

```
Get Computer Name and Running Processes from all machines with Running Processes contains "SetupHost"
```

If `SetupHost.exe` (or `setup.exe`) is still running, the upgrade may still be working. Leave it alone and check again later.

**What Deploy thinks happened on a specific endpoint**

```
Get Deploy - Deployments from all machines with Computer Name contains "WS-EXAMPLE-01"
```

This shows every deployment on that endpoint and its result. It is the fastest way to explain why a package shows **Not Applicable** (for example, an earlier deployment already marked it Installed).

**Compatibility scan failures**

```
Get Computer Name and Deploy - Windows Upgrade Scan Results from all machines with Registry Value Data["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] contains "WIM File Copied"
```

**Do setup logs exist on the endpoint?**

```
Get Computer Name and File Exists["C:\$WINDOWS.~BT\Sources\Panther\setupact.log"] from all machines with Computer Name contains "WS-EXAMPLE-01"
```

!!! tip
    Sensor names can differ between Tanium content versions. If a sensor is not found, type part of the name in the Interact question bar and pick it from the suggestions.

---

## 4. Recovering a stuck endpoint

Symptom: `OSD\Status` = `Upgrade In Progress`, `CurrentBuildNumber` is still the old build, and re-running Phase 3 either shows **Not Applicable** or repeats a false **Complete**.

Why re-running Phase 3 does not fix it, for two reasons:

1. The endpoint still matches **Branch A** of the install verification (`Status = Upgrade In Progress` plus the staged `setupprep.exe` in `C:\$Windows.~BT\Sources`), so Deploy considers Phase 3 already installed.
2. Phase 3 only treats an endpoint as eligible when `OSD\Status` = `Compat Scan OK`.

Changing `Status` away from `Upgrade In Progress` breaks Branch A, and the Phase 2 re-scan brings it back to `Compat Scan OK`. That is what the steps below do.

### Step 1: Confirm Setup is dead

Run the **Is Windows Setup still running?** question from section 3. If `SetupHost.exe` is running, wait. Only reset endpoints where Setup is no longer running.

### Step 2: Tag the stuck endpoints

1. Run the **Stuck endpoints** question.
2. Select the rows where the build did not change.
3. Click **Deploy Action**, choose the **Custom Tagging - Add Tags** package, and add the tag `IPU-Stuck`.

This gives you a stable target for the next steps.

### Step 3: Reset the OSD status with Registry - Set Value

1. In Interact, ask:
   ```
   Get Online from all machines with Custom Tags contains "IPU-Stuck"
   ```
2. Select the results and click **Deploy Action**.
3. In **Deployment Package**, search for and select **Registry - Set Value**.
4. Fill in the parameters:

| Parameter | Value |
|---|---|
| OS Architecture | Match the targeted endpoints (see the note below) |
| Registry Key Name | `HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD` |
| Value Name | `Status` |
| Value Data | `WIM File Copied` |
| Value | `REG_SZ` |

5. Deploy to **one** endpoint first, then ask this question and confirm the `Status` column now reads `WIM File Copied`:
   ```
   Get Computer Name and Registry Value Data["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] and Registry Value Data["HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion","CurrentBuildNumber"] from all machines with Computer Name contains "WS-EXAMPLE-01"
   ```
   Once it looks right, deploy to the rest.

!!! warning "Test the key path on one endpoint first"
    Tanium's documented example enters the full `WOW6432Node` path in **Registry Key Name** and sets **OS Architecture** to match the endpoints. Another approach is to enter `HKEY_LOCAL_MACHINE\Software\Tanium\Tanium Client\OSD` with **OS Architecture = 32** and let Windows redirect it to `WOW6432Node`. Either way, verify on one endpoint that the value landed under `WOW6432Node` before targeting the group.

!!! note "Why WIM File Copied and not Compat Scan OK"
    Some guides reset the value straight to `Compat Scan OK` so Phase 3 picks the endpoint up immediately. That skips the compatibility scan, and the interrupted upgrade may have left the machine in a different state than when it last passed. `WIM File Copied` is the value Tanium documents for this reset, and it forces a fresh scan in Step 4. Use `Compat Scan OK` only if you have confirmed the endpoint is healthy and you accept skipping the re-scan.

### Step 4: Re-scan with Phase 2

1. Create a deployment with the **Phase2 - Re-Scan** package targeting the `IPU-Stuck` tag.
2. When it finishes, ask this question. Passing endpoints now show `Compat Scan OK`:
   ```
   Get Computer Name and Registry Value Data["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] and Registry Value Data["HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion","CurrentBuildNumber"] from all machines with Custom Tags contains "IPU-Stuck"
   ```
3. Endpoints that fail the scan need the fix in section 5 before going further.

### Step 5: Run Phase 3 again

1. Create a new Phase 3 deployment targeting the `IPU-Stuck` tag.
2. Enable **End User Notification** with a restart prompt.
3. Set the deployment to **Ongoing** or give it a long **End Time**.
4. Confirm success with this question. Every endpoint should show `26200`:
   ```
   Get Computer Name and Registry Value Data["HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion","CurrentBuildNumber"] and Registry Value Data["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] from all machines with Custom Tags contains "IPU-Stuck"
   ```
5. Remove the `IPU-Stuck` tag from the upgraded endpoints with **Custom Tagging - Remove Tags**.

---

## 5. Logs to check

### Find the Tanium Client folder

The Tanium Client install path varies. Get it on the endpoint with:

```powershell
(Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Tanium\Tanium Client').Path
```

On most endpoints it is `C:\Program Files (x86)\Tanium\Tanium Client`.

### Tanium Deploy logs

```
C:\Program Files (x86)\Tanium\Tanium Client\Tools\SoftwareManagement\logs\
```

Check `subprocess.log` first. Each command step in a Deploy package runs as a subprocess, and this log shows what was launched and the exit code.

List everything in the folder, newest first, to see which logs changed during the upgrade:

```powershell
$tc = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Tanium\Tanium Client').Path
Get-ChildItem "$tc\Tools\SoftwareManagement\logs" -Recurse | Sort-Object LastWriteTime -Descending | Select-Object LastWriteTime, Length, FullName -First 30
```

### In-place upgrade transcripts (WinIPU folder)

The in-place upgrade package scripts write PowerShell transcripts to:

```
C:\Program Files (x86)\Tanium\Tanium Client\Tools\SoftwareManagement\logs\WinIPU\
```

| File | Written by | What to look for |
|---|---|---|
| `Win_PreCache.txt` | Phase 1 | Which media it found (`Found ISO Image`, `Found Local Install.Wim`), 7-Zip extraction, and any `throw` message such as `Please attach 7zip download to Phase1 Package` |

The Phase 2 and Phase 3 scripts write their own transcripts to the same folder. File names can vary by package version, so list the folder to see what is there:

```powershell
$tc = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Tanium\Tanium Client').Path
Get-ChildItem "$tc\Tools\SoftwareManagement\logs\WinIPU" | Sort-Object LastWriteTime -Descending | Select-Object LastWriteTime, Length, Name
```

Read the end of the Phase 1 transcript:

```powershell
$tc = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Tanium\Tanium Client').Path
Get-Content "$tc\Tools\SoftwareManagement\logs\WinIPU\Win_PreCache.txt" -Tail 60
```

Check where the extracted media landed:

```powershell
Get-ChildItem 'C:\deploy\Tanium\OS' | Select-Object Name, Length
Test-Path 'C:\deploy\Tanium\OS\setup.exe'
```

### Windows Setup logs

| Log | Path | When to use it |
|---|---|---|
| `setupact.log` | `C:\$WINDOWS.~BT\Sources\Panther\setupact.log` | Full record of what Setup did before the first restart. Start at the bottom and read up. |
| `setuperr.log` | `C:\$WINDOWS.~BT\Sources\Panther\setuperr.log` | Errors only. Short, check it first. |
| `ScanResult.xml` | `C:\$WINDOWS.~BT\Sources\Panther\ScanResult.xml` | Compatibility scan results. Shows the app, driver, or hardware item that blocked the upgrade. |
| `CompatData_*.xml` | `C:\$WINDOWS.~BT\Sources\Panther\` | Detailed compatibility data per scan. |
| `setupact.log` (rollback) | `C:\$WINDOWS.~BT\Sources\Rollback\setupact.log` | Upgrade failed and Windows rolled back. |
| `setupapi.dev.log` (rollback) | `C:\$WINDOWS.~BT\Sources\Rollback\setupapi\setupapi.dev.log` | Driver install failures during rollback, often behind `0xC1900101`. |
| `setupact.log` (post-upgrade) | `C:\Windows\Panther\setupact.log` | Upgrade got past the first restart. |
| SetupDiag results | `C:\Windows\Logs\SetupDiag\SetupDiagResults.xml` | Windows Setup runs SetupDiag automatically on failure. Read this before the raw logs. |

Pull the last 50 lines of the setup error log remotely or in a local shell:

```powershell
Get-Content 'C:\$WINDOWS.~BT\Sources\Panther\setuperr.log' -Tail 50
```

Search the full log for the failure:

```powershell
Select-String -Path 'C:\$WINDOWS.~BT\Sources\Panther\setupact.log' -Pattern '0xC19|0x8007|Error' | Select-Object -Last 40
```

### Running SetupDiag manually

If `SetupDiagResults.xml` does not exist, download `SetupDiag.exe` from Microsoft and run it on the endpoint:

```cmd
SetupDiag.exe /Output:C:\Temp\SetupDiagResults.log
```

It reads the Panther and Rollback logs and names the rule that matched (driver, app, disk space).

---

## 6. Common Windows Setup error codes

Windows Setup errors come as a result code plus an extend code, for example `0xC1900101 - 0x20017`. The result code says what failed, the extend code says which phase.

| Code | Meaning | What to check |
|---|---|---|
| `0xC1900101 - 0x20017` | Failed in the SAFE_OS phase during boot | Almost always a driver. Look at third-party security, encryption, and storage drivers. |
| `0xC1900101 - 0x30018` | Failed during device installation | A device driver stopped responding. Check `setupapi.dev.log` in the Rollback folder. |
| `0xC1900101 - 0x4000D` / `0x40017` | Failed in SECOND_BOOT, rolled back | Driver or security software. Update or remove, then retry. |
| `0xC1900208` | Incompatible app blocking the upgrade | `ScanResult.xml` names the app. Remove or update it, then run Phase 2. |
| `0xC1900200` / `0xC1900202` | Hardware does not meet requirements | TPM, Secure Boot, CPU, or RAM. Not fixable with a re-scan alone. |
| `0x80070070` | Not enough disk space | Free at least 20 GB on `C:` and run Phase 2. |
| `0x80070002` / `0x80070003` | File or path not found | Staged media is missing or incomplete. Re-run Phase 1 to re-cache. |

---

## 7. Troubleshooting checklist

| Symptom | Likely cause | Fix |
|---|---|---|
| Phase 3 shows **Complete** but the build did not change | Endpoint matches Branch A of Install Verification (Setup staged, `Status = Upgrade In Progress`) but the upgrade never completed | Check `CurrentBuildNumber` with the Fleet overview question in [section 3](#3-interact-questions). Treat those endpoints as stuck (section 4). |
| Phase 3 shows **Not Applicable** | `OSD\Status` is not `Compat Scan OK` | Run the Fleet overview question in [section 3](#3-interact-questions). If it says `Upgrade In Progress`, follow section 4. |
| Phase 1 shows **Not Applicable** | An earlier deployment already marked the package Installed | Run `Get Deploy - Deployments` for that endpoint. The endpoint may already be eligible for Phase 3. |
| **Update Ineligible** after Phase 1 | Compatibility scan failed | Check the Scan Results sensor and `ScanResult.xml`, fix, run Phase 2. |
| `Deployment ended before completing ... Waiting for notification` | Deployment window too short for the notification plus install time | Set the deployment to Ongoing or extend the End Time. |
| Upgrade rolled back after restart | Driver or security software | Read `SetupDiagResults.xml`, then `Rollback\setupact.log`. |
| Stuck at `Upgrade In Progress`, `SetupHost.exe` running | Upgrade still working | Wait. Do not reset. |
| `Status` stays at `Ready to Install` after Phase 1 | Media extraction failed | Read `WinIPU\Win_PreCache.txt`. Usually a missing or misnamed 7-Zip installer, no ISO over 2 GB in the package, or antivirus blocking `C:\deploy`. |
| Phase 1 log: `Please attach 7zip download to Phase1 Package` | 7-Zip installer missing or file name does not match the pattern | Add a full 7-Zip installer named like `7z2409-x64.msi` to the package (section 2). |
| Phase 1 log: `Missing Setup.Exe` | Extracted media attached without `setup.exe` | Attach the ISO instead, or the complete extracted media. |

---

## References

- Tanium Deploy: Use case, Upgrading Windows (Tanium Resource Center)
- Tanium Deploy: Troubleshooting Deploy (Tanium Resource Center)
- Microsoft Learn: Resolve Windows upgrade errors, log files and error codes
- Microsoft Learn: SetupDiag
