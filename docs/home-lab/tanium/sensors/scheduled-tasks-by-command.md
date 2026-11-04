---
tags:
  - Tanium
  - Sensors
  - PowerShell
---

# Scheduled Tasks - By Command (Sensor)

This page shows how to create the **Scheduled Tasks - By Command** sensor in the Tanium Console. It is the general version of [Java - Scheduled Tasks](java-scheduled-tasks.md): you type what to look for when you ask the question.

**What it returns:** one row per scheduled task whose name, command line, or script contains the text you enter, with the task path, its state, the account it runs as, when it last ran, and its command line.

**How it differs from the built-in Scheduled Tasks sensor:** the built-in sensor lists every task on every machine, with only the task name and action, and leaves out run times so that results merge. This sensor filters on the endpoint, so only matching tasks come back, and it adds the state, the run-as account, and a last-run value you choose the detail of.

!!! warning "Command lines are returned"
    Matching tasks come back with their full command line, and arguments can hold passwords or connection strings. Keep the sensor in a content set that only your endpoint team can use, and read results before you paste them anywhere.

---

## How the sensor works

The script reads every scheduled task through the Task Scheduler COM API (`Schedule.Service`), including hidden tasks and every subfolder. It does not use WMI, so it answers on machines where `Get-ScheduledTask` fails.

For each task action, it checks the **Match** text, ignoring case, against:

- The task path and name, for example `\Vendor\NightlyExport`
- The program and its arguments, with environment variables expanded
- The class ID and data of COM handler actions
- With **ScanScripts** set to `Yes`: the contents of any `.bat`, `.cmd`, `.ps1`, or `.vbs` file under 1 MB that the task runs, either as the program itself or named in the arguments (for example `powershell.exe -File D:\Scripts\cleanup.ps1`). A match inside a script adds `[script <name> matches]` to the command.

Match is plain text, not a regular expression or wildcard. `D:\Scripts` finds every task that mentions that folder.

### Last run and merging

Tanium merges result rows only when every column is identical. An exact run time is different on almost every machine, so the same task on 300 machines comes back as up to 300 rows, and each unique value adds load on the Tanium Server. The **LastRun** parameter lets you choose:

| LastRun | Last Run value | Use it for |
|---|---|---|
| `Age` (default) | `0-7 days`, `8-30 days`, `31-90 days`, `91-365 days`, `Over 1 year`, or `Never` | Questions across the fleet. Rows merge, and it still answers whether a task is in use |
| `Day` | `2026-10-28` | Seeing whether a task ran across many machines on the same day |
| `Exact` | `2026-10-28 08:31` | A few machines, when you need the minute |

The output is capped at 500 rows per machine. If a machine reaches the cap, it adds a `Max rows reached` row so you know its answer is partial.

---

## Use cases

**Before deleting a folder or share.** Match `D:\Scripts` or `\\fileserver01\scripts` to find every task that would break when that folder goes away.

**Before retiring a server.** Match the server name (for example `app-old01`) to find tasks on other machines that copy from it, connect to it, or run scripts from it.

**Finding what runs an interpreter.** Match `python`, `wscript`, or `mshta` to find tasks that run scripts through that interpreter, for example before removing an old Python version.

**Hunting for unwanted tools.** Match a tool name such as `rclone`, `psexec`, or a remote-access agent to find scheduled tasks that start it. Match `-enc` to find PowerShell started with an encoded command, which legitimate tasks rarely need.

**Finding dead tasks.** With `LastRun` set to `Age`, rows with `Over 1 year` or `Never` are tasks nobody has used in a long time. They are good candidates for cleanup.

**Java.** Use [Java - Scheduled Tasks](java-scheduled-tasks.md) instead. A Match of `java` also hits `javascript`, while the Java sensor excludes it and also catches `.jar` and `.jnlp`.

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
| Name | `Scheduled Tasks - By Command` |
| Description | Searches Windows scheduled tasks for a text match in the task path and name, the action command line, or COM handler CLSID, using the Task Scheduler COM API, so it works on machines with broken WMI. When ScanScripts is Yes, it also searches inside .bat, .cmd, .ps1 and .vbs files under 1 MB that a task runs. Returns one row per matching task with the task path, state, run-as account, last run, and command line. LastRun controls the last run format: Age (default) returns time buckets so results merge across machines, Day returns the date, and Exact returns the date and time. The Match parameter is case-insensitive plain text, minimum 3 characters. Output is capped at 500 rows per endpoint. Returns "No matching scheduled tasks" when nothing matches. |
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
2. Add these 5 columns in this order.

| Index | Column Name | Value Type | Ignore case | Hidden |
|---|---|---|---|---|
| 0 | Task | Text | Checked | Unchecked |
| 1 | State | Text | Checked | Unchecked |
| 2 | Run As | Text | Checked | Unchecked |
| 3 | Last Run | Text | Checked | Unchecked |
| 4 | Command | Text | Checked | Unchecked |

**Last Run** must be Text, because with `LastRun` set to `Age` it holds buckets such as `8-30 days`, not dates.

### Step 5: Parameters section

The parameter **Key** values must match the placeholders in the script exactly, including capitalization: `Match`, `ScanScripts`, and `LastRun`. Create them in this order, because the order sets the order of values in brackets when you type the question: `[Match,ScanScripts,LastRun]`.

#### Parameter 1: Match (Text Input)

