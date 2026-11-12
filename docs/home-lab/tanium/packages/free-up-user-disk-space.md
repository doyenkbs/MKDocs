---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Endpoint Management
---

# Free Up User Disk Space (Package)

This Tanium package frees disk space on Windows endpoints. It removes files that Windows does not need. It sets old OneDrive files to online-only. It asks the signed-in user before it empties old items from the Recycle Bin.

!!! warning "Test status"
    The package was run through Tanium on endpoints with the default settings and with all options set to `Yes`, including Windows.old. All runs completed with exit code `0`. **The time limit for the user part was not tested.** Deploy to one endpoint first and read the action log.

!!! warning "Options that you cannot undo"
    The **Windows.old** option removes the previous Windows version. After this, the endpoint cannot go back to that version. Use this option only when the upgrade is stable.

## What the package does

The package has two scripts:

| Script | Runs as | Function |
|---|---|---|
| `Invoke-DiskCleanup.ps1` | SYSTEM | Does the cleanup for the full endpoint. Starts the second script for each signed-in user. |
| `Invoke-UserDiskCleanup.ps1` | The signed-in user | Does the cleanup for that user. Shows the Recycle Bin question to that user. |

The Tanium Client runs scripts as SYSTEM. SYSTEM cannot show a window to a user, and SYSTEM cannot get access to the OneDrive of a user. Thus, the first script starts the second script in the session of each signed-in user. It uses a scheduled task that runs one time. The task uses the normal rights of the user, not administrator rights. The first script removes the task when the work is complete.

### Steps that always run

These steps run on the full endpoint. They run also when no user is signed in.

| Item | Location | Rule |
|---|---|---|
| Windows temporary files | `C:\Windows\Temp` | Removes files older than 7 days |
| Windows error reports | `C:\ProgramData\Microsoft\Windows\WER\ReportArchive` and `ReportQueue` | Removes all |
| Delivery Optimization cache | Managed by Windows | Removes all |

These steps run for each signed-in user:

| Item | Location | Rule |
|---|---|---|
| Temporary files of the user | `%LOCALAPPDATA%\Temp` | Removes files older than 7 days |
| Error reports of the user | `%LOCALAPPDATA%\Microsoft\Windows\WER` | Removes all |
| OneDrive files | All folders that OneDrive keeps in sync for the user | Sets files that the user did not use for 14 days to online-only |
| Recycle Bin | `C:\$Recycle.Bin\<user ID>` on each fixed drive | Asks the user before it removes items older than 30 days |

### Optional steps

All optional steps are off by default.

| Option | Location | Rule |
|---|---|---|
| Windows Update downloads | `C:\Windows\SoftwareDistribution\Download` | Removes all. Stops the Windows Update service for a short time. |
| Crash dump files | `C:\Windows\Minidump`, `C:\Windows\LiveKernelReports`, `C:\Windows\MEMORY.DMP` | Removes files older than 7 days |
| Browser caches | Chrome, Edge, and Firefox cache folders of each signed-in user | Removes cache files only |
| Windows.old | `C:\Windows.old` | Removes the previous Windows version |

## How each step works

### OneDrive

The script finds the files that are on the endpoint and that the user did not use for 14 days. A file is "used" when the user opened it, changed it, or created it. The script uses the newest of these three dates.

The script sets each of these files to online-only. This is the same as **Free up space** in File Explorer. The file stays in OneDrive. Windows downloads the file again when the user opens it.

The script does not change these files:

- Files that the user marked **Always keep on this device**
- Files that are already online-only
- Hidden files and system files
- Empty files

The OneDrive step has a time limit of 8 minutes for each user. If the time limit occurs, the script stops this step. The next run continues with the remaining files.

!!! note
    The script does not change files marked **Always keep on this device**. On some endpoints, most OneDrive files have this mark. On these endpoints, the OneDrive step frees little space.

### Recycle Bin

The script finds the Recycle Bin items that the user deleted more than 30 days ago. If there are no such items, the script does not show a question.

