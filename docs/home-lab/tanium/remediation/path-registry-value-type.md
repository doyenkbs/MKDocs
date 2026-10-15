---
tags:
  - Tanium
  - Windows
  - Registry
  - WMI
  - PowerShell
  - Packages
---

# Path Registry Value Type (Client Core Health)

The **Tanium Client Core Health** sensor can return this on Windows endpoints:

```
Error: Path registry value type is not correct. It should be REG_EXPAND_SZ.
```

The machine's system PATH is stored in the registry with the wrong value type. Everything else on the machine usually looks normal, so treat it as a cleanup item, not an outage. This page explains the error, how to find the affected machines in Tanium, and a package that fixes the value type without touching the data.

The same sensor returns other messages too. [The PowerShell execution test error](#the-powershell-execution-test-error) and [Other messages from this sensor](#other-messages-from-this-sensor) cover them, including a small package to check and repair WMI.

!!! note "Test status"
    `Fix-PathRegType.ps1` was tested on Windows 11 with Windows PowerShell 5.1 against a scratch registry key, run through `cmd.exe` the same way a Tanium package runs it. See [Test results](#test-results). The sensor behavior described on this page comes from reading the sensor's script. `Repair-WmiHealth.ps1` was tested the same way, with the salvage step stubbed out. Neither package has been run through a Tanium action yet. Use [Reproduce it in a lab](#reproduce-it-in-a-lab) and test on one machine before deploying wider.

---

## What the error means

The system PATH lives in this registry value:

```
HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment\Path
```

On a normal Windows install, its type is `REG_EXPAND_SZ`. That type tells Windows to expand variables such as `%SystemRoot%` into real paths such as `C:\Windows`.

On the affected machines the value has been rewritten as `REG_SZ`, a plain string. The entries can still contain `%SystemRoot%`, but nothing marks them as variables that need expanding.

The sensor only reports this error when both of these are true:

- The Path value is not `REG_EXPAND_SZ`.
- The Path data contains a `%`.

A `REG_SZ` Path with no variables in it is not flagged. The fix script below converts any `REG_SZ` Path anyway, since `REG_EXPAND_SZ` is the Windows default and the conversion does not change the data.

I have not confirmed what changes the value. Scripts and installers that rewrite PATH without setting the value type are the usual suspects.

---

## Find the affected machines

Run these in **Interact**, in the question bar.

All machines with the error:

```
Get Computer Name and Tanium Client Core Health from all machines with Tanium Client Core Health contains "REG_EXPAND_SZ"
```

One machine, for example after running the fix:

```
Get Tanium Client Core Health from all machines with Computer Name equals "WIN11-TEST01"
```

No direct or remote access to the endpoint is needed for either question.

---

## Why the fix is written the way it is

The obvious fix is to read PATH with `Get-ItemProperty`, delete the value, and recreate it as `ExpandString`. The script avoids that for two reasons.

**`Get-ItemProperty` expands the value when it reads it.** On a healthy machine it returns `C:\WINDOWS\system32`, not `%SystemRoot%\system32`. Writing that back would replace every variable with a hardcoded path. The script reads the raw value with the .NET registry API and the `DoNotExpandEnvironmentNames` option instead.

**Deleting and recreating leaves a gap.** If the recreate step fails, the machine has no system PATH at all. The script overwrites the value in place with one call, changing only the type.

The script also:

- Leaves machines alone when PATH is already `REG_EXPAND_SZ`.
- Refuses to write when PATH is missing, empty, or a type other than `REG_SZ`.
- Exports the whole `Environment` key to `C:\Windows\Temp\Environment_Path_backup.reg` before writing, and stops if the export fails.
- Reads the value back after writing and confirms the type is `REG_EXPAND_SZ` and the data did not change.

`HKLM\SYSTEM` is not redirected for 32-bit processes, so the script gives the same result whether the Tanium client starts 32-bit or 64-bit PowerShell.

---

## Exit codes

| Exit code | Meaning |
|---|---|
| `0` | PATH was converted to `REG_EXPAND_SZ`, or it already was. |
| `1` | The write or the check after the write failed. Run the [rollback package](#roll-back). |
| `2` | The backup failed. Nothing was changed. |
| `3` | PATH is missing, empty, or an unexpected type. Nothing was changed. |

---

## Requirements

- Windows endpoints with Windows PowerShell 5.1.
- A Tanium account with permission to create packages in a content set and deploy actions to the target computers.

---

## Create the package

Menu labels can differ slightly between Tanium versions.

1. Save the script at the bottom of this page as `Fix-PathRegType.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package**.
4. Fill in the fields:
    - **Package Display Name:** `Fix Path Registry Value Type` (add your team's prefix if you use one).
    - **Content Set:** the content set your team uses for custom content.
    - **Command:**
      ```
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Fix-PathRegType.ps1
      ```
    - **Command Timeout:** `5` minutes. The script normally finishes in a few seconds.
5. Under **Files**, click **Add**, choose **Local File**, and upload `Fix-PathRegType.ps1`.
6. Click **Save**.

The package has no parameters.

---

## Deploy the package

Start with one machine.

1. In **Interact**, ask:
    ```
    Get Computer Name and Tanium Client Core Health from all machines with Tanium Client Core Health contains "REG_EXPAND_SZ"
    ```
2. Select one computer in the results grid.
3. Click **Deploy Action**.
4. In **Deployment Package**, search for and select `Fix Path Registry Value Type`.
5. Under the schedule, leave it as a one-time action.
6. Click **Show preview to continue**, review the target, then click **Deploy Action**.
7. When the action completes, ask the single-machine question from [Find the affected machines](#find-the-affected-machines) for that computer. If the result has not changed, wait a few minutes and ask again. Tanium can return a cached sensor result until it ages out.
8. Once that machine reports healthy, repeat steps 1 through 6 with the rest of the computers selected.

The script skips machines that are already correct, so targeting a broad group is safe.

### After the fix

The registry change takes effect right away, but processes that were already running keep the environment they started with. Services keep it until the machine reboots. Let the machines reboot in their normal maintenance window instead of forcing one.

---

## View the results

1. Open the action from **Administration** > **Actions** > **Action History**.
2. Select an endpoint.
3. Open its action log. The script output appears between the `Command Line` line and the `Completed` line.

A converted machine:

```
2026-10-13 16:08:33 [INFO] Current type: String
2026-10-13 16:08:33 [INFO] Path has 4 entries. Contains variables: True
2026-10-13 16:08:33 [INFO] Backup saved: C:\Windows\Temp\Environment_Path_backup.reg
2026-10-13 16:08:33 [INFO] Converted Path from REG_SZ to REG_EXPAND_SZ. Data unchanged.
2026-10-13 16:08:33 [INFO] Running processes keep their old environment until they restart or the machine reboots.
```

A machine that was already correct:

```
2026-10-13 16:08:34 [INFO] Current type: ExpandString
2026-10-13 16:08:34 [INFO] Path is already REG_EXPAND_SZ. Nothing to do.
```

For many endpoints, ask a question with the built-in **Tanium Action Log** sensor, using the action ID from the top of the log:

```
Get Tanium Action Log[12345] from all machines
```

---

## Roll back

Rollback is a second package with no files. It imports the backup the fix saved on each endpoint.

1. In **Administration** > **Content** > **Packages**, click **Create Package**.
2. Fill in the fields:
    - **Package Display Name:** `Rollback Path Registry Value Type`
    - **Content Set:** the same content set as the fix.
    - **Command:**
      ```
      cmd.exe /d /c reg.exe import C:\Windows\Temp\Environment_Path_backup.reg
      ```
    - **Command Timeout:** `5` minutes.
3. Click **Save**.
4. Deploy it only to the machines you want to roll back, then let them reboot in the normal maintenance window.

The import restores every value in the `Environment` key to what it was when the backup was taken, not only `Path`. If anything else in that key changed after the fix ran, the import reverts it too.

---

## The PowerShell execution test error

The same sensor can also return:

```
Unable to perform PowerShell execution test, please ensure the latest Default Content tools are installed.
```

Despite the wording, this is not a PowerShell problem. Before the sensor runs its PowerShell test, it checks for this file in the Tanium Client folder:

```
Tools\StdUtils\tanium-clm-test.ps1
```

If the file is missing, the sensor reports this message and skips the test. It never starts PowerShell. Confirm the file is missing with:

```
Get Computer Name and File Exists[C:\Program Files (x86)\Tanium\Tanium Client\Tools\StdUtils\tanium-clm-test.ps1] from all machines with Tanium Client Core Health contains "PowerShell execution test"
```

That path assumes the default install folder. The sensor finds the client folder from the `TANIUM_CLIENT_ROOT` environment variable, or from the `Path` value under `HKLM\SOFTWARE\Tanium\Tanium Client` (or `HKLM\SOFTWARE\WOW6432Node\Tanium\Tanium Client`). Adjust the path if your clients are installed somewhere else.

If the file is missing, get the Standard Utilities tools redistributed to that endpoint. In **Administration** > **Content** > **Packages**, search for `Standard Utilities` to find the package that distributes them. In most environments a scheduled action already does this, so also check why it did not reach the machine.

If the file is present, the sensor runs it and reports a different message when PowerShell fails or is not in FullLanguage mode. See the next section.

---

## Other messages from this sensor

The sensor runs a series of checks and prints one line for each check that fails. It prints `Healthy` only when every check passes. One machine can return several lines, so the counts in a question's results are lines, not machines. Add **Computer Name** to see which machine returned what:

```
Get Computer Name and Tanium Client Core Health from all machines with Tanium Client Core Health does not contain "Healthy"
```

If the sensor cannot create its basic objects (WScript.Shell, FileSystemObject, or the WMI registry provider), it prints that one error and stops. The rest of the checks never run on that machine, so fix that error first and ask again.

| Message | What failed | What to do |
|---|---|---|
| `Error: <number>. Cannot create StdRegProv object.` | The WMI registry provider in `root\default` could not be loaded | [Check and repair WMI](#check-and-repair-wmi) |
| `Error: Cannot properly access registry via WMI` | A registry read through WMI failed | [Check and repair WMI](#check-and-repair-wmi) |
| `Error: <number>. Cannot create WMI object.` / `Cannot query WMI.` | WMI `root\cimv2` could not be opened or queried | [Check and repair WMI](#check-and-repair-wmi) |
| `Error: WMI cannot retrieve a basic property` | `Select ProductType from Win32_OperatingSystem` returned nothing | [Check and repair WMI](#check-and-repair-wmi) |
| `Error: Path is missing Windows\system32 directory` (or `Wbem`) | The PATH the Tanium Client is running with does not include those folders | Fix the system Path, then restart the Tanium Client service or reboot. The client keeps the PATH it started with |
| `Tanium Signing Certificate <years> Not Found` | That Tanium code-signing certificate is not in the machine's Trusted Publishers store | Reinstall the Tanium signing certificates. Signed Tanium PowerShell content can fail where AllSigned or WDAC is enforced |
| `Unable to execute PowerShell from the Tanium Client` / `PowerShell command failed with exit code <n>` / `Unable to determine Powershell execution status` | The test script ran but did not report success | Check whether antivirus or application control is blocking PowerShell started by the Tanium Client |
| `PowerShell is not operating in the required FullLanguage mode.` | PowerShell is in Constrained Language Mode | The sensor names the cause: either the `__PSLockdownPolicy` system variable, which should be removed, or WDAC, which needs a rule allowing Tanium-signed scripts |
| `PowerShell Not Found` / `PowerShell must be at least version 3.0` | No supported PowerShell version found in the registry | Install or repair Windows PowerShell 5.1 |
| `TSE-Error: Sensor evaluation timed out` | The Tanium Client stopped the sensor before it finished | Ask again. The PowerShell test waits for PowerShell to exit, so a hung PowerShell or WMI call can cause this. If it repeats, check whether other PowerShell sensors also time out on that machine |
| `TSE-Error: Failed to send to sensor child process: broken pipe` | The Tanium Client lost contact with the sensor process. This comes from the client, not the sensor script | Ask again. If it keeps happening on the same machine, restart the Tanium Client service |

The negative numbers in the WMI messages are Windows error codes. Convert them to hex to look them up. For example, `-2147217406` is `0x80041002`, which means WMI could not find the class or object it was asked for.

### Check and repair WMI

`Repair-WmiHealth.ps1` runs the same two WMI calls the sensor depends on:

1. A registry read through `StdRegProv` in `root\default`.
2. `Select ProductType from Win32_OperatingSystem` in `root\cimv2`.

In **Check** mode it only reports. In **Repair** mode it runs `winmgmt /salvagerepository` when a check fails, then runs the checks again. Salvage only rebuilds the WMI repository if it finds it inconsistent, and it keeps everything it can still read. The script never runs `/resetrepository`.

Every run also logs the `Winmgmt` service state and the result of `winmgmt /verifyrepository`, so the action log shows what was wrong before anything changed.

| Exit code | Meaning |
|---|---|
| `0` | Both checks pass, either right away or after the salvage. |
| `1` | Repair mode ran the salvage and a check still fails. |
| `2` | A check failed in Check mode. Nothing was changed. |
| `3` | The Mode value was not `Check` or `Repair`. |

#### Create the package

1. Save `Repair-WmiHealth.ps1` from the [Scripts](#scripts) section.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages** and click **Create Package**.
3. Fill in the fields:
    - **Package Display Name:** `Check and Repair WMI`
    - **Content Set:** the content set your team uses for custom content.
    - **Command:**
      ```
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Repair-WmiHealth.ps1 "$1"
      ```
    - **Command Timeout:** `15` minutes. A salvage can take several minutes on a slow machine.
4. Under **Files**, click **Add**, choose **Local File**, and upload `Repair-WmiHealth.ps1`.
5. Expand **Parameters**. Under **Parameter Inputs**, add a **Drop Down List** parameter. It shows in the list as `$1`.
    - **Label:** `Mode`
    - **Values:** `Check` and `Repair`, with `Check` as the default.
6. Click **Save**.

#### Use it

1. In **Interact**, find the machines with a WMI message:
    ```
    Get Computer Name and Tanium Client Core Health from all machines with Tanium Client Core Health contains "WMI" or Tanium Client Core Health contains "StdRegProv"
    ```
2. Deploy the package with **Mode** set to `Check`, and read the action log on each machine.
3. Deploy again with **Mode** set to `Repair` on the machines that failed.
4. Ask the sensor again for those machines.

A check that fails in Check mode looks like this. The error text after the check name depends on what is broken on the machine:

```
2026-10-13 16:46:20 [INFO] Mode: Check
2026-10-13 16:46:20 [INFO] Winmgmt service: Running, startup Automatic
2026-10-13 16:46:21 [ERROR] StdRegProv (root\default): Invalid namespace
2026-10-13 16:46:21 [INFO] Win32_OperatingSystem (root\cimv2): OK, ProductType 1
2026-10-13 16:46:21 [WARN] WMI checks failed. Check mode, nothing changed. Run again with Mode Repair.
```

If Repair mode ends with exit code `1`, the repository may be consistent while a provider is missing or broken, which a salvage does not fix. That machine needs hands-on work, such as re-registering the WMI providers. `winmgmt /resetrepository` is the last resort: it removes classes that other software registered (for example a configuration management client) until that software registers them again.

---

## Reproduce it in a lab

`Break-PathRegType.ps1` puts a lab VM into the broken state so the fix and the sensor can be checked end to end. **Only run it on a lab VM, and take a snapshot first.**

Run each command in an elevated PowerShell session on the VM, from the folder where the script is saved.

1. Check the starting state. Path type should be `ExpandString`:
    ```powershell
    .\Break-PathRegType.ps1 -Mode Status
    ```
2. Break PATH the same way the affected machines were broken:
    ```powershell
    .\Break-PathRegType.ps1 -Mode Break
    ```
3. In **Interact**, confirm the sensor now returns the `REG_EXPAND_SZ` error for the VM.
4. Deploy the fix package to the VM and confirm the sensor clears.
5. Optional: run `-Mode BreakNoVars`, which leaves PATH as `REG_SZ` with no `%` in it. The sensor should not report the error for this case. Run `-Mode Restore` before the next step.
6. Optional: run `-Mode HideClmTest`, which renames `tanium-clm-test.ps1` to `tanium-clm-test.ps1.bak`. The sensor should return the PowerShell execution test error.
7. Put everything back:
    ```powershell
    .\Break-PathRegType.ps1 -Mode Restore
    ```

The first `Break` or `BreakNoVars` saves the untouched key to `C:\Windows\Temp\Break-PathRegType_original.reg`, and `Restore` imports it.

---

## Test results

Each case ran `Fix-PathRegType.ps1` through `cmd.exe`, the same way a Tanium package runs it, against a scratch key under `HKCU` instead of the real system PATH.

| Case | Expected | Result |
|---|---|---|
| `REG_SZ` containing `%SystemRoot%` | Exit 0, `REG_EXPAND_SZ`, data unchanged | Pass |
| Run again on the fixed value | Exit 0, nothing to do | Pass |
| Rollback with `reg import` | Back to `REG_SZ`, data unchanged | Pass |
| `REG_SZ` with no variables | Exit 0, `REG_EXPAND_SZ` | Pass |
| Empty `REG_SZ` | Exit 3, unchanged | Pass |
| Path value missing | Exit 3, not created | Pass |
| Unexpected type (`REG_MULTI_SZ`) | Exit 3, unchanged | Pass |
| Backup fails | Exit 2, unchanged | Pass |
| Run from 32-bit PowerShell | Exit 0, `REG_EXPAND_SZ` | Pass |

Also confirmed on Windows 11: `Get-ItemProperty` returns the Path entries already expanded, and 32-bit PowerShell reads the same `HKLM\SYSTEM` value as 64-bit PowerShell.

### Repair-WmiHealth.ps1

Each case ran through `cmd.exe` with the Mode parameter quoted, the same way a Tanium package runs it. The broken cases used a copy of the script pointed at a namespace that does not exist, with the salvage command replaced by a stub, so no real WMI repository was changed.

| Case | Expected | Result |
|---|---|---|
| Healthy machine, Check | Exit 0, both checks logged | Pass |
| Blank Mode | Treated as Check, exit 0 | Pass |
| Healthy machine, Repair | Exit 0, no salvage | Pass |
| Invalid Mode | Exit 3 | Pass |
| Run from 32-bit PowerShell | Restarts as 64-bit, exit 0 | Pass |
| Broken check, Check | Exit 2, no salvage | Pass |
| Broken check, salvage does not help | Exit 1 | Pass |
| Broken check, salvage fixes it | Exit 0 | Pass |

`winmgmt /salvagerepository` itself was not run in testing. `winmgmt /verifyrepository` needs administrator rights, which a Tanium action has as SYSTEM.

---

## Scripts

### Fix-PathRegType.ps1

```powershell
--8<-- "tanium/packages/fix-path-reg-type/Fix-PathRegType.ps1"
```

### Repair-WmiHealth.ps1

```powershell
--8<-- "tanium/packages/wmi-health/Repair-WmiHealth.ps1"
```

### Break-PathRegType.ps1 (lab only)

```powershell
--8<-- "tanium/packages/fix-path-reg-type/Break-PathRegType.ps1"
```
