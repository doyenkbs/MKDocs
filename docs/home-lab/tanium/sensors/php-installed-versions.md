---
tags:
  - Tanium
  - Sensors
  - Linux
  - Windows
  - PHP
---

# PHP - Installed Versions (Sensor)

A Tanium sensor that shows which PHP versions are on a Windows or Linux endpoint. It also shows how each one was installed, and whether a process uses it now. The sensor has one script for Windows and one script for Linux. It has no parameters.

The sensor is read-only. It changes nothing on the endpoint.

!!! warning "Test status"
    The Linux script was tested through Tanium on RHEL 9 and Ubuntu 24.04 lab endpoints. All tested cases gave the correct result, including a PHP update that still needs a restart. **The Windows script has not been tested through Tanium yet.** See [Test results](#test-results).

## How the sensor works

### Windows

The sensor looks for PHP in four places:

1. **The usual PHP folders:**
    - `C:\PHP`
    - `C:\Program Files\PHP` and `C:\Program Files (x86)\PHP`
    - The PHP folders of IIS Express, in `Program Files\IIS Express\PHP`
    - XAMPP (`C:\xampp\php`), WampServer (`C:\wamp64\bin\php`), and Laragon (`C:\laragon\bin\php`)
    - `C:\tools\php*` (the folder that Chocolatey uses)

    The sensor also looks one folder level down, for example `C:\Program Files (x86)\PHP\v7.1`.

2. **The folders on the system PATH.**
3. **The PHP folders that IIS uses.** The sensor reads them from the FastCGI settings in `C:\Windows\System32\inetsrv\config\applicationHost.config`.
4. **Running processes.** A PHP program that runs from a different folder is also found.

For each PHP file, the sensor does these steps:

1. It reads the version from the file properties.
2. It looks in the installed programs list for an installer whose folder holds the file. A PHP folder that someone copied from a zip file has no installer.
3. It looks at the running processes to see if a process uses the file. For the Apache module, it looks at the Apache processes (`httpd.exe`).

The sensor skips `php-win.exe`. It is the same PHP as `php.exe`, without a console window.

### Linux

The sensor looks for PHP in two places:

1. **The usual install folders.** These folders hold the PHP from distribution packages and from these sources:
    - Remi (`/opt/remi`)
    - Red Hat Software Collections (`/opt/rh`)
    - cPanel (`/opt/cpanel`)
    - Plesk (`/opt/plesk`)
    - LiteSpeed (`/usr/local/lsws`)
    - Builds in `/usr/local`
2. **Running processes.** A PHP program that runs from a different folder is also found.

For each PHP file, the sensor does these steps:

1. It follows symbolic links to the real file. Thus `/usr/bin/php` and `/usr/bin/php8.3` give one row, not two.
2. It reads the version from the program with `-n -v`. The `-n` option starts PHP with no `php.ini`, so no extension loads. For the Apache module, it reads the version from the package.
3. It asks `rpm` or `dpkg-query` which package installed the file.
4. It looks at the running processes to see if a process uses the file.

The sensor skips these files on purpose:

- Helper scripts such as `php-config` and `phpize`. They are not PHP itself.
- Shell scripts with a PHP name, such as a `php81` wrapper. The sensor reports only real programs.

Both scripts stop themselves after 20 seconds.

## Use cases

| Scenario | What to look for | Why it matters |
|---|---|---|
| **A scanner reports an old PHP version** | **Version** and **Package** | The row shows the exact PHP file and how it was installed. On Linux, the distribution adds security fixes to the package without a change to the main PHP version. Compare the package version with the fixed version in the vendor advisory. |
| **An old PHP folder stays after IIS no longer uses it** (Windows) | **Package** shows `No package` and **Running** shows `No` | No program updates or removes this folder. It stays on the disk, and the scanner keeps reporting it, until someone removes it. See [Remove PHP Install](../packages/remove-php-install.md). |
| **A package update did not fix the finding** (Linux) | **Running** shows `Yes, restart needed` | The update replaced the file, but the old program still runs. Restart the service (for example `php-fpm` or `httpd`). |
| **PHP that no package manager or installer updates** | **Package** shows `No package` | A person built or copied this PHP. An update of the operating system does not change it. The owner of the app must update it. |
| **PHP that nobody uses** | **Running** shows `No` on every row of the endpoint | The PHP is installed but not in use now. It can be a candidate for removal. Confirm with the owner first, because a scheduled job can start PHP later. |

To see if anyone visits a PHP website on IIS, use [IIS - PHP Usage](iis-php-usage.md). This sensor does not read web server logs.

## Before you start

- Windows endpoints with Windows PowerShell 5.1.
- Linux endpoints with `rpm` or `dpkg-query` (RHEL, Rocky, AlmaLinux, Debian, Ubuntu, and similar).
- On Linux, the `timeout` command, which is part of coreutils. Without it, the sensor takes the version from the package only.
- A Tanium account with permission to create sensors.

## Create the sensor

### Step 1: Open a new sensor

1. Sign in to the Tanium Console.
2. Open the main menu, then go to **Administration > Content > Sensors**.
3. Click **Create Sensor**.

### Step 2: Details section

| Field | Value |
|---|---|
| Name | `PHP - Installed Versions` |
| Description | Lists PHP on Windows and Linux endpoints. Windows: php.exe, php-cgi.exe, phpdbg.exe, and the Apache PHP module (php*apache2*.dll) in the usual PHP folders (C:\PHP, Program Files\PHP, IIS Express, XAMPP, WampServer, Laragon, C:\tools), the system PATH, the PHP folders that IIS uses, and running processes. Linux: the php, php-cgi, php-fpm, phpdbg, and lsphp programs and the Apache PHP module (libphp*.so) in the usual install folders (distribution packages, Remi, Red Hat Software Collections, cPanel, Plesk, LiteSpeed, /usr/local) and in running processes. Columns: PHP Path, Type, Version, Package (installer or package name and version, or No package), Running (Yes, Yes restart needed on Linux, No, or Unknown on Windows). Returns None when no PHP is found. Mac, Solaris, and AIX return Not Applicable. Does not look inside containers. Read-only. |
| Content Set | Your own custom content set |

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
2. Add these 5 columns in this order.

| Index | Column Name | Value Type | Ignore case | Hidden |
|---|---|---|---|---|
| 0 | PHP Path | Text | Checked | Unchecked |
| 1 | Type | Text | Checked | Unchecked |
| 2 | Version | Text | Checked | Unchecked |
| 3 | Package | Text | Checked | Unchecked |
| 4 | Running | Text | Checked | Unchecked |

**Version** is Text because it can hold `Unknown`.

### Step 5: Parameters section

None. Leave this section empty.

### Step 6: Scripts section

| Platform | Enable | Query Type | Script |
|---|---|---|---|
| Windows | Checked | PowerShell | Windows script below |
| Linux | Checked | UnixShell | Linux script below |
| Mac | Checked | UnixShell | Stub below |
| Solaris | Checked | UnixShell | Stub below |
| AIX | Checked | UnixShell | Stub below |

Set **Timeout** to `30` seconds, above the time limit of 20 seconds that is in each script.

=== "Windows (PowerShell)"

    ```powershell
    --8<-- "tanium/sensors/php-installed-versions/windows.ps1"
    ```

=== "Linux (UnixShell)"

    ```sh
    --8<-- "tanium/sensors/php-installed-versions/linux.sh"
    ```

=== "Mac, Solaris, AIX (UnixShell)"

    ```sh
    #!/bin/sh
    echo "Not Applicable||||"
    ```

### Step 7: Save

Click **Save**.

## Ask the question

All Windows endpoints:

```text
Get Computer Name and PHP - Installed Versions from all machines with Is Windows equals True
```

All Linux endpoints:

```text
Get Computer Name and PHP - Installed Versions from all machines with Is Linux equals True
```

Each endpoint shows one row for each PHP file. Endpoints with no PHP show `None`.

Only the Linux endpoints where an update needs a restart:

```text
Get Computer Name and PHP - Installed Versions from all machines with PHP - Installed Versions:Running contains "restart needed"
```

Only one PHP branch, for example 7.4:

```text
Get Computer Name and PHP - Installed Versions from all machines with PHP - Installed Versions:Version contains "7.4"
```

## Reading the results

### Output columns

| Column | Type | Contents |
|---|---|---|
| PHP Path | Text | The full path of the PHP file. On Linux, symbolic links are resolved to the real file. |
| Type | Text | `CLI` (command line), `CGI`, `FPM` (Linux only), `Debugger` (phpdbg), `LiteSpeed` (lsphp, Linux only), or `Apache module`. |
| Version | Text | The main PHP version, for example `8.3.6`. `Unknown` when the sensor cannot read a version. |
| Package | Text | How the file was installed. On Windows: the name and version from the installed programs list, for example `XAMPP 8.2.12`. On Linux: the package name and its full version, for example `php8.3-cli 8.3.6-0ubuntu0.24.04.14`. `No package` when no installer or package manager knows the file. |
| Running | Text | `Yes`: a process uses the file now. `Yes, restart needed` (Linux only): a process uses an older copy of the file. `No`: no process uses it now. `Unknown` (Windows only): the sensor could not read the running processes. |

Example rows from a RHEL 9 endpoint, through Tanium:

```text
/srv/testapp/bin/php|CLI|8.0.30|No package|Yes
/usr/bin/php-cgi|CGI|8.0.30|php-cli 8.0.30-8.el9_8.1|No
/usr/bin/php|CLI|8.0.30|php-cli 8.0.30-8.el9_8.1|No
/usr/sbin/php-fpm|FPM|8.0.30|php-fpm 8.0.30-8.el9_8.1|Yes, restart needed
```

On RHEL, the `php-cli` package also installs `php-cgi`.

Example rows from an Ubuntu 24.04 endpoint with Apache, through Tanium:

```text
/usr/bin/php8.3|CLI|8.3.6|php8.3-cli 8.3.6-0ubuntu0.24.04.13|No
/usr/lib/apache2/modules/libphp8.3.so|Apache module|8.3.6|libapache2-mod-php8.3 8.3.6-0ubuntu0.24.04.13|Yes
```

### Status results

| Result | Meaning |
|---|---|
| `None` | The sensor found no PHP on the endpoint. |
| `Not Applicable` | The endpoint is Mac, Solaris, or AIX. |
| `Error: Time limit reached, results incomplete` | The sensor stopped after 20 seconds. The rows above it are correct, but some PHP files can be missing. |
| `Error: Unexpected failure` | The Windows script failed before it could return results. |

## Troubleshooting

| What you see | Likely cause | What to do |
|---|---|---|
| `TSE-Error: Sensor evaluation timed out` | The sensor **Timeout** is below 30 seconds. | Edit the sensor and check Step 6. |
| `TSE-Error: No Sensor Definition for this Platform` | A script tab was left empty. | Edit the sensor and add the script or the stub to that tab (Step 6). |
| All values in one column | The column split was not saved. | Edit the sensor and check Step 4. |
| An update or removal is done, but the old result still shows | Tanium uses the saved result until the Max Sensor Age passes. | Ask again after 1 hour. |
| **Running** still shows `Yes, restart needed` after the update | The service was not restarted. | Restart the service through your normal change process. Then ask again after 1 hour. |
| **Running** shows `Unknown` on a Windows endpoint | The sensor could not read the running processes, or the Apache processes. | Ask `Get Computer Name and Running Processes from all machines with Running Processes contains "php"` to see if PHP runs on that endpoint. |
| An endpoint is missing from the results | The endpoint is offline, or it has not answered yet. | Compare with `Get Computer Name from all machines with Is Windows equals True` or `Get Computer Name from all machines with Is Linux equals True`. |

## Limits

- **Other folders.** PHP that is not in a usual folder, not on the system PATH, not used by IIS, and not running now is not found. On Windows, this includes PHP on other drives (for example `D:\php`) and PHP that one user installed in their own profile.
- **Containers.** The sensor does not look inside container images. A PHP process that runs in a container can show with a path from inside the container. This case was not tested.
- **Old copy in an unusual folder (Linux).** If a PHP program in an unusual folder was replaced while it runs, the sensor cannot see it. The old file is gone, and the new file is not in a usual folder.
- **Version from the program.** The **Version** column shows the main PHP version. A Linux distribution can add security fixes without a change to that number. Use the **Package** column to compare with the vendor advisory.

## Test results

All tests ran through Tanium in a lab.

| Case | Expected | Result |
|---|---|---|
| Linux endpoint with no PHP | `None` | Pass |
| RHEL 9, `php-cli` and `php-fpm` installed, not running | `php`, `php-cgi`, and `php-fpm` rows with the RHEL packages, **Running** `No` | Pass |
| RHEL 9, `php-fpm` started | FPM row shows `Yes` | Pass |
| RHEL 9, `php-fpm` file replaced while it runs | FPM row shows `Yes, restart needed` | Pass |
| RHEL 9, PHP copy running from an unusual folder | Found, `No package`, `Yes` | Pass |
| Ubuntu 24.04, Apache with the PHP module running | Apache module row shows `Yes` | Pass |
| Ubuntu 24.04, PHP from a third-party repository | Package and version from that repository | Pass |
| Filter question on **Running** | Endpoints with `restart needed` only | Pass |
| Filter question on **Version** | Endpoints with that PHP branch only | Pass |
| Windows endpoint with no PHP | `None` | Not tested |
| Windows, PHP folder in `C:\Program Files (x86)\PHP\v7.1` used by IIS | `php.exe` and `php-cgi.exe` rows, `No package` | Not tested |
| Windows, `php-cgi.exe` running for an IIS site | CGI row shows `Yes` | Not tested |
| Windows, PHP folder on the system PATH only | Found | Not tested |

## Related

- [IIS - PHP Usage](iis-php-usage.md)
- [Remove PHP Install](../packages/remove-php-install.md)
- [PHP on IIS](../remediation/php-on-iis.md)
