---
tags:
  - Tanium
  - Sensors
  - Java
  - PowerShell
---

# Java - Last Run - Prefetch (Sensor)

!!! tip "Replaced by Java - Install Usage - Prefetch"
    [Java - Install Usage - Prefetch](java-install-usage.md) returns everything this sensor does, tied to the exact Java that ran, and it tells you when Prefetch is switched on but not being written (common on servers, where this sensor would wrongly report "No Java runs recorded"). Use the newer sensor for new work.

This page shows how to create the **Java - Last Run - Prefetch** sensor in the Tanium Console, and how to use it to decide whether Java can be uninstalled from a workstation without asking anyone.

**What it returns:** one row per Java launcher that Windows has recorded running, with the Prefetch file name, when it last ran, and how many days ago that was.

**Why Prefetch:** a running-process question only shows what is running at the moment you ask. Users start Java on demand (a desktop app, a Web Start link, a vendor tool), so "not running right now" does not mean "not used". Windows Prefetch keeps a record of every executable that ran, updated each time it runs, so it answers the better question: **has Java run on this machine recently?**

---

## How the sensor works

Windows writes a Prefetch file to `C:\Windows\Prefetch` for each executable it runs, named `<EXECUTABLE>-<HASH>.pf`. The hash is calculated from the executable's full path, so each install location gets its own file, and the same path gives the same hash on every machine. The file's last-write time is updated each time the executable runs.

The script:

1. Reads `EnablePrefetcher` from `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters`. If it is `0`, Prefetch is off and the sensor returns `Prefetch disabled`.
2. Lists the `.pf` files in `C:\Windows\Prefetch` whose name starts with one of the Java launchers below.
3. Returns the file name, its last-write time, and the number of whole days since then.

| Launcher | What starts it |
|---|---|
| `JAVA.EXE` | Console Java programs, services, scripts, scheduled tasks |
| `JAVAW.EXE` | Java desktop applications (no console window) |
| `JAVAWS.EXE` | Java Web Start (`.jnlp` links). Also run by the Oracle Java installer during install and update |
| `JP2LAUNCHER.EXE` | Java Web Start and the old browser plug-in launcher |

The sensor only reads file names and dates. It does not open the Prefetch files or change anything.

---

## Use cases

