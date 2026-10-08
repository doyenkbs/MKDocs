---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Endpoint Management
---

# Remove File (Package)

A parameterized Tanium package that deletes one file from Windows endpoints.

The operator types the file name a second time before anything is deleted. The script also refuses files in Windows system folders, boot files, and anything in the Tanium Client folder, whatever is typed.

Use this package to remove a single file that a scan or a ticket has flagged, such as a vulnerable DLL left behind by an old install, a stale configuration file, or a log file that has grown too large. To delete a whole folder, use [Remove Folder](remove-folder.md) instead. To find where a file is first, use [Find File by Name](find-file-by-name.md).

!!! note "Test status"
    Tested on Windows 11 Pro 24H2 with Windows PowerShell 5.1. Each test ran the script through `cmd.exe` from the script's own folder with URL-encoded parameters, the same way a Tanium package runs it. The tests ran as a standard user, not as SYSTEM, and have not yet been repeated through a Tanium action. See [Test results](#test-results).

---

## Why there is a confirmation parameter

The package runs as SYSTEM, which can delete almost any file on the endpoint. A typo, or a path pasted from the wrong ticket, would delete the wrong file without any prompt.

The **Confirm Name** parameter must match the file name, extension included. For `C:\ProgramData\ExampleApp\example.dll`, the operator types `example.dll`. Typing `example` without the extension does not match. If the two do not match, nothing is deleted and the action log says why.

