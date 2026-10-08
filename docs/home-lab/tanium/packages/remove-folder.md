---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Endpoint Management
---

# Remove Folder (Package)

A parameterized Tanium package that deletes one folder, and everything inside it, from Windows endpoints.

The operator types the folder's name a second time before anything is deleted. The script also refuses system folders, user profile roots, and the Tanium Client folder, whatever is typed.

Use this package to clean up leftover application folders, failed install directories, or cached data that is blocking a reinstall. To delete a single file, use [Remove File](remove-file.md) instead.

!!! note "Test status"
    Tested on Windows 11 Pro 24H2 with Windows PowerShell 5.1. Each test ran the script through `cmd.exe` from the script's own folder with URL-encoded parameters, the same way a Tanium package runs it. The tests ran as a standard user, not as SYSTEM, and have not yet been repeated through a Tanium action. See [Test results](#test-results).

---

## Why there is a confirmation parameter

The package runs as SYSTEM, which can delete almost anything on the endpoint. A typo, or a path pasted from the wrong ticket, would delete the wrong folder without any prompt.

The **Confirm Name** parameter must match the last part of the folder path. For `C:\ProgramData\ExampleApp`, the operator types `ExampleApp`. If the two do not match, nothing is deleted and the action log says why.

This catches careless mistakes. It does not stop someone who types the wrong path twice, which is why the script also has a list of [folders it refuses to delete](#what-it-refuses-to-delete).

---

## Parameters

| Parameter | Passed as | Required | What to enter |
|---|---|---|---|
| Folder Path | `$1` | Yes | Full local path of the folder. Example: `C:\ProgramData\ExampleApp` |
| Confirm Name | `$2` | Yes | The folder's name, typed again. Example: `ExampleApp`. Not case sensitive. |

- The path must start with a drive letter, such as `C:\`. Network paths (`\\server\share`) and relative paths are rejected.
- Wildcards (`*` and `?`) are rejected. The package deletes exactly one folder per action.
- A trailing backslash makes no difference. `C:\ProgramData\ExampleApp\` and `C:\ProgramData\ExampleApp` are treated the same.

Tanium replaces `$1` and `$2` in the command line with the values you enter, in the order the parameters are defined in the package. Folder Path must be the first parameter and Confirm Name the second.

---

## What it refuses to delete

The script stops with exit code `4`, and deletes nothing, when the folder is one of these:

- A drive root, such as `C:\`.
- `C:\Windows`, `C:\Windows\System32`, or `C:\Windows\SysWOW64`.
- `C:\Program Files`, `C:\Program Files (x86)`, or `C:\ProgramData`.
- `C:\Users`, `C:\Users\Public`, or `C:\Users\Default`.
- A user profile root, such as `C:\Users\jdoe`. Deleting the folder leaves a broken profile behind. Remove profiles through Windows instead.
- Any folder that contains one of the folders above. For example, `C:\` contains all of them.
- The Tanium Client folder, or anything inside it. Deleting it would break the client while the action is still running.
- A junction or symbolic link. Deleting through a link can remove the contents of the folder it points to.

Paths are resolved before they are checked, so `C:\Temp\..\Windows` is caught as `C:\Windows`.

Folders inside those locations are allowed. `C:\ProgramData\ExampleApp` and `C:\Program Files\ExampleApp` are exactly what the package is for.

---

## Exit codes

| Exit code | Meaning |
|---|---|
| `0` | The folder was deleted, or it was not there to begin with. |
| `1` | The delete failed or only partly worked. Usually a file inside the folder is in use. |
| `2` | Folder Path was blank, not a full local path, contained a wildcard, or pointed to a file. |
| `3` | Confirm Name did not match the folder's name. Nothing was deleted. |
| `4` | The folder is protected, or it is a junction or symbolic link. Nothing was deleted. |

In Action History, exit codes other than `0` can show as **Failed**. For codes `2`, `3`, and `4`, that is the script working as intended: it stopped before deleting anything.

---

## Requirements

- Windows endpoints with Windows PowerShell 5.1.
- A Tanium account with permission to create packages in a content set and deploy actions to the target computers.

---

## Create the package

Menu labels can differ slightly between Tanium versions.

1. Save the script at the bottom of this page as `Remove-Folder.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package**.
4. Fill in the fields:
    - **Package Display Name:** `Remove Folder` (add your team's prefix if you use one).
    - **Content Set:** the content set your team uses for custom content.
    - **Command:**
      ```
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-Folder.ps1 "$1" "$2"
      ```
    - **Command Timeout:** `15` minutes. Most folders delete in a few seconds, but a folder with hundreds of thousands of small files can take several minutes.
5. Under **Files**, click **Add**, choose **Local File**, and upload `Remove-Folder.ps1`.
6. Expand **Parameters**. Under **Parameter Inputs**, add a **Text Input** parameter. It shows in the list as `$1`.
    - **Label:** `Folder Path`
    - **Provide Help Text:** select it and enter `Full path of the folder to delete, for example C:\ProgramData\ExampleApp`
7. Add a second **Text Input** parameter. It shows in the list as `$2`.
    - **Label:** `Confirm Name`
    - **Provide Help Text:** select it and enter `Type the folder name again, for example ExampleApp`
8. In the **Preview** panel on the right, confirm you see **Folder Path** followed by **Confirm Name**.
9. Click **Save**.

---

## Deploy the package

1. In **Interact**, ask a question that returns the computers you want to clean up. Example:
    ```
    Get Computer Name from all machines with Computer Name starts with "nyc-"
    ```
2. Select the computers in the results grid.
3. Click **Deploy Action**.
4. In **Deployment Package**, search for and select `Remove Folder`.
5. In **Folder Path**, enter the full path, for example `C:\ProgramData\ExampleApp`.
6. In **Confirm Name**, type the folder name again, for example `ExampleApp`.
7. Under the schedule, leave it as a one-time action.
8. Click **Show preview to continue**, review the targets, then click **Deploy Action**.

Endpoints that do not have the folder finish with exit code `0` and log `Folder not found. Nothing to do.`, so it is safe to target a broad group.

---

## View the results

### One endpoint

1. Open the action from **Administration** > **Actions** > **Action History**.
2. Select an endpoint.
3. Open its action log. The script output appears between the `Command Line` line and the `Completed` line.

Folder deleted:

```
2026-10-08 11:19:09 [INFO] Requested folder: 'C:\ProgramData\ExampleApp'
2026-10-08 11:19:09 [INFO] Confirmation value: 'ExampleApp'
2026-10-08 11:19:09 [INFO] Resolved folder: 'C:\ProgramData\ExampleApp'
2026-10-08 11:19:10 [INFO] Confirmation matched folder name 'ExampleApp'.
2026-10-08 11:19:10 [INFO] Deleting 'C:\ProgramData\ExampleApp' (4 items inside).
2026-10-08 11:19:10 [INFO] Folder deleted.
```

Confirmation did not match:

```
2026-10-08 11:19:08 [ERROR] Confirmation 'ExampleAp' does not match folder name 'ExampleApp'. Nothing deleted.
```

Protected folder:

```
2026-10-08 11:19:14 [ERROR] Refusing to delete 'C:\Users\jdoe': user profile root (remove profiles through Windows, not by deleting the folder). Nothing deleted.
```

A file inside the folder is in use:

```
2026-10-08 11:19:12 [ERROR] Folder still exists. 2 items remain. 3 delete errors.
2026-10-08 11:19:12 [ERROR]   The process cannot access the file 'C:\ProgramData\ExampleApp\cache\data.db' because it is being used by another process.
```

### Many endpoints

Ask a question with the built-in **Tanium Action Log** sensor, using the action ID from the top of the log:

```
Get Tanium Action Log[12345] from all machines
```

---

## Things to know

- **Parameters arrive URL-encoded.** Tanium passes `C:\ProgramData\ExampleApp` to the script as `C%3A%5CProgramData%5CExampleApp`. The script decodes it, and strips extra quotes and spaces, before using it.
- **It runs as 64-bit.** If the Tanium client starts 32-bit PowerShell, the script restarts itself as 64-bit. Without this, a path under `C:\Windows\System32` would point to `C:\Windows\SysWOW64` instead.
- **There is no Recycle Bin.** Files deleted by the package are gone. Check the path in a test action on one endpoint before deploying widely.
- **Locked files leave a partial delete.** The script deletes everything it can, then exits with code `1` and logs up to five of the errors. Stop the application that holds the files, or reboot, and run the action again.
- **Hidden, system, and read-only files are deleted too.**
- **Only the folder itself is checked for links.** If the target folder contains a junction to somewhere else, that case has not been tested. Test on one endpoint first if the folder might contain links.
- **The item count is logged before the delete,** so the action log shows how much was removed.

---

## Test results

Each case ran through `cmd.exe` with URL-encoded parameters. Real deletes ran only against test folders created for the purpose. Protected-folder cases ran against a copy of the script with the delete command replaced by a stub, so a failed check would have shown up in the log without deleting anything.

| Case | Expected | Result |
|---|---|---|
| Blank path | Exit 2 | Pass |
| Relative path, UNC path, wildcard | Exit 2 | Pass |
| Wrong confirmation | Exit 3, folder kept | Pass |
| Path with spaces, hidden and read-only files inside | Exit 0, folder deleted | Pass |
| Folder already gone | Exit 0 | Pass |
| Confirmation typed in a different case | Exit 0, folder deleted | Pass |
| File path instead of a folder | Exit 2, file kept | Pass |
| Junction | Exit 4, junction and its target kept | Pass |
| File inside the folder held open | Exit 1, locked file kept | Pass |
| Run from 32-bit PowerShell | Restarts as 64-bit, exit 0 | Pass |
| `C:\`, `C:\Windows`, `System32`, both Program Files folders, `ProgramData` | Exit 4 | Pass |
| `C:\Users`, `C:\Users\Public`, a profile root | Exit 4 | Pass |
| `..\` path that resolves to `C:\Users`, `C:\.`, trailing slash on `C:\Windows\` | Exit 4 | Pass |
| Tanium Client folder and a folder inside it | Exit 4 | Pass |

---

## Script

```powershell
--8<-- "tanium/packages/remove-folder/Remove-Folder.ps1"
```
