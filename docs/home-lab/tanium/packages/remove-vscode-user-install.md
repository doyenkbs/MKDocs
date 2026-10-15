---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Endpoint Management
---

# Remove VS Code User Install (Package)

Two Tanium packages that remove the per-user copy of Visual Studio Code from Windows endpoints. One handles users who are signed in. The other handles profiles of users who are signed out.

The per-user copy is the one installed with the VS Code **User** installer, or by the Microsoft Store version of VS Code. It lives inside each user's profile, so the usual approach of running an uninstaller as SYSTEM does not remove it cleanly. These packages do.

The system-wide copy in `C:\Program Files\Microsoft VS Code` is not touched.

!!! note "Vulnerability findings"
    A common reason to run this is a vulnerability finding on an outdated VS Code. Scanners, Tanium Comply included, check the per-user copy separately from the system-wide one. The test name usually ends in **(user)**. Installing or upgrading the system-wide copy does not clear that finding, because the old per-user copy is still in the profile. Removing the per-user copy clears it. If users need to keep VS Code, deploy the system-wide installer as well, so they have a patched copy that Tanium can keep updated.

!!! warning "Test status"
    An earlier version of the signed-in script was run through Tanium on Windows endpoints, including a user with VS Code open, and removed the per-user copy cleanly. The scripts on this page add parameter handling, extra checks, and a summary, and have only been tested for parameter validation and the elevation check so far. **The signed-out script has not been run against a real profile yet.** Test both on one endpoint before deploying widely. See [Test results](#test-results).

---

## Which copy of VS Code is which

| Copy | Location | Shows in Installed Applications as | Removed by these packages |
|---|---|---|---|
| System installer | `C:\Program Files\Microsoft VS Code` | `Microsoft Visual Studio Code` | No |
| User installer | `C:\Users\<user>\AppData\Local\Programs\Microsoft VS Code` | `Microsoft Visual Studio Code (User)` | Yes |
| Microsoft Store | A small Store app (`Microsoft.VisualStudioCode`) that runs the User installer the first time it is opened | `Microsoft Visual Studio Code (User)` after first launch, plus the Store app under Installed Store Apps | The User copy, yes. The Store app, see [The Store version](#the-store-version). |

---

## Why two packages

The User installer writes two things:

- **Files** in `C:\Users\<user>\AppData\Local\Programs\Microsoft VS Code`.
- **An uninstall entry** in that user's own registry, under `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\{771FD6B0-FA20-440A-A002-3B3BAC16DC50}_is1`. Inventory sensors and vulnerability scanners read the installed version from this entry.

A Tanium package runs as SYSTEM. If SYSTEM runs the user's `unins000.exe`, the files go away, but the uninstaller looks for the uninstall entry in SYSTEM's own registry instead of the user's. The user's entry stays, and the endpoint keeps reporting VS Code as installed.

The two packages get around that in different ways:

| Package | When it applies | How it works |
|---|---|---|
| **Signed-In Users** | The user is signed in (at the console or through Remote Desktop) | Runs the user's own `unins000.exe` inside the user's session, through a one-time scheduled task. This is a normal uninstall, so files, the uninstall entry, shortcuts, and the PATH entry are all removed. |
| **Signed-Out Profiles** | The user is not signed in | Loads the user's registry file (`NTUSER.DAT`) offline, deletes the uninstall entry, unloads it, then deletes the install folder and shortcuts. The VS Code uninstaller itself is not run. |

Each package reports the profiles it skipped, so you know when to run the other one.

---

## Find the endpoints

In **Interact**, ask:

```
Get Computer Name and Installed Applications from all machines with Installed Applications contains "Visual Studio Code (User)"
```

To see who is signed in on those endpoints, ask:

```
Get Computer Name and User Sessions from all machines with Installed Applications contains "Visual Studio Code (User)"
```

In the **User Sessions** results:

- **Active** with a user name: someone is signed in. Use the Signed-In Users package.
- **Conn** with no user name on the `console` session: nobody is signed in, the sign-in screen is showing. Use the Signed-Out Profiles package.
- **Disc** with a user name: the user disconnected from Remote Desktop without signing out. They still count as signed in.
- **rdp-tcp** with **Listen**: the Remote Desktop listener. It is on every machine and does not mean anyone is connected.

To check whether VS Code is open on an endpoint, ask:

```
Get Computer Name and Running Processes from all machines with Running Processes contains "Code.exe"
```

VS Code runs as many `Code.exe` processes at once, so 10 to 20 per endpoint is normal for one open window.

---

## Package 1: Signed-In Users

### What the script does

1. Finds every profile that has the per-user copy (`AppData\Local\Programs\Microsoft VS Code`).
2. Finds who is signed in, by checking who owns a running `explorer.exe`.
3. For each signed-in user who has the per-user copy:
    1. Checks whether VS Code is open for that user. If it is, and **Close VS Code** is `No`, the user is skipped. If it is `Yes`, VS Code is closed.
    2. Creates a one-time scheduled task that runs `unins000.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES` as that user, in their session, and starts it.
4. Waits up to 5 minutes for the uninstallers to finish.
5. For each user, checks that `unins000.exe` is gone and that the uninstall entry is gone from the user's registry, then copies the last 20 lines of the uninstaller's own log into the action log.
6. Deletes the scheduled tasks and prints a summary.

Profiles that have the per-user copy but are not signed in are listed in the summary and left alone.

### Parameter

| Parameter | Passed as | Required | What to enter |
|---|---|---|---|
| Close VS Code | `$1` | No | `No` (or blank) skips users who have VS Code open. `Yes` closes VS Code for them first. |

!!! danger "Close VS Code = Yes"
    The script ends every `Code.exe` process the user owns, without asking. VS Code usually restores unsaved files from its backups the next time it opens, but a forced close can still lose recent edits. Tell the user first, or run it outside working hours.

### Why the uninstaller has to see VS Code closed

In testing, running the uninstaller while the user had VS Code open left the install in place, with no prompt and no error in the action log. The silent switches hide the prompt that would normally ask the user to close VS Code. The script now checks for open VS Code before starting, so the action log says why the user was skipped instead of only showing a failure.

### Exit codes

When more than one applies, the lowest non-zero code is returned.

| Exit code | Meaning |
|---|---|
| `0` | Removed for every signed-in user who had it, or no profile has the per-user copy. |
| `1` | The uninstall could not start for at least one user, or it ran and the install is still there. The uninstaller log lines in the action log show why. |
| `2` | **Close VS Code** has a value other than `No`, `Yes`, or blank. Nothing changed. |
| `3` | At least one user was skipped because VS Code was open. |
| `4` | Profiles that are not signed in still have the per-user copy. Run the Signed-Out Profiles package. |
| `5` | The script is not running as SYSTEM or an administrator. Nothing changed. |

### Create the package

Menu labels can differ slightly between Tanium versions.

1. Save the [signed-in script](#signed-in-users-script) at the bottom of this page as `Remove-VSCodeUserInstall.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package**.
4. Fill in the fields:
    - **Package Display Name:** `Remove VS Code User Install - Signed-In Users` (add your team's prefix if you use one).
    - **Content Set:** the content set your team uses for custom content.
    - **Command:**
      ```
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-VSCodeUserInstall.ps1 "$1"
      ```
    - **Command Timeout:** `10` minutes. The script waits up to 5 minutes for the uninstaller.
5. Under **Files**, click **Add**, choose **Local File**, and upload `Remove-VSCodeUserInstall.ps1`.
6. Expand **Parameters**. Under **Parameter Inputs**, add a **Drop-Down List** parameter. It shows in the list as `$1`.
    - **Label:** `Close VS Code`
    - **Provide Help Text:** select it and enter `No skips users who have VS Code open. Yes closes VS Code first, unsaved work can be lost.`
    - **Values:** add two entries, in this order: `No`, then `Yes`.
7. In the **Preview** panel on the right, confirm you see **Close VS Code** with `No` selected.
8. Click **Save**.

### Deploy the package

1. In **Interact**, ask the question from [Find the endpoints](#find-the-endpoints).
2. Select the computers in the results grid.
3. Click **Deploy Action**.
4. In **Deployment Package**, search for and select `Remove VS Code User Install - Signed-In Users`.
5. In **Close VS Code**, leave `No` for the first run.
6. Under the schedule, leave it as a one-time action for the first run.
7. Click **Show preview to continue**, review the targets, then click **Deploy Action**.

For endpoints that return exit code `3`, either ask the user to close VS Code and deploy again, or deploy again with **Close VS Code** set to `Yes`.

Users who are not signed in when the action runs are not covered. To catch them as they sign in, deploy the action with a repeating schedule (for example every 4 hours for a few days) instead of one time.

---

## Package 2: Signed-Out Profiles

### What the script does

For each profile on the endpoint:

1. If the user is signed in and has the per-user copy, it is listed in the summary and skipped.
2. Otherwise, loads the user's `NTUSER.DAT` as `HKEY_USERS\VSCODE_CLEANUP`, deletes the VS Code uninstall entry if it is there, and unloads the hive.
3. If VS Code was found (folder or uninstall entry), deletes:
    - `C:\Users\<user>\AppData\Local\Programs\Microsoft VS Code`
    - `C:\Users\<user>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Visual Studio Code`
    - `C:\Users\<user>\Desktop\Visual Studio Code.lnk`, only if the shortcut points into the per-user install folder.
4. Prints a summary.

Every signed-out profile's hive is checked, not only profiles that still have the folder. When someone deletes the VS Code folder by hand, the uninstall entry stays behind and the endpoint keeps reporting VS Code as installed. This catches that case.

### What it leaves behind

The VS Code uninstaller is not run, so a few things it would normally clean up stay in the user's registry. None of them run anything, they only point to a folder that no longer exists:

- The `...\Microsoft VS Code\bin` entry in the user's PATH.
- **Open with Code** entries in the Explorer right-click menu, if they were selected during install.
- File associations to VS Code, if they were selected during install.

User settings and extensions (`C:\Users\<user>\AppData\Roaming\Code` and `C:\Users\<user>\.vscode`) are not deleted by either package, which is also how the normal uninstaller behaves.

!!! warning "Registry hive unload"
    The script loads each signed-out user's registry file while that user is away. If a hive does not unload (for example, another program opened it at the same moment), the script stops and returns exit code `6`. If that user signs in before the endpoint restarts, Windows can give them a temporary profile. When you see exit code `6`, restart the endpoint before the user signs in.

### Exit codes

When more than one applies, `6` is returned first, then `1`, then `4`.

| Exit code | Meaning |
|---|---|
| `0` | Removed from every signed-out profile that had it, or no profile has it. |
| `1` | At least one profile could not be fully cleaned: the hive could not be loaded, the uninstall entry could not be deleted, or the folder could not be deleted. |
| `4` | Signed-in users still have the per-user copy. Run the Signed-In Users package. |
| `5` | The script is not running as SYSTEM or an administrator. Nothing changed. |
| `6` | A registry hive could not be unloaded. Restart the endpoint before that user signs in. |

### Create the package

1. Save the [signed-out script](#signed-out-profiles-script) at the bottom of this page as `Remove-VSCodeUserInstallOffline.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package**.
4. Fill in the fields:
    - **Package Display Name:** `Remove VS Code User Install - Signed-Out Profiles` (add your team's prefix if you use one).
    - **Content Set:** the content set your team uses for custom content.
    - **Command:**
      ```
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-VSCodeUserInstallOffline.ps1
      ```
    - **Command Timeout:** `10` minutes.
5. Under **Files**, click **Add**, choose **Local File**, and upload `Remove-VSCodeUserInstallOffline.ps1`.
6. This package has no parameters. Click **Save**.

### Deploy the package

1. In **Interact**, ask the question from [Find the endpoints](#find-the-endpoints).
2. Select the computers where nobody is signed in, or where the Signed-In Users package returned exit code `4`.
3. Click **Deploy Action**.
4. In **Deployment Package**, search for and select `Remove VS Code User Install - Signed-Out Profiles`.
5. Under the schedule, leave it as a one-time action.
6. Click **Show preview to continue**, review the targets, then click **Deploy Action**.

Running both packages on the same endpoint is safe. Each one skips the profiles the other one handles.

---

## The Store version

When VS Code came from the Microsoft Store, the Store app (`Microsoft.VisualStudioCode`) is a small launcher. The first time it is opened, it runs the User installer, and from then on the endpoint shows both the Store app and `Microsoft Visual Studio Code (User)`.

The VS Code uninstaller checks for this Store app for the user it runs as, and is built to remove it when it is there. You can see the check in the uninstaller log. In this example the Store app was not installed for that user, so there was nothing to remove:

```
Get-AppxPackage for package with name: Microsoft.VisualStudioCode
Get-AppxPackage result: name=Microsoft.VisualStudioCode, installed=false, resultCode=0, packageFullName=
Skipping Remove-AppxPackage for current appx because package is not installed.
```

The Signed-Out Profiles package does not run the uninstaller, and the Store app can also be registered for other users. If the Store app is still there after these packages run, the user can open it and get the per-user copy back. To check, ask:

```
Get Computer Name and Installed Store Apps from all machines with Installed Store Apps contains "VisualStudioCode"
```

To remove it for every user, deploy the [Remove Store Apps](remove-store-apps.md) package with **Apps** set to `Microsoft.VisualStudioCode` and **Confirm Count** set to `1`.

---

## View the results

### One endpoint

1. Open the action from **Administration** > **Actions** > **Action History**.
2. Select an endpoint.
3. Open its action log. The script output appears between the `Command Line` line and the `Completed` line. The last lines are the summary.

Example, Signed-In Users package, VS Code open and **Close VS Code** set to `No`:

```
2026-10-14 21:26:10 [INFO] Close VS Code parameter: 'No'
2026-10-14 21:26:10 [INFO] Profiles with the VS Code user install: 1
2026-10-14 21:26:11 [WARN] EXAMPLE\jdoe : VS Code is open, skipped. Ask the user to close it, or run again with Close VS Code = Yes.
2026-10-14 21:26:11 [INFO] Summary:
2026-10-14 21:26:11 [INFO]   Removed: none
2026-10-14 21:26:11 [INFO]   Failed: none
2026-10-14 21:26:11 [INFO]   Skipped, VS Code open: EXAMPLE\jdoe
2026-10-14 21:26:11 [INFO]   Not signed in: none
```

Example, Signed-In Users package, successful removal. The lines after `--- last 20 lines ---` come from the VS Code uninstaller's own log:

```
2026-10-14 21:56:20 [INFO] EXAMPLE\jdoe : uninstall started
2026-10-14 21:56:20 [INFO] Waiting up to 5 minutes for the uninstaller(s) to finish.
2026-10-14 21:57:50 [INFO] EXAMPLE\jdoe : task last run 10/14/2026 9:56:24 PM, result 0x0
2026-10-14 21:57:50 [INFO] EXAMPLE\jdoe : removed
2026-10-14 21:57:50 [INFO] --- last 20 lines of C:\Users\jdoe\AppData\Local\Temp\VSCodeUserUninstall.log ---
2026-10-14 21:57:37.973 Deleting file: C:\Users\jdoe\AppData\Local\Programs\Microsoft VS Code\unins000.exe
2026-10-14 21:57:37.973 Failed to delete the file; it may be in use (5).
2026-10-14 21:57:39.650 Deleting Uninstall data files.
2026-10-14 21:57:40.365 Deleting directory: C:\Users\jdoe\AppData\Local\Programs\Microsoft VS Code
2026-10-14 21:57:40.402 Uninstallation process succeeded.
2026-10-14 21:57:40.402 Removed all? Yes
```

`Failed to delete the file; it may be in use` lines in the uninstaller log are normal. The uninstaller cannot delete itself while it is running, so it retries at the end. `Removed all? Yes` is the line that matters.

`KillContextMenuComSurrogate ... exited with non-zero code 1` lines can also appear. The uninstaller tried to stop the process that hosts VS Code's right-click menu and continued. They do not affect the result.

### Many endpoints

Ask a question with the built-in **Tanium Action Log** sensor, using the action ID from the top of the log:

```
Get Tanium Action Log[12345] from all machines
```

### Confirm the copy is gone

Ask the question from [Find the endpoints](#find-the-endpoints) again. The endpoint should no longer return `Microsoft Visual Studio Code (User)`. The **Installed Applications** sensor can return a cached result for a while after the change, so an endpoint that still shows it right after the action may clear on its own. If the removal was for a vulnerability finding, run the Comply assessment again afterward.

---

## Requirements

- Windows 10 or Windows 11 endpoints with Windows PowerShell 5.1.
- The actions must run as SYSTEM, which is the Tanium default. Without administrator rights, both scripts stop with exit code `5`.
- The Signed-In Users package needs the **Task Scheduler** service running, which it is by default.
- A Tanium account with permission to create packages in a content set and deploy actions to the target computers.

---

## Things to know

- **Signed in means `explorer.exe` is running for the user.** A user who disconnected from Remote Desktop without signing out still counts. A user who is only running a service or a scheduled task does not.
- **Work and school (Entra ID) accounts have not been tested.** The scheduled task is created with the account name the endpoint reports for that user. If it fails for an Entra ID account, the action log shows `could not start the uninstall task` with the reason.
- **Success is checked, not assumed.** The uninstaller hands off to a temporary copy and exits right away, so the scheduled task's result is not enough. The Signed-In Users script waits until `unins000.exe` is gone and the uninstall entry is gone before it reports `removed`.
- **It runs as 64-bit.** If the Tanium client starts 32-bit PowerShell, both scripts restart themselves as 64-bit.
- **Parameters arrive URL-encoded.** The Signed-In Users script decodes **Close VS Code** before checking it.
- **Deleting the folder by hand is not enough.** It leaves the uninstall entry behind, and inventory and scanners keep reporting the old version. Use one of these packages instead.

---

## Test results

| Case | Expected | Result |
|---|---|---|
| Earlier draft, signed-in user with VS Code open, no open check | Uninstaller does not finish | Install still present after 5 minutes. This is why the open check was added. |
| Earlier draft, signed-in user with VS Code open, open check added | Skipped, reported as open | Pass |
| Earlier draft, signed-in user after VS Code was closed | Removed, task result `0x0`, uninstaller log ends with `Removed all? Yes` | Pass |
| Folder deleted by hand, uninstall entry checked afterward | Entry still present | Confirmed. This is why the Signed-Out Profiles package checks every hive. |
| Close VS Code = `Maybe` | Exit 2 | Pass |
| Close VS Code = `Yes`, `yes`, `No`, or blank, not elevated | Exit 5, value accepted | Pass |
| Close VS Code URL-encoded (`%59es`), from 32-bit PowerShell | Restarts as 64-bit, decoded to `Yes`, exit 5 | Pass |
| Signed-out script, not elevated, 64-bit and 32-bit | Exit 5, nothing loaded | Pass |
| Current signed-in script, full removal through Tanium | Removed and verified | **Not tested yet** |
| Signed-out script, hive load, entry and folder removal through Tanium | Removed and verified | **Not tested yet** |

---

## Scripts

### Signed-In Users script

```powershell
--8<-- "tanium/packages/remove-vscode-user-install/Remove-VSCodeUserInstall.ps1"
```

### Signed-Out Profiles script

```powershell
--8<-- "tanium/packages/remove-vscode-user-install/Remove-VSCodeUserInstallOffline.ps1"
```