If there are such items, the user sees this window:

- The window shows the number of old items and their size.
- **Delete old items** removes these items permanently.
- **Keep them** closes the window. The script does not remove items.
- The Enter key and the Esc key also select **Keep them**.
- If the user does not answer, the window closes after the time limit. The script does not remove items.

The script never removes items that the user deleted in the last 30 days.

### Browser caches

The script removes only the cache files of Chrome, Edge, and Firefox. It does not remove bookmarks, passwords, history, cookies, or sign-ins. If the browser is open, the script does not remove the files that the browser uses.

### Windows Update downloads

If Windows must restart to complete an update installation, the script does not do this step. Run the package again after the restart.

If an update is downloaded but not installed, Windows downloads it again.

### Windows.old

The script uses the Windows Disk Cleanup tool to remove `C:\Windows.old`. This is the same as **Previous Windows installation(s)** in **Settings > System > Storage > Temporary files**.

The script does not remove `C:\Windows.old` with its own commands. This folder contains links to user profile folders in `C:\Users`. A tool that follows these links can delete user data. Disk Cleanup does not follow these links.

The step does these actions:

1. Tells Windows that the endpoint cannot go back to the previous version.
2. Sets Disk Cleanup profile number 731 to remove **Previous Windows installation(s)** only.
3. Starts Disk Cleanup with profile 731.
4. Monitors `C:\Windows.old` every 15 seconds. The step stops when Disk Cleanup removes the folder, or after 40 minutes.
5. Removes profile 731 from the registry.

This step usually takes 5 to 30 minutes.

The script does not do this step if a Windows upgrade is in progress.

## Safety rules

The scripts obey these rules:

- They never follow a link to a folder. They remove only the link, not the target of the link.
- In `C:\Windows\Temp`, they do not open folders that a standard user created. This prevents a standard user from making the SYSTEM script delete files in a different location.
- They do not remove files that are in use.
- They write counts and sizes to the log. They do not write file names or folder names.
- They do not restart the endpoint.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1
- The Tanium Client
- For the OneDrive step: the OneDrive sync app, with the user signed in
- For the Windows.old option: `C:\Windows\System32\cleanmgr.exe` on the endpoint

## Create the package

1. In the Tanium Console, go to **Administration > Content > Packages**.
2. Click **Create Package**.
3. Fill in the fields with the values in the table below.
4. In the **Files** section, add the two script files.
5. In the **Parameters** section, add the seven parameters in the second table below.
6. Click **Save**.

| Field | Value |
|---|---|
| Package Name | `Free Up User Disk Space` |
| Display Name | `Free Up User Disk Space` |
| Description | `Frees disk space. Always: removes temp files older than 7 days, Windows error reports, and the Delivery Optimization cache; sets OneDrive files not used for a set number of days (default 14) to online-only; asks the signed-in user before removing Recycle Bin items older than a set number of days (default 30). Optional, off by default: Windows Update downloads, old crash dumps, browser caches, and C:\Windows.old. Windows only.` |
| Content Set | Your custom content set |
| Command | `cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Invoke-DiskCleanup.ps1 "$1" "$2" "$3" "$4" "$5" "$6" "$7"` |
| Command Timeout | 60 minutes |
| Download Timeout | 10 minutes |
| Ignore Action Lock | Clear (not selected) |
| Launch this package command in a process group | Selected |
| Files | `Invoke-DiskCleanup.ps1`, `Invoke-UserDiskCleanup.ps1` |

### Parameters

Add the parameters in this order. The order sets the number (`$1` to `$7`).

| Key | Type | Label | Values | Default |
|---|---|---|---|---|
| `$1` | Numeric | OneDrive: days since last use | 1 to 3650 | 14 |
| `$2` | Numeric | Recycle Bin: days since deleted | 1 to 3650 | 30 |
| `$3` | Numeric | Seconds to wait for the user's answer | 30 to 600 | 300 |
| `$4` | Drop Down List | Empty the Windows Update download folder | No, Yes | No |
| `$5` | Drop Down List | Remove crash dump files older than 7 days | No, Yes | No |
| `$6` | Drop Down List | Empty browser caches (Chrome, Edge, Firefox) | No, Yes | No |
| `$7` | Drop Down List | Remove C:\Windows.old (no going back to the previous Windows version) | No, Yes | No |

