---
tags:
  - Tanium
  - Sensors
  - Java
  - PowerShell
  - Linux
---

# Java - Runtime Inventory - Dependencies (Sensor)

This page shows how to create the **Java - Runtime Inventory - Dependencies** sensor by hand in the Tanium Console, and how to use it with your vulnerability scanner to find and fix vulnerable Java for the long term.

**What it returns:** every Java runtime on each endpoint, patched or not, one row per runtime per thing that uses it. Each row gives the `java.exe` path, the Java line (8, 11, 17, 21, 25, ...), the version, the vendor, what installed it, the uninstall command, and the service, process, scheduled task, variable, or file association that depends on it.

!!! note "Why there is no version list in this sensor"
    Java gets security fixes every quarter, so any list of vulnerable versions inside a sensor goes out of date within three months and then gives wrong answers without any warning. This sensor only reports facts that do not expire: what is installed, where, and what uses it. Your vulnerability scanner decides which versions are vulnerable, because it already receives new CVE data automatically. For a one-time cleanup with a built-in version list, use the Tanium sensor **Java - Vulnerable Installs - Dependencies**.

!!! warning "Build it by hand"
    The Tanium Console limits each platform script to 28,000 characters. The Windows script below is about 25,800 characters. Paste it exactly as shown; do not add comments or indentation.

---

## How the sensor works

### 1. Find every Java runtime

A Java runtime is any folder that has `bin\java.exe` or `bin\server\jvm.dll`. The Windows script looks in:

