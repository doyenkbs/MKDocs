---
tags:
  - Tanium
  - Tanium Comply
  - Vulnerability Remediation
  - PHP
  - IIS
---

# PHP on IIS

Tanium Comply flags PHP on Windows by the file version of `php.exe`. On IIS servers there are usually two cases: a current PHP that is a few patches behind, and an old PHP (often `C:\Program Files (x86)\PHP\v7.1` from the Web Platform Installer) that nobody remembers. Comply shows no patch for either, so Tanium Patch does not fix them.

---

## Fix level

Example: CVE-2026-14355 (heap overflow in the OpenSSL extension, CVSS 5.3).

| PHP branch | Fixed in |
|---|---|
| 8.2 | 8.2.32 |
| 8.3 | 8.3.32 |
| 8.4 | 8.4.23 |
| 8.5 | 8.5.8 |
| 8.1 and older | No fix. These branches no longer get security updates |

---

## Find the scope

1. In Tanium Comply, open the CVE, select a failing test, and read **Actual Values**. Note the `path` and `version`.
2. Click **View Endpoints** to get the computer names.
3. In **Interact**, ask the [IIS - PHP Usage](../sensors/iis-php-usage.md) sensor on those endpoints:
    ```text
    Get Computer Name and IIS - PHP Usage[7] from all machines with Computer Name contains "<server name>"
    ```

---

## Decide

| What you find | Action |
|---|---|
| Supported branch (8.2 to 8.5), behind on patches | [Upgrade in place](#upgrade-supported-php) |
| Old branch, **PHP Folder** is `None` or the site has `0` requests and is `Stopped` | [Remove old PHP](#remove-old-php) |
| Old branch, site has requests | Do not remove. The site owner moves the site to a supported PHP or retires it. Record a risk exception in Comply until then |

Requests can be internet scanners, but any request means the site is reachable. Tell the site owner either way.

---

## Upgrade supported PHP

This is a change on the server, done by the server or site owner in a change window.

1. Download the latest release of the **same branch** from `https://windows.php.net/download/`, with the same build type (Thread Safe or Non Thread Safe, x64). Check the SHA256 on that page. Staying on the same branch avoids breaking changes.
2. Stop the site or the service that runs PHP.
3. Extract the new zip to a new folder, copy `php.ini` and any third-party `ext\*.dll` from the old folder, then swap the folder names. Keep the old folder as the rollback.
4. Start the site and have the owner test it.

Replace the whole folder, not only `php.exe`. Comply checks `php.exe`, so swapping only that file clears the finding while the vulnerable DLLs stay.

---

## Remove old PHP

1. **Report:** deploy [Remove IIS PHP Handler](../packages/remove-iis-php-handler.md) with **Mode** = `Report`. Confirm the listed entries.
2. **Approval:** get the site owner's go-ahead.
3. **IIS cleanup:** deploy Remove IIS PHP Handler with **Mode** = `Remove`. Note the backup name in the action log.
4. **Folder:** deploy [Remove PHP Install](../packages/remove-php-install.md) with the PHP folder from Comply. Use **Force** = `Yes` only if the log shows processes and their owner agreed.

Rollback for step 3: deploy **Restore IIS Config Backup** with the backup name. See [Create the rollback package](../packages/remove-iis-php-handler.md#create-the-rollback-package).

---

## Verify

1. Ask [IIS - PHP Usage](../sensors/iis-php-usage.md) again. The old folder no longer appears.
2. In Comply, run a new vulnerability scan on the endpoints.
3. Open the CVE again. The endpoints are no longer listed under **View Endpoints**.

---

## Related

- [IIS - PHP Usage](../sensors/iis-php-usage.md)
- [Remove IIS PHP Handler](../packages/remove-iis-php-handler.md)
- [Remove PHP Install](../packages/remove-php-install.md)
