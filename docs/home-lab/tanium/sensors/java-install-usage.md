---
tags:
  - Tanium
  - Sensors
  - Java
  - PowerShell
---

# Java - Install Usage - Prefetch (Sensor)

This page shows how to create the **Java - Install Usage - Prefetch** sensor in the Tanium Console, and how to use it to decide which Java on a machine can be removed and which one is actually being used.

**What it returns:** one row per Java on a Windows machine. Each row gives the Java folder, its version, how it was installed, when it was installed, when it last ran, a plain-language usage summary, which Java programs ran, and the uninstall command.

**Why it exists:** a machine often has several Java installs at once: two or three Java 8 updates, a JDK, and Java bundled inside applications. A list of what is installed doesn't tell you which one is used. Windows Prefetch keeps a record of every program that runs, and this sensor ties each of those records to the exact Java folder that ran, so you can see which Java is in use and which has never run.

!!! note "Replaces Java - Last Run - Prefetch"
    [Java - Last Run - Prefetch](java-last-run-prefetch.md) shows that Java ran, but not which Java. This sensor shows everything that one did, tied to the Java that ran it, and it also tells you when Prefetch is switched on but not being written. Use this one going forward.

---

## How the sensor works

### 1. Windows Prefetch names each file after the program's path

When a program runs, Windows writes a file to `C:\Windows\Prefetch` named `<PROGRAM>-<HASH>.pf`, for example `JAVAW.EXE-4A2EFA53.pf`. The 8-character hash is worked out from the full path of the program that ran, so the same program in two different folders gets two different files. The file's date changes every time the program runs.

### 2. The sensor works out that hash for every Java it finds

For each Java folder on the machine, the script calculates the hash that Windows would use for `java.exe`, `javaw.exe`, `javaws.exe`, and `jp2launcher.exe` in that folder, and looks for a Prefetch file with that name. A match proves that this exact Java ran, and the file's date says when.

It finds Java in:

- Installed programs in Apps and Features whose name looks like Java (Oracle, OpenJDK, Temurin, Corretto, Zulu, Semeru, Liberica)
- The JavaSoft registry keys
- Running Java processes
- Oracle's `javapath` shortcut folders, and copies of `java.exe` in `C:\Windows\System32` or `SysWOW64`
- The Java that Tanium Comply ships inside the Tanium Client folder
- A folder search: `Program Files` and `Program Files (x86)` 2 levels deep, other top-level folders on each fixed drive 3 levels deep, and in each user profile the `.jdks` folder, VS Code Java extensions, and `AppData\Local\Programs`

The folder search stops after 15 seconds. If it stops early, the sensor adds a **Scan incomplete** row.

### 3. Java that has been removed

When a Prefetch file doesn't match any Java on disk, the script also tries Oracle's standard folder names for Java 6, 7, and 8 (for example `C:\Program Files\Java\jre1.8.0_503`). A match there means that Java ran before it was removed, which is common after an update replaces the previous version.

### 4. Checking that Prefetch is working

Prefetch can be switched on but not written. This is common on Windows Server, where the SysMain service is usually turned off. A running machine writes Prefetch files all day, so if no Prefetch file anywhere is newer than 3 days, the sensor reports **Unknown (Prefetch not recording)** instead of claiming that Java never ran.

The sensor is read-only. It doesn't use WMI, doesn't compile code, doesn't write files, and works whether the Tanium Client runs it in 64-bit or 32-bit PowerShell.

---

## Use cases

**Choosing which Java to remove on a machine with several.** Rows with **No runs recorded** or **Ran only on install day** are safe to remove. A row with **Ran after install** is the one people use.

**Telling an update apart from real use.** When Java updates, the installer itself runs `javaws.exe`. The sensor compares the last run date with the install date, so those runs show as **Ran only on install day** instead of looking like use.

**Finding Java that hides inside applications.** Bundled Java shows with **Installed By** set to `No installer entry`, so you can hand those to the application owner instead of uninstalling them.

**Knowing when the answer can't be trusted.** Servers that don't write Prefetch show **Unknown (Prefetch not recording)**, so you know to check those another way before removing anything.

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
| Name | `Java - Install Usage - Prefetch` |
| Description | Lists every Java on a Windows endpoint, one row per install, and shows whether and when it last ran, based on Windows Prefetch files. Each Prefetch file is matched to the exact Java folder that ran it, including Oracle Java 6, 7 and 8 folders that have since been removed. Returns the Java folder, file version, installer name, install date, last run date, days since last run, a usage summary, the Java programs that ran, and the uninstall command. Reports "Unknown (Prefetch not recording)" when Prefetch is on but not being written, which is common on servers. Read-only. Returns "None" when no Java is found. |
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
2. Add these 9 columns in this order. The order must match, because the script returns the values in this order.

