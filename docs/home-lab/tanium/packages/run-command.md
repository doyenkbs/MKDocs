---
tags:
  - Tanium
  - PowerShell
  - Bash
  - Linux
  - Packages
  - Endpoint Management
---

# Run Command (Package)

Two Tanium packages that run one command that the operator types, after a set of checks:

- **Run Command (Windows)** runs the command in Windows PowerShell 5.1 as SYSTEM.
- **Run Command (Linux and macOS)** runs the command in bash as the Tanium client user, normally root.

This is a break-glass tool. Use it when no dedicated package fits and you must run something on a group of endpoints now. The package runs whatever is typed, so the access control around it matters more than the script.

The packages have an **Audit** mode. Audit mode runs the checks and reports whether the command would run. It runs nothing.

The packages do not restart the endpoint unless the command does. The checks stop a shutdown or a power off. A restart is allowed.

!!! danger "Restrict this to a locked-down content set"
    The real control on this package is who can deploy it. Put it in its own content set. Give deploy rights to a few senior operators through RBAC. Never target an open group such as All Computers. The checks inside the scripts stop common mistakes. They are not a security boundary, and a person who wants to get around them can. Do not loosen deploy rights because the checks exist.

!!! warning "Test status"
    Tested through Tanium on one Windows endpoint and one Linux endpoint: Audit and Run mode, blocked commands, exit codes, special characters in the command, and the 60-line limit in the action log. The power-off check was added after the lab tests and was tested outside Tanium only. **Not tested: macOS, and endpoints with CrowdStrike or CyberArk installed.** Deploy to one endpoint first and read the action log.

---

## What the package does

