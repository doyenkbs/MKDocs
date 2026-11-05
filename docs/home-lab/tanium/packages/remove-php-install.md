---
tags:
  - Tanium
  - PowerShell
  - Packages
  - PHP
---

# Remove PHP Install (Package)

A Tanium package that deletes an old PHP folder from a Windows computer. A common example is `C:\Program Files (x86)\PHP\v7.1`, often left behind by the old Microsoft Web Platform Installer. The package also removes PHP from the installed programs list and from the system PATH, so inventory and vulnerability scans stop reporting it.

It deletes only the one folder you type in. It doesn't look at the PHP version. To protect other PHP copies, it only deletes folders directly inside `C:\Program Files (x86)\PHP` or `C:\Program Files\PHP`.

!!! warning "Test status"
    Tested in a lab through Tanium. The script correctly refused to remove PHP while IIS was still using it, and correctly refused a folder outside `Program Files\PHP`. **The removal itself has not been tested yet.** See [Test results](#test-results).

---

## What the script does

First it checks that it's safe to delete. If any check fails, it stops and changes nothing:

1. **Is it the right kind of folder?** The folder must be directly inside `C:\Program Files (x86)\PHP` or `C:\Program Files\PHP`, and must contain `php.exe`.
2. **Is a website using it?** If IIS (the Windows web server) is set up to run PHP from this folder, the script stops. Deleting the folder would break those websites. **Force does not skip this check.** Remove the IIS settings first with [Remove IIS PHP Handler](remove-iis-php-handler.md).
3. **Is PHP running right now?** If a program is running from the folder, the script stops. If you set **Force** to `Yes`, it closes those programs, waits 5 seconds, and checks again. If they started again on their own, something (a service or scheduled task) keeps launching them, and the script stops.

If everything is safe, it:

1. Runs PHP's uninstaller, if PHP was installed with one (an MSI installer).
2. Deletes the folder.
3. Removes PHP from the installed programs list, if it's still there.
4. Removes the folder from the system PATH.

Every step is written to the Tanium action log and to `C:\Windows\Temp\Remove-PHPInstall.log` on the computer.

---

## Exit codes

The exit code tells you how the action ended. You'll find it at the end of the action log.

| Exit code | Meaning |
|---|---|
| `0` | The folder was removed, or it was already gone. |
| `1` | Something went wrong. Look for lines with `[ERROR]` in the action log. |
| `2` | The script stopped on purpose because it wasn't safe to delete. IIS uses the folder, PHP is running (or started again after Force), or the folder isn't in an allowed place. Nothing was changed. |

---

## Create the package

1. Save the [script](#script) at the bottom of this page as `Remove-PHPInstall.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package** and fill in:

| Field | Value |
|---|---|
| Package Name | `<prefix> - Remove PHP Install (Windows)` |
| Display Name | `<prefix> - Remove PHP Install (Windows)` |
| Description | `Deletes one old PHP folder inside Program Files\PHP or Program Files (x86)\PHP, and removes it from the installed programs list and PATH. Stops if IIS uses the folder. Force = Yes closes PHP programs running from the folder. Exit 0 removed or already gone, 1 failed, 2 stopped because it was not safe.` |
| Content Set | The content set your team uses for custom content |
| Command | `cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Remove-PHPInstall.ps1 "$1" "$2"` |
| Command Timeout | `10` minutes |
| Download Timeout | `5` minutes |
| Ignore Action Lock | Unchecked |
| Launch this package command in a process group | Checked. If the uninstaller hangs, Tanium closes it when the time runs out |
| Files | Click **Add File**, choose **Local File**, upload `Remove-PHPInstall.ps1` |

4. Add the parameters:

| # | Type | Label | Values |
|---|---|---|---|
| 1 | Text Input | `PHP install folder` | Default value `C:\Program Files (x86)\PHP\v7.1`. Copy the folder from Comply: open the CVE, select a test, and look at `path` under **Actual Values** |
| 2 | Drop-Down List | `Force kill running PHP processes` | `No` first, then `Yes` |

5. Click **Save**.

!!! tip "Failed to create process: Error code 0x00000057"
    If an action fails with this before the script runs, the **Command** field starts with a space or tab, usually from copying. Edit the package, clear the field, and paste the command again with nothing before `cmd.exe`.

---

## Deploy

1. First, ask the [IIS - PHP Usage](../sensors/iis-php-usage.md) sensor about the computer. If a website still uses this PHP folder and people are visiting it, stop here and talk to the website owner.
2. In **Interact**, find the computer, for example:
    ```text
    Get Computer Name from all machines with Computer Name contains "<server name>"
    ```
3. Select the computer, click **Deploy Action**, and choose `<prefix> - Remove PHP Install (Windows)`.
4. Type the folder. Leave **Force** at `No` the first time.
5. Click **Show preview to continue**, then **Deploy Action**.
6. To see what happened, go to **Administration** > **Actions** > **Action History**, open the action, select the computer, and read the action log.

### Example output (illustrative)

This run stopped because IIS still used the folder:

```text
2026-11-05T10:27:59 [INFO] Start. Target folder: C:\Program Files (x86)\PHP\v7.1 | Force: True
2026-11-05T10:27:59 [INFO] php.exe version: 7.1.33
2026-11-05T10:27:59 [ERROR] Blocked: IIS applicationHost.config references 'C:\Program Files (x86)\PHP\v7.1'. Remove the FastCGI application and handler mapping first. Force does not override this.
```

---

## Things to know

- **Force can break things.** If a scheduled task or script was running that PHP, it fails the next time it runs, because the folder is gone. Tell its owner first.
- **Only the folder you type.** PHP in other places, such as `C:\PHP` or `D:\php`, is refused. This stops a typo from deleting the PHP a website still needs.
- **Don't use this for current PHP.** If the PHP version still gets security fixes, update it instead. See [PHP on IIS](../remediation/php-on-iis.md).

---

## Test results

| What was tested | Expected | Result |
|---|---|---|
| Script checked for syntax errors (Windows PowerShell 5.1) | No errors | Pass |
| IIS uses the folder, Force = Yes (earlier version) | Stops with exit 2, nothing changed | Pass |
| IIS uses the folder, folder left blank, Force = No | Uses the default folder, stops with exit 2 | Pass |
| Folder outside `Program Files\PHP` (`C:\PHP`) | Stops with exit 2 | Pass. Tanium sent the folder as `C%3a%5cPHP` and the script read it correctly as `C:\PHP` |
| Folder not used by IIS, PHP not running | Folder, installed programs entry, and PATH entry removed, exit 0 | **Not tested yet** |
| PHP running from the folder, Force = No | Stops with exit 2 | **Not tested yet** |
| PHP running from the folder, Force = Yes | PHP closed, folder removed, exit 0 | **Not tested yet** |
| Folder with spaces and brackets typed in Tanium | Read correctly | **Not tested yet** |

---

## Script

```powershell
--8<-- "tanium/packages/remove-php-install/Remove-PHPInstall.ps1"
```