| Index | Column Name | Value Type | Ignore case | Hidden |
|---|---|---|---|---|
| 0 | Java Home | Text | Checked | Unchecked |
| 1 | Version | Text | Checked | Unchecked |
| 2 | Installed By | Text | Checked | Unchecked |
| 3 | Installed On | Text | Checked | Unchecked |
| 4 | Last Run | Text | Checked | Unchecked |
| 5 | Days Ago | Numeric | Checked | Unchecked |
| 6 | Usage | Text | Checked | Unchecked |
| 7 | Launchers | Text | Checked | Unchecked |
| 8 | Uninstall Command | Text | Checked | Unchecked |

**Installed On** and **Last Run** are Text because they also hold `N/A` and `Never`. The `yyyy-MM-dd` format still sorts correctly.

### Step 5: Parameters section

Leave it empty. This sensor has no parameters.

### Step 6: Scripts section

For each platform in the table: click the platform tab on the left, check **Enable sensor for [platform] platform**, set **Query Type** in the top right, click inside the script editor, press **Ctrl + A**, press **Delete**, then paste the script for that platform.

| Platform | Enable | Query Type | Script |
|---|---|---|---|
| Windows | Checked | PowerShell | Windows script below |
| Linux | Checked | UnixShell | Stub below |
| Mac | Checked | UnixShell | Stub below |
| Solaris | Checked | UnixShell | Stub below |
| AIX | Checked | UnixShell | Stub below |

=== "Windows (PowerShell)"

    ```powershell
    --8<-- "tanium/sensors/java-install-usage/windows.ps1"
    ```

=== "Linux, Mac, Solaris, AIX (UnixShell)"

    ```sh
    #!/bin/sh
    echo "Not Applicable|N/A|N/A|N/A|N/A|N/A|N/A|N/A|N/A"
    ```

### Step 7: Save

Scroll to the bottom of the page and click **Save**. If the console reports that the name already exists, cancel and edit the existing sensor.

### Step 8: Check it on one machine

1. Go to **Interact**.
2. In the question bar, enter `Get Java - Install Usage - Prefetch from all machines with Computer Name contains "<hostname>"`, replacing `<hostname>` with a workstation you know has Java.
3. Check that you see 9 columns. If everything is in one column with `|` inside the value, the column split was not saved. Edit the sensor and recheck Step 4.

---

## Reading the results

### Columns

