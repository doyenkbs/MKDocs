---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Endpoint Management
---

# Windows Component Cleanup (DISM) (Package)

This Tanium package makes the Windows component store smaller. The component store is the folder `C:\Windows\WinSxS`.

Each Windows update keeps the old versions of the files that it replaces. The package tells Windows to remove the old versions that Windows does not need. It uses this Microsoft command:

```text
dism.exe /Online /Cleanup-Image /StartComponentCleanup
```

The package does not restart the endpoint.

!!! warning "Test status"
    The package was run through Tanium on an endpoint with ResetBase set to `Yes`. The run completed with exit code `0` and freed 5.05 GB. **A run with ResetBase set to `No` was not tested.** Deploy to one endpoint first and read the action log.

!!! warning "The ResetBase option"
    The **ResetBase** option frees more space. But after you use it, you cannot uninstall the updates that are installed now. Updates that you install later are not affected.

## What the package does

1. Makes sure that Windows does not wait for a restart. If Windows must restart to complete an update installation, the package stops. It uses exit code 2.
2. Asks Windows how much space the cleanup can free. It writes the result to the action log.
3. Starts the cleanup.
4. Writes the free space before and after the cleanup to the action log.

The cleanup can take from a few minutes to more than one hour.

## When to use ResetBase

Windows does a component cleanup automatically on a schedule. On an endpoint that Windows cleans regularly, the cleanup without ResetBase frees little space. Most of the space comes from ResetBase.

| Setting | Use it when |
|---|---|
| `No` (default) | You want a safe cleanup. You can run it on many endpoints at a time. |
| `Yes` | The current monthly updates are stable, and you do not plan to uninstall them. For example, wait one to two weeks after the monthly updates install. |

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1
- The Tanium Client

## Create the package

1. In the Tanium Console, go to **Administration > Content > Packages**.
2. Click **Create Package**.
3. Fill in the fields with the values in the table below.
4. In the **Files** section, add the script file.
5. In the **Parameters** section, add the parameter in the second table below.
6. Click **Save**.

| Field | Value |
|---|---|
| Package Name | `Windows Component Cleanup (DISM)` |
| Display Name | `Windows Component Cleanup (DISM)` |
| Description | `Shrinks the Windows component store (C:\Windows\WinSxS) by removing old versions of files replaced by updates, using DISM /StartComponentCleanup. Reports how much can be freed first. Skips the computer if Windows is waiting for a restart. Optional ResetBase frees more, but updates installed today can no longer be uninstalled. Does not restart the computer. Windows only.` |
| Content Set | Your custom content set |
| Command | `cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Invoke-ComponentCleanup.ps1 "$1"` |
| Command Timeout | 120 minutes |
| Download Timeout | 10 minutes |
| Ignore Action Lock | Clear (not selected) |
| Launch this package command in a process group | Selected |
| Files | `Invoke-ComponentCleanup.ps1` |

### Parameter

| Key | Type | Label | Values | Default |
|---|---|---|---|---|
| `$1` | Drop Down List | Use ResetBase (installed updates can no longer be uninstalled) | No, Yes | No |

## Deploy the package

1. In the Tanium Console, go to **Interact**.
2. In the question bar, type this question:

    ```text
    Get Computer Name and Disk Free Space from all machines with Is Windows equals True
    ```

3. Press Enter.
4. Select the endpoints that you want to clean.
5. Click **Deploy Action**.
6. In the **Deployment Package** field, type `Windows Component Cleanup (DISM)`. Select the package.
7. Set **Use ResetBase** to `No` or `Yes`. Read [When to use ResetBase](#when-to-use-resetbase) first.
8. Click **Show preview to continue**.
9. Make sure that the list shows the correct endpoints.
10. Click **Deploy Action**.

!!! tip
    The cleanup uses much processor and disk time. Deploy it outside of work hours when possible.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | The cleanup completed. |
| 1 | The cleanup failed. Read the action log. |
| 2 | Windows waits for a restart. The cleanup did not start. Restart the endpoint, then deploy again. |

## Read the results

The action log shows the DISM analysis, the cleanup result, and the free space before and after.

To read the action log from the Tanium Console:

1. Go to **Interact**.
2. Type this question. Replace `<action ID>` with the ID of your action.

    ```text
    Get Tanium Action Log[<action ID>] from all machines with Computer Name equals ENDPOINT-01
    ```

3. Press Enter.

### Example log

```text
[INFO] Free space on C: before: 132.89 GB
[INFO] Asking Windows how much can be cleaned up (this can take a few minutes).
    Actual Size of Component Store : 17.68 GB
    Backups and Disabled Features : 9.19 GB
    Component Store Cleanup Recommended : Yes
[INFO] Starting the cleanup with /ResetBase. Updates that are installed now can no longer be uninstalled afterwards.
    The operation completed successfully.
[INFO] Free space on C: after: 137.95 GB (change: 5.05 GB)
[INFO] Windows component cleanup finished with exit code 0.
```

In the analysis, **Backups and Disabled Features** shows the old update files. **Component Store Cleanup Recommended** shows if Windows thinks that a cleanup is necessary.

## Troubleshooting

| Log message | Cause | Action |
|---|---|---|
| `Windows is waiting for a restart` | An update installation is not complete. | Restart the endpoint. Then deploy again. |
| `The cleanup failed with DISM code ...` | DISM could not complete the cleanup. | The full details are in `C:\Windows\Logs\DISM\dism.log` on the endpoint. |
| `Windows asks for a restart to complete it` | The cleanup completed, but Windows must restart to complete some work. | Restart the endpoint at a convenient time. |
| The command timeout occurs | The cleanup takes more than 120 minutes. | Increase the command timeout. Then deploy again. |

## Script

### Invoke-ComponentCleanup.ps1

```powershell
--8<-- "tanium/packages/windows-component-cleanup/Invoke-ComponentCleanup.ps1"
```

## Related

- [Free Up User Disk Space](free-up-user-disk-space.md)
