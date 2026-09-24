---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Linux
  - macOS
  - Endpoint Management
---

# Set Time Zone (Package)

Two Tanium packages that set the time zone on endpoints to one of the common U.S. time zones, picked from a drop-down list when you deploy the action.

- **Set Time Zone (Windows)** uses a PowerShell script.
- **Set Time Zone (Linux and macOS)** uses a shell script.

Both packages use the same drop-down values and the same exit codes, so the results read the same way on every platform.

Use these packages when endpoints were built or imaged with the wrong time zone, or when devices move to a site in a different time zone.

---

## Time zones in the drop-down

| Drop-down value | Windows time zone | Linux / macOS time zone | Daylight saving time |
|---|---|---|---|
| `Eastern` | Eastern Standard Time | America/New_York | Yes |
| `Central` | Central Standard Time | America/Chicago | Yes |
| `Mountain` | Mountain Standard Time | America/Denver | Yes |
| `Arizona` | US Mountain Standard Time | America/Phoenix | No |
| `Pacific` | Pacific Standard Time | America/Los_Angeles | Yes |
| `Alaska` | Alaskan Standard Time | America/Anchorage | Yes |
| `Hawaii` | Hawaiian Standard Time | Pacific/Honolulu | No |
| `PuertoRico` | SA Western Standard Time | America/Puerto_Rico | No |

`Arizona` and `Mountain` are separate on purpose. Most of Arizona stays on Mountain Standard Time all year, so a device in Phoenix set to `Mountain` will be one hour off for half the year.

The drop-down values must be typed exactly as shown in the first column. The scripts ignore upper and lower case, but the spelling has to match.

---

## What the scripts do

1. Read the drop-down value and decode it (Tanium passes parameters URL-encoded).
2. Stop with exit code `2` if the value is blank or not in the list above.
3. Read the current time zone.
4. If it already matches, log that and exit `0` without changing anything.
5. Set the new time zone.
6. Read the time zone again to confirm the change, and exit `3` if it does not match.

Platform-specific behavior:

- **Windows:** the script uses `tzutil.exe`. If **Set time zone automatically** is turned on, Windows can switch the time zone back based on location. The script turns that setting off by setting the `Start` value of the `tzautoupdate` service to `4` (disabled) under `HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate`, and logs that it did so.
- **Linux:** the script uses `timedatectl`. On systems without it, it points `/etc/localtime` at the correct file under `/usr/share/zoneinfo`. It also updates `/etc/timezone` (Debian and Ubuntu) and `/etc/sysconfig/clock` (older Red Hat systems) when those files exist.
- **macOS:** the script uses `systemsetup -settimezone`. If that command fails, it points `/etc/localtime` at the correct zone file instead.

---

## Exit codes

| Exit code | Meaning |
|---|---|
| `0` | The time zone was changed, or it was already correct. |
| `1` | Audit mode only: the endpoint is not in the selected time zone. Nothing was changed. |
| `2` | The drop-down value was blank or not recognized. |
| `3` | The change failed, or the check after the change did not match. |
| `4` | Windows: unexpected error. Linux / macOS: unsupported operating system, or the time zone file is missing (the `tzdata` package is not installed). |

---

## Requirements

- **Windows:** PowerShell 5.1.
- **Linux:** `/bin/bash` and the `tzdata` package (installed by default on most distributions).
- **macOS:** no extra requirements.
- A Tanium account with permission to create packages in a content set and deploy actions to the target computers.

---

## Create the Windows package

Menu labels can differ slightly between Tanium versions.

