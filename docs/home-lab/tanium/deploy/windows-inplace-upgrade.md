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

!!! info "No endpoint access needed"
    Every check on this page is written as a Tanium question you run from **Interact**, so an operator without direct or remote access to the endpoint can still troubleshoot. Where a PowerShell command is shown, it is an alternate for someone who does have access.

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

Each time Phase 1 runs, it renames the existing `OSD` key to `OSD.1` (then `OSD.2`, `OSD.3`, and so on) and creates a fresh `OSD` key. Check the current key, and the backup keys if you need to know what state an endpoint was in before a re-run:

=== "Tanium question"

    ```
    Get "Computer Name" and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","TargetedBuildVersion"] from all machines with "Computer Name" contains "WS-EXAMPLE-01"
    ```

    `OSD` is the current state and the only key on an endpoint that has run Phase 1 once. To see earlier runs, change `OSD` to `OSD.1` in both places, then `OSD.2`, and so on. `OSD.1` is the oldest run; the highest number is the run just before the current one. An empty result means that backup key does not exist.

=== "PowerShell (alternate)"

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

    Do not use the Deploy Complete count as your success number. The real success number is Branch B: `CurrentBuildNumber = 26200`. The stuck population is exactly "matches Branch A, fails Branch B." Section 3.2 covers how to find and fix them.

---

## 2. Running the deployment

### Import the packages

1. Go to **Modules > Deploy > Software > Predefined Package Gallery**.
2. Search for `InPlace Upgrade to Windows 11`.
3. Import the three packages for your target version: **Phase1 - Pre-Cache** (or **Phase1 - Direct-Cache**), **Phase2 - Re-Scan**, and **Phase3 - Upgrade**.

### Add the Windows installation ISO to Phase 1

The **Phase1 - Pre-Cache** package includes the wrapper script, the compatibility scan script, and a 7-Zip installer. It does **not** include Windows media. You add the ISO yourself.

**What the script accepts as media** (it checks in this order and uses the first match):

| Media you attach | How the script finds it |
|---|---|
| ISO file | Any `*.iso` larger than 2 GB. The file name does not matter. If there are several, it uses the largest. |
| Extracted ISO contents | An `install.wim` larger than 2 GB plus `setup.exe`. Both are required. |
| ESD file | An `*.esd` larger than 2 GB. If it has no matching `setup.exe`, the script builds the media with DISM, using the image name set in the script's `$ImageName` parameter. Make sure that matches your edition. |

The ISO is the simplest option.

**Why the package contains 7zip.msi:** the Tanium Client's built-in `7za.exe` cannot open ISO files, so the script extracts `7z.exe` and `7z.dll` from the 7-Zip installer in the package and uses those to unpack the ISO. 7-Zip is never installed on the endpoint; the two files go to `%TEMP%` and are deleted after extraction.

Tanium maintains the `7zip.msi` entry in the predefined package (its origin is `https://www.7-zip.org`), so you do not need to download or replace it. The Tanium Server downloads it and serves it to endpoints like any other package file.

**Steps**

1. Download the Windows 11 ISO for the target version, language, and edition from your licensed source (for example, the Microsoft 365 admin center or Volume Licensing Service Center).
2. Go to **Modules > Deploy > Software**.
3. Click the **InPlace Upgrade to Windows 11 Version 25H2 - Phase1 - Pre-Cache** package, then click **Edit**.
4. Expand **Package Files** and confirm **7zip.msi** is listed with a **Size** and **Sha-256**. That means the Tanium Server has it cached. Leave it as is.
5. Click **Add Package Files**.
6. Choose **Local File**, browse to the ISO, and click **Open**. For a large ISO, you can host it on an internal web server and use **Remote File** with that URL instead.
7. Click **Save**.

!!! note "Only if 7zip.msi is not cached"
    If your Tanium Server cannot reach `www.7-zip.org` (proxy or isolated network), the `7zip.msi` entry will not download and Phase 1 fails with `Please attach 7zip download to Phase1 Package`. In that case, download the 7-Zip x64 MSI from `https://www.7-zip.org` on a machine with internet access, delete the existing `7zip.msi` entry, and add the downloaded file with **Add Package Files > Local File**. Keep a name the script recognizes: `7z` or `7zip`, optional version digits, optional `-x64`, ending in `.msi` or `.exe` (for example `7z2409-x64.msi` or `7zip.msi`).

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

