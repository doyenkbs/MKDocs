---
tags:
  - Tanium
  - Sensors
  - Processes
  - PowerShell
  - Linux
---

# Running Processes - Paths - Hashes (Sensor)

A Tanium sensor that lists the full path of every program running on each endpoint, with an optional MD5, SHA1, or SHA256 hash of the file. One sensor covers Windows and Linux.

It does the same job as the **Running Processes with MD5 Hash** sensor from Incident Response content, without needing Incident Response tools on the endpoint. See [Compared with built-in content](#compared-with-built-in-content).

**What it returns:** one row per unique running executable, with its path and hash. A program running ten times on a machine appears once.

---

## Use cases

**Checking whether an old runtime is actually in use before removing it.** Installed Applications shows that Java 6, an old .NET runtime, or an old Python is installed. It doesn't show whether anything is running it. Ask this sensor with a path filter, such as `\jre6\` for Java 6, across every machine that has it installed. Machines that return nothing for that path had no process running from it when you asked. It is a point-in-time check, so combine it with [Java - Last Run - Prefetch](java-last-run-prefetch.md) and [Java - Scheduled Tasks](java-scheduled-tasks.md) for Java, and get the application owner's sign-off before removing anything from a server.

**Sweeping the fleet for a known-bad file.** A security advisory or threat report gives you a SHA256 for a malicious or vulnerable binary. Filter on that hash to find every machine running it right now, whatever the file is named and wherever it was copied.

**Finding software that runs from user folders.** Programs running from `\AppData\`, `\Downloads\`, `\Temp\`, or `C:\ProgramData\` were usually installed per user, outside your software deployment process. Per-user installs don't show up in machine-wide Installed Applications, and they don't get patched. The [Remove Zoom User Install](../packages/remove-zoom-user-install.md) and [Remove VS Code User Install](../packages/remove-vscode-user-install.md) packages handle two common cases.

**Spotting version drift or a replaced binary.** Ask without Computer Name, filtered to one path. Each unique hash becomes its own row, and **Count** shows how many machines have it. One path with several hashes means machines are on different versions of that program, or one copy was replaced. A hash that appears on only one or two machines is the one to look at first.

**Finding remote access tools.** Filter on the program names your organization does not approve, such as `TeamViewer`, `AnyDesk`, or `ScreenConnect`. The path shows whether each one is a machine-wide install or a copy running from a user folder.

**Finding Linux services still running a replaced binary.** When a package upgrade replaces a program while it is running, Linux reports the path with ` (deleted)` at the end. The service is still running the old version until it restarts. Filter on `(deleted)` after a patch cycle to find services that need a restart. This only covers the program file itself. A service that still has an old shared library loaded, such as OpenSSL after an update, keeps its normal path and does not show up here.

**Building an application allowlist.** Before writing allow rules for an application control tool, collect the SHA256 of every program that actually runs on a group of machines. That is a better starting list than a scan of every executable on disk.

**Confirming a remediation worked.** After an uninstall or upgrade, ask again with the old path or hash. If it still shows, the old program is still running and the machine needs a restart, or the remediation did not apply.

### When not to use it

- **You need the command line, user, process ID, parent process, or start time.** This sensor returns only the path and hash. Command lines often hold passwords, so they are left out on purpose.
- **You need to know what ran in the past.** It only sees what is running at the moment the question is asked. On Windows, Prefetch shows what ran recently. See [Java - Last Run - Prefetch](java-last-run-prefetch.md) for the Java version.
- **The tenant has Incident Response or Threat Response tools on every endpoint.** The built-in sensor already works there.

---

## What it returns

Sample results from one Windows workstation, with hashes shortened:

| Path | Hash |
|---|---|
| `C:\Program Files (x86)\Google\Chrome\Application\chrome.exe` | `645d9a01...` |
| `C:\Program Files (x86)\TeamViewer\TeamViewer_Service.exe` | `1b3b4498...` |
| `C:\WINDOWS\Explorer.EXE` | `967bca06...` |
| `C:\WINDOWS\system32\lsass.exe` | `fd9b7c6b...` |
| `C:\WINDOWS\system32\svchost.exe` | `d122d210...` |
| `C:\Program Files\Microsoft OneDrive\OneDrive.exe` | `67e33a15...` |

With `NONE`, the Hash column is empty and the sensor returns faster.

### Output columns

| Column | Type | Contents |
|---|---|---|
| Path | Text | Full path of the running program, in the case Windows recorded it (`C:\WINDOWS\system32\...` and `C:\Windows\System32\...` both occur). On Linux, the path as the process sees it. |
| Hash | Text | Lowercase hex hash of the file, using the algorithm chosen in **HashType**. Empty when HashType is `NONE` or the file could not be hashed. |

### Status results

These appear in the Path column with the Hash column empty.

| Result | Meaning |
|---|---|
| `Error hashing <path>: <reason>` | That one file could not be hashed. The other rows are still returned. |
| `Error: Unsupported HashType '<value>'...` | The parameter value was not MD5, SHA1, SHA256, or NONE. |
| `Error: Unable to query Win32_Process: <reason>` | WMI did not answer on that Windows machine. |
| `Error: md5sum not found on this endpoint.` | Linux endpoint without the coreutils hash tool for the chosen algorithm. |
| `N/A` | A platform with no script, such as macOS. |

---

## How it works

### Windows

1. Reads every running process from WMI (`Win32_Process`) and keeps the unique executable paths. WMI returns full paths for both 32-bit and 64-bit processes.
2. Opens each file read-only, with sharing set so files in use and files marked for deletion can still be read, and hashes it with the .NET hash classes.
3. Skips the hash for files over 1 GB.

**Why the Sysnative mapping matters.** The Tanium Client is a 32-bit program on most installs (`C:\Program Files (x86)\Tanium\Tanium Client`), so the sensor runs in 32-bit PowerShell. Windows quietly redirects a 32-bit program's reads from `C:\Windows\System32` to `C:\Windows\SysWOW64`. Without a fix, two things go wrong:

- Files that exist only as 64-bit, such as `dwm.exe`, `lsass.exe`, and `winlogon.exe`, return `Cannot find path ... because it does not exist`.
- Files that exist in both folders, such as `svchost.exe`, return the hash of the 32-bit copy, not the file that is running. On one test machine the first version returned `c3c6de0c...` for `svchost.exe`. The fixed version returned `d122d210...`, which is the real 64-bit file.

The script detects 32-bit PowerShell on 64-bit Windows and reads `System32` files through `C:\Windows\Sysnative`, which bypasses the redirection. The Path column still shows the real `System32` path. `DriverStore` paths were never affected, because Windows excludes that folder from redirection.

### Linux

1. Lists every process in `/proc` and reads the `/proc/<pid>/exe` link to get the program path. Kernel threads have no program file and are skipped.
2. Hashes `/proc/<pid>/exe` itself, not the path it points to. That link always opens the file the process is actually running, so a binary that was replaced or deleted after the process started still hashes correctly, and so does a process inside a container.
3. Uses `md5sum`, `sha1sum`, or `sha256sum` from coreutils.

---

## Parameters

| Key | Label | Type | Values | Default |
|---|---|---|---|---|
| `HashType` | Hash Type | Drop-down list | `MD5`, `SHA1`, `SHA256`, `NONE` | `MD5` |

- **`NONE`** returns paths only. Use it when you only care which programs are running. It is much faster because no files are read.
- **`SHA256`** is the one to use for threat intelligence lookups, since most advisories publish SHA256.
- **MD5 on FIPS-enforced Windows machines.** When the Windows FIPS policy is enforced, .NET may refuse MD5 and every file returns an `Error hashing` row. Use `SHA256` on those machines. The Linux script is not affected.

Each parameter value is cached separately, so `[MD5]` and `[NONE]` each keep their own result for the Max Sensor Age.

---

## Requirements

- **Windows:** PowerShell 5.1. Works under both 32-bit and 64-bit Tanium Clients.
- **Linux:** `sh`, `readlink`, `stat`, `sort`, `awk`, and the coreutils hash tools. These are present on standard installs.
- No Python, Tanium Python modules, or Incident Response tools.
- A Tanium account with permission to create sensors.

---

## Create the sensor

### Step 1: Open a new sensor

On the Tanium Console:

1. Sign in to the Tanium Console.
2. Open the main menu, then go to **Administration > Content > Sensors**.
3. Click **Create Sensor**.

### Step 2: Details section

| Field | Value |
|---|---|
| Name | `Running Processes - Paths - Hashes` |
| Description | Returns the full executable path of each running process, with an optional file hash. Windows (PowerShell) and Linux (shell). Does not require Incident Response or Threat Response tools. Parameter HashType accepts MD5, SHA1, SHA256, or NONE (default MD5). Use NONE for path-only results, which is faster. Files over 1 GB are not hashed. On FIPS-enforced Windows hosts MD5 returns an error; use SHA256 instead. On Linux, paths ending in "(deleted)" mean the binary was replaced or removed while the process was running. Output columns: Path, Hash. |
| Content Set | Your own custom content set, restricted to your endpoint team |

### Step 3: Settings section

| Field | Value |
|---|---|
| Category | Processes (or any category you use for custom sensors) |
| Result Type | Text |
| Max Sensor Age | `10` and set the unit dropdown to **Minutes**. Running processes change quickly |
| Max String Age | Leave **Enable** unchecked |
| Max Strings | Leave **Enable** unchecked |
| Ignore case in result values | Checked |
| Hide this sensor from sensor lists and parse results | Unchecked |
| Split into multiple columns | Checked |

### Step 4: Column settings

1. Set **Delimiter** to `|#`.
2. Add these 2 columns in this order.

| Index | Column Name | Value Type | Ignore case | Hidden |
|---|---|---|---|---|
| 0 | Path | Text | Checked | Unchecked |
| 1 | Hash | Text | Checked | Unchecked |

!!! note "Why `|#` and not `|`"
    The other sensors on this site use `|`. This one uses `|#`, the same delimiter as the Incident Response sensor it replaces, so saved questions and reports built on that sensor's output keep working. It also avoids splitting a Linux path, which can legally contain `|`.

### Step 5: Parameters section

1. Click **Add Parameter** and choose **Drop-Down List**.
2. Set **Key** to `HashType`. It must match the `||HashType||` placeholder in the scripts exactly, including capitalization.
3. Set **Label** to `Hash Type`.
4. Add the values `MD5`, `SHA1`, `SHA256`, and `NONE`.
5. Set the default value to `MD5`.

### Step 6: Scripts section

| Platform | Enable | Query Type | Script |
|---|---|---|---|
| Windows | Checked | PowerShell | Windows script below |
| Linux | Checked | UnixShell | Linux script below |
| Mac | Checked | UnixShell | Stub below, returns N/A |
| Solaris | Checked | UnixShell | Stub below, returns N/A |
| AIX | Checked | UnixShell | Stub below, returns N/A |

Copy each script with the copy button on its code block so nothing is changed.

=== "Windows (PowerShell)"

    ```powershell
    --8<-- "tanium/sensors/running-processes-paths-hashes/windows.ps1"
    ```

=== "Linux (UnixShell)"

    ```sh
    --8<-- "tanium/sensors/running-processes-paths-hashes/linux.sh"
    ```

=== "Mac, Solaris, AIX (UnixShell)"

    ```sh
    #!/bin/sh
    echo "N/A"
    ```

### Step 7: Save

Scroll to the bottom of the page and click **Save**.

### Step 8: Test

On the Tanium Console, in **Interact**:

1. Test one Windows machine with both code paths. Replace `<windows-host>` with a real computer name.

    ```
    Get Computer Name and Running Processes - Paths - Hashes[NONE] from all machines with Computer Name equals "<windows-host>"
    ```

    ```
    Get Computer Name and Running Processes - Paths - Hashes[MD5] from all machines with Computer Name equals "<windows-host>"
    ```

2. In the MD5 result, check that `C:\Windows\System32\lsass.exe` and `dwm.exe` have hashes. `Error hashing ... does not exist` on System32 files means an older copy of the script without the Sysnative fix was pasted.
3. Repeat on one Linux machine:

    ```
    Get Computer Name and Running Processes - Paths - Hashes[SHA256] from all machines with Is Linux equals True and Computer Name equals "<linux-host>"
    ```

---

## Ask a question

**Is anything running from a specific folder?** Example for Java 6:

```
Get Computer Name and Running Processes - Paths - Hashes[NONE] from all machines with Running Processes - Paths - Hashes[NONE]:Path contains "\jre6\"
```

**Which machines are running a known file?**

```
Get Computer Name and Running Processes - Paths - Hashes[SHA256] from all machines with Running Processes - Paths - Hashes[SHA256]:Hash equals "<sha256>"
```

**What runs from user folders?**

```
Get Computer Name and Running Processes - Paths - Hashes[NONE] from all machines with Running Processes - Paths - Hashes[NONE]:Path contains "\AppData\"
```

Repeat with `\Downloads\` and `\Temp\`.

**How many versions of one program are running across the fleet?**

```
Get Running Processes - Paths - Hashes[SHA256] from all machines with Running Processes - Paths - Hashes[SHA256]:Path contains "\Microsoft\Edge\Application\msedge.exe"
```

Without Computer Name, each unique path and hash pair is one row, and **Count** shows how many machines have it.

**Which Linux services need a restart after patching?**

```
Get Computer Name and Running Processes - Paths - Hashes[NONE] from all machines with Running Processes - Paths - Hashes[NONE]:Path contains "(deleted)"
```

!!! warning "Tanium Comply runs its own Java"
    During a Comply scan, `C:\Program Files (x86)\Tanium\Tanium Client\extensions\comply\jre\bin\java.exe` appears in the results. It is the private Java runtime Comply uses for its scanner. It is not the system Java and doesn't depend on it, and it goes away when the scan finishes. A filter such as `Path contains "jre"` will catch it, so filter on the specific folder instead (`\jre6\`, `\jre1.8`, `\jdk-11`). Never include it in a cleanup.

---

## Troubleshooting

| What you see | Likely cause | What to do |
|---|---|---|
| `Error hashing C:\Windows\System32\...: Cannot find path ... because it does not exist` on many rows | An older copy of the Windows script without the Sysnative fix | Edit the sensor and paste the Windows script from this page again. |
| `Error hashing` on every file with MD5, but SHA256 works | Windows FIPS policy is enforced | Use `SHA256` on those machines. |
| `Error: Unsupported HashType` | The parameter value was typed instead of picked, or the drop-down list values were changed | Check Step 5. |
| `Error: Unable to query Win32_Process` | WMI is broken on that machine | Repair WMI on that machine, then ask again. |
| `Error: <tool> not found on this endpoint.` | Minimal Linux install | Install coreutils, or use `NONE`. |
| `Error locating necessary files. Ensure Incident Response Tools are deployed. Error was: No module named 'taniumlib'` | That is the Incident Response sensor, not this one | Use this sensor, and disable the imported one so nobody else hits the same error. |
| `TSE-Error: Sensor evaluation timed out` | Hashing took too long, usually on a busy server with many large programs | Ask with `NONE`, or target fewer machines. |
| `N/A` | macOS, Solaris, or AIX | Not supported on those platforms. |
| A program you expected is missing | It wasn't running when the question was asked, or the result is cached | Ask again after the Max Sensor Age (10 minutes). |

---

## Compared with built-in content

| | Running Processes (core) | Running Processes with MD5 Hash (Incident Response) | This sensor |
|---|---|---|---|
| Full path | No, names only | Yes | Yes |
| Hash | No | MD5, SHA1, SHA256 | MD5, SHA1, SHA256, or none |
| Dependencies | None | Tanium Python and Incident Response tools. Without them it returns `Error locating necessary files` | None. PowerShell 5.1, or `sh` and coreutils |
| Platforms | Windows, Linux, macOS | Windows, Linux, macOS | Windows, Linux |

---

## Limits

- **Point in time.** A program that runs on a schedule or a few times a month only shows up if it is running when the question is asked.
- **No command lines, users, process IDs, or start times.** Path and hash only.
- **Protected processes are skipped on Windows.** `System`, `Registry`, and some security agents return no path to WMI, even for `SYSTEM`.
- **Files over 1 GB are listed without a hash.**
- **No internal time limit.** Unlike the other sensors on this site, the script does not stop itself before the sensor timeout. On a machine with hundreds of large programs, hashing can run long. Use `NONE` if that happens.
- **Container processes on Linux show the path as the container sees it**, for example `/usr/bin/python3` inside the container, not the host path. The hash is still correct.
- **macOS is not covered.** macOS has no `/proc`.