1. Save the Windows script at the bottom of this page as `Set-USTimeZone.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package**.
4. Fill in the fields:
    - **Package Display Name:** `Set Time Zone (Windows)` (add your team's prefix if you use one).
    - **Content Set:** the content set your team uses for custom content.
    - **Command:**
      ```
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Set-USTimeZone.ps1 "$1"
      ```
    - **Command Timeout:** `5` minutes. The script normally finishes in a few seconds.
5. Under **Files**, click **Add**, choose **Local File**, and upload `Set-USTimeZone.ps1`.
6. Under **Parameter Inputs**, click **Add** and choose **Drop Down List**:
    - **Label:** `Time Zone`
    - **Values:** add one entry for each value, in this order:
      `Eastern`, `Central`, `Mountain`, `Arizona`, `Pacific`, `Alaska`, `Hawaii`, `PuertoRico`
7. Click **Save**.

## Create the Linux and macOS package

1. Save the shell script at the bottom of this page as `set-us-timezone.sh`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package**.
4. Fill in the fields:
    - **Package Display Name:** `Set Time Zone (Linux and macOS)`
    - **Content Set:** the same content set as the Windows package.
    - **Command:**
      ```
      /bin/bash set-us-timezone.sh "$1"
      ```
    - **Command Timeout:** `5` minutes.
5. Under **Files**, click **Add**, choose **Local File**, and upload `set-us-timezone.sh`.
6. Under **Parameter Inputs**, add the same **Drop Down List** as the Windows package, with the same label and the same eight values.
7. Click **Save**.

The command calls the script with `/bin/bash` directly, so the script does not need to be marked executable after Tanium downloads it.

---

## Deploy the package

1. In **Interact**, ask a question that returns the computers you want to change. Examples:

    Windows computers whose name starts with `nyc-`:
    ```
    Get Computer Name from all machines with ( Is Windows equals True and Computer Name starts with "nyc-" )
    ```

    Linux and macOS computers whose name starts with `nyc-`:
    ```
    Get Computer Name from all machines with ( Is Windows equals False and Computer Name starts with "nyc-" )
    ```

2. Select the computers in the results grid.
3. Click **Deploy Action**.
4. In **Deployment Package**, search for and select the package that matches the platform: `Set Time Zone (Windows)` or `Set Time Zone (Linux and macOS)`.
5. In **Time Zone**, pick the time zone from the drop-down list.
6. Under the schedule, leave it as a one-time action.
7. Click **Show preview to continue**, review the targets, then click **Deploy Action**.

Deploy the Windows package only to Windows computers, and the Linux and macOS package only to non-Windows computers. The filters in step 1 take care of that.

---

## View the results

### One endpoint

1. Open the action from **Administration** > **Actions** > **Action History**.
2. Select an endpoint that shows **Completed**.
3. Open its action log. The script output appears between the `Command Line` line and the `Completed` line:

```
2026-09-23 11:45:20 Host: web-01 | Current: Pacific Standard Time | Target: Eastern Standard Time
2026-09-23 11:45:20 Automatic time zone was enabled (Start=3). Disabled it (Start=4).
2026-09-23 11:45:20 SUCCESS: Time zone changed from 'Pacific Standard Time' to 'Eastern Standard Time'.
```

An endpoint that was already correct shows:

```
2026-09-23 11:45:20 Host: web-02 | Current: Eastern Standard Time | Target: Eastern Standard Time
2026-09-23 11:45:20 Already set to target zone. No change made.
```

### Many endpoints

Ask a question with the built-in **Tanium Action Log** sensor, using the action ID from the top of the log:

```
Get Tanium Action Log[12345] from all machines
```

---

## Audit mode (optional)

Both scripts can check the time zone without changing it. This is useful before a large rollout, to see how many endpoints are actually wrong.

To build an audit version, create a copy of each package with a different name (for example `Set Time Zone (Windows) - Audit Only`) and change only the command:

Windows:
```
cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Set-USTimeZone.ps1 "$1" -WhatIfOnly
```

Linux and macOS:
```
/bin/bash set-us-timezone.sh "$1" --whatif
```

In audit mode, each endpoint logs `COMPLIANT` (exit code `0`) or `NOT COMPLIANT` (exit code `1`). In Action History, an exit code of `1` can show as **Failed**. That is expected in audit mode: it means the endpoint is not in the selected time zone.

---

## Things to know

- **Parameters arrive URL-encoded.** Both scripts decode the value and strip extra quotes and spaces before matching it.
- **Automatic time zone gets turned off on Windows.** If a laptop user travels and expects the clock to follow them, that stops after this package runs. Remove that block from the script if you want to keep automatic time zone on.
- **Running programs may keep the old time zone.** The clock changes right away, but some services and applications that were already running keep logging in the old time zone until they restart. Plan a reboot in the next maintenance window if log timestamps matter.
- **Group Policy or configuration management can undo the change.** If a GPO, Intune profile, or a tool like Ansible also sets the time zone, the endpoint will switch back the next time that policy applies. Fix the policy first.
- **macOS privacy controls.** On newer macOS versions, `systemsetup` can be blocked. The script falls back to updating `/etc/localtime` directly, and the log shows which method was used.

---

## Windows script

```powershell
<#
.SYNOPSIS
    Sets the Windows time zone to a common U.S. zone. Built for a Tanium action package.

.DESCRIPTION
    Takes a short zone key from a Tanium drop-down parameter, maps it to the Windows
    time zone ID, applies it with tzutil.exe, and verifies the result.

    If "Set time zone automatically" is on (tzautoupdate service enabled), Windows can
    move the clock back to a location-based zone. The script disables that service so
    the change sticks, and logs that it did so.

    Valid keys (use these exact values in the Tanium drop-down):
        Eastern, Central, Mountain, Arizona, Pacific, Alaska, Hawaii, PuertoRico

