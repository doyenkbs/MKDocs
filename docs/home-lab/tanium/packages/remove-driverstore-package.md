---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Vulnerability Remediation
---

# Remove DriverStore Package (Package)

A parameterized Tanium package that removes old driver packages from the Windows DriverStore, by folder name.

Windows keeps a copy of every driver package it has installed under `C:\Windows\System32\DriverStore\FileRepository\`. When a driver is updated, the old copy usually stays behind. Vulnerability scanners and Tanium Comply read the files in those old copies, so a driver that was updated long ago can still be flagged for a library it bundles, such as OpenSSL.

This package removes the old copy the supported way, with `pnputil /delete-driver`. It never uses `/force`, so Windows refuses to remove a package that a device is still using.

For a worked example, see [OpenSSL in the Intel iCLS Driver (CVE-2024-13176)](../remediation/openssl-intel-icls.md).

!!! note "Test status"
    The lookup and delete steps ran through a Tanium action on a Windows 11 endpoint and removed a stale driver package (exit code `0`, folder gone). That run used an earlier single-folder version of the script with the same lookup and delete logic. The current script's input handling was tested locally through `cmd.exe` with URL-encoded parameters, including from 32-bit PowerShell. See [Test results](#test-results).

---

## Why the package works from the folder name

`pnputil /delete-driver` needs the package's **published name**, such as `oem59.inf`. Windows assigns that number on each machine when the driver is installed, so `oem59.inf` on one endpoint can be a completely different driver on the next one. A package that runs `pnputil /delete-driver oem59.inf` everywhere would either fail or delete the wrong driver.

The FileRepository folder name is the same on every machine for the same driver package. For example, `iclsclient.inf_amd64_c25dbc60ad3b371a` always holds the same files. The script takes the folder name, looks up the published name on each endpoint, and deletes that.

The folder name is what scanners and Comply report in the file path, so it can be copied straight from the finding.

---

## Parameters

| Parameter | Passed as | Required | What to enter |
|---|---|---|---|
| Folder Names | `$1` | Yes | One or more FileRepository folder names, separated by commas. Example: `iclsclient.inf_amd64_c25dbc60ad3b371a,iclsclient.inf_amd64_b4ad878dc01a7e41` |

- Enter the folder name only, not the full path.
- Each name must look like `<name>.inf_<architecture>_<16 hex characters>`. The architecture is `amd64`, `x86`, `arm64`, or `wow64`.
- Wildcards (`*` and `?`) are rejected.
- If any name in the list is invalid, the script stops before deleting anything.
- Spaces around the commas and uppercase letters are ignored.

---

## What it does not do

- **It does not remove a driver that is in use.** pnputil refuses, the script logs it, and the exit code is `2`. The fix for those machines is a newer driver from the vendor, deployed separately.
- **It does not remove orphaned folders.** A folder can exist under FileRepository with no driver package registered for it. pnputil can't see those folders, so the script reports them with exit code `1` and leaves them alone. Deleting them means taking ownership of a protected folder under `System32`, which this package does not do.
- **It does not touch Windows inbox drivers.** It only looks at third-party driver packages (the ones with an `oem##.inf` published name).

---

## Exit codes

Each folder in the list gets its own result in the action log. The action exits with the highest code from all of them.

| Exit code | Meaning |
|---|---|
| `0` | Every package was deleted, or was not on the machine to begin with. |
| `1` | At least one folder exists but no driver package is registered for it (orphaned). Nothing was deleted for that folder. |
| `2` | pnputil refused to delete at least one package. It is most likely the driver a device is using. |
| `3` | A folder name was blank or invalid, or the driver lookup failed. Nothing was deleted. |
| `4` | pnputil reported success, but the folder is still on disk. |

In Action History, exit codes other than `0` can show as **Failed**. Read the action log to see which folder caused it.

---

## Requirements

- Windows 10 or 11 endpoints with Windows PowerShell 5.1.
- The script runs as SYSTEM through the Tanium Client. It needs administrator rights for `Get-WindowsDriver` and `pnputil`.
- A Tanium account with permission to create packages in a content set and deploy actions to the target computers.

---

## Create the package

Menu labels can differ slightly between Tanium versions.

1. Save the script at the bottom of this page as `Remove-DriverStorePackage.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package**.
4. Fill in the fields:
    - **Package Name** and **Package Display Name:** `Remove DriverStore Package by Folder Name` (add your team's prefix if you use one).
    - **Description:** `Resolves the oem##.inf for each DriverStore FileRepository folder name (comma-separated) and deletes it with pnputil, without /force. Exit 0 deleted or absent, 1 orphaned folder, 2 in use, 3 invalid input or lookup error, 4 folder remains. Log: C:\Windows\Temp\Remove-DriverStorePackage.log`
    - **Content Set:** the content set your team uses for custom content.
    - **Command:**
      ```
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-DriverStorePackage.ps1 "$1"
      ```
    - **Command Timeout:** `10` minutes. `Get-WindowsDriver` can take up to a minute on some machines, and pnputil a few seconds per package.
    - **Download Timeout:** `10` minutes.
    - **Ignore Action Lock:** leave it cleared.
    - **Launch this package command in a process group:** select it, so Tanium can stop the PowerShell process if the command times out.
5. Under **Files**, click **Add**, choose **Local File**, and upload `Remove-DriverStorePackage.ps1`.
6. Expand **Parameters**. Under **Parameter Inputs**, add a **Text Input** parameter. It shows in the list as `$1`.
    - **Label:** `Folder Names`
    - **Provide Help Text:** select it and enter `Comma-separated FileRepository folder names, for example iclsclient.inf_amd64_c25dbc60ad3b371a`
    - **Default Value:** leave it blank.