**Uninstalling Java from workstations without approval.** The main use. When a workstation has Oracle Java installed, Java has not run for 30 days or more, and the Java on it is not bundled with an application, it is a safe removal. See [Workstation removal process](#workstation-removal-process).

**Telling installer activity apart from real use.** The Oracle Java installer runs `javaws.exe` itself during an install or update. When many machines show `JAVAWS.EXE`, `JAVAW.EXE`, and `JP2LAUNCHER.EXE` all running within a couple of minutes of each other, on the same date across the fleet, that is an update being installed, not people using Java. Check that date against your Java update or deployment schedule before you treat it as use.

**Finding where Java Web Start is still in use.** Machines with a recent `JAVAWS.EXE` or `JP2LAUNCHER.EXE` outside an update window are running a `.jnlp` application. Those are the users to talk to before Java leaves their machine.

**Checking a removal campaign.** After Java is removed, the Prefetch files stay behind and their Days Ago keeps rising. A machine where a new Java launcher row appears after removal has another Java on it (often a bundled or copied runtime).

---

## Before you start

- You need a role that can create sensors in the content set you plan to use.
- If a sensor with the same name already exists, edit it instead of creating a second one. Sensor names must be unique.
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
| Name | `Java - Last Run - Prefetch` |
| Description | Reports when each Java launcher (java.exe, javaw.exe, javaws.exe, jp2launcher.exe) last ran on a Windows endpoint, based on Windows Prefetch files. Returns one row per Prefetch file with the file name, last run time, and days since last run. Returns "No Java runs recorded" when no Java Prefetch file exists, and "Prefetch disabled" or "Prefetch folder missing" when Prefetch data is unavailable. Use it to decide whether installed Java is in use before removal. |
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

1. Set **Delimiter** to `|` (the pipe character, Shift + Backslash on a US keyboard).
2. Add these 3 columns in this order. The order must match, because the script returns the values in this order.

| Index | Column Name | Value Type | Ignore case | Hidden |
|---|---|---|---|---|
| 0 | Executable | Text | Checked | Unchecked |
| 1 | Last Run | Text | Checked | Unchecked |
| 2 | Days Ago | Numeric | Checked | Unchecked |

**Last Run** is Text, not Date/Time. The script writes it as `yyyy-MM-dd HH:mm`, which sorts correctly as text, and status rows put `N/A` in it.

### Step 5: Parameters section

Leave it empty. This sensor has no parameters.

### Step 6: Scripts section

For each platform in the table: click the platform tab on the left, check **Enable sensor for [platform] platform**, set **Query Type** in the top right, click inside the script editor, press **Ctrl + A**, press **Delete**, then paste the script for that platform.

| Platform | Enable | Query Type | Script |
|---|---|---|---|
| Windows | Checked | PowerShell | Windows script below |
| Linux | Checked | UnixShell | Stub below, returns N/A |
| Mac | Checked | UnixShell | Stub below, returns N/A |
| Solaris | Checked | UnixShell | Stub below, returns N/A |
| AIX | Checked | UnixShell | Stub below, returns N/A |

=== "Windows (PowerShell)"

    ```powershell
    --8<-- "tanium/sensors/java-last-run-prefetch/windows.ps1"
    ```

=== "Linux, Mac, Solaris, AIX (UnixShell)"

    ```sh
    #!/bin/sh
    echo "N/A"
    ```

### Step 7: Save

Scroll to the bottom of the page and click **Save**. If the console reports that the name already exists, cancel and edit the existing sensor.

### Step 8: Test on a few machines first

1. Go to **Interact**.
2. In the question bar, enter `Get Computer Name and Java - Last Run - Prefetch from all machines with Computer Name contains "<hostname>"`, replacing `<hostname>` with a workstation you know has Java.
3. Check that you see 3 columns. If everything is in one column with `|` inside the value, the column split was not saved. Edit the sensor and recheck Step 4.

---

## Reading the results

| Executable | Last Run | Days Ago | Meaning |
|---|---|---|---|
| `JAVAW.EXE-4A2EFA53.pf` | `2026-10-30 13:04` | `4` | A Java launcher at one specific path last ran 4 days ago |
| `No Java runs recorded` | `N/A` | `N/A` | No Java launcher has a Prefetch file. Either Java never ran, or its entry was removed because Prefetch was full (see [Limits](#limits)) |
| `Prefetch disabled` | `N/A` | `N/A` | `EnablePrefetcher` is `0`. Common on Windows Server. This sensor cannot answer for that machine |
| `Prefetch folder missing` | `N/A` | `N/A` | `C:\Windows\Prefetch` does not exist |

A machine can return several rows for the same launcher. Each hash is a different install path, for example `C:\Program Files\Java\jre1.8.0_401\bin\javaw.exe` and an application's bundled `jre\bin\javaw.exe`. The same hash on many machines means the same path on each of them.

!!! note "The sensor can't tell which Java ran"
    The hash comes from the path, but the path itself is stored inside the Prefetch file in a compressed format that a fast sensor does not read. A recent `JAVA.EXE` row can be an application's bundled Java rather than the Oracle Java you want to remove. Use the [Java - Runtime Inventory - Dependencies](java-runtime-inventory.md) sensor or a running-process question to see the path.

---

## Workstation removal process

Use this when your change process allows Java to be removed from a workstation without approval as long as nobody uses it and it is not part of an application.

### 1. Ask the question

Target your workstations only, with a positive filter:

```text
Get Computer Name and Java - Last Run - Prefetch and Installed Applications from all machines with ( Operating System contains "Windows 10" or Operating System contains "Windows 11" ) and Installed Applications:Name contains "Java"
```

### 2. Put each workstation in a bucket

| Prefetch result | Bucket |
|---|---|
| `No Java runs recorded` | Uninstall |
| Every row has Days Ago over 30 | Uninstall |
| Every recent row falls in a known Java update window (same date fleet-wide, launchers within minutes of each other) | Uninstall |
| Any other row with Days Ago of 30 or less | Review |
| `Prefetch disabled` or `Prefetch folder missing` | Review |

30 days is a starting point. Use 60 or 90 days if month-end or quarter-end tools are common in your environment.

### 3. Clear the Review bucket

For each Review machine, find out which Java actually ran:

- Ask a running-process question on those machines a few times across a working day, and look at the path of any `java.exe` or `javaw.exe`.
- Ask the [Java - Scheduled Tasks](java-scheduled-tasks.md) sensor to rule out a scheduled job.
- Ask the user.

If only an application's bundled Java runs, move the machine to Uninstall. The Oracle Java uninstall doesn't touch bundled runtimes.

### 4. Pilot, then the rest

1. Uninstall Oracle Java on about 5 machines from the Uninstall bucket with your uninstall package, using the product codes from the **Installed Applications** uninstall string. Wait 3 to 5 business days for tickets.
2. Build a computer group from a positive filter that matches the rest of the Uninstall bucket, and deploy to it.

Bundled Java and the Java runtime Tanium Comply ships inside the Tanium Client folder are not MSI products, so an uninstall that targets Oracle Java MSI product codes leaves them alone.

### 5. Verify

Ask the question from step 1 again. Machines where the uninstall worked drop out, because they no longer match `Installed Applications:Name contains "Java"`. Your vulnerability findings clear after the next Comply scan of each machine.

---

## Troubleshooting

| Result | Meaning | What to do |
|---|---|---|
| All values in one column | **Split into multiple columns** or the `\|` delimiter was not saved | Edit the sensor and recheck Step 4 |
| `Prefetch disabled` on workstations | Prefetch was turned off by policy or a tuning script | Use a running-process question over several days for those machines instead |
| Every machine shows Java on the same date | An update or deployment ran on that date | Treat those rows as install activity, see [Use cases](#use-cases) |
| `N/A` on Linux or Mac | Expected | Those platforms are not covered |

---

## Limits

- **Windows workstations only.** Prefetch is usually disabled on Windows Server, so servers mostly return `Prefetch disabled`.
- **Prefetch holds about 1,024 entries.** On a busy machine, an entry for something that has not run in a long time can be removed. That shows as `No Java runs recorded`, which is still evidence that Java has not run recently.
- **Last Run is approximate.** Windows writes the Prefetch file a few seconds after the program starts.
- **No path.** The sensor can't tell Oracle Java from bundled Java. See the note in [Reading the results](#reading-the-results).
- **Installers count as runs.** The Oracle Java installer runs `javaws.exe` during install and update.
