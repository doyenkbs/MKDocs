---
tags:
  - Tanium
  - Sensors
  - Java
  - PowerShell
---

# Java - Scheduled Tasks (Sensor)

This page shows how to create the **Java - Scheduled Tasks** sensor in the Tanium Console, and how to use it to check whether any scheduled job depends on Java before Java is removed.

**What it returns:** one row per scheduled task that launches Java, with the task path, its state, the account it runs as, when it last ran, and its command line. Machines with no such task return a single `No Java scheduled tasks` row, so the whole fleet answers in one merged row.

!!! warning "Command lines are returned"
    This sensor returns the full command line of each matching task. Arguments can hold passwords or connection strings (for example `-Dpassword=...`). Keep the sensor in a content set that only your endpoint team can use, and don't paste results into tickets without reading them first. The [Java - Runtime Inventory - Dependencies](java-runtime-inventory.md) sensor never returns command lines, if you need a safer view of the same dependency.

---

## How the sensor works

The script reads every scheduled task through the Task Scheduler COM API (`Schedule.Service`), including hidden tasks and tasks in every subfolder. It does not use WMI or the `ScheduledTasks` PowerShell module, so it still answers on machines where WMI is broken. On those machines `Get-ScheduledTask` fails with errors such as `Invalid namespace`, `Invalid class`, or `The type initializer for 'Microsoft.Management.Infrastructure.Native.ApplicationMethods' threw an exception`.

For each task action that starts a program, the script:

1. Expands environment variables in the program path. When the Tanium Client runs the sensor in 32-bit PowerShell, it also maps `%ProgramFiles%` and `System32` to the real 64-bit locations, so the paths it checks are the ones the task will use.
2. Checks the program path and arguments for `java.exe`, `javaw.exe`, `javaws.exe`, a `.jar` file, or a `.jnlp` file. The match ignores `javascript`.
3. If the task runs a `.bat`, `.cmd`, `.ps1`, or `.vbs` file under 1 MB, also checks the contents of that file and adds `[script calls Java]` to the command when it matches.

Tasks that run COM handlers instead of a program are skipped, since they don't start Java directly.

---

## Use cases

**Clearing Java for removal.** Before Java is uninstalled, a scheduled job that calls it is the dependency nobody remembers. Ask this sensor across the fleet once. Machines that return `No Java scheduled tasks` have no scheduled dependency, and the rows that remain are a short list to check.

**Finding dead jobs.** A task that is still **Ready** but last ran a year or more ago is usually a retired job that was never deleted. Confirm with its owner, then remove the task instead of keeping Java around for it.

**Finding jobs that run as a named user.** The **Run As** column shows tasks running as a person's account instead of a service account or `SYSTEM`. Those jobs break when that person leaves or changes their password, Java or not.

**Workstations and servers.** The sensor is light enough to ask across every Windows machine. On servers it is most useful together with a check of Windows services, since server Java usually runs as a service.

For any program other than Java, use [Scheduled Tasks - By Command](scheduled-tasks-by-command.md).

---

## Before you start

- You need a role that can create sensors in the content set you plan to use.
- If a sensor with the same name already exists, edit it instead of creating a second one.
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
| Name | `Java - Scheduled Tasks` |
| Description | Lists Windows scheduled tasks that launch Java, using the Task Scheduler COM API, so it works on machines with broken WMI. Matches java.exe, javaw.exe, javaws.exe, .jar and .jnlp in the task action, and also checks .bat, .cmd, .ps1 and .vbs scripts under 1 MB that the task runs. Returns one row per matching task with the task path, state, run-as account, last run time, and command line. Returns "No Java scheduled tasks" when none are found. Use it to confirm whether any scheduled job depends on Java before removal. |
| Content Set | Your own custom content set, restricted to your endpoint team |

### Step 3: Settings section

| Field | Value |
|---|---|
| Category | Miscellaneous (or any category you use for custom sensors) |
| Result Type | Text |
| Max Sensor Age | `4` and set the unit dropdown to **Hours**. Scheduled tasks change rarely |
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
| 0 | Task | Text | Checked | Unchecked |
| 1 | State | Text | Checked | Unchecked |
| 2 | Run As | Text | Checked | Unchecked |
| 3 | Last Run | Text | Checked | Unchecked |
| 4 | Command | Text | Checked | Unchecked |

