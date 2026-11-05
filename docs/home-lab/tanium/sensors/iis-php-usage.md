---
tags:
  - Tanium
  - Sensors
  - PowerShell
  - IIS
  - PHP
---

# IIS - PHP Usage (Sensor)

This page shows how to create the **IIS - PHP Usage** sensor in the Tanium Console, and how to use it to find out whether an IIS server is still serving PHP before you remove or upgrade PHP on it.

**What it returns:** one row per IIS site, with the site state, the PHP folder and version that handle `.php` pages for that site, how many `.php` files are in the site folders, how many `.php` requests the site logged in the last N days, and the most recent one. Machines without IIS return a single `Not Applicable` row.

!!! warning "Test status"
    Run through Tanium on Windows lab endpoints with and without IIS, including a server with PHP 7.1 mapped at server level, before and after the mapping was removed. Stopped sites and handlers set in a site `web.config` have not been tested yet. See [Test results](#test-results).

---

## How the sensor works

For each site in `C:\Windows\System32\inetsrv\config\applicationHost.config`, the script:

1. Reads the site state (`Started`, `Stopped`) from `appcmd list site`.
2. Finds the `*.php` handler mapping that applies to the site, in this order: the `web.config` in the site root folder, a `<location>` section for the site in `applicationHost.config`, then the server-level handler. It reports the folder of the `php-cgi.exe` that handler points to, and that file's version.
3. Counts `.php` files under every physical folder of the site. Junctions are skipped.
4. Reads the site's W3C logs (`C:\inetpub\logs\LogFiles\W3SVC<site ID>` unless the site logs somewhere else) for the last N days, and counts requests whose URL path ends in `.php` or contains `.php/`.

The script stops itself after 45 seconds. A count that was cut short ends with `(partial)`.

---

## Use cases

**Before removing old PHP.** A PHP folder that IIS still maps can't be removed safely. The PHP Folder and PHP Version columns show which sites use it, and the request count shows whether anyone is using those sites.

**Finding forgotten sites.** A site with thousands of `.php` files, a `Started` state, and requests every day is live, even if everyone thinks it moved somewhere else.

**Fleet view of PHP on IIS.** One question across all Windows servers lists every PHP version IIS still serves.

---

## Before you start

- You need a role that can create sensors in the content set you plan to use.
- If a sensor with the same name already exists, edit it instead of creating a second one.
- Copy the script with the copy button on its code block so nothing is changed.

---

## Create the sensor

### Step 1: Open a new sensor

1. Sign in to the Tanium Console.
2. Open the main menu, then go to **Administration > Content > Sensors**.
3. Click **Create Sensor**.

### Step 2: Details section

| Field | Value |
|---|---|
| Name | `IIS - PHP Usage` |
| Description | Lists each IIS site with its state, the PHP folder and php-cgi.exe version mapped to *.php for that site (site web.config, then applicationHost.config location, then server level), the number of .php files in the site folders, and the number of .php requests in the site W3C logs over the last N days (Days parameter, default 7, 1 to 30) with the most recent one in UTC. Counts cut short by the 45-second limit end with (partial). Returns Not Applicable when IIS is not installed. Read-only. |
| Content Set | Your own custom content set, restricted to your endpoint team |

### Step 3: Settings section

| Field | Value |
|---|---|
| Category | Miscellaneous (or any category you use for custom sensors) |
| Result Type | Text |
| Max Sensor Age | `1` and set the unit dropdown to **Hours** |
| Max String Age | Leave **Enable** unchecked |
| Max Strings | Leave **Enable** unchecked |
| Ignore case in result values | Checked |
| Hide this sensor from sensor lists and parse results | Unchecked |
| Split into multiple columns | Checked |

### Step 4: Column settings

1. Set **Delimiter** to `|`.
2. Add these 7 columns in this order.

| Index | Column Name | Value Type | Ignore case | Hidden |
|---|---|---|---|---|
| 0 | Site | Text | Checked | Unchecked |
| 1 | State | Text | Checked | Unchecked |
| 2 | PHP Folder | Text | Checked | Unchecked |
| 3 | PHP Version | Text | Checked | Unchecked |
| 4 | PHP Files | Text | Checked | Unchecked |
| 5 | PHP Requests | Text | Checked | Unchecked |
| 6 | Last PHP Request | Text | Checked | Unchecked |

**PHP Files** and **PHP Requests** are Text because they can hold `(partial)` or `No logs`.

### Step 5: Parameters section

The **Key** must be `Days`, matching the `||Days||` placeholder in the script.

1. In the **Parameters** section, click **Add Parameter**, then select **Text Input**.
2. **Key:** replace `parameter_1` with `Days`.
3. **Label:** `Days of IIS logs to scan`
4. Under **Options**:
    - Check **Provide Help Text** and enter: `1 to 30. Larger values take longer on busy servers.`
    - Check **Provide Default Value** and enter: `7`
    - Check **Provide Max Chars** and enter: `2`
5. Under **Validation Expressions**:
    - Replace `.*` with `^([1-9]|[12][0-9]|30)$`
    - In **Enter Help Text**, type: `Enter a number from 1 to 30.`

### Step 6: Scripts section

| Platform | Enable | Query Type | Script |
|---|---|---|---|
| Windows | Checked | PowerShell | Windows script below |
| Linux | Checked | UnixShell | Stub below |
| Mac | Checked | UnixShell | Stub below |
| Solaris | Checked | UnixShell | Stub below |
| AIX | Checked | UnixShell | Stub below |

Set **Timeout** to `60` seconds, above the script's own 45-second limit.

=== "Windows (PowerShell)"

    ```powershell
    --8<-- "tanium/sensors/iis-php-usage/windows.ps1"
    ```

=== "Linux, Mac, Solaris, AIX (UnixShell)"

    ```sh
    #!/bin/sh
    echo "Not Applicable|N/A|N/A|N/A|N/A|N/A|N/A"
    ```

### Step 7: Save

Scroll to the bottom of the page and click **Save**.

### Step 8: Test

1. Go to **Interact**.
2. Ask:

    ```text
    Get Computer Name and IIS - PHP Usage[7] from all machines with Computer Name contains "<test server>"
    ```

3. Check that you see 7 columns and one row per IIS site.

---

## Ask the question

All Windows servers:

```text
Get Computer Name and IIS - PHP Usage[7] from all machines with Windows OS Type contains "Server"
```

Only sites mapped to a given PHP branch, for example 7.x:

```text
Get Computer Name and IIS - PHP Usage[7] from all machines with IIS - PHP Usage[7]:PHP Version starts with "7."
```

---

## Reading the results

| Column | What it tells you |
|---|---|
| Site | IIS site name |
| State | `Started`, `Stopped`, or `Unknown` if `appcmd` could not be read |
| PHP Folder | Folder of the `php-cgi.exe` that handles `*.php` for the site. `None` means no PHP handler applies |
| PHP Version | File version of that `php-cgi.exe`. `Missing` means the handler points to a file that no longer exists |
| PHP Files | Number of `.php` files in the site folders |
| PHP Requests | `.php` requests logged in the last N days. `No logs` means the site has no log folder (logging off, or the site never served a request). The count comes from the logs, so it stays after PHP is removed until those days pass |
| Last PHP Request | Date, time (UTC), and URL path of the most recent `.php` request |

Example rows (values are illustrative):

```text
www.example.com|Started|C:\Program Files (x86)\PHP\v7.1|7.1.29|3944|412|2026-11-03 14:11:14 UTC /index.php
Default Web Site|Stopped|C:\Program Files (x86)\PHP\v7.1|7.1.29|3944|No logs|No logs
```

### What to do with a row

| What you see | Meaning | Next step |
|---|---|---|
| PHP Folder is `None` | IIS does not run PHP for this site | PHP on this server is not used by IIS. Go to [Remove PHP Install](../packages/remove-php-install.md) |
| Requests are `0` or `No logs`, and State is `Stopped` | The site is not in use | Confirm with the site owner, then follow [PHP on IIS](../remediation/php-on-iis.md#remove-old-php) |
| Requests above `0` | The site is serving PHP | Do not remove PHP. The site owner moves it to a supported PHP version or retires it |

Requests can come from internet scanners probing for common files. Look at **Last PHP Request**: a scanner usually asks for paths such as `/wp-login.php` or config files and gets errors. A real site gets requests for its own pages. Even scanner traffic means the site is reachable.

---

## Troubleshooting

| Result | Meaning | What to do |
|---|---|---|
| `Error: cannot read applicationHost.config` | The IIS config file is locked or damaged | Check IIS on that server |
| `(partial)` in a count | The 45-second limit was reached | Ask again with a smaller **Days** value |
| `TSE-Error: Sensor evaluation timed out` | The sensor **Timeout** is below 60 seconds | Edit the sensor and recheck Step 6 |
| `TSE-Error: No Sensor Definition for this Platform` | The Linux, Mac, Solaris, or AIX script tab was left empty | Edit the sensor and add the stub script to those tabs (Step 6) |
| All values in one column | The column split was not saved | Edit the sensor and recheck Step 4 |

---

## Limits

- Only IIS. PHP run by Apache, a scheduled task, or a service is not reported. Use [Remove PHP Install](../packages/remove-php-install.md), which refuses to delete a folder with running processes.
- Only W3C logs that include the `cs-uri-stem` field are counted. That field is on by default.
- Handlers set in a `web.config` below the site root, or in a nested application, are not read.

---

## Test results

| Case | Expected | Result |
|---|---|---|
| Windows PowerShell 5.1 parser | No errors | Pass |
| Machine without IIS, run locally | `Not Applicable` row | Pass |
| Through Tanium, Windows machines without IIS | `Not Applicable` row | Pass |
| Through Tanium, IIS with two sites and no PHP | One row per site, `Started`, PHP Folder `None`, counts `0` | Pass |
| Through Tanium, site that has never logged | `No logs` | Pass |
| Through Tanium, Linux endpoints with no stub script | `TSE-Error: No Sensor Definition for this Platform` | Expected. Fixed by adding the stub |
| Through Tanium, server-level PHP 7.1 handler, two sites | Both sites show `C:\Program Files (x86)\PHP\v7.1` and `7.1.33` | Pass |
| Site with requests in the logs | Count above 0, last request shown | Pass. `4`, `2026-11-05 14:48:34 UTC /index.php` |
| Site that was never browsed | `No logs` | Pass |
| After the handler was removed | PHP Folder and PHP Version `None`, request history still shown | Pass |
| Stopped site | `Stopped` | **Not tested yet** |
| Handler set in the site `web.config` | Site-level folder reported | **Not tested yet** |