.PARAMETER Zone
    One of the keys above. Case-insensitive. Passed by position ($1), so the
    Tanium command does not need to name it.

.PARAMETER WhatIfOnly
    Report current and target zone, change nothing. Exit 0 if already compliant, 1 if not.

.NOTES
    Tanium command line:
        cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Set-USTimeZone.ps1 "$1"

    Exit codes:
        0  Success, or already set to the target zone
        1  WhatIfOnly: not compliant
        2  Invalid or missing Zone parameter
        3  tzutil failed or verification did not match
        4  Unexpected error
#>
[CmdletBinding()]
param(
    [string]$Zone,
    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message)
    Write-Output ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

$ZoneMap = @{
    'eastern'    = 'Eastern Standard Time'       # America/New_York
    'central'    = 'Central Standard Time'       # America/Chicago
    'mountain'   = 'Mountain Standard Time'      # America/Denver
    'arizona'    = 'US Mountain Standard Time'   # America/Phoenix (no DST)
    'pacific'    = 'Pacific Standard Time'       # America/Los_Angeles
    'alaska'     = 'Alaskan Standard Time'       # America/Anchorage
    'hawaii'     = 'Hawaiian Standard Time'      # Pacific/Honolulu (no DST)
    'puertorico' = 'SA Western Standard Time'    # America/Puerto_Rico (AST, no DST)
}

try {
    # Tanium can URL-encode parameter values. Decode and normalize before matching.
    $key = ''
    if ($Zone) { $key = [uri]::UnescapeDataString($Zone).Trim().Trim('"', "'").ToLower() -replace '\s', '' }

    if (-not $key -or -not $ZoneMap.ContainsKey($key)) {
        Write-Log "ERROR: Invalid or missing zone '$Zone'. Valid: $((($ZoneMap.Keys | Sort-Object) -join ', '))"
        exit 2
    }

    $targetId = $ZoneMap[$key]

    # Tanium client may run 32-bit on 64-bit Windows. Use Sysnative so we hit the real tzutil.
    $tzutil = Join-Path $env:WINDIR 'Sysnative\tzutil.exe'
    if (-not (Test-Path $tzutil)) { $tzutil = Join-Path $env:WINDIR 'System32\tzutil.exe' }

    $currentId = (& $tzutil /g).Trim()
    Write-Log "Host: $env:COMPUTERNAME | Current: $currentId | Target: $targetId"

    if ($WhatIfOnly) {
        if ($currentId -eq $targetId) { Write-Log 'COMPLIANT'; exit 0 }
        Write-Log 'NOT COMPLIANT'
        exit 1
    }

    # Automatic time zone (tzautoupdate) can revert the change. Start=4 means disabled.
    $tzAutoKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate'
    if (Test-Path $tzAutoKey) {
        $start = (Get-ItemProperty -Path $tzAutoKey -Name Start -ErrorAction SilentlyContinue).Start
        if ($null -ne $start -and $start -ne 4) {
            Set-ItemProperty -Path $tzAutoKey -Name Start -Value 4 -Type DWord
            Write-Log "Automatic time zone was enabled (Start=$start). Disabled it (Start=4)."
        }
    }

    if ($currentId -eq $targetId) {
        Write-Log 'Already set to target zone. No change made.'
        exit 0
    }

    $out = & $tzutil /s "$targetId" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "ERROR: tzutil /s failed with exit code $LASTEXITCODE. Output: $out"
        exit 3
    }

    $newId = (& $tzutil /g).Trim()
    if ($newId -ne $targetId) {
        Write-Log "ERROR: Verification failed. Expected '$targetId', got '$newId'."
        exit 3
    }

    Write-Log "SUCCESS: Time zone changed from '$currentId' to '$newId'."
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 4
}
```

---

## Linux and macOS script

```sh
#!/bin/sh
# ---------------------------------------------------------------------------
# set-us-timezone.sh
# Sets the time zone on Linux and macOS to a common U.S. zone.
# Built for a Tanium action package. POSIX sh (works with macOS /bin/sh too).
#
# Usage:
#   set-us-timezone.sh <Zone> [--whatif]
#
# Valid keys (use these exact values in the Tanium drop-down):
#   Eastern, Central, Mountain, Arizona, Pacific, Alaska, Hawaii, PuertoRico
#
# Tanium command line:
#   /bin/bash set-us-timezone.sh "$1"
#
# Exit codes:
#   0  Success, or already set to the target zone
#   1  --whatif: not compliant
#   2  Invalid or missing Zone parameter
#   3  Change failed or verification did not match
#   4  Unsupported OS or zoneinfo file missing
# ---------------------------------------------------------------------------

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