This catches careless mistakes. It does not stop someone who types the wrong path twice, which is why the script also has a list of [locations it refuses to touch](#what-it-refuses-to-delete).

---

## Parameters

| Parameter | Passed as | Required | What to enter |
|---|---|---|---|
| File Path | `$1` | Yes | Full local path of the file. Example: `C:\ProgramData\ExampleApp\example.dll` |
| Confirm Name | `$2` | Yes | The file name with its extension, typed again. Example: `example.dll`. Not case sensitive. |

- The path must start with a drive letter, such as `C:\`. Network paths (`\\server\share\file.txt`) and relative paths are rejected.
- Wildcards (`*` and `?`) are rejected. The package deletes exactly one file per action.
- A path that ends with a backslash is treated as a folder and rejected.

Tanium replaces `$1` and `$2` in the command line with the values you enter, in the order the parameters are defined in the package. File Path must be the first parameter and Confirm Name the second.

---

## What it refuses to delete

The script stops with exit code `4`, and deletes nothing, when the file is:

- Anywhere under `C:\Windows\System32`, `C:\Windows\SysWOW64`, `C:\Windows\WinSxS`, or `C:\Windows\Boot`.
- Anywhere under `C:\Boot` or `C:\Recovery`.
- Directly in `C:\`, such as `pagefile.sys`, `hiberfil.sys`, or `bootmgr`.
- Directly in `C:\Windows`, such as `explorer.exe`.
- Anywhere in the Tanium Client folder.
- A symbolic link.

Paths are resolved before they are checked, so `C:\Temp\..\Windows\System32\notepad.exe` is caught as a System32 file.

Files under `C:\Program Files` and `C:\ProgramData` are allowed on purpose. Removing a single file left behind by an application, such as an old DLL flagged by a vulnerability scan, is one of the main uses for this package.

---

## Exit codes

| Exit code | Meaning |
|---|---|
| `0` | The file was deleted, or it was not there to begin with. |
| `1` | The delete failed. Usually the file is in use by a running program or service. |
| `2` | File Path was blank, not a full local path, contained a wildcard, ended with a backslash, or pointed to a folder. |
| `3` | Confirm Name did not match the file name. Nothing was deleted. |
| `4` | The file is in a protected location, or it is a symbolic link. Nothing was deleted. |

In Action History, exit codes other than `0` can show as **Failed**. For codes `2`, `3`, and `4`, that is the script working as intended: it stopped before deleting anything.

---

## Requirements

- Windows endpoints with Windows PowerShell 5.1.
- A Tanium account with permission to create packages in a content set and deploy actions to the target computers.

---

## Create the package

Menu labels can differ slightly between Tanium versions.

1. Save the script at the bottom of this page as `Remove-File.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package**.
4. Fill in the fields:
    - **Package Display Name:** `Remove File` (add your team's prefix if you use one).
    - **Content Set:** the content set your team uses for custom content.
    - **Command:**
      ```
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-File.ps1 "$1" "$2"
      ```
    - **Command Timeout:** `5` minutes. The script normally finishes in a few seconds.
5. Under **Files**, click **Add**, choose **Local File**, and upload `Remove-File.ps1`.
6. Expand **Parameters**. Under **Parameter Inputs**, add a **Text Input** parameter. It shows in the list as `$1`.
    - **Label:** `File Path`
    - **Provide Help Text:** select it and enter `Full path of the file to delete, for example C:\ProgramData\ExampleApp\example.dll`
7. Add a second **Text Input** parameter. It shows in the list as `$2`.
    - **Label:** `Confirm Name`
    - **Provide Help Text:** select it and enter `Type the file name again with its extension, for example example.dll`
8. In the **Preview** panel on the right, confirm you see **File Path** followed by **Confirm Name**.
9. Click **Save**.

---

## Deploy the package

1. In **Interact**, ask a question that returns the computers you want to clean up. Example:
    ```
    Get Computer Name from all machines with Computer Name starts with "nyc-"
    ```
2. Select the computers in the results grid.
3. Click **Deploy Action**.
4. In **Deployment Package**, search for and select `Remove File`.
5. In **File Path**, enter the full path, for example `C:\ProgramData\ExampleApp\example.dll`.
6. In **Confirm Name**, type the file name again, for example `example.dll`.
7. Under the schedule, leave it as a one-time action.
8. Click **Show preview to continue**, review the targets, then click **Deploy Action**.

Endpoints that do not have the file finish with exit code `0` and log `File not found. Nothing to do.`, so it is safe to target a broad group.

---

## View the results

### One endpoint

1. Open the action from **Administration** > **Actions** > **Action History**.
2. Select an endpoint.
3. Open its action log. The script output appears between the `Command Line` line and the `Completed` line.

File deleted. The size, date, and attributes are logged before the delete, so there is a record of what was removed:

```
2026-10-08 11:19:40 [INFO] Requested file: 'C:\ProgramData\ExampleApp\example.dll'
2026-10-08 11:19:40 [INFO] Confirmation value: 'example.dll'
2026-10-08 11:19:40 [INFO] Resolved file: 'C:\ProgramData\ExampleApp\example.dll'
2026-10-08 11:19:40 [INFO] Confirmation matched file name 'example.dll'.
2026-10-08 11:19:40 [INFO] Deleting 'C:\ProgramData\ExampleApp\example.dll' (348,160 bytes, modified 2023-03-31 08:18, attributes: ReadOnly).
2026-10-08 11:19:40 [INFO] File deleted.
```

Confirmation without the extension:

```
2026-10-08 11:19:39 [ERROR] Confirmation 'example' does not match file name 'example.dll'. Nothing deleted.
```

Protected location:

```
2026-10-08 11:19:45 [ERROR] Refusing to delete 'C:\Windows\System32\drivers\etc\hosts': inside protected folder (C:\Windows\System32). Nothing deleted.
```

File in use:

```
2026-10-08 11:19:42 [ERROR] Delete error: The process cannot access the file 'C:\ProgramData\ExampleApp\example.log' because it is being used by another process.
2026-10-08 11:19:42 [ERROR] File still exists. It is most likely locked by a running process or service.
```

### Many endpoints

Ask a question with the built-in **Tanium Action Log** sensor, using the action ID from the top of the log:

```
Get Tanium Action Log[12345] from all machines
```

---

## Things to know

- **Parameters arrive URL-encoded.** Tanium passes `C:\ProgramData\ExampleApp\example.dll` to the script as `C%3A%5CProgramData%5CExampleApp%5Cexample.dll`. The script decodes it, and strips extra quotes and spaces, before using it.
- **It runs as 64-bit.** If the Tanium client starts 32-bit PowerShell, the script restarts itself as 64-bit. Without this, a path under `C:\Windows\System32` would point to `C:\Windows\SysWOW64` instead.
- **There is no Recycle Bin.** A file deleted by the package is gone. Run a test action on one endpoint before deploying widely.
- **Hidden, system, and read-only files are deleted too.**
- **A locked file is not retried.** If a service holds the file open, stop the service first (for example with another package), or deploy the action again after a reboot.
- **An application may recreate the file.** If the file belongs to software that is still installed, removing the file alone may only last until the application repairs itself or updates. Uninstall or update the application instead when that is the real fix.

---

## Test results

Each case ran through `cmd.exe` with URL-encoded parameters. Real deletes ran only against test files created for the purpose. Protected-location cases ran against a copy of the script with the delete command replaced by a stub, so a failed check would have shown up in the log without deleting anything.

| Case | Expected | Result |
|---|---|---|
| Blank path | Exit 2 | Pass |
| Path ending in a backslash | Exit 2 | Pass |
| Wildcard | Exit 2 | Pass |
| Confirmation without the extension | Exit 3, file kept | Pass |
| Read-only, hidden file with a space in the name | Exit 0, file deleted | Pass |
| File already gone | Exit 0 | Pass |
| Folder path instead of a file | Exit 2, folder kept | Pass |
| File held open by another process | Exit 1, file kept | Pass |
| Run from 32-bit PowerShell | Restarts as 64-bit, exit 0 | Pass |
| Symbolic link | Exit 4, link and target kept | Pass |
| `hosts` in System32, a file in SysWOW64, a file in WinSxS | Exit 4 | Pass |
| `C:\pagefile.sys`, `C:\Windows\explorer.exe` | Exit 4 | Pass |
| `..\` path that resolves into System32 | Exit 4 | Pass |
| File in the Tanium Client folder | Exit 4 | Pass |

---

## Script

```powershell
--8<-- "tanium/packages/remove-file/Remove-File.ps1"
```
