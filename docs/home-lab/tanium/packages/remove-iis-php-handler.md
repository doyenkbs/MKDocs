---
tags:
  - Tanium
  - PowerShell
  - Packages
  - IIS
  - PHP
---

# Remove IIS PHP Handler (Package)

One Tanium package that removes the IIS handler mappings and FastCGI applications that point to a PHP folder. Run it before [Remove PHP Install](remove-php-install.md), which refuses to delete a folder IIS still references.

It defaults to **Report** mode, which only lists what it would remove. **Remove** mode backs up the IIS configuration first, so the change can be rolled back with a second package on this page.

!!! danger "This stops PHP on the site"
    After Remove, any IIS site that used those entries can no longer run `.php` pages. Run [IIS - PHP Usage](../sensors/iis-php-usage.md) first, and run Remove only with the site owner's approval.

!!! warning "Test status"
    Tested in a lab through Tanium on a server where IIS ran PHP 7.1. Report listed the right settings, Remove deleted them, and the rollback package put them back. **PHP settings made for a single website (instead of the whole server) have not been tested yet.** See [Test results](#test-results).

---

## What the script does

1. Checks that the folder is directly under `C:\Program Files (x86)\PHP` or `C:\Program Files\PHP`.
2. Reads `C:\Windows\System32\inetsrv\config\applicationHost.config` and finds:
    - every handler mapping whose script processor is in that folder, at server level and in `<location>` sections for individual sites
    - every FastCGI application whose path is in that folder
3. **Report:** writes the list to the action log and stops.
4. **Remove:** runs `appcmd add backup PHP-Cleanup-<date-time>`, removes the handler mappings, then the FastCGI applications, then reads the config again to confirm they are gone.

The log is written to the action log and to `C:\Windows\Temp\Remove-IISPhpHandler.log`.

---

## Exit codes

| Exit code | Meaning |
|---|---|
| `0` | Report completed, nothing references the folder, or removal succeeded. |
| `1` | Failed: backup failed, `appcmd` returned an error, or entries are still there afterward. |
| `2` | Blocked: the folder is outside the allowed roots. Nothing changed. |

---

## Create the package

1. Save the [script](#script) at the bottom of this page as `Remove-IISPhpHandler.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package** and fill in:

| Field | Value |
|---|---|
| Package Name | `<prefix> - Remove IIS PHP Handler (Windows)` |
| Display Name | `<prefix> - Remove IIS PHP Handler (Windows)` |
| Description | `Finds IIS handler mappings and FastCGI applications that point to a PHP folder. Report lists them. Remove backs up the IIS config (appcmd backup PHP-Cleanup-<date-time>) and deletes them. Exit 0 done or nothing found, 1 failed, 2 blocked.` |
| Content Set | The content set your team uses for custom content |
| Command | `cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Remove-IISPhpHandler.ps1 "$1" "$2"` |
| Command Timeout | `5` minutes |
| Download Timeout | `5` minutes |
| Ignore Action Lock | Unchecked |
| Launch this package command in a process group | Checked |
| Files | Click **Add File**, choose **Local File**, upload `Remove-IISPhpHandler.ps1` |

4. Add the parameters:

| # | Type | Label | Values |
|---|---|---|---|
| 1 | Text Input | `PHP install folder` | Default value `C:\Program Files (x86)\PHP\v7.1` |
| 2 | Drop-Down List | `Mode` | `Report` first, then `Remove` |

5. Click **Save**.

---

## Create the rollback package

The rollback uses its own small script instead of calling `appcmd` directly in the command line. Tanium URL-encodes the parameter, so a backup name such as `PHP-Cleanup-20261105-142210` reaches the endpoint as `PHP%2dCleanup%2d20261105%2d142210`, and `appcmd` can't find it. The script decodes the name, checks that the backup exists, and lists the available backups when it doesn't.

1. Save the [rollback script](#rollback-script) at the bottom of this page as `Restore-IISConfigBackup.ps1`.
2. In **Administration** > **Content** > **Packages**, click **Create Package** and fill in:

| Field | Value |
|---|---|
| Package Name | `<prefix> - Restore IIS Config Backup (Windows)` |
| Display Name | `<prefix> - Restore IIS Config Backup (Windows)` |
| Description | `Restores an IIS configuration backup by name, for example one created by Remove IIS PHP Handler. Restores the whole IIS configuration as it was at backup time. Lists available backups if the name is not found. Exit 0 restored, 1 failed, 2 blocked.` |
| Content Set | The content set your team uses for custom content |
| Command | `cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Restore-IISConfigBackup.ps1 "$1"` |
| Command Timeout | `5` minutes |
| Download Timeout | `5` minutes |
| Ignore Action Lock | Unchecked |
| Launch this package command in a process group | Checked |
| Files | Click **Add File**, choose **Local File**, upload `Restore-IISConfigBackup.ps1` |
| Parameter 1 | Text Input, label `Backup name`, no default. Copy it from the cleanup action log, for example `PHP-Cleanup-20261105-142210` |

Restore puts back the **whole** IIS configuration as of the backup. Any other IIS change made after the cleanup is rolled back too.

!!! tip "Failed to create process: Error code 0x00000057"
    If an action fails with this before the script runs, the **Command** field has a leading space or tab, usually from copying. Edit the package, clear the field, and type or paste the command again with nothing before `cmd.exe`.

---

## Deploy

1. Deploy with **Mode** = `Report` to the endpoint. Read the action log and confirm only the expected handler and FastCGI entries are listed.
2. Get the site owner's approval.
3. Deploy again with **Mode** = `Remove`. Write down the backup name from the log.
4. Run [Remove PHP Install](remove-php-install.md) for the same folder.

### Example output (illustrative)

```text
2026-11-05T14:22:08 [INFO] Start. PHP folder: C:\Program Files (x86)\PHP\v7.1 | Mode: Remove
2026-11-05T14:22:08 [INFO] Handler: 'PHP_via_FastCGI' path=*.php [server level] -> C:\Program Files (x86)\PHP\v7.1\php-cgi.exe
2026-11-05T14:22:08 [INFO] FastCGI application: C:\Program Files (x86)\PHP\v7.1\php-cgi.exe arguments=''
2026-11-05T14:22:08 [INFO] Found 1 handler mapping(s) and 1 FastCGI application(s).
2026-11-05T14:22:10 [INFO] IIS config backed up as 'PHP-Cleanup-20261105-142210'. Rollback: appcmd restore backup "PHP-Cleanup-20261105-142210"
2026-11-05T14:22:11 [INFO] All IIS references to C:\Program Files (x86)\PHP\v7.1 removed. Backup: 'PHP-Cleanup-20261105-142210'. Exit 0.
```

---

## Things to know

- **Handlers in a site's `web.config` are not removed.** The script only edits `applicationHost.config`. If [IIS - PHP Usage](../sensors/iis-php-usage.md) still shows the old folder for a site after Remove, the mapping is in that site's own `web.config`.
- **Backups stay on the server** under `C:\Windows\System32\inetsrv\backup\`. Remove old ones by hand once you're sure you won't need them.

---

## Test results

| Case | Expected | Result |
|---|---|---|
| Windows PowerShell 5.1 parser | No errors | Pass |
| Report, server-level handler and FastCGI app | Both listed, nothing changed, exit 0 | Pass |
| Remove, same setup | Backup created, both removed, exit 0 | Pass |
| Restore, first version (appcmd in the command line) | Handler and FastCGI app back | Fail. Command field had a leading tab (error `0x00000057`), and the backup name arrived URL-encoded. Replaced with the rollback script |
| Restore with the rollback script | Name decoded, handler and FastCGI app back, exit 0 | Pass. `PHP%2dCleanup%2d...` decoded and restored, exit 0 |
| Restore with a name that doesn't exist | Exit 2, available backups listed | **Not tested yet** |
| Handler in a `<location>` section for one site | Listed and removed | **Not tested yet** |
| No IIS installed | Exit 0, nothing to do | **Not tested yet** |

---

## Script

```powershell
--8<-- "tanium/packages/remove-iis-php-handler/Remove-IISPhpHandler.ps1"
```

## Rollback script

```powershell
--8<-- "tanium/packages/remove-iis-php-handler/Restore-IISConfigBackup.ps1"
```