| Column | What it tells you |
|---|---|
| Java Home | The Java folder, for example `C:\Program Files\Java\jre1.8.0_511`. For bundled Java it's the application's Java folder, for example `C:\Program Files\ExampleApp\jre` |
| Version | The file version of `java.exe`, for example `8.0.5110.33` for Java 8 Update 511 build 33, or `11.0.32.1`. This is the same format Installed Applications and most vulnerability scanners show |
| Installed By | The name in Apps and Features, or one of the values in [Installed By values](#installed-by-values) |
| Installed On | The install date from Apps and Features, or the date the folder was created |
| Last Run | The last day any Java program in this folder ran, `Never`, or `N/A` when Prefetch can't be used |
| Days Ago | Days since Last Run. Use it to filter, for example `Days Ago less than 30` |
| Usage | A summary, see [Usage values](#usage-values) |
| Launchers | Which Java programs ran: `java`, `javaw`, `javaws`, `jp2launcher`. `(javapath)` after a name means it ran through Oracle's shortcut folder |
| Uninstall Command | For MSI installs, a ready silent uninstall: `MsiExec.exe /X{GUID} /qn /norestart`. `None registered` when there is no uninstaller |

Example row (values are illustrative): `C:\Program Files\Java\jre1.8.0_511|8.0.5110.33|Java 8 Update 511 (64-bit)|2026-10-28|2026-10-28|9|Ran only on install day|javaw, javaws, jp2launcher|MsiExec.exe /X{00000000-0000-0000-0000-000000000000} /qn /norestart`

### Usage values

| Usage | Meaning | What to do |
|---|---|---|
| `No runs recorded` | No Java program in this folder has run as far as Prefetch remembers | Safe to remove, unless it's bundled with an application |
| `Ran only on install day` | It ran only on the day it was installed. This is the installer, not a person | Safe to remove |
| `Last ran before this install` | Its last run is older than its install date, usually because it was reinstalled or repaired | Treat as not used |
| `Ran after install` | Something ran it after it was installed | In use. Check Days Ago and Launchers, and talk to the user before removing it |
| `Ran before removal` | A Java that has already been removed | Nothing to do |
| `Ran from a folder that was not found` | A Java program ran from a folder the search didn't reach | Use [Java - Runtime Inventory - Dependencies](java-runtime-inventory.md) on that machine to find it |
| `Unknown (Prefetch not recording)` | Prefetch is switched on but no file is newer than 3 days. Common on Windows Server | Don't use this sensor to decide. Check **Used By** in Java - Runtime Inventory - Dependencies |
| `Unknown (Prefetch disabled)` | Prefetch is turned off | Same as above |

### Installed By values

| Installed By | Meaning |
|---|---|
| The Apps and Features name, for example `Java 8 Update 511 (64-bit)` | A normal install. Remove it with the Uninstall Command or the Uninstall MSI package |
| `No installer entry` | Java with no uninstaller: either copied or unzipped by someone, or bundled inside an application. If the folder sits inside an application's folder, it belongs to that application. Don't delete it; update the application |
| `Copy in Windows folder` | Old Java installers copied `java.exe` into `C:\Windows\System32` or `SysWOW64`. These usually go away when that Java is uninstalled |
| `Oracle javapath (runs the default Java)` | Oracle's shortcut folder. When only one installed Java has the same version, its runs are credited to that Java instead |
| `Tanium Comply (do not remove)` | The Java that Tanium Comply uses. Leave it alone |
| `Removed (folder no longer exists)` | Java that ran here but has since been removed |

---

## Using it in a Java cleanup

1. **Ask the question with Computer Name,** so every row is tied to a machine:

    ```text
    Get Computer Name and Java - Install Usage - Prefetch from all machines with ( Is Windows equals True and Installed Applications:Name contains "Java" )
    ```

2. **Workstations:** remove installed Java whose Usage is `No runs recorded`, `Ran only on install day`, or `Last ran before this install`, and that your vulnerability scanner flags. Keep the current patched version. Contact the user for any `Ran after install` row before changing it.
3. **Servers:** Usage is usually `Unknown (Prefetch not recording)`. Ask [Java - Runtime Inventory - Dependencies](java-runtime-inventory.md) instead and use its **Used By** column. Servers usually run Java as a Windows service, and that sensor reads the service settings.
4. **Bundled Java** (`No installer entry` inside an application folder): send the list to the application owners. Only an application update fixes it.
5. **Copied Java** (`No installer entry` in a folder such as `C:\Tools\jdk-17.0.12` or `C:\Downloads\jdk1.8.0_131`): there is no uninstaller. Confirm nothing uses it with Java - Runtime Inventory - Dependencies, then delete the folder with a package.
6. **Ask again after removal.** Removed Java changes to `Ran before removal`, or drops off if it never ran.

For a large result set, export the results to CSV and sort by **Usage** and **Installed By**.

!!! warning "No runs recorded is not proof on its own"
    The sensor only sees Java started through `java.exe`, `javaw.exe`, `javaws.exe`, or `jp2launcher.exe`. Some services load Java through their own program instead, for example a Tomcat service (`Tomcat9.exe`) or an application's own launcher. Those leave no Java Prefetch file. On workstations this is rare. On servers, always check **Used By** in Java - Runtime Inventory - Dependencies before removing anything.

---

## Troubleshooting

| Result | Meaning | What to do |
|---|---|---|
| All values in one column | **Split into multiple columns** or the `\|` delimiter was not saved | Edit the sensor and recheck Step 4 |
| `Unknown (Prefetch not recording)` on workstations | The SysMain service is stopped or Prefetch was turned off by a tuning script | Use Java - Runtime Inventory - Dependencies for those machines |
| **Scan incomplete** row | The folder search hit its 15-second limit | Ask again. The list for that machine may be missing some Java |
| `TSE-Error: Sensor evaluation timed out` | The script didn't finish in time, usually on a busy server with many folders | Ask again |
| Same Java shows as `Ran after install` on many machines on the same date | An update or deployment ran on that date | Check the date against your Java deployment schedule |
| `Not Applicable` on Linux or Mac | Expected | Those platforms are not covered |

---

## Limits

- **Windows only.** Linux and macOS have no Prefetch.
- **Prefetch remembers about 1,024 programs.** On a busy machine, the record of something that hasn't run in a long time can be dropped. That shows as `No runs recorded`, which still means it hasn't run recently.
- **Java started through a renamed program is not seen.** See the warning in [Using it in a Java cleanup](#using-it-in-a-java-cleanup).
- **Removed Java is named only for Oracle Java 6, 7, and 8.** A removed Java 11 or newer shows as `Ran from a folder that was not found`, because those folder names carry the full version.
- **Per-user installs** show `No installer entry`. The sensor doesn't read installer entries from user profiles.
- **Last Run is a date, not a time,** so results from many machines merge into fewer rows.