## Deploy the package

1. In the Tanium Console, go to **Interact**.
2. In the question bar, type this question:

    ```text
    Get Computer Name and Disk Free Space from all machines with Is Windows equals True
    ```

3. Press Enter.
4. Sort the results by **Disk Free Space**.
5. Select the endpoints that you want to clean.
6. Click **Deploy Action**.
7. In the **Deployment Package** field, type `Free Up User Disk Space`. Select the package.
8. Set the parameters. For the first run, keep the default values.
9. Click **Show preview to continue**.
10. Make sure that the list shows the correct endpoints.
11. Click **Deploy Action**.

!!! tip
    Users can see the Recycle Bin question. Tell the users before you deploy the package.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | The package completed. This includes "no user is signed in" and "the user selected Keep them". |
| 1 | A step failed. Read the action log. |
| 2 | The cleanup for a user did not complete in the time limit. The work that completed stays complete. |

## Read the results

The action log shows each step, the number of items, and the space freed. It also shows the results of the user part.

To read the action log from the Tanium Console:

1. Go to **Interact**.
2. Type this question. Replace `<action ID>` with the ID of your action.

    ```text
    Get Tanium Action Log[<action ID>] from all machines with Computer Name equals ENDPOINT-01
    ```

3. Press Enter.

To compare the free space before and after the action, ask this question:

```text
Get Computer Name and Disk Free Space from all machines with Is Windows equals True
```

### Example log

```text
[INFO] Free space on C: before: 23.80 GB
[INFO] Signed-in people found: EXAMPLE\user01
[INFO] Windows temp folder (older than 7 days): 8 items removed, about 2.7 MB freed.
[INFO] Delivery Optimization cache: emptied, about 798.1 MB freed.
[INFO] Crash dump files (older than 7 days): 2 items removed, about 3.65 GB freed.
[INFO] Windows.old: removed, about 25.87 GB freed.
[INFO] Free space on C: after: 56.91 GB (change: 33.11 GB)
[INFO] Disk cleanup finished with exit code 0.
```

## Troubleshooting

| Log message | Cause | Action |
|---|---|---|
| `Nobody is signed in.` | No user is signed in. The user steps do not run. The steps for the full endpoint run. | Deploy again when a user is signed in. |
| `OneDrive is not running for this person.` | The OneDrive sync app is not open. | The files are marked. OneDrive frees the space when it starts. |
| `the 8-minute time limit was reached` | The OneDrive folder has many files. | Deploy the package again. The next run continues. |
| `no answer within ... seconds` | The user did not answer the Recycle Bin question. | Nothing was removed from the Recycle Bin. Deploy again later. |
| `Windows is waiting for a restart` | An update installation is not complete. | Restart the endpoint. Then deploy again. |
| `Windows.old: still there after Disk Cleanup` | Disk Cleanup did not complete. | Restart the endpoint. Then deploy again with `$7` set to `Yes`. |
| `Delivery Optimization cache: could not be emptied` | The Delivery Optimization module is not available. | No action is necessary. |

## Scripts

The package has two scripts. Select a tab to see each script.

=== "Invoke-DiskCleanup.ps1 (SYSTEM)"

    ```powershell
    --8<-- "tanium/packages/free-up-user-disk-space/Invoke-DiskCleanup.ps1"
    ```

=== "Invoke-UserDiskCleanup.ps1 (signed-in user)"

    ```powershell
    --8<-- "tanium/packages/free-up-user-disk-space/Invoke-UserDiskCleanup.ps1"
    ```

## Related

- [Windows Component Cleanup (DISM)](windows-component-cleanup.md)