1. In the **Parameters** section, click **Add Parameter**, then select **Text Input**.
2. **Key:** replace `parameter_1` with `Match`.
3. **Label:** `Match`
4. Under **Options**:
    - Check **Provide Help Text** and enter: `Text to find in the task name, command line, or script contents. Case-insensitive, minimum 3 characters.`
    - Check **Provide Prompt Text** and enter: `python, D:\Scripts, backup.ps1`
    - Leave **Provide Default Value** unchecked, so every question has to supply a value.
    - Check **Provide Max Chars** and enter: `200`
    - Leave **Enable drill-down autofill** unchecked.
5. Under **Validation Expressions**:
    - Replace `.*` with `^.{3,}$`
    - In **Enter Help Text**, type: `Enter at least 3 characters.`

#### Parameter 2: ScanScripts (Drop-Down List)

1. Click **Add Parameter**, then select **Drop-Down List**.
2. **Key:** `ScanScripts`
3. **Label:** `Scan scripts`
4. Under **Options**:
    - Check **Provide Help Text** and enter: `Yes also searches inside .bat, .cmd, .ps1 and .vbs files the task runs.`
    - Leave **Enable drill-down autofill** unchecked.
5. Under **Values**:
    - In the first **Value** box, enter: `Yes`
    - Click **+ add value** and enter: `No`

#### Parameter 3: LastRun (Drop-Down List)

1. Click **Add Parameter**, then select **Drop-Down List**.
2. **Key:** `LastRun`
3. **Label:** `Last run format`
4. Under **Options**:
    - Check **Provide Help Text** and enter: `Age returns buckets that merge across machines. Day and Exact return dates and create a unique row per machine.`
    - Leave **Enable drill-down autofill** unchecked.
5. Under **Values**, enter in this order: `Age`, then `Day`, then `Exact`, clicking **+ add value** between each.

#### Check the parameters

- **Parameter Inputs** lists `Match - Text Input`, `ScanScripts - Drop-Down List`, and `LastRun - Drop-Down List`, in that order. If not, drag them into place with the handle on the right of each entry.
- A drop-down list has no default setting. Put the value you want preselected first (`Yes` and `Age`). The script also falls back to `Yes` and `Age` if it gets an unexpected value.
- Expand **Preview** to confirm the three inputs show with your labels and prompt text.

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
    --8<-- "tanium/sensors/scheduled-tasks-by-command/windows.ps1"
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
2. Ask a question with a value you know exists on a test machine, for example:

    ```text
    Get Computer Name and Scheduled Tasks - By Command[CheckStatus,Yes,Exact] from all machines with Computer Name contains "<hostname>"
    ```

3. Check that you see 5 columns, and that the task you expected is listed.
4. Ask it again with a value that doesn't exist (for example `zzzq`) and check that the machine returns `No matching scheduled tasks`.

---

## Asking questions

Values in brackets are positional, in the order the parameters were created: `[Match,ScanScripts,LastRun]`. If the question bar doesn't accept a value (for example one that contains a comma), open the question in **Question Builder** and type the values in the parameter fields instead.

```text
Get Scheduled Tasks - By Command[python,Yes,Age] from all machines with Is Windows equals True
Get Computer Name and Scheduled Tasks - By Command[D:\Scripts,No,Day] from all machines with Is Windows equals True
```

**Computer Name is optional.** Without it, identical rows from different machines merge into one row, and the **Count** column shows how many machines returned it. Use that to see what exists across the fleet. Add Computer Name when you need the list of machines, or select a row in the results and ask a follow-up question that adds Computer Name, so only the machines behind that row answer.

---

## Reading the results

| Column | What it tells you |
|---|---|
| Task | Full task path, for example `\Vendor\NightlyExport` |
| State | `Ready`, `Running`, `Disabled`, `Queued`, or `Unknown` |
| Run As | The account the task runs as |
| Last Run | Depends on the `LastRun` parameter, see [Last run and merging](#last-run-and-merging) |
| Command | Program and arguments. `COM handler {CLSID} <data>` for COM actions. `[script <name> matches]` when the match was found inside the script |

| Status row | Meaning |
|---|---|
| `No matching scheduled tasks` | Nothing on that machine matches |
| `Error: Match parameter was not provided` | The question had no Match value |
| `Error: Match must be at least 3 characters` | The Match value was too short |
| `Error: <message>` | The Task Scheduler service could not be reached |
| `Max rows reached` | The machine had more than 500 matches. Use a more specific Match |

---

## Troubleshooting

| Result | Meaning | What to do |
|---|---|---|
| `Error: Match parameter was not provided` on every machine | The parameter **Key** does not match the script placeholder | Edit the sensor and check the Key is exactly `Match` |
| ScanScripts or LastRun seems ignored | Same cause, for that parameter | Check the Keys are exactly `ScanScripts` and `LastRun` |
| Thousands of rows | The Match is too broad, for example `exe` or `Microsoft`, which also matches task paths | Use a more specific value, and keep LastRun on `Age` |
| `TSE-Error: Failed to send to sensor child process: broken pipe` | The Tanium Client could not run PowerShell on that machine | A client-side problem, not this sensor. Check `C:\Program Files (x86)\Tanium\Tanium Client\Logs\log0.txt` on that machine |
| All values in one column | The column split was not saved | Edit the sensor and recheck Step 4 |

---

## Limits

- Plain text matching only. No wildcards or regular expressions.
- The Run As account is returned but not searched. To find tasks for one account, match on something in the task instead, or filter the results on the **Run As** column.
- Script contents are checked one level deep, and only for files under 1 MB that the Tanium Client account can read.
- Only scheduled tasks. Services, Run registry keys, the Startup folder, and logon scripts are not checked.