7. Click **Save**.

---

## Deploy the package

1. Get the folder names from the finding. In Tanium Comply, open the vulnerability, select the failing test, and read the file path under **Actual Values**. The folder name is the part after `FileRepository\`.
2. In **Interact**, ask a question that returns only the machines that have the folder. Example:
    ```
    Get Computer Name and File Exists[C:\Windows\System32\DriverStore\FileRepository\iclsclient.inf_amd64_c25dbc60ad3b371a\iclsclient.inf] from all machines with File Exists[C:\Windows\System32\DriverStore\FileRepository\iclsclient.inf_amd64_c25dbc60ad3b371a\iclsclient.inf] contains "File exists"
    ```
    Run it once without the `with` filter to confirm the exact text the sensor returns on your Tanium version. Machines without the file return **File does not exist**.
3. Select the computers in the results grid.
4. Click **Deploy Action**.
5. In **Deployment Package**, search for and select `Remove DriverStore Package by Folder Name`.
6. In **Folder Names**, enter the folder name, or several names separated by commas.
7. Leave the schedule as a one-time action.
8. Click **Show preview to continue**, review the targets, then click **Deploy Action**.

Deploy to one machine first. Endpoints that do not have the folder finish with exit code `0`, so a broad target group is safe once the first run looks right.

---

## View the results

### One endpoint

1. Open the action from **Administration** > **Actions** > **Action History**.
2. Select an endpoint.
3. Open its action log. The script output appears between the `Command Line` line and the `Completed` line.

Package deleted:

```
2026-11-02 14:06:08  Decoded parameter: iclsclient.inf_amd64_c25dbc60ad3b371a
2026-11-02 14:06:08  Target folder: C:\WINDOWS\System32\DriverStore\FileRepository\iclsclient.inf_amd64_c25dbc60ad3b371a
2026-11-02 14:06:16  Found oem59.inf for iclsclient.inf_amd64_c25dbc60ad3b371a (version 1.74.210.0, date 08/01/2024 00:00:00)
2026-11-02 14:06:17  pnputil exit code 0. Output: Microsoft PnP Utility
Driver package deleted successfully.
2026-11-02 14:06:17  RESULT [iclsclient.inf_amd64_c25dbc60ad3b371a]: Driver package deleted and folder removed.
2026-11-02 14:06:17  Finished. Exit code 0.
```

Invalid folder name:

```
2026-11-05 00:12:56  Decoded parameter: iclsclient.inf_amd64_ZZZ
2026-11-05 00:12:56  ERROR: 'iclsclient.inf_amd64_zzz' is not a valid FileRepository folder name. Nothing was deleted.
```

The script also writes the same lines to `C:\Windows\Temp\Remove-DriverStorePackage.log` on the endpoint.

### Many endpoints

Ask a question with the built-in **Tanium Action Log** sensor, using the action ID from the top of the log:

```
Get Tanium Action Log[12345] from all machines
```

---

## Things to know

- **Parameters arrive URL-encoded.** Tanium passes `iclsclient.inf_amd64_c25dbc60ad3b371a` to the script as `iclsclient%2einf%5famd64%5fc25dbc60ad3b371a`, and commas as `%2c`. The script decodes the value before checking it. An earlier version without the decode step rejected every name with exit code `3`, which is the validation working as intended.
- **It runs as 64-bit.** If the Tanium Client starts 32-bit PowerShell, the script restarts itself as 64-bit. Without this, `pnputil.exe` and `Get-WindowsDriver` would not work against `C:\Windows\System32`.
- **The error "the specified file is not an installed OEM INF"** from a manual `pnputil /delete-driver` means the oem number does not match a registered package on that machine. Either the number came from another machine, or the folder is orphaned. This package avoids the first case by looking up the number on each endpoint.
- **Folder dates are not a reliable age.** After a pnputil delete, the **Date modified** on many FileRepository folders can change at the same time. Use the driver version in the action log, or the library version in the Comply finding, to tell old packages from new ones.
- **Removing an unused package is not the same as fixing the active driver.** If the flagged package is the one in use, exit code `2` is the signal to deploy a newer driver from the vendor first, then run this package again to remove the old copy.
- **Removed packages can't be rolled back from the DriverStore.** Reinstalling the driver from the vendor brings the package back if it is needed.

---

## Test results

The input cases ran on Windows 11 through `cmd.exe` from the script's folder, with URL-encoded parameters, the same way a Tanium package runs it. They ran as a standard user, not as SYSTEM.

| Case | Expected | Result |
|---|---|---|
| Invalid name, URL-encoded | Exit 3, nothing deleted | Pass |
| Wildcard, URL-encoded | Exit 3, nothing deleted | Pass |
| Blank value | Exit 3, nothing deleted | Pass |
| Two names with an encoded comma | Both names decoded and split | Pass |
| Parameter passed positionally (`"$1"`) | Same result as a named parameter | Pass |
| Started from 32-bit PowerShell | Restarts as 64-bit, same exit code | Pass |
| Stale registered package, through a Tanium action (single-folder version) | Exit 0, package and folder removed | Pass |
| Package in use | Exit 2, package kept | Not yet tested |
| Orphaned folder | Exit 1, folder kept | Not yet tested |

---

## Script

```powershell
--8<-- "tanium/packages/remove-driverstore-package/Remove-DriverStorePackage.ps1"
```
