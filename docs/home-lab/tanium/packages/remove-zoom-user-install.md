---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Endpoint Management
---

# Remove Zoom User Install (Package)

A Tanium package that removes the per-user copy of Zoom from Windows endpoints, workstations and servers alike. It cleans every user profile on the endpoint, whether the user is signed in or not.

The per-user copy is the one a user gets by clicking a Zoom meeting link and running the installer that downloads. It installs into the user's profile instead of Program Files, so it does not need administrator rights, and tools that patch software as SYSTEM cannot update it. Old per-user copies tend to sit in profiles for years.

The system-wide copy in `C:\Program Files\Zoom` or `C:\Program Files (x86)\Zoom` is never changed, and the package does not install anything. The script only checks whether it is there, to decide which folders in the profile are safe to delete. See [Per-user and system-wide on the same endpoint](#per-user-and-system-wide-on-the-same-endpoint).

!!! note "Vulnerability findings"
    A common reason to run this is a vulnerability finding on an outdated Zoom. Scanners, Tanium Comply included, check for `Zoom.exe` in each user profile separately from the system-wide copy. Removing the per-user copy clears that finding. If users still need Zoom, they need another copy that is kept up to date, because this package takes theirs away.

!!! warning "Test status"
    The package was run through Tanium on two endpoints: one with only a per-user copy, open at the time (removed, exit `0`), and one with only the system-wide copy (nothing touched, exit `0`). **An endpoint with both copies, and a signed-out profile, have not been tested yet.** Test those on one endpoint before deploying widely. See [Test results](#test-results).

---

## Which copy of Zoom is which

Both copies create `AppData\Roaming\Zoom` and `AppData\Local\Zoom` in each user's profile. The difference is what is inside them.

| Copy | Program files | What it puts in the profile | Removed by this package |
|---|---|---|---|
| Per-user (installed from a meeting link or the download page without admin rights) | `C:\Users\<user>\AppData\Roaming\Zoom\bin\Zoom.exe` (the folder can be `bin_00` after an update) | Program folders (`bin` or `bin_00`, `uninstall`) and user data (`data`, `logs`, `reports`, `plugin`) | Yes |
| System-wide, 64-bit MSI | `C:\Program Files\Zoom\bin\Zoom.exe` | User data only (`data`, `logs`, `reports`, `plugin`), no `.exe` files | No |
| System-wide, 32-bit MSI | `C:\Program Files (x86)\Zoom\bin\Zoom.exe` | User data only, no `.exe` files | No |

The user data folders hold the user's Zoom settings, sign-in, and local chat history. A `Zoom.exe` anywhere under the two Zoom folders in a profile means a per-user copy. The system-wide copy never puts one there.

The per-user copy also writes to the user's own registry:

- An uninstall entry at `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\ZoomUMX`, with an uninstall command of `"C:\Users\<user>\AppData\Roaming\Zoom\uninstall\Installer.exe" /uninstall`. Inventory, including **Installed Applications**, reads the installed version from here.
- Sometimes a `Zoom` value under `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run`, if the user turned on starting Zoom at sign-in. A fresh per-user install in testing did not create one.

Deleting the `Zoom` folder by hand removes the files but leaves both registry entries, and inventory keeps reporting Zoom as installed. The package removes both.

---

## Find the endpoints

In **Interact**, ask:

```
Get Computer Name and Installed Applications from all machines with Installed Applications contains "Zoom"
```

**Installed Applications** shows both the per-user and the system-wide copy, and their names can look the same. To find only per-user copies, use the [Find File by Name](../sensors/find-file-by-name.md) sensor:

```
Get Computer Name and Find File by Name[Zoom.exe,C:\Users,] from all machines
```

Any path under `C:\Users\<user>\AppData\Roaming\Zoom` is a per-user copy.

To check whether Zoom is open on those endpoints, ask:

```
Get Computer Name and Running Processes from all machines with Running Processes contains "Zoom.exe"
```

Zoom open during a meeting is the case that matters. See [Close Zoom](#parameter).

---

## Per-user and system-wide on the same endpoint

Both copies on one endpoint usually means the per-user copy was installed first. When a system-wide copy is already there, the per-user installer (`ZoomInstallerFull.exe`) does not install anything. It opens the system-wide Zoom instead. This was confirmed in testing.

Because both copies use the same two folders in the profile, deleting those folders whole would also wipe the data of users on the system-wide copy. The script decides what to delete like this:

| Endpoint | Profile | What is deleted from the profile |
|---|---|---|
| Has a system-wide Zoom | Has a per-user `Zoom.exe` | Only the per-user program parts: `bin`, `bin_*`, `uninstall`, any other subfolder that contains an `.exe`, and `.exe` files at the top of either Zoom folder. The data folders stay, because the system-wide copy uses them. |
| No system-wide Zoom | Has a per-user `Zoom.exe` | Both `AppData\Roaming\Zoom` and `AppData\Local\Zoom`. Nothing else on the endpoint uses them. |
| Either | No per-user `Zoom.exe` (data folders only) | Nothing. This is a system-wide user, or a profile left over from a Zoom that was uninstalled. |

The check for a system-wide copy looks for `Zoom.exe` in `C:\Program Files\Zoom\bin` and `C:\Program Files (x86)\Zoom\bin`. It is read only. The first line of the action log after the parameter line says which case the endpoint is in.

A Zoom that is open from Program Files is not closed and does not block anything, because nothing it uses is deleted.

---

## What the script does

1. Finds every user profile on the endpoint: profiles Windows knows about (local, domain, and work or school accounts), plus folders left in `C:\Users` by accounts that were deleted.
2. Checks whether a system-wide Zoom is installed, and for each profile, whether it has a per-user `Zoom.exe`. That decides what is deleted, as in the table above.
3. Checks whether Zoom is running from anything that will be deleted. If it is and **Close Zoom** is `No`, the profile is skipped. If it is `Yes`, Zoom is closed.
4. Cleans the user's registry:
    - **Signed in:** works on the user's loaded registry directly.
    - **Signed out:** loads the user's `NTUSER.DAT` as `HKEY_USERS\ZOOM_CLEANUP`, cleans it, and unloads it.

    In both cases it deletes the `ZoomUMX` uninstall entry, any other uninstall entry whose uninstall command points into `AppData\Roaming\Zoom`, and any **Run** value that points there. Every signed-out profile's registry is checked, not only profiles that still have the folder, so entries left behind by a manual delete are caught too.
5. Deletes the shortcuts in the user's Start menu and on the desktop that point into what is being deleted, and the Start menu folder if that leaves it empty. Shortcuts that point anywhere else, including to the system-wide copy, are left alone.
6. Deletes the folders from step 2.
7. Checks that no `Zoom.exe` is left in the profile, and prints a summary.

### What it leaves behind

- Zoom's link handlers (what opens `zoommtg:` links) can stay registered for the user. They point to a file that no longer exists, so nothing runs.
- Shortcuts outside the user's Start menu and desktop, for example a desktop redirected to OneDrive, are not checked.
- On endpoints with a system-wide Zoom, the user data folders of users who had a per-user copy. The system-wide copy keeps using them.
- The system-wide copy, the Zoom Outlook plug-in, and anything else installed for all users.

---

## Parameter

| Parameter | Passed as | Required | What to enter |
|---|---|---|---|
| Close Zoom | `$1` | No | `No` (or blank) skips users who have Zoom open. `Yes` closes Zoom for them first. |

!!! danger "Close Zoom = Yes"
    The script ends every Zoom process running from a user's per-user copy, without asking. Anyone in a meeting is dropped from it. On a Remote Desktop session host, this applies to every signed-in user at once. Use `Yes` on servers, or on workstations outside working hours.

---

## Exit codes

When more than one applies, `6` is returned first, then `1`, then `3`.

| Exit code | Meaning |
|---|---|
| `0` | Removed from every profile that had it, or no profile has it. |
| `1` | At least one profile could not be fully cleaned: a folder could not be deleted, a registry entry could not be deleted, or a hive could not be loaded. The action log shows which. |
| `2` | **Close Zoom** has a value other than `No`, `Yes`, or blank. Nothing changed. |
| `3` | At least one user was skipped because Zoom was open. Deploy again later, or with **Close Zoom** set to `Yes`. |
| `5` | The script is not running as SYSTEM or an administrator. Nothing changed. |
| `6` | A registry hive could not be unloaded. Restart the endpoint before that user signs in. |

!!! warning "Registry hive unload"
    The script loads each signed-out user's registry file while that user is away. If a hive does not unload (for example, another program opened it at the same moment), the script stops and returns exit code `6`. If that user signs in before the endpoint restarts, Windows can give them a temporary profile. When you see exit code `6`, restart the endpoint before the user signs in.

---

## Create the package

Menu labels can differ slightly between Tanium versions.

1. Save the [script](#script) at the bottom of this page as `Remove-ZoomUserInstall.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package**.
4. Fill in the fields:
    - **Package Display Name:** `Remove Zoom User Install` (add your team's prefix if you use one).
    - **Description:**
      ```
      Removes the per-user copy of Zoom (AppData\Roaming\Zoom\bin) from every profile, signed in or not, plus its ZoomUMX uninstall entry and shortcuts. If a system-wide Zoom is installed, user data folders are kept. The system-wide copy is never changed. Close Zoom = Yes drops live meetings. Exit 0 = removed or nothing to do. Exit 1 = something remains. Exit 3 = skipped, Zoom open. See the action log.
      ```
    - **Content Set:** the content set your team uses for custom content.
    - **Command:**
      ```
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-ZoomUserInstall.ps1 "$1"
      ```
    - **Command Timeout:** `10` minutes. Each signed-out profile takes a few seconds for the registry load and unload, so endpoints with many profiles take longer.
5. Under **Files**, click **Add**, choose **Local File**, and upload `Remove-ZoomUserInstall.ps1`.
6. Expand **Parameters**. Under **Parameter Inputs**, add a **Drop-Down List** parameter. It shows in the list as `$1`.
    - **Label:** `Close Zoom`
    - **Provide Help Text:** select it and enter `No skips users who have Zoom open. Yes closes Zoom first and drops any meeting in progress.`
    - **Values:** add two entries, in this order: `No`, then `Yes`.
7. In the **Preview** panel on the right, confirm you see **Close Zoom** with `No` selected.
8. Click **Save**.

---

## Deploy the package

1. In **Interact**, ask the Find File by Name question from [Find the endpoints](#find-the-endpoints).
2. Select the computers in the results grid.
3. Click **Deploy Action**.
4. In **Deployment Package**, search for and select `Remove Zoom User Install`.
5. Set **Close Zoom**:
    - **Servers:** `Yes`, unless the server is a Remote Desktop session host in use.
    - **Workstations during working hours:** `No`.
6. Under the schedule, leave it as a one-time action for the first run.
7. Click **Show preview to continue**, review the targets, then click **Deploy Action**.

For endpoints that return exit code `3`, deploy again later, or deploy again after hours with **Close Zoom** set to `Yes`.

---

## View the results

### One endpoint

1. Open the action from **Administration** > **Actions** > **Action History**.
2. Select an endpoint.
3. Open its action log. The script output appears between the `Command Line` line and the `Completed` line. The last lines are the summary:

```
Summary:
  Removed: <profile paths>
  Failed: <profile paths, or none>
  Skipped, Zoom open: <profile paths, or none>
```

Each profile also gets its own lines, such as `deleted`, `removed uninstall entry 'ZoomUMX'`, `Zoom is open, skipped`, or `still present`, so a failure shows which file or registry entry was the problem.

Example, endpoint with only a per-user copy, Zoom open, **Close Zoom** set to `Yes`:

```
2026-10-20 13:43:08 [INFO] Close Zoom parameter: 'Yes'
2026-10-20 13:43:09 [INFO] No system-wide Zoom. Profiles with a per-user copy have both Zoom folders deleted.
2026-10-20 13:43:12 [INFO] C:\Users\jdoe : found C:\Users\jdoe\AppData\Roaming\Zoom\bin\Zoom.exe version 7.2.1.48556
2026-10-20 13:43:12 [INFO] C:\Users\jdoe : closed Zoom.exe (PID 9984)
2026-10-20 13:43:12 [INFO] C:\Users\jdoe : closed Zoom.exe (PID 7340)
2026-10-20 13:43:15 [INFO] C:\Users\jdoe : removed uninstall entry 'ZoomUMX'
2026-10-20 13:43:15 [INFO] C:\Users\jdoe : deleted C:\Users\jdoe\AppData\Roaming\Zoom
2026-10-20 13:43:16 [INFO] C:\Users\jdoe : deleted C:\Users\jdoe\AppData\Local\Zoom
2026-10-20 13:43:16 [INFO] C:\Users\jdoe : removed
2026-10-20 13:43:18 [INFO] Summary:
2026-10-20 13:43:18 [INFO]   Removed: C:\Users\jdoe
2026-10-20 13:43:18 [INFO]   Failed: none
2026-10-20 13:43:18 [INFO]   Skipped, Zoom open: none
```

Example, endpoint with only the system-wide copy. Nothing is a per-user copy, so nothing is touched:

```
2026-10-20 13:43:13 [INFO] Close Zoom parameter: 'Yes'
2026-10-20 13:43:14 [INFO] System-wide Zoom found (C:\Program Files\Zoom\bin\Zoom.exe). User data folders are kept; only per-user program folders are deleted.
2026-10-20 13:43:17 [INFO] Summary:
2026-10-20 13:43:17 [INFO]   Removed: none
2026-10-20 13:43:17 [INFO]   Failed: none
2026-10-20 13:43:17 [INFO]   Skipped, Zoom open: none
```

### Many endpoints

Ask a question with the built-in **Tanium Action Log** sensor, using the action ID from the top of the log:

```
Get Tanium Action Log[12345] from all machines
```

### Confirm the copy is gone

Ask the Find File by Name question from [Find the endpoints](#find-the-endpoints) again. The endpoint should return `NOT FOUND`. The **Installed Applications** sensor can return a cached result for a while after the change, so an endpoint that still shows Zoom right after the action may clear on its own. If the removal was for a vulnerability finding, run the Comply assessment again afterward.

---

## Requirements

- Windows 10, Windows 11, or Windows Server endpoints with Windows PowerShell 5.1.
- The action must run as SYSTEM, which is the Tanium default. Without administrator rights, the script stops with exit code `5`.
- A Tanium account with permission to create packages in a content set and deploy actions to the target computers.

---

## Things to know

- **Zoom is closed by path, not by name.** Only processes running from what is about to be deleted are closed. A system-wide Zoom that is open is not touched.
- **A per-user copy is found by `Zoom.exe`, not by the folders.** The folders alone do not mean a per-user copy, since the system-wide copy creates them too.
- **It runs as 64-bit.** If the Tanium client starts 32-bit PowerShell, the script restarts itself as 64-bit.
- **Parameters arrive URL-encoded.** The script decodes **Close Zoom** before checking it.
- **Users can install it again.** Any user can click a meeting link and get a new per-user copy. To stop that, block `%OSDRIVE%\Users\*\AppData\Roaming\Zoom\bin\*` with Tanium Enforce or AppLocker.
- **Deleting the folder by hand is not enough.** It leaves the uninstall entry behind, and inventory keeps reporting Zoom. Use this package instead.

---

## Test results

| Case | Expected | Result |
|---|---|---|
| Parser check, Windows PowerShell 5.1 | No errors | Pass |
| Endpoint with system-wide Zoom 7.2, profile with data folders only, detection run read only | System-wide copy found, no per-user `Zoom.exe`, nothing targeted | Pass |
| Simulated profiles: per-user `bin` or `bin_00` with system-wide present | Only `bin` or `bin_00` and `uninstall` deleted, `data`, `logs`, `reports`, `plugin` kept | Pass |
| Simulated profile: per-user copy, no system-wide Zoom | Both Zoom folders deleted | Pass |
| Simulated profile: data folders only, with or without system-wide Zoom | Nothing deleted | Pass |
| Real per-user install (7.2.1), layout and registry checked by hand | `ZoomUMX` entry pointing to `Roaming\Zoom\uninstall`, program folders `bin` and `uninstall`, same data folders as the system-wide copy | Confirmed |
| Close Zoom = `Maybe` | Exit 2, nothing changed | Pass |
| Close Zoom = `Yes` or blank, not elevated | Value accepted, exit 5, nothing changed | Pass |
| Close Zoom URL-encoded (`%59es`, `%4eo`), from 32-bit PowerShell | Restarts as 64-bit, decoded to `Yes` and `No`, exit 5 | Pass |
| Per-user copy only (7.2.1), signed-in user, Zoom open, Close Zoom = `Yes`, through Tanium | Zoom closed, `ZoomUMX` removed, both Zoom folders deleted, exit 0 | Pass |
| System-wide copy only (7.2), Close Zoom = `Yes`, through Tanium | System-wide copy found, nothing touched, exit 0 | Pass |
| Per-user and system-wide copy on the same endpoint | Only `bin` and `uninstall` deleted, data folders kept, system-wide Zoom still opens with the user's settings | **Not tested yet** |
| Signed-in user, Zoom open, Close Zoom = `No` | Skipped, exit 3 | **Not tested yet** |
| Signed-out profile, hive load, entry and folder removal | Removed, hive unloaded | **Not tested yet** |
| Folder deleted by hand earlier, entry still in a signed-out hive | Entry removed | **Not tested yet** |

---

## Script

```powershell
--8<-- "tanium/packages/remove-zoom-user-install/Remove-ZoomUserInstall.ps1"
```