- The JavaSoft registry keys (where Oracle installers register Java)
- Installed programs in Apps and Features that point at a Java folder
- `JAVA_HOME`, `JRE_HOME`, `JDK_HOME`, and `PATH` (system and logged-on users)
- Running `java.exe`, `javaw.exe`, `javaws.exe`, and `jp2launcher.exe` processes, wherever they are on disk
- A folder search of `C:\Program Files`, `C:\Program Files (x86)`, `C:\ProgramData`, other top-level folders on `C:\`, other fixed drives, and each user's `AppData\Local\Programs`, `AppData\Local\JetBrains`, and `.jdks` folders

The folder search skips cache and data folders and stops after 35 seconds. If it stops early, the sensor adds a **Scan incomplete** row so you know that result is partial.

The Linux script looks in `/usr/lib/jvm`, `/usr/java`, the default `java` on the PATH, running Java processes, `JAVA_HOME` in `/etc/environment`, `/etc/profile.d`, and `/etc/default`, and searches `/opt`, `/usr/local`, `/srv`, `/app`, `/apps`, `/u01`, and `/data` without crossing into network mounts. That search stops after 30 seconds in total and adds the same **Scan incomplete** row.

### 2. Read the version and who installed it

The version comes from the `release` file in the Java folder, or from the file version of `java.exe` if there is no `release` file. The sensor reports it two ways: **Version String** exactly as Java writes it (for example `1.8.0_401`), and **Version** in a sortable form (for example `8.0.401`), so Java 8 and newer lines can be compared the same way.

### 3. Find what uses each runtime

| Used By Type | How it is found |
|---|---|
| Service / Service (path in arguments) | The service executable is inside the Java folder, or the Java path appears in the service command line |
| Service (procrun Jvm setting) | Apache Commons Daemon services (Tomcat and many vendor services) store their JVM path in the registry under `Procrun 2.0\<service>\Parameters\Java` |
| Service (Java Service Wrapper .conf) / Service (WinSW .xml) | The wrapper configuration file points at this Java |
| Service (java from PATH) | The service runs a bare `java` command, which Windows resolves through the system PATH |
| Running Process | A process running from this Java folder. Shows the process name, PID, owning service, and the jar name or main class |
| Scheduled Task / Scheduled Task (path in arguments) | The task runs this `java.exe`, passes its path as an argument, or runs a `.bat`, `.cmd`, or `.ps1` file that calls it |
| Environment Variable / PATH | `JAVA_HOME`, `JRE_HOME`, `JDK_HOME`, or a PATH entry points at this Java (including the Oracle `javapath` folder) |
| Registry Default | The JavaSoft registry lists this runtime as the default Java |
| File Association | `.jar` files open with this Java |
| Service (systemd) / Service (init script) / Cron Job / Environment File / Default Java | Linux equivalents: a unit file, init script, cron entry, or environment file references this Java, or `/usr/bin/java` points to it |
| ... (same application folder, likely uses it) | A service or process in the same application folder as a bundled Java. This is an inference, not a direct reference |
| None found | Nothing references it. This runtime is usually the safest to remove |

Command lines are never returned. For running Java processes the sensor shows only the jar file name or main class, so `-D` arguments (which can hold passwords) stay on the endpoint.

---

## Before you start

- You need a role that can create sensors in the content set you plan to use.
- If a sensor named **Java - Runtime Inventory - Dependencies** already exists, edit it instead of creating a second one. Sensor names must be unique.
- Copy each script with the copy button on its code block so nothing is changed.

---

## Create the sensor

### Step 1: Open a new sensor

1. Sign in to the Tanium Console.
2. Open the main menu, then go to **Administration > Content > Sensors**.
3. Click **Create Sensor**.

### Step 2: Details section

| Field | Value |
|---|---|
| Name | `Java - Runtime Inventory - Dependencies` |
| Description | Returns every Java runtime on the endpoint, patched or not, one row per runtime per thing that uses it: the java.exe path, the Java line (8, 11, 17, 21, 25, ...), the version, the vendor, what installed it, the uninstall command, and the service, process, scheduled task, variable, or file association that depends on it. |
| Content Set | Your own custom content set (for example the one you use for lab or custom sensors) |

### Step 3: Settings section

| Field | Value |
|---|---|
| Category | Miscellaneous (or any category you use for custom sensors) |
| Result Type | Text |
| Max Sensor Age | `1` and set the unit dropdown to **Hours**. Installed Java changes rarely, and the folder search takes a few seconds per endpoint |
| Max String Age | Leave **Enable** unchecked |
| Max Strings | Leave **Enable** unchecked |
| Ignore case in result values | Checked |
| Hide this sensor from sensor lists and parse results | Unchecked |
| Split into multiple columns | Checked |

### Step 4: Column settings

After you check **Split into multiple columns**:

1. Set **Delimiter** to `|` (the pipe character, Shift + Backslash on a US keyboard).
2. Add these 10 columns in this order. The order must match, because the scripts return the values in this order.

| Index | Column Name | Value Type | Ignore case | Hidden |
|---|---|---|---|---|
| 0 | Java Path | Text | Checked | Unchecked |
| 1 | Java Line | Numeric | Checked | Unchecked |
| 2 | Version | Version | Checked | Unchecked |
| 3 | Version String | Text | Checked | Unchecked |
| 4 | Type | Text | Checked | Unchecked |
| 5 | Vendor | Text | Checked | Unchecked |
| 6 | Installed By | Text | Checked | Unchecked |
| 7 | Uninstall Command | Text | Checked | Unchecked |
| 8 | Used By Type | Text | Checked | Unchecked |
| 9 | Used By | Text | Checked | Unchecked |

**Java Line** as Numeric and **Version** as Version let the results grid sort them correctly (so `8.0.60` sorts before `8.0.401`). Rows where the version could not be read show `unknown` in both columns.

### Step 5: Parameters section

Leave it empty. This sensor has no parameters.

### Step 6: Scripts section

For each platform in the table: click the platform tab on the left, check **Enable sensor for [platform] platform**, set **Query Type** in the top right, click inside the script editor, press **Ctrl + A**, press **Delete**, then paste the script for that platform.

| Platform | Enable | Query Type | Script |
|---|---|---|---|
| Windows | Checked | PowerShell | Windows script below |
| Linux | Checked | UnixShell | Linux script below |
| Mac | Checked | UnixShell | Stub below, returns N/A |
| Solaris | Checked | UnixShell | Stub below, returns N/A |
| AIX | Checked | UnixShell | Stub below, returns N/A |

=== "Windows (PowerShell)"

    ```powershell
    --8<-- "tanium/sensors/java-runtime-inventory/windows.ps1"
    ```

=== "Linux (UnixShell)"

    ```bash
    --8<-- "tanium/sensors/java-runtime-inventory/linux.sh"
    ```

=== "Mac (UnixShell)"

    ```sh
    #!/bin/sh
    echo "N/A"
    ```

=== "Solaris (UnixShell)"

    ```sh
    #!/bin/sh
    echo "N/A"
    ```

=== "AIX (UnixShell)"

    ```sh
    #!/bin/sh
    echo "N/A"
    ```

### Step 7: Save

1. Scroll to the bottom of the page and click **Save**.
2. If you see `SensorQueryTooLong`, the Windows script is over 28,000 characters. Clear the Windows editor and paste the script again using the copy button.
3. If the console reports that the name already exists, cancel and edit the existing sensor.

### Step 8: Test on a few machines first

1. Go to **Interact**.
2. In the question bar, enter `Get Java - Runtime Inventory - Dependencies from all machines with Computer Name contains "<hostname>"`, replacing `<hostname>` with a machine you know has Java.
3. Check the results:
    - You see 10 columns. If everything is in one column with `|` inside the value, the column split was not saved. Edit the sensor and recheck Step 4.
    - Every Java on the machine is listed, including patched ones.
    - No row starts with **Scan incomplete**, and the result does not stay on **[current result unavailable]**. If either happens, see [Troubleshooting](#troubleshooting).

---

## Finding vulnerable Java with this sensor

This sensor tells you where Java is and what depends on it. Your vulnerability scanner tells you which versions are vulnerable. Use them together:

1. **Get the fixed version from the scanner.** Open a Java finding in your vulnerability report and note the fixed (or first non-vulnerable) version for each Java line, for example Java 17 fixed in 17.0.21. A Java line that no longer receives updates (check the vendor's support roadmap) has no fixed version, so every copy of it is vulnerable.
2. **List Java on the affected machines.** Ask the sensor on all machines, or narrow it to the machines in the report: `Get Java - Runtime Inventory - Dependencies from all machines`
3. **Narrow to one Java line if needed.** In the results, narrow by the **Java Line** column (for example `8`) or the **Version String** column (for example `1.8.0_`).
4. **Compare.** In the results grid, sort by **Java Line** and then **Version**. Every row whose Version is below the fixed version for its Java line is vulnerable. For large result sets, export the results to CSV from the results grid and compare there.
5. **Remediate** using the Installed By, Uninstall Command, and Used By columns. See [Remediation by finding](#remediation-by-finding).

---

## Reading the results

| Column | What it tells you |
|---|---|
| Java Path | Full path to `java.exe` (or `jvm.dll` if there is no `java.exe`). Use it with **File Exists** to confirm removal |
| Java Line | The major version: 8, 11, 17, 21, 25, and so on. Java 1.8 is reported as 8 |
| Version | Sortable version, for example `8.0.401` for Java 8 update 401, or `17.0.5` |
| Version String | Exactly as Java writes it, for example `1.8.0_401` or `17.0.5`. This is the value vulnerability reports usually show |
| Type | JDK if `javac.exe` is present, otherwise JRE |
| Vendor | For example Oracle Corporation, Eclipse Adoptium, Amazon.com Inc., Azul Systems |
| Installed By | The installer entry (standalone Java), `Bundled with <application>`, `Package <name>` on Linux, `No installer entry` (copied or unzipped), or `Unknown (user profile not logged on)` (see [Check before you remove anything](#check-before-you-remove-anything)) |
| Uninstall Command | For MSI installs: `MsiExec.exe /X{GUID} /qn /norestart`. For bundled Java: `Update or remove <application>`. On Linux: the package manager command |
| Used By Type / Used By | What depends on this runtime (see the table in [How the sensor works](#3-find-what-uses-each-runtime)) |

Example row (values are illustrative): `C:\Program Files\Java\jre1.8.0_401\bin\java.exe|8|8.0.401|1.8.0_401|JRE|Oracle Corporation|Java 8 Update 401 (64-bit) 8.0.4010.11|MsiExec.exe /X{00000000-0000-0000-0000-000000000000} /qn /norestart|None found|No service, process, scheduled task, variable, or file association references it`

---

## Remediation by finding

Match each vulnerable row to a finding below using its **Installed By** and **Used By Type** values. The findings are not steps in a sequence. One machine can have rows in several of them.

### Check before you remove anything

Skip a row, or confirm it first, when any of these apply:

- **Installed By is `Unknown (user profile not logged on)`.** The Java is inside the profile of a user who was logged off when the sensor ran, so the sensor could not read that user's installer entries or environment variables. The row doesn't show whether the Java was installed or copied, or whether that user's `JAVA_HOME` points at it. Don't act on it. Ask the sensor again on that machine while the user is logged on, and use the new answer.
- **Used By Type ends with `likely uses it`.** The link is based on folder location only. Confirm with the application owner.
- **The machine also returned a Scan incomplete row.** The list for that machine is partial.
- **The answer is older than the change you are about to make.** Results are reused for up to an hour (Max Sensor Age), so ask again right before removing anything.

### Standalone Java, nothing uses it

Installed By is a Java installer, Uninstall Command starts with `MsiExec.exe /X`, and Used By Type is **None found**. Uninstall with a Tanium package that runs the Uninstall Command.

### Standalone Java that something uses

Installed By is a Java installer, and Used By Type lists a service, process, task, variable, or file association. Install a supported Java version first, point the service, task, or `JAVA_HOME` at it, then uninstall the old one.

### Java bundled with an application

Installed By starts with `Bundled with`, or reads `No installer entry (inside <folder>)` on Windows or `No package owner (inside /opt/<app>)` on Linux. The Java sits inside an application's folder, and removing it will break the application. Update the application or ask its vendor for a version with a supported Java.

### Java with no installer entry (copied or unzipped)

Installed By is `No installer entry found` (Windows) or `No package owner found` (Linux), and Uninstall Command is `None registered`. Nothing registered this Java, so there is no uninstaller and it has to be deleted.

1. **Confirm nothing uses it.** Used By Type must be **None found** in a fresh answer. If anything is listed, move it to a supported Java first, as in [Standalone Java that something uses](#standalone-java-that-something-uses).
2. **Work out the folder to delete.** It's the Java Path minus `\bin\java.exe` (Windows) or `/bin/java` (Linux). For example, `C:\Tools\jdk-17.0.5\bin\java.exe` means you delete `C:\Tools\jdk-17.0.5`, and `/opt/jdk-17.0.5/bin/java` means `/opt/jdk-17.0.5`. If the Java Path ends in `\bin\server\jvm.dll`, remove that part instead.
3. **Check that the folder holds only Java.** A Java folder contains `bin`, `lib`, and usually a `release` file. If the folder name is generic (for example `C:\App\runtime`) or it sits inside another product's folder, treat it as [bundled](#java-bundled-with-an-application) instead.
4. **Delete it with a Tanium package.** On Windows use `cmd.exe /c rmdir /s /q "C:\Tools\jdk-17.0.5"`, and on Linux use `rm -rf /opt/jdk-17.0.5`, with the folder from step 2.
5. **Confirm** with `Get File Exists[<Java Path>] from all machines`, replacing `<Java Path>` with the value from the Java Path column.

### Java lines that no longer get updates

Your scanner reports no fixed version for the Java line, or the Java Line is not a long-term support (LTS) release. The LTS lines are 8, 11, 17, 21, and 25. Every other line gets updates only until the next release, six months later. For LTS lines, the end of updates depends on the vendor, so check the **Vendor** column against that vendor's support roadmap. These runtimes can't be patched in place.

1. **Pick the replacement.** Choose the newest LTS release the application supports. Check with the application owner or vendor first. If the row is bundled, follow [Java bundled with an application](#java-bundled-with-an-application) instead.
2. **Install the new Java** with a Tanium package.
3. **Repoint every dependency listed in Used By:**
    - **Windows:** the service (procrun `Jvm` setting, wrapper `.conf`, WinSW `.xml`, or the service path), the scheduled task action, `JAVA_HOME` and PATH, and the `.jar` file association.
    - **Linux:** the systemd unit (`ExecStart` or `Environment=JAVA_HOME`), cron entries, environment files, and the default Java (`alternatives --set java` on RHEL, `update-alternatives --set java` on Debian and Ubuntu).
4. **Restart the service or run the task**, and confirm the application works on the new Java.
5. **Remove the old Java** using the finding above that matches its Installed By.

After any removal, ask this sensor again and check the Version column against the fixed version.

---

## Maintenance

None for new Java releases or security updates: the sensor has no version list. Revisit it only if:

- **Java is installed in a folder the search does not cover.** Add it to `$ExtraScanRoots` (Windows, for example `@('D:\Apps')`) or `EXTRA_SCAN_ROOTS` (Linux, for example `"/data/apps"`) near the top of the script.
- **Scans stop early on large servers.** Raise `$ScanSeconds` or `SCAN_SECONDS`.

---

## Troubleshooting

| Result | Meaning | What to do |
|---|---|---|
| **Scan incomplete** row | The folder search hit its time limit on that machine | Raise `$ScanSeconds` (Windows) or `SCAN_SECONDS` (Linux), or add the application folder to `$ExtraScanRoots` / `EXTRA_SCAN_ROOTS` |
| Stays on **[current result unavailable]** | The script is running longer than the Tanium Client allows and is being stopped | Lower `$ScanSeconds` to 20 and test again |
| All values in one column | **Split into multiple columns** or the `\|` delimiter was not saved | Edit the sensor and recheck Step 4 |
| `unknown` in Java Line and Version | No `release` file and no version on `java.exe` | Check the version on that machine manually |
| Java you expected is missing | It is outside the searched folders and not running | Add its folder to `$ExtraScanRoots` / `EXTRA_SCAN_ROOTS` |
| `N/A` on Mac / Solaris / AIX | Expected | Those platforms are not covered |

---

## Limits

- Per-user Java folders (`AppData\Local\Programs`, `AppData\Local\JetBrains`, `.jdks`) are searched for every profile, logged on or not. Only the registry checks are limited to logged-on users: per-user installer entries and user environment variables are read from loaded profiles only. For a user who is logged off, a per-user Java still appears, but Installed By and Uninstall Command show `Unknown (user profile not logged on)`, and a user `JAVA_HOME` or PATH entry that points at it is not listed.
- **(java from PATH)** dependencies use the system PATH, so a task that runs as a user with a different PATH may resolve to another Java.
- Rows marked **likely uses it** are based on folder location only. Confirm before removing.
- The sensor returns more rows than the vulnerable-only version, because patched runtimes are included.
- Java-based products such as Apache Tomcat or Log4j have their own vulnerabilities. Updating Java does not fix those.
