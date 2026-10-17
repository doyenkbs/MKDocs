---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Endpoint Management
  - Python
---

# Remove Legacy Python (Package)

One Tanium package that removes Python 3.10, 3.11, and 3.12 from Windows endpoints. It covers all-users installs, per-user installs in every profile (signed in or not), and copies in custom folders such as `C:\Python311`.

Newer versions of Python are not touched, and neither is the all-users Python Launcher (`C:\Windows\py.exe`).

!!! note "Why these three versions"
    python.org no longer publishes Windows installers for Python 3.10, 3.11, or 3.12. The last ones were 3.10.11, 3.11.9, and 3.12.10. Later releases of those versions are security fixes published as source code only, so a Windows copy of 3.10, 3.11, or 3.12 cannot be patched in place. The fix is to install a supported version (3.14 is the safest choice, since it still gets Windows installers) and remove the old one. Python 3.10 reached end of life in October 2026. Python 3.11 and 3.12 keep getting source-only security fixes until October 2027 and October 2028.

!!! note "Vulnerability findings"
    Scanners, Tanium Comply included, check the per-user copy in `C:\Users\<user>\AppData\Local\Programs\Python\` separately from the all-users copy. Installing a newer Python does not clear the finding, because the old copy is still there. Removing the old copy clears it. A finding can cover several vulnerabilities at once when they all point to the same old `python.exe`, so one removal often clears several findings on the same endpoint.

!!! warning "Test status"
    An earlier version of this script (all-users uninstall plus per-user folders, uninstall entries, Start menu, and PATH, for 3.10 and 3.11) was run through Tanium on one Windows endpoint with a per-user Python 3.11.2 install, and removed the install folder. The script on this page adds 3.12, custom folders, PythonCore registry keys, the per-user launcher, signed-out profiles, logging, and exit codes. **It has only been checked for syntax so far.** Test it on one endpoint before deploying widely. See [Test results](#test-results).

---

## Where Python gets installed

| Install type | Location | Shows in Installed Applications as | Removed by this package |
|---|---|---|---|
| All users, 64-bit | `C:\Program Files\Python311` | `Python 3.11.x (64-bit)` | Yes, with the installer's own uninstall |
| All users, 32-bit | `C:\Program Files (x86)\Python311-32` | `Python 3.11.x (32-bit)` | Yes, with the installer's own uninstall |
| Per user (the installer's default) | `C:\Users\<user>\AppData\Local\Programs\Python\Python311` | `Python 3.11.x (64-bit)` | Yes, cleaned directly |
| Per user, custom folder | Anywhere the user chose, for example `C:\Python311` | `Python 3.11.x (64-bit)` | Yes, found through its registry entry |
| Copied by hand or embeddable zip | Anywhere, for example `C:\python3.11` | Not listed | Only at the root of the system drive |
| pip `--user` packages | `C:\Users\<user>\AppData\Roaming\Python\Python311` | Not listed | Yes |
| Per-user Python Launcher | `C:\Users\<user>\AppData\Local\Programs\Python\Launcher` | `Python Launcher` | Only if it is version 3.10, 3.11, or 3.12 |

The same table applies to 3.10 (`Python310`) and 3.12 (`Python312`).

---

## Why per-user installs need special handling

The Python installer is a bundle (a small setup program) that installs several hidden MSI packages: the core interpreter, the standard library, pip, and so on. For a per-user install, the bundle registers everything in that user's own registry, under `HKEY_CURRENT_USER`.

A Tanium package runs as SYSTEM. SYSTEM cannot run another user's per-user uninstall: the uninstaller looks in SYSTEM's own registry, finds nothing, and the files and uninstall entry stay. In the Tanium console, this often shows as `Python 3.11.x (64-bit)` with **Not Uninstallable** in Installed Applications.

So the script does not try to uninstall per-user copies. It deletes the files and the registry entries directly, for every profile. For users who are signed out, it loads their registry file (`NTUSER.DAT`) offline, cleans it, and unloads it.

---

## Before you remove anything

### Give users a supported version first

If users need Python, install the replacement before running this package. Tanium Deploy has Python in its software gallery.

1. In the Tanium Console, go to **Modules** > **Deploy** > **Software**.
2. Search for `Python 3.14`. If it is not listed, import it from the gallery first.
3. Deploy it to the same endpoints you plan to clean.

Menu labels can differ slightly between Tanium versions.

### Save the user's packages

Removing the old version deletes the packages the user installed with pip. If the user needs them, have the user run this in PowerShell **before** the package runs. It saves the package names without version numbers:

```powershell
py -3.11 -m pip freeze | ForEach-Object { $_ -replace '==.*', '' } | Set-Content "$env:USERPROFILE\python-requirements.txt"
```

Change `-3.11` to the version they have. Version numbers are dropped on purpose: package versions from a few years ago often have no ready-made build for Python 3.14, and pinned installs then fail.

After the package runs, the user reinstalls them into a virtual environment in their own profile. This needs no administrator rights:

```powershell
py -3.14 -m venv "$env:USERPROFILE\venvs\py314"
& "$env:USERPROFILE\venvs\py314\Scripts\python.exe" -m pip install -r "$env:USERPROFILE\python-requirements.txt"
```

Calling the virtual environment's `python.exe` directly avoids `Activate.ps1`, which is often blocked by execution policy on managed endpoints. If one package fails to build, the whole install stops. Remove that line from the file and run the install again.

---

## Find the endpoints

In **Interact**, ask:

```
Get Computer Name and Installed Applications from all machines with ( Installed Applications contains "Python 3.10" or Installed Applications contains "Python 3.11" or Installed Applications contains "Python 3.12" )
```

To check whether Python is running on those endpoints (a running `python.exe` blocks the folder delete), ask:

```
Get Computer Name and Running Processes from all machines with Running Processes contains "python.exe"
```

Copies made by hand or from the embeddable zip do not show in Installed Applications. If Comply reports one, the test's **Actual Values** show its path.

---

## What the script does

1. Checks it is running as SYSTEM or an administrator. If not, it stops with exit code `5`.
2. **All-users installs:**
    1. Reads the install folders registered for 3.10, 3.11, and 3.12 under `HKLM\SOFTWARE\Python\PythonCore`.
    2. For each `Python 3.1x.x (64-bit)` or `(32-bit)` entry, runs the installer's own quiet uninstall from `C:\ProgramData\Package Cache\`.
    3. If the cached installer is gone, removes the hidden MSI components one by one with `msiexec /x`.
3. **Custom folders:** deletes registered install folders that still exist, and `Python*` folders at the root of the system drive, but only when `python.exe` directly inside the folder is version 3.10, 3.11, or 3.12. A drive root and anything under `C:\Windows` are never deleted.
4. Removes the `PythonCore\3.10`, `3.11`, and `3.12` keys for all users, once their uninstall entries are gone.
5. **Every user profile:**
    1. Deletes `AppData\Local\Programs\Python\Python3xx` and `AppData\Roaming\Python\Python3xx`.
    2. Deletes the per-user Python Launcher, only if its `py.exe` is version 3.10, 3.11, or 3.12.
    3. Deletes `AppData\Local\Programs\Python` if nothing is left in it.
    4. Deletes Start menu folders named `Python 3.10`, `Python 3.11`, or `Python 3.12`.
    5. Opens the user's registry (the live one if the user is signed in, otherwise `NTUSER.DAT` loaded as `HKEY_USERS\PY_CLEANUP`) and deletes custom install folders registered there, the uninstall entries, the `PythonCore` keys, and the PATH entries for those versions.
6. Checks that nothing is left and prints a summary.

### What it leaves behind

- **Windows Installer records for per-user installs.** The hidden MSI packages stay registered to the user. They do not run anything and do not affect inventory or scanners, but that user cannot repair or reinstall that exact old version per user afterward.
- **pip's download cache** in `C:\Users\<user>\AppData\Local\pip\cache`. It is shared by all Python versions.
- **Virtual environments** the user created with the old version. They stop working once the old version is gone and have to be recreated.

### Changing the versions

The versions are set in one line near the top of the script:

```powershell
$Minor = @('10', '11', '12')
```

Folder names, registry key names, and the version checks all follow this list. To include 3.9, change it to `@('9', '10', '11', '12')`. If you change it, rename the package to match.

---

## Exit codes

When more than one applies, `6` is returned first, then `1`.

| Exit code | Meaning |
|---|---|
| `0` | Removed everything found, or nothing was found. |
| `1` | Something could not be removed, or is still present afterward. Look for `[ERROR]` lines and the `Still present` line in the action log. |
| `5` | The script is not running as SYSTEM or an administrator. Nothing changed. |
| `6` | A user's registry file could not be unloaded. Restart the endpoint before that user signs in. |

!!! warning "Registry hive unload"
    The script loads each signed-out user's registry file while that user is away. If one does not unload (for example, another program opened it at the same moment), the script stops and returns exit code `6`. If that user signs in before the endpoint restarts, Windows can give them a temporary profile. When you see exit code `6`, restart the endpoint before the user signs in.

---

## Create the package

1. Save the [script](#script) at the bottom of this page as `Remove-LegacyPython.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package**.
4. Fill in the fields:
    - **Package Name** and **Display Name:** `Remove Legacy Python 3.10-3.12 [Windows]` (add your team's prefix if you use one).
    - **Description:**
      ```
      Removes Python 3.10, 3.11, and 3.12 from all-users installs, every user profile, and custom folders at the root of the system drive. Cleans related registry keys, Start menu folders, and user PATH entries. Does not touch newer Python or C:\Windows\py.exe. Exit 0 = removed. Exit 1 = something remains (see action log).
      ```
    - **Content Set:** the content set your team uses for custom content.
    - **Command:**
      ```
      cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Remove-LegacyPython.ps1
      ```
    - **Command Timeout:** `15` minutes. Uninstalling all-users copies and their MSI components can take several minutes on a slow endpoint.
5. Under **Files**, click **Add File**, choose **Local File**, and upload `Remove-LegacyPython.ps1`.
6. This package has no parameters. Click **Save**.

---

## Deploy the package

1. Deploy the replacement Python first, if users need it. See [Give users a supported version first](#give-users-a-supported-version-first).
2. Ask users who need their packages to save the list. See [Save the user's packages](#save-the-users-packages).
3. In **Interact**, ask the question from [Find the endpoints](#find-the-endpoints).
4. Select the computers in the results grid.
5. Click **Deploy Action**.
6. In **Deployment Package**, search for and select `Remove Legacy Python 3.10-3.12 [Windows]`.
7. Under the schedule, leave it as a one-time action.
8. Click **Show preview to continue**, review the targets, then click **Deploy Action**.

For endpoints that return exit code `1` with `a file may be in use`, ask the user to close Python (including editors and terminals running it) and deploy again.

---

## View the results

### One endpoint

1. Open the action from **Administration** > **Actions** > **Action History**.
2. Select an endpoint.
3. Open its action log. The script output appears between the `Command Line` line and the `Completed` line. The last lines are the summary.

This example shows the format of the output for a signed-in user with a per-user Python 3.11 install. It is written to show the format, not captured from a real run:

```
2026-10-17 14:02:10 [INFO] Versions to remove: 3.10, 3.11, 3.12
2026-10-17 14:02:11 [INFO] Deleted C:\Users\jdoe\AppData\Local\Programs\Python\Python311
2026-10-17 14:02:11 [INFO] Deleted C:\Users\jdoe\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Python 3.11
2026-10-17 14:02:11 [INFO] Removed C:\Users\jdoe : 'Python 3.11.2 (64-bit)' uninstall entry
2026-10-17 14:02:11 [INFO] Removed C:\Users\jdoe : PythonCore\3.11 registry key
2026-10-17 14:02:11 [INFO] C:\Users\jdoe : removed 2 PATH entries
2026-10-17 14:02:12 [INFO] Summary:
2026-10-17 14:02:12 [INFO]   Removed: C:\Users\jdoe\AppData\Local\Programs\Python\Python311, ...
2026-10-17 14:02:12 [INFO]   Failed: none
2026-10-17 14:02:12 [INFO]   Still present: none
```

### Many endpoints

Ask a question with the built-in **Tanium Action Log** sensor, using the action ID from the top of the log:

```
Get Tanium Action Log[12345] from all machines
```

### Confirm Python is gone

Ask the question from [Find the endpoints](#find-the-endpoints) again. The endpoint should no longer return Python 3.10, 3.11, or 3.12. The **Installed Applications** sensor can return a cached result for a while after the change, so an endpoint that still shows it right after the action may clear on its own. If the removal was for a vulnerability finding, run the Comply assessment again afterward.

---

## Requirements

- Windows 10, Windows 11, or Windows Server endpoints with Windows PowerShell 5.1.
- The action must run as SYSTEM, which is the Tanium default. Without administrator rights, the script stops with exit code `5`.
- A Tanium account with permission to create packages in a content set and deploy actions to the target computers.

---

## Things to know

- **Users can reinstall the old version.** A per-user install needs no administrator rights, so a user can download Python 3.11 again and the finding comes back. If this keeps happening, the fix is a policy (application control or a standard Python version), not this package.
- **Signed-in users are cleaned too.** Their registry is edited live. A PATH change takes effect the next time the user signs in.
- **Folder deletes are checked, not assumed.** Each delete is checked afterward, and the final check looks for every `python.exe` the script knows about.
- **It runs as 64-bit.** If the Tanium client starts 32-bit PowerShell, the script restarts itself as 64-bit, so 64-bit registry entries are not missed.
- **Copies outside the known locations are not found.** A copy made by hand in a nested folder such as `C:\Tools\python3.11` or on another drive has no registry entry to follow. Use the path from Comply's **Actual Values** and the [Remove Folder](remove-folder.md) package for those.
- **Deleting the folder by hand is not enough.** It leaves the uninstall entry and PythonCore keys behind, and inventory keeps reporting the old version. Use this package instead.

---

## Test results

| Case | Expected | Result |
|---|---|---|
| Earlier version, per-user Python 3.11.2, signed-in user, through Tanium | Install folder removed | Pass. Folder confirmed gone in the file browser. |
| Current script, syntax check with the PowerShell parser | No errors | Pass |
| Current script, per-user install, signed-in user, through Tanium | Folder, uninstall entry, PythonCore key, PATH removed | **Not tested yet** |
| Current script, per-user install, signed-out profile | Hive loaded, cleaned, unloaded | **Not tested yet** |
| Current script, all-users install with cached installer | Uninstalled by the bundle, exit 0 | **Not tested yet** |
| Current script, all-users install, cached installer missing | MSI components removed, exit 0 | **Not tested yet** |
| Current script, `C:\Python311` copy with no registry entry | Folder removed | **Not tested yet** |
| Current script, `C:\Python314` present | Left alone | **Not tested yet** |
| Current script, not elevated | Exit 5, nothing changed | **Not tested yet** |

---

## Script

```powershell
--8<-- "tanium/packages/remove-legacy-python/Remove-LegacyPython.ps1"
```
