---
tags:
  - Tanium
  - Tanium Comply
  - Vulnerability Remediation
  - Packages
---

# OpenSSL in the Intel iCLS Driver (CVE-2024-13176)

Tanium Comply can flag CVE-2024-13176 on Windows machines that have no OpenSSL installed. The files it finds belong to the **Intel iCLS Client** driver, a component of the Intel Management Engine software. The driver bundles its own copy of `libssl-3-x64.dll` and `libcrypto-3-x64.dll`, and Windows keeps every old version of the driver in the DriverStore.

The DLLs can't be patched on their own. The fix is to remove the old driver packages that nobody uses, and to update the iCLS driver where the old version is still the active one.

!!! note "Test status"
    The scope question and the removal package were run through Tanium on a Windows 11 endpoint with three iCLS driver packages in its DriverStore. Removing the stale package worked (exit code `0`). The cases for an in-use package and an orphaned folder have not been tested yet.

---

## Fix level

| OpenSSL branch | Fixed in |
|---|---|
| 1.0.2 | 1.0.2zl |
| 1.1.1 | 1.1.1zb |
| 3.0 | 3.0.16 |
| 3.1 | 3.1.8 |
| 3.2 | 3.2.4 |
| 3.3 | 3.3.3 |
| 3.4 | 3.4.1 |

The iCLS driver uses the 3.0 branch, so any copy below `3.0.16` is flagged.

### How serious it is

CVE-2024-13176 is a timing side channel in ECDSA signatures that use the NIST P-521 curve. An attacker has to measure the time of a large number of signatures, either from the same machine or over a very fast, low-latency network, to recover the private key. The CVSS v3 base score in Comply is 4.1.

That makes it a low-priority finding. It still shows on reports, so it is worth cleaning up, and the cleanup is low risk.

---

## Why the machine is flagged

The files live in a folder like this one:

```
C:\Windows\System32\DriverStore\FileRepository\iclsclient.inf_amd64_<16 hex characters>\lib\
```

- Each version of the iCLS driver gets its own folder. The 16 characters at the end are fixed for that driver package, so the same folder name means the same files on every machine.
- When Windows installs a newer iCLS driver, the old folder usually stays. One machine can have several.
- Comply checks every folder, not only the one in use. A machine with a current iCLS driver can still be flagged for an old copy left in the DriverStore.

Examples of flagged folders:

| Folder | iCLS version | OpenSSL in `lib\` |
|---|---|---|
| `iclsclient.inf_amd64_c25dbc60ad3b371a` | 1.74.210.0 | 3.0.14 |
| `iclsclient.inf_amd64_b4ad878dc01a7e41` | Not recorded | 3.0.13 |

Your environment may have other folder names. Use the ones Comply reports.

---

## Find the scope

### 1. Collect the folder names from Comply

1. In Tanium Comply, open **CVE-2024-13176**.
2. Select a failing test, such as **Check if the version of Libssl is ...** or **Check if the version of Libcrypto is ...**.
3. Read **Actual Values**. Each result shows a `filepath` and a `product_version`.
4. Click **View Endpoints** and export the list.
5. From the file paths, write down every distinct folder name after `FileRepository\`. Note the `product_version` for each one.

Both `libssl-3-x64.dll` and `libcrypto-3-x64.dll` sit in the same `lib\` folder, so one folder can fail two tests. Removing the folder clears both.

### 2. Confirm in Interact

Replace the folder name with one from your list:

```
Get Computer Name and File Version[C:\Windows\System32\DriverStore\FileRepository\iclsclient.inf_amd64_c25dbc60ad3b371a\lib\libcrypto-3-x64.dll] from all machines with ( Windows OS Type equals "Windows Workstation" and File Exists[C:\Windows\System32\DriverStore\FileRepository\iclsclient.inf_amd64_c25dbc60ad3b371a\lib\libcrypto-3-x64.dll] contains "File exists" )
```

To check two folders in one question:

```
Get Computer Name and File Version[C:\Windows\System32\DriverStore\FileRepository\iclsclient.inf_amd64_c25dbc60ad3b371a\lib\libcrypto-3-x64.dll] and File Version[C:\Windows\System32\DriverStore\FileRepository\iclsclient.inf_amd64_b4ad878dc01a7e41\lib\libcrypto-3-x64.dll] from all machines with ( Windows OS Type equals "Windows Workstation" and ( File Exists[C:\Windows\System32\DriverStore\FileRepository\iclsclient.inf_amd64_c25dbc60ad3b371a\lib\libcrypto-3-x64.dll] contains "File exists" or File Exists[C:\Windows\System32\DriverStore\FileRepository\iclsclient.inf_amd64_b4ad878dc01a7e41\lib\libcrypto-3-x64.dll] contains "File exists" ) )
```

- Run `Get File Exists[<path>] from all machines` once without a filter to confirm the exact text the sensor returns on your Tanium version. A missing file returns **File does not exist**.
- Drop the `Windows OS Type` part to include servers. The iCLS driver is mostly found on workstations, but a server built from a workstation image can have it.
- **Folder Contents** is not a good filter here. It returns the list of files in the folder, not true or false, so `Folder Contents[...] contains true` matches nothing.

---

## Fix

### Step 1: Remove the stale packages

1. [Create the Remove DriverStore Package package](../packages/remove-driverstore-package.md#create-the-package).
2. Target the machines from [question 2](#2-confirm-in-interact).
3. In **Folder Names**, enter the flagged folder names, separated by commas. Example:
    ```
    iclsclient.inf_amd64_c25dbc60ad3b371a,iclsclient.inf_amd64_b4ad878dc01a7e41
    ```
4. Deploy to one machine first and read the action log.
5. Deploy to the rest.

Only enter folders that Comply flagged. A machine usually has one iCLS package in use and keeps it. Removing an unflagged package gains nothing and removes the copy Windows would use to reinstall the driver.

### Step 2: Act on the exit code

| Exit code | What it means | What to do |
|---|---|---|
| `0` | The stale package was removed, or was not there | Go to [Verify](#verify) |
| `2` | The flagged package is the iCLS driver in use | Update the iCLS driver (Step 3), then run Step 1 again |
| `1` | The folder exists but no driver package is registered for it | Record a risk exception, or plan a manual cleanup. pnputil can't remove it |
| `3` | Invalid folder name or lookup error | Check the folder names and the action log |

### Step 3: Update the iCLS driver where the old one is active

1. Get a newer iCLS Client driver package from the Microsoft Update Catalog or from the computer maker's Intel Management Engine driver bundle.
2. Install it on one test machine. Then confirm the `libcrypto-3-x64.dll` and `libssl-3-x64.dll` in its new `FileRepository\iclsclient.inf_amd64_<hash>\lib\` folder are version `3.0.16` or later. Not every newer iCLS build ships a fixed OpenSSL, so check before deploying.
3. Deploy the driver through Tanium Deploy or a package.
4. Run Step 1 again for the old folder. Once the new driver is active, the old package is no longer in use and pnputil can remove it.

---

## Verify

1. Rerun [question 2](#2-confirm-in-interact). The removed folders should return **File does not exist**.
2. In Comply, run a new vulnerability scan on the affected machines.
3. Open CVE-2024-13176 again. The machines should no longer appear under **View Endpoints**.

---

## Related

- [Remove DriverStore Package](../packages/remove-driverstore-package.md)
- [Defender Vulnerability Remediation](defender-vulnerabilities.md), another case where a scanner flags files that are no longer in use.