1. Reads **Mode** and **Command**, and decodes the command. Tanium sends both values URL-encoded.
2. Stops with exit code 2 when a parameter is incorrect. For example, the command is empty, or it is not valid PowerShell.
3. Runs the checks. When a check trips, the package logs `BLOCKED` with the reason and stops. Nothing runs.
4. In Audit mode, logs `WOULD RUN` and stops. Nothing runs.
5. In Run mode, runs the command and writes its output to the action log.
6. Logs the result and ends with an exit code. See [Exit codes](#exit-codes).

## What the checks stop

| Category | What happens |
|---|---|
| Delete a protected system path | Blocked. On Windows: the Windows folder, boot and recovery folders, the root of each drive, the root of `Program Files` and `Users`, protected registry keys, and admin shares. On Linux and macOS: system folders such as `/etc`, `/usr`, `/boot`, `/var/lib`, and the roots of `/home`, `/root`, `/opt`, `/var`. Cleanup folders such as `C:\Windows\Temp` and `/usr/local` are allowed. |
| Delete with a path that the script cannot read | Blocked. For example, a path built from a variable. |
| High-damage disk, boot, or registry operation | Blocked. Disk format, partition changes, shadow-copy or backup deletion, boot configuration deletion, raw disk writes. |
| Shut down, power off, hibernate, or suspend | Blocked, because Tanium cannot start the endpoint again. A restart is allowed. |
| Stop, disable, uninstall, or delete a security agent | Blocked for CrowdStrike, Tanium, and CyberArk, also when the agent folder or registry key is the target. Reading the status of these agents is allowed. |
| Encoded or decode-and-run command | Blocked. On Windows: a PowerShell encoded command, and `Invoke-Expression`. On Linux and macOS: text that is decoded and sent to a shell. |

The checks are a list of known patterns. Anything that is not on the list runs. The Windows checks read the command through the PowerShell parser. The Linux and macOS checks have no parser and are weaker.

## Requirements

- **Windows:** Windows PowerShell 5.1 and the Tanium Client.
- **Linux and macOS:** bash and the Tanium Client.
- A Tanium account with permission to create packages in a content set and deploy actions. The content set must be restricted to a small group.

---

## Create the packages

1. In the Tanium Console, go to **Administration > Content > Packages**.
2. Click **Create Package**.
3. Fill in the fields with the values in the tab for the package. Then add the file and the parameters.

=== "Run Command (Windows)"

    | Field | Value |
    |---|---|
    | Package Name | `Run Command (Windows)` |
    | Display Name | `Run Command (Windows)` |
    | Description | `Runs one PowerShell command that you type, as SYSTEM, for break-glass work when no other package fits. Checks the command first and refuses it when it deletes a protected Windows folder or registry key, formats a disk, deletes shadow copies or boot settings, shuts down the endpoint, stops or removes CrowdStrike, Tanium, or CyberArk, or uses an encoded command. Audit mode runs the checks, reports the result, and runs nothing. The checks prevent accidents and are not a security boundary. The command is written to the action log as typed. Windows only.` |
    | Content Set | Your custom content set. Use a content set that only a few senior administrators can deploy. |
    | Command | `cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File RunCommand.ps1 "$1" "$2"` |
    | Command Timeout | 15 minutes |
    | Download Timeout | 10 minutes |
    | Ignore Action Lock | Clear (not selected) |
    | Launch this package command in a process group | Selected |
    | Files | `RunCommand.ps1` |

    Parameters:

    | Key | Type | Label | Values | Default |
    |---|---|---|---|---|
    | `$1` | Drop-Down List | Mode | `Audit` first, then `Run` | None. An empty value counts as `Audit`. |
    | `$2` | Text Input | Command | Any PowerShell command | None. The operator must enter a value. |

    Help text:

    | Key | Help text |
    |---|---|
    | `$1` | `Audit runs the safety checks and reports the result. It runs nothing. Run runs the command if the checks pass.` |
    | `$2` | `The PowerShell command to run as SYSTEM, for example Get-Service -Name wuauserv. The action log shows it as typed, so do not type a password.` |

=== "Run Command (Linux and macOS)"

    | Field | Value |
    |---|---|
    | Package Name | `Run Command (Linux and macOS)` |
    | Display Name | `Run Command (Linux and macOS)` |
    | Description | `Runs one bash command that you type, as the Tanium client user (normally root), for break-glass work when no other package fits. Checks the command first and refuses it when it deletes a protected system folder, writes to a raw disk, shuts down the endpoint, stops or removes CrowdStrike, Tanium, or CyberArk, or decodes and runs hidden text. Audit mode runs the checks, reports the result, and runs nothing. The checks prevent accidents, are weaker than the Windows checks, and are not a security boundary. The command is written to the action log as typed. Linux and macOS.` |
    | Content Set | The same restricted content set. |
    | Command | `/bin/bash runcommand.sh "$1" "$2"` |
    | Command Timeout | 15 minutes |
    | Download Timeout | 10 minutes |
    | Ignore Action Lock | Clear (not selected) |
    | Launch this package command in a process group | Selected |
    | Files | `runcommand.sh` |

    Parameters:

    | Key | Type | Label | Values | Default |
    |---|---|---|---|---|
    | `$1` | Drop-Down List | Mode | `Audit` first, then `Run` | None. An empty value counts as `Audit`. |
    | `$2` | Text Input | Command | Any bash command | None. The operator must enter a value. |

    Help text:

    | Key | Help text |
    |---|---|
    | `$1` | `Audit runs the safety checks and reports the result. It runs nothing. Run runs the command if the checks pass.` |
    | `$2` | `The bash command to run as root, for example systemctl status sshd. The action log shows it as typed, so do not type a password.` |

4. Click **Save**.
5. Do steps 2 to 4 again for the second package.

!!! tip "Changed a script later?"
    Tanium keeps its own copy of each uploaded file. After you change a script, edit the package and upload the file again.

---

## Deploy the package

Deploy the package two times on one endpoint first. Use Audit mode first. Then use Run mode.

### Run 1: Audit

1. In the Tanium Console, go to **Interact**.
2. In the question bar, type this question. Replace `ENDPOINT-01` with the name of your endpoint.

    ```text
    Get Computer Name from all machines with Computer Name equals ENDPOINT-01
    ```

3. Press Enter.
4. Select the endpoint.
5. Click **Deploy Action**.
6. In the **Deployment Package** field, type `Run Command`. Select `Run Command (Windows)` or `Run Command (Linux and macOS)`.
7. Set **Mode** to `Audit`.
8. In **Command**, type the command.
9. Click **Show preview to continue**.
10. Make sure that the list shows the correct endpoint.
11. Click **Deploy Action**.
12. Read the action log. Refer to [Read the results](#read-the-results).
13. Make sure that the log shows `WOULD RUN`.

### Run 2: Run

1. Deploy the package again to the same endpoint.
2. Set **Mode** to `Run`.
3. Type the same command.
4. Click **Show preview to continue**.
5. Click **Deploy Action**.
6. Read the action log. Make sure that it shows `RAN` and the output that you expect.

When the result is correct, deploy to the group that needs it. For a group of one operating system, use a filter such as `Is Windows equals True` or `Is Linux equals True`.

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Finished. Run mode: the command ran and returned 0. Audit mode: always 0. Read the `BLOCKED` or `WOULD RUN` line. |
| 1 | The command ran and failed. It returned a code that is not 0, or it stopped with an error. The `FAILED` line shows the command's own code. |
| 2 | A parameter was incorrect: Mode, an empty command, a split value, or a Windows command that is not valid PowerShell. Nothing ran. |
| 3 | Blocked: a protected system path, a high-damage disk, boot, or registry operation, or a shutdown. Nothing ran. |
| 4 | An error occurred that the package did not expect. Nothing ran. Read the action log. |
| 5 | Blocked: a protected security agent. Nothing ran. |
| 6 | Blocked: an encoded or decode-and-run command. Nothing ran. |

Action History shows **Completed** for every exit code, also for a blocked command. The status only says that the package command started. Read the exit code in the last line of the action log, `Action Exit Code: N`.

Some programs, such as robocopy, use codes that are not 0 for success. The package returns 1 for these. Read the code in the `FAILED` line.

---

## Read the results

To read the action log from the Tanium Console:

1. Go to **Interact**.
2. Type this question. Replace `<action ID>` with the ID of your action.

    ```text
    Get Tanium Action Log[<action ID>] from all machines with Computer Name equals ENDPOINT-01
    ```

3. Press Enter.

Each run starts with a `started on` line and a `Settings:` line, and ends with a `Summary` line and a `Finished with exit code` line. Between them, the result line starts with one of these words:

| Word | Meaning |
|---|---|
| `WOULD RUN` | Audit mode only. The checks passed. Run mode would run the command. |
| `BLOCKED` | A check stopped the command. The line shows the reason. Nothing ran. |
| `WRONG INPUT` | A parameter was incorrect. Nothing ran. |
| `RUNNING` | Run mode. The checks passed. The command output follows. |
| `RAN` | The command returned exit code 0. |
| `FAILED` | The command returned another code, or stopped with an error. |
| `TRUNCATED` | The output had more than 60 lines. The action log shows the first 60. |

The action log shows the first 60 lines of the command output, and drops blank lines, so the result stays on screen. The package writes every line, with up to 5000 lines of output, to a log file on the endpoint:

- **Windows:** `C:\Windows\Temp\RunCommand.log`
- **Linux and macOS:** `/var/log/runcommand.log`, when the client user can write there.

On Windows, each line has a level such as `[INFO]` or `[WARN]`. On Linux and macOS, warnings and errors start with `WARNING:` or `ERROR:`. Each line also starts with the date and time. The Tanium Console shows one space after the first word of a line, and table output loses its column alignment. Add `| Format-List` to a PowerShell command when the output is a table.

### Example log: Audit, blocked (Windows)

```text
[INFO] ===== RunCommand 2.0.0 started on ENDPOINT-01 =====
[INFO] Settings: mode=Audit; command=Remove-Item -Path "C:\Users" -Recurse -Force
[WARN] BLOCKED command deletes 'C:\Users', a protected OS path.
[INFO] Summary (Audit, nothing changed): would run=0; blocked=1
[INFO] ===== Finished with exit code 0 =====
```

### Example log: Run (Windows)

```text
[INFO] ===== RunCommand 2.0.0 started on ENDPOINT-01 =====
[INFO] Settings: mode=Run; command=whoami
[INFO] RUNNING the checks passed. Output follows.
nt authority\system
[INFO] RAN the command returned exit code 0.
[INFO] Summary (Run): ran=1; failed=0
[INFO] ===== Finished with exit code 0 =====
```

### Example log: Run, failed (Linux)

```text
===== runcommand 2.0.0 started on ENDPOINT-02 =====
Settings: mode=Run; command=ls /nonexistent_xyz_123
RUNNING the checks passed. Output follows.
ls: cannot access '/nonexistent_xyz_123': No such file or directory
ERROR: FAILED the command returned exit code 2.
Summary (Run): ran=1; failed=1; command exit code=2
===== Finished with exit code 1 =====
```

---

## Troubleshooting

| Log message | Cause | Action |
|---|---|---|
| `BLOCKED command deletes '<path>', a protected OS path.` | The command deletes a path on the protected list. | Check the path. If the target is correct, use a dedicated package for that cleanup. |
| `BLOCKED ... a path built from a variable ...` | The delete path is built from a variable, so the script cannot check it. | Deploy again with the full path typed in the command. |
| `BLOCKED command targets a protected security agent ...` | The command stops, disables, uninstalls, or deletes CrowdStrike, Tanium, or CyberArk. | Use the vendor's own process for that agent. |
| `BLOCKED command shuts down, powers off, or hibernates the endpoint. ...` | The command would turn the endpoint off. Tanium cannot start it again. | Deploy again with a restart command. The log line names one. |
| `WRONG INPUT Mode must be Audit or Run. Got: <value>. Nothing ran.` | The Mode value is not on the list. | Edit the package. Make sure that the Mode values are `Audit` and `Run`. |
| `WRONG INPUT the command is empty. Nothing ran.` | The Command box was empty. | Deploy again with a command. |
| `WRONG INPUT input did not parse cleanly as PowerShell (...)` | Windows only. The command is not valid PowerShell. For example, it uses cmd syntax with `&`. | Deploy again with the command corrected. For cmd syntax, start the command with `cmd /c` and put the rest in double quotes. |
| `WRONG INPUT the script received 3 values instead of 2. ...` | The package command line is wrong, so the command was split. | Edit the package. Make sure that the command line ends with `"$1" "$2"`. |
| `TRUNCATED the action log shows the first 60 of 200 output lines. ...` | The command printed more than 60 lines. | Deploy again with a command that prints less, or that filters its output. |
| `FAILED the command stopped with an error: <message>` | Windows only. A PowerShell error stopped the command. The package stops at the first error. | Read the message. Correct the command and deploy again. |
| No `Finished with exit code` line | The command ran longer than the command timeout, and Tanium stopped it. | Increase the command timeout. Then deploy again. |

## Things to know

- **Parameters arrive URL-encoded.** Tanium encodes each character that is not a letter or a digit. For example, a space arrives as `%20` and `-` arrives as `%2d`. The script decodes the command before it checks it.
- **The command goes into the action log as typed.** A password or token in the command is also in the action log, in Action History, and in the log file.
- **The checks are a list of known patterns.** They stop common high-damage mistakes. They do not stop every way to damage an endpoint, and they do not protect business data outside the protected paths.
- **CrowdStrike's own tamper protection is the real defense for Falcon.** The agent check in this package stops an operator mistake. It is not a guarantee.
- **The Windows script always runs in 64-bit PowerShell.** If the Tanium Client starts the 32-bit PowerShell, the script starts again in the 64-bit one.
- **Windows: output on the error stream of a program is not counted.** It goes to the action log as it is, without the 60-line limit.
- **Linux: the Tanium client does not set `HOME`.** A command that reads `$HOME` gets an empty value. `~` still points to the home folder of the client user, `/root`.
- **macOS runs the command in bash, not zsh.** A command in zsh-only syntax behaves differently.
- **The log file stays on the endpoint.** Tanium removes the action folder after some time. The log file stays until a person or a cleanup deletes it. When the file passes 1 MB, the package keeps one old copy and starts a new file.

---

## Test results

| What was tested | Expected | Result |
|---|---|---|
| Windows, Audit, delete `C:\Users` | `BLOCKED`, exit 0 | Pass |
| Windows, Run, delete `C:\Users` | `BLOCKED`, exit 3 | Pass |
| Windows, Run, delete a folder in a user profile | `RAN`, folder deleted, exit 0 | Pass |
| Windows, Run, `Stop-Service` on the Tanium Client | `BLOCKED`, exit 5, endpoint stays online | Pass |
| Windows, Run, `whoami` | `nt authority\system` | Pass |
| Windows, no Mode selected | Counts as Audit, nothing ran | Pass |
| Windows, special characters `` ` " & \| ^ % ! ' `` | Command reaches the script unchanged | Pass |
| Windows, 200 output lines | 60 lines, `TRUNCATED`, whole log visible in the console | Pass |
| Linux, Audit and Run, delete `/etc` | `BLOCKED`, exit 0 and exit 3 | Pass |
| Linux, Audit, delete `/opt/Tanium` | `BLOCKED` as a security agent | Pass |
| Linux, Run, delete with a path from a variable | `BLOCKED`, exit 3 | Pass |
| Linux, Run, `systemctl stop taniumclient` | `BLOCKED`, exit 5 | Pass |
| Linux, Run, decode-and-run | `BLOCKED`, exit 6 | Pass |
| Linux, shell characters `$HOME`, `$(...)`, `\` | Reach the script unchanged | Pass |
| Linux, 200 output lines | 60 lines, `TRUNCATED`, all lines in the log file | Pass |
| Linux, Run, a command that fails | `FAILED`, exit 1 | Pass |
| Shutdown and power off blocked, restart allowed | `BLOCKED`, exit 3 | Tested outside Tanium only |
| macOS | Same as Linux | **Not tested** |
| Endpoints with CrowdStrike or CyberArk installed | Agent commands blocked | **Not tested** |

---

## Scripts

The page has two scripts. Select a tab to see each script.

=== "Windows"

    ```powershell
    --8<-- "tanium/packages/run-command/RunCommand.ps1"
    ```

=== "Linux and macOS"

    ```bash
    --8<-- "tanium/packages/run-command/runcommand.sh"
    ```