If the log shows `Please attach 7zip download to Phase1 Package`, the `7zip.msi` package file is missing or was not cached (see the note above). If it shows `Missing Setup.Exe. Package must have *BOTH* Install.wim and Setup.exe`, you attached extracted media without `setup.exe`.

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
3. Set the deployment to **Ongoing**, or set the **End Time** well past the notification window plus the install time. If the window is too short you get `Deployment ended before completing. Previous sub-status was "Waiting for notification".` (see [3.3](#33-deployment-ended-while-waiting-for-notification)).
4. After it finishes, confirm the build number in Interact. Do not rely on the Complete count:
   ```
   Get "Computer Name" and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion","CurrentBuildNumber"] and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","TargetedBuildVersion"] from all machines
   ```
   Endpoints showing `26200` in the `CurrentBuildNumber` column finished. Anything still on the old build did not, whatever Deploy reports.

---

## 3. Troubleshooting

Every check in this section is a Tanium question. Run it from **Interact** (main menu > **Interact**): paste the question into the question bar and press Enter. Replace `WS-EXAMPLE-01` with the endpoint name.

!!! tip
    Sensor names can differ between Tanium content versions. If a sensor is not found, type part of the name in the Interact question bar and pick it from the suggestions.

### 3.1 Check where an endpoint is

Start here for any problem. This shows the running build, the OSD status, and the build the endpoint was staged for:

```
Get "Computer Name" and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion","CurrentBuildNumber"] and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","TargetedBuildVersion"] from all machines with "Computer Name" contains "WS-EXAMPLE-01"
```

Remove the `with "Computer Name" contains ...` part to see the whole fleet.

| `CurrentBuildNumber` | `Status` | What it means | Go to |
|---|---|---|---|
| `26200` | any | Upgrade finished. A leftover `Upgrade In Progress` value is harmless. | Done |
| old build | `Upgrade In Progress` | Stuck mid-upgrade, or Setup is still running | [3.2](#32-stuck-at-upgrade-in-progress) |
| old build | `Compat Scan OK` | Ready for Phase 3 but it never started, usually a notification or deployment window problem | [3.3](#33-deployment-ended-while-waiting-for-notification) |
| old build | `WIM File Copied` | Compatibility scan did not pass, or a re-scan is pending | [3.4](#34-compatibility-scan-failed) |
| old build | `Ready to Install` | Phase 1 failed while extracting the media | [3.5](#35-phase-1-failed) |
| old build | blank | Phase 1 never ran on this endpoint | Deploy Phase 1 |

To see what Deploy recorded for every deployment on the endpoint (useful when a package shows **Not Applicable**):

```
Get "Deploy - Deployments" from all machines with "Computer Name" contains "WS-EXAMPLE-01"
```

---

### 3.2 Stuck at Upgrade In Progress

**Symptom:** `Status` = `Upgrade In Progress`, `CurrentBuildNumber` is still the old build, and Phase 3 shows **Complete** or **Not Applicable**.

**Why re-running Phase 3 does not fix it:**

1. The endpoint still matches **Branch A** of the install verification (`Status = Upgrade In Progress` plus the staged `setupprep.exe` in `C:\$Windows.~BT\Sources`), so Deploy considers Phase 3 already installed.
2. Phase 3 only treats an endpoint as eligible when `Status` = `Compat Scan OK`.

The fix is to move `Status` off `Upgrade In Progress`, re-scan with Phase 2, and run Phase 3 again. Work through the steps in order.

#### Step 1: Find the stuck endpoints

```
Get "Computer Name" and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion","CurrentBuildNumber"] from all machines with "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] contains "Upgrade In Progress"
```

Rows still on the old build (for example `22631`) are stuck. Rows showing `26200` finished and only have a stale status value; ignore them.

#### Step 2: Check whether Windows Setup is still running

```
Get "Computer Name" and "Running Processes" from all machines with ( "Running Processes" contains "setup.exe" or "Running Processes" contains "SetupHost.exe" ) and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] contains "Upgrade In Progress"
```

Any endpoint returned here still has Setup running. The upgrade may still be working, especially before the first restart. **Do not reset these.** Check them again later. Continue only with the endpoints from Step 1 that do **not** appear here.

#### Step 3: Tag the stuck endpoints

1. Re-run the Step 1 question.
2. Select the rows still on the old build that were not in the Step 2 results.
3. Click **Deploy Action**.
4. In **Deployment Package**, select **Custom Tagging - Add Tags**, enter the tag `IPU-Stuck`, and deploy.

The tag gives you a stable target for the rest of the steps.

#### Step 4: Check Action Lock

While Action Lock is on, the Tanium Client does not run actions, so the registry reset, Phase 2, and Phase 3 would all sit waiting. Check it before pushing anything:

```
Get "Computer Name" and "Action Lock Status" from all machines with "Custom Tags" contains "IPU-Stuck"
```

The result shows `Action Lock Off` or `Action Lock On` for each endpoint. If any endpoint shows `Action Lock On`:

1. Select those rows and click **Deploy Action**.
2. In **Deployment Package**, select **Tanium Client - Set Action Lock Off** and deploy. The package shows **Action Lock Override is On**, which lets it run on an endpoint that is locked.
3. Re-run the question above and confirm the result is now `Action Lock Off`.

!!! warning "Find out why Action Lock was on"
    Action Lock is sometimes set on purpose (for example, on machines that must not receive changes). Confirm with the owner before turning it off, and note which endpoints you changed so you can turn it back on with the **Tanium Client - Set Action Lock On** package after the upgrade.

#### Step 5: Reset the OSD status with Registry - Set Value

1. In Interact, ask:
   ```
   Get "Online" from all machines with "Custom Tags" contains "IPU-Stuck"
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
   Get "Computer Name" and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion","CurrentBuildNumber"] from all machines with "Computer Name" contains "WS-EXAMPLE-01"
   ```
   Once it looks right, deploy to the rest of the `IPU-Stuck` endpoints.

!!! warning "Test the key path on one endpoint first"
    Tanium's documented example enters the full `WOW6432Node` path in **Registry Key Name** and sets **OS Architecture** to match the endpoints. Another approach is to enter `HKEY_LOCAL_MACHINE\Software\Tanium\Tanium Client\OSD` with **OS Architecture = 32** and let Windows redirect it to `WOW6432Node`. Either way, verify on one endpoint that the value landed under `WOW6432Node` before targeting the group.

!!! note "Why WIM File Copied and not Compat Scan OK"
    Some guides reset the value straight to `Compat Scan OK` so Phase 3 picks the endpoint up immediately. That skips the compatibility scan, and the interrupted upgrade may have left the machine in a different state than when it last passed. `WIM File Copied` is the value Tanium documents for this reset, and it forces a fresh scan in Step 6. Use `Compat Scan OK` only if you have confirmed the endpoint is healthy and you accept skipping the re-scan.

#### Step 6: Re-scan with Phase 2

1. Go to **Modules > Deploy > Deployments > Create Deployment**, select the **Phase2 - Re-Scan** package, and target the `IPU-Stuck` tag.
2. When it finishes, ask:
   ```
   Get "Computer Name" and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion","CurrentBuildNumber"] from all machines with "Custom Tags" contains "IPU-Stuck"
   ```
   Endpoints that passed now show `Compat Scan OK`. Endpoints that did not pass need [3.4](#34-compatibility-scan-failed) first.

#### Step 7: Run Phase 3 again

1. Create a new Phase 3 deployment targeting the `IPU-Stuck` tag.
2. Enable **End User Notification** with a restart prompt.
3. Set the deployment to **Ongoing** or give it a long **End Time** (see [3.3](#33-deployment-ended-while-waiting-for-notification)).

#### Step 8: Confirm and clean up

1. Confirm the upgrade. Every endpoint should show `26200`:
   ```
   Get "Computer Name" and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion","CurrentBuildNumber"] and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] from all machines with "Custom Tags" contains "IPU-Stuck"
   ```
2. Remove the tag from the upgraded endpoints with the **Custom Tagging - Remove Tags** package.
3. If you turned Action Lock off in Step 4 on endpoints that need it, turn it back on with the **Tanium Client - Set Action Lock On** package.

---

### 3.3 Deployment ended while waiting for notification

**Symptom:** the Phase 3 deployment shows:

`Deployment ended before completing. Previous sub-status was "Waiting for notification".`

**Cause:** the deployment reached its **End Time** while the endpoint was still showing the user the restart notification (the user postponed, ignored it, or was not logged on). Setup never started, so the endpoint is usually still at `Status` = `Compat Scan OK` on the old build.

1. Confirm the endpoint state with the [3.1](#31-check-where-an-endpoint-is) question. If it shows `Upgrade In Progress`, use [3.2](#32-stuck-at-upgrade-in-progress) instead.
2. Check what Deploy recorded:
   ```
   Get "Deploy - Deployments" from all machines with "Computer Name" contains "WS-EXAMPLE-01"
   ```
3. Create a new Phase 3 deployment for these endpoints and either set it to **Ongoing**, or set the **End Time** well past the notification deadline plus the install time. Keep the **End User Notification** deadline shorter than the deployment window so the upgrade starts before the deployment ends.

---

### 3.4 Compatibility scan failed

**Symptom:** Phase 1 or Phase 2 shows **Update Ineligible**, and `Status` stays at `WIM File Copied`.

1. See why the scan failed:
   ```
   Get "Computer Name" and "Deploy - Windows Upgrade Scan Results" from all machines with "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client\OSD","Status"] contains "WIM File Copied"
   ```
   Some content versions name the sensor **Deploy - Windows Upgrade Scan Details**.
2. Fix the blocker (free disk space, remove or update the incompatible app, update the driver). The full scan result is in `C:\$WINDOWS.~BT\Sources\Panther\ScanResult.xml` (section 4).
3. Deploy the **Phase2 - Re-Scan** package to those endpoints and re-check with the [3.1](#31-check-where-an-endpoint-is) question.

Hardware blocks (TPM, Secure Boot, CPU, RAM) do not clear with a re-scan. Those endpoints need a hardware or firmware change first.

---

### 3.5 Phase 1 failed

**Symptom:** `Status` stays at `Ready to Install` after Phase 1.

Check that the extracted media reached the endpoint:

```
Get "Computer Name" and "File Exists"["C:\deploy\Tanium\OS\setup.exe"] and "File Exists"["C:\deploy\Tanium\OS\sources\install.wim"] from all machines with "Computer Name" contains "WS-EXAMPLE-01"
```

If either file is missing, extraction failed. Read `WinIPU\Win_PreCache.txt` (section 4) for the error:

| Log message | Cause | Fix |
|---|---|---|
| `Please attach 7zip download to Phase1 Package` | `7zip.msi` missing from the package or not cached by the Tanium Server | Check **Package Files** in the Phase 1 package. If `7zip.msi` has no size or hash, follow the "Only if 7zip.msi is not cached" note in section 2. |
| `Missing Setup.Exe. Package must have *BOTH* Install.wim and Setup.exe` | Extracted media attached without `setup.exe` | Attach the ISO instead, or the complete extracted media. |
| No media found | No ISO, WIM, or ESD over 2 GB in the package | Add the ISO to the package (section 2). |

Antivirus blocking `C:\deploy` can also stop extraction. Confirm the exclusion is in place.

---

### 3.6 Quick reference

| Symptom | Go to |
|---|---|
| Phase 3 shows **Complete** but the build did not change | [3.2](#32-stuck-at-upgrade-in-progress) |
| Phase 3 shows **Not Applicable** | [3.1](#31-check-where-an-endpoint-is), then follow the table |
| Phase 1 shows **Not Applicable** | Run `Get "Deploy - Deployments"` for the endpoint. An earlier deployment may already have marked it Installed, and the endpoint may already be eligible for Phase 3. |
| **Update Ineligible** | [3.4](#34-compatibility-scan-failed) |
| `Deployment ended before completing ... Waiting for notification` | [3.3](#33-deployment-ended-while-waiting-for-notification) |
| Stuck at `Ready to Install` | [3.5](#35-phase-1-failed) |
| Upgrade rolled back after restart | Check which setup logs exist (section 4), read SetupDiag results, then look up the code in section 5 |
| Deploy actions sit in **Waiting** and never run | Check Action Lock ([3.2, Step 4](#step-4-check-action-lock)) |

---

## 4. Logs to check

### Find the Tanium Client folder

The Tanium Client install path varies. Get it with:

=== "Tanium question"

    ```
    Get "Computer Name" and "Registry Value Data"["HKEY_LOCAL_MACHINE\Software\WOW6432Node\Tanium\Tanium Client","Path"] from all machines with "Computer Name" contains "WS-EXAMPLE-01"
    ```

=== "PowerShell (alternate)"

    ```powershell
    (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Tanium\Tanium Client').Path
    ```

On most endpoints it is `C:\Program Files (x86)\Tanium\Tanium Client`.

### Tanium Deploy logs

```
C:\Program Files (x86)\Tanium\Tanium Client\Tools\SoftwareManagement\logs\
```

Check `subprocess.log` first. Each command step in a Deploy package runs as a subprocess, and this log shows what was launched and the exit code.

List the files in the folder:

=== "Tanium question"

    ```
    Get "Computer Name" and "Folder Contents"["C:\Program Files (x86)\Tanium\Tanium Client\Tools\SoftwareManagement\logs"] from all machines with "Computer Name" contains "WS-EXAMPLE-01"
    ```

=== "PowerShell (alternate)"

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

=== "Tanium question"

    ```
    Get "Computer Name" and "Folder Contents"["C:\Program Files (x86)\Tanium\Tanium Client\Tools\SoftwareManagement\logs\WinIPU"] from all machines with "Computer Name" contains "WS-EXAMPLE-01"
    ```

=== "PowerShell (alternate)"

    ```powershell
    $tc = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Tanium\Tanium Client').Path
    Get-ChildItem "$tc\Tools\SoftwareManagement\logs\WinIPU" | Sort-Object LastWriteTime -Descending | Select-Object LastWriteTime, Length, Name
    ```

Read the end of the Phase 1 transcript. Reading log text needs access to the endpoint (or a log collection your Tanium admin has approved), so this one is PowerShell only:

```powershell
$tc = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Tanium\Tanium Client').Path
Get-Content "$tc\Tools\SoftwareManagement\logs\WinIPU\Win_PreCache.txt" -Tail 60
```

Check that the extracted media landed:

=== "Tanium question"

    ```
    Get "Computer Name" and "File Exists"["C:\deploy\Tanium\OS\setup.exe"] and "File Exists"["C:\deploy\Tanium\OS\sources\install.wim"] from all machines with "Computer Name" contains "WS-EXAMPLE-01"
    ```

=== "PowerShell (alternate)"

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

Check which setup logs exist on the endpoint. This tells you how far Setup got (Panther only: failed before the first restart; Rollback present: it rolled back; SetupDiag present: read that first):

```
Get "Computer Name" and "File Exists"["C:\$WINDOWS.~BT\Sources\Panther\setuperr.log"] and "File Exists"["C:\$WINDOWS.~BT\Sources\Rollback\setupact.log"] and "File Exists"["C:\Windows\Logs\SetupDiag\SetupDiagResults.xml"] from all machines with "Computer Name" contains "WS-EXAMPLE-01"
```

With access to the endpoint (alternate), pull the last 50 lines of the setup error log:

```powershell
Get-Content 'C:\$WINDOWS.~BT\Sources\Panther\setuperr.log' -Tail 50
```

Search the full log for the failure:

```powershell
Select-String -Path 'C:\$WINDOWS.~BT\Sources\Panther\setupact.log' -Pattern '0xC19|0x8007|Error' | Select-Object -Last 40
```

### Running SetupDiag manually

If `SetupDiagResults.xml` does not exist, run SetupDiag through Tanium with a small custom package:

1. Download `SetupDiag.exe` from Microsoft.
2. Go to **Modules > Deploy > Software > Create Software Package**, add `SetupDiag.exe` under **Package Files**, and set the install command to:
   ```
   cmd.exe /c SetupDiag.exe /Output:C:\Windows\Logs\SetupDiag\SetupDiagResults.log
   ```
3. Deploy it to the affected endpoints, then confirm the result file was written:
   ```
   Get "Computer Name" and "File Exists"["C:\Windows\Logs\SetupDiag\SetupDiagResults.log"] from all machines with "Computer Name" contains "WS-EXAMPLE-01"
   ```

With access to the endpoint (alternate), run it directly:

```cmd
SetupDiag.exe /Output:C:\Temp\SetupDiagResults.log
```

It reads the Panther and Rollback logs and names the rule that matched (driver, app, disk space).

---

## 5. Common Windows Setup error codes

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

## References

- Tanium Deploy: Use case, Upgrading Windows (Tanium Resource Center)
- Tanium Deploy: Troubleshooting Deploy (Tanium Resource Center)
- Microsoft Learn: Resolve Windows upgrade errors, log files and error codes
- Microsoft Learn: SetupDiag