RAW="$1"
WHATIF=0
[ "$2" = "--whatif" ] && WHATIF=1

# Normalize: strip quotes, whitespace, and URL-encoded spaces; lowercase.
KEY=$(printf '%s' "$RAW" | sed -e 's/%20//g' -e 's/["'\'' ]//g' | tr '[:upper:]' '[:lower:]')

case "$KEY" in
    eastern)    TZ_TARGET="America/New_York" ;;
    central)    TZ_TARGET="America/Chicago" ;;
    mountain)   TZ_TARGET="America/Denver" ;;
    arizona)    TZ_TARGET="America/Phoenix" ;;
    pacific)    TZ_TARGET="America/Los_Angeles" ;;
    alaska)     TZ_TARGET="America/Anchorage" ;;
    hawaii)     TZ_TARGET="Pacific/Honolulu" ;;
    puertorico) TZ_TARGET="America/Puerto_Rico" ;;
    *)
        log "ERROR: Invalid or missing zone '$RAW'. Valid: Eastern, Central, Mountain, Arizona, Pacific, Alaska, Hawaii, PuertoRico"
        exit 2
        ;;
esac

OS=$(uname -s)
HOST=$(hostname)

# Resolve the zoneinfo directory (macOS points /usr/share/zoneinfo at /var/db/timezone/zoneinfo).
ZONEDIR=/usr/share/zoneinfo
if [ ! -f "$ZONEDIR/$TZ_TARGET" ]; then
    log "ERROR: $ZONEDIR/$TZ_TARGET not found. tzdata may be missing on this host."
    exit 4
fi

get_current() {
    CUR=""
    if [ "$OS" = "Linux" ] && command -v timedatectl >/dev/null 2>&1; then
        CUR=$(timedatectl show -p Timezone --value 2>/dev/null)
    fi
    if [ -z "$CUR" ] && [ -L /etc/localtime ]; then
        CUR=$(readlink /etc/localtime | sed -e 's#.*/zoneinfo/##')
    fi
    if [ -z "$CUR" ] && [ -f /etc/timezone ]; then
        CUR=$(cat /etc/timezone)
    fi
    [ -z "$CUR" ] && CUR="unknown"
    printf '%s' "$CUR"
}

CURRENT=$(get_current)
log "Host: $HOST | OS: $OS | Current: $CURRENT | Target: $TZ_TARGET"

if [ "$WHATIF" -eq 1 ]; then
    if [ "$CURRENT" = "$TZ_TARGET" ]; then log "COMPLIANT"; exit 0; fi
    log "NOT COMPLIANT"
    exit 1
fi

if [ "$CURRENT" = "$TZ_TARGET" ]; then
    log "Already set to target zone. No change made."
    exit 0
fi

case "$OS" in
    Linux)
        if command -v timedatectl >/dev/null 2>&1 && timedatectl set-timezone "$TZ_TARGET" 2>/dev/null; then
            log "Applied with timedatectl."
        else
            # No systemd, or timedatectl failed (container, old distro). Fall back to the symlink.
            ln -sf "$ZONEDIR/$TZ_TARGET" /etc/localtime || { log "ERROR: Could not update /etc/localtime"; exit 3; }
            log "Applied by relinking /etc/localtime."
        fi
        # Keep distro-specific files in sync so other tools agree.
        [ -f /etc/timezone ] && printf '%s\n' "$TZ_TARGET" > /etc/timezone
        if [ -f /etc/sysconfig/clock ]; then
            sed -i "s#^ZONE=.*#ZONE=\"$TZ_TARGET\"#" /etc/sysconfig/clock
        fi
        ;;
    Darwin)
        # systemsetup can fail under recent macOS privacy controls. Fall back to the symlink.
        if /usr/sbin/systemsetup -settimezone "$TZ_TARGET" >/dev/null 2>&1; then
            log "Applied with systemsetup."
        else
            ln -sf "$ZONEDIR/$TZ_TARGET" /etc/localtime || { log "ERROR: Could not update /etc/localtime"; exit 3; }
            log "systemsetup failed. Applied by relinking /etc/localtime."
        fi
        ;;
    *)
        log "ERROR: Unsupported OS '$OS'."
        exit 4
        ;;
esac

NEW=$(get_current)
if [ "$NEW" != "$TZ_TARGET" ]; then
    log "ERROR: Verification failed. Expected '$TZ_TARGET', got '$NEW'."
    exit 3
fi

log "SUCCESS: Time zone changed from '$CURRENT' to '$NEW'."
exit 0
```