**Last Run** is Text because it also holds `Never` and `N/A`. The `yyyy-MM-dd HH:mm` format still sorts correctly.

### Step 5: Parameters section

Leave it empty. This sensor has no parameters.

### Step 6: Scripts section

| Platform | Enable | Query Type | Script |
|---|---|---|---|
| Windows | Checked | PowerShell | Windows script below |
| Linux | Checked | UnixShell | Stub below, returns N/A |
| Mac | Checked | UnixShell | Stub below, returns N/A |
| Solaris | Checked | UnixShell | Stub below, returns N/A |
| AIX | Checked | UnixShell | Stub below, returns N/A |

=== "Windows (PowerShell)"

    ```powershell
    --8<-- "tanium/sensors/java-scheduled-tasks/windows.ps1"
    ```

=== "Linux, Mac, Solaris, AIX (UnixShell)"

    ```sh
    #!/bin/sh
    echo "N/A"
    ```

### Step 7: Save

Scroll to the bottom of the page and click **Save**.

### Step 8: Test

1. Go to **Interact**.
2. Ask `Get Java - Scheduled Tasks from all machines with Is Windows equals True`.
3. Most machines should merge into one `No Java scheduled tasks` row. Every other row is a task to check.
4. To see which machines have a task, select its row and ask a follow-up question that adds **Computer Name**, or ask `Get Computer Name and Java - Scheduled Tasks from all machines with Java - Scheduled Tasks:Task contains "<task name>"`.

---

## Reading the results

| Column | What it tells you |
|---|---|
| Task | Full task path, for example `\Vendor\NightlyExport` |
| State | `Ready`, `Running`, `Disabled`, `Queued`, or `Unknown`. A disabled task does not run, but it will break if someone turns it back on |
| Run As | The account the task runs as, for example `SYSTEM`, a service account, or a person's account |
| Last Run | `yyyy-MM-dd HH:mm`, or `Never` if the task has never run |
| Command | Program and arguments. `[script calls Java]` means the match was found inside the script the task runs, not in the task itself |

Example row (values are illustrative): `\NightlyExport|Ready|svc-reports|2026-10-30 02:00|D:\Apps\Reports\export.bat [script calls Java]`

### What to do with a row

1. **Open the script or command and find which Java it calls.**
    - A path inside an application folder (for example `D:\Apps\Vendor\jre\bin\java.exe`) uses the application's bundled Java. Removing Oracle Java does not affect it.
    - A bare `java` or `%JAVA_HOME%\bin\java` uses whatever Java the system PATH or `JAVA_HOME` points to. Removing that Java breaks the task.
2. **Check Last Run.** A task that has not run in a year or more is a candidate for removal itself. Confirm with the owner first.
3. **If the task is needed**, install a supported Java first, change the task or script to use it, and then remove the old Java.

---

## Troubleshooting

| Result | Meaning | What to do |
|---|---|---|
| `Error: <message>` | The Task Scheduler service could not be reached | Check that the **Task Scheduler** service (`Schedule`) is running on that machine |
| `TSE-Error: Sensor evaluation timed out` | The script did not finish in time, usually on a machine with many tasks or slow script files | Ask again. If it repeats, check the machine for other slow sensors |
| `TSE-Error: Failed to send to sensor child process: broken pipe` | The Tanium Client could not start or talk to the PowerShell process on that machine | A client-side problem, not this sensor. Check `C:\Program Files (x86)\Tanium\Tanium Client\Logs\log0.txt` on that machine, and whether security software blocked the child process |
| All values in one column | The column split was not saved | Edit the sensor and recheck Step 4 |

---

## Limits

- Only scheduled tasks. Windows services, Run registry keys, the Startup folder, and logon scripts are not checked.
- Script contents are checked one level deep. A `.bat` file that calls another `.bat` file that calls Java is not found.
- A script on a network share is only read if the account running the Tanium Client (usually `SYSTEM`) can read it.
- A bare `java` in a command matches, but the sensor does not resolve which Java the PATH points to.
