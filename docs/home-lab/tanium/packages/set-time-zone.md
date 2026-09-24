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

Two Tanium packages that set the time zone on endpoints to one of the common U.S. time zones, picked from a drop-down list when you deploy the action. The Windows package also has a checkbox that turns automatic time zone on or off.

- **Set Time Zone (Windows)** uses a PowerShell script.
- **Set Time Zone (Linux and macOS)** uses a shell script.

Both packages use the same time zone values and the same exit codes, so the results read the same way on every platform.

Use these packages when endpoints were built or imaged with the wrong time zone, or when devices move to a site in a different time zone.

---

## Parameters

| Parameter | Type | Passed as | Package |
|---|---|---|---|
| Time Zone | Drop-down list | `$1` | Windows, Linux and macOS |
| Automatic Time Zone | Checkbox | `$2` | Windows only |

Tanium assigns `$1` to the first parameter input you add to the package and `$2` to the second. The number is shown next to each input in the **Parameter Inputs** list, for example `$1 - Time Zone`. Add Time Zone first and Automatic Time Zone second, so the numbers match the command line.

The drop-down values must be typed exactly as shown below. The scripts ignore upper and lower case, but the spelling has to match.

### Time Zone ($1)

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

### Automatic Time Zone ($2, Windows only)

Automatic time zone is the Windows **Set time zone automatically** setting (**Settings** > **Time & language** > **Date & time**). When it is on, Windows picks the time zone from the device's location.

| Checkbox | What happens |
|---|---|
| Checked (Tanium sends `1`) | The time zone is set first, then automatic time zone is turned on. Windows can later replace the time zone based on location. |
| Unchecked (Tanium sends `0`) | Automatic time zone is turned off first, then the time zone is set. The time zone stays where you put it. |

There is no "leave it as it is" option. Every run of the Windows package turns automatic time zone either on or off.

Check the box only for devices that move between locations, such as laptops. On a desktop or server, leave it unchecked, so the time zone you set is the one that stays.

The setting is the `Start` value of the `tzautoupdate` service, under `HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate`. `3` means on, `4` means off.

The Linux and macOS package does not change automatic time zone.

---

## What the scripts do

1. Read the parameter values and decode them (Tanium passes parameters URL-encoded).
2. Stop with exit code `2` if the time zone is blank or not in the list.
3. Read the current time zone.
4. **Windows, box unchecked:** turn automatic time zone off.
5. If the time zone already matches, log that and skip the change.
6. Set the new time zone, then read it again to confirm the change. Exit `3` if it does not match.
7. **Windows, box checked:** turn automatic time zone on and log a warning that the time zone can now change based on location.

The order matters on Windows. Turning automatic time zone off before setting the time zone stops Windows from switching it back in between.

Platform-specific behavior:

- **Windows:** the script uses `tzutil.exe`. When the box is checked, it also checks whether location access is denied on the device, and logs a warning if it is, because automatic time zone cannot work without it. It does not change the location setting.
- **Linux:** the script uses `timedatectl`. On systems without it, it points `/etc/localtime` at the correct file under `/usr/share/zoneinfo`. It also updates `/etc/timezone` (Debian and Ubuntu) and `/etc/sysconfig/clock` (older Red Hat systems) when those files exist.
- **macOS:** the script uses `systemsetup -settimezone`. If that command fails, it points `/etc/localtime` at the correct zone file instead.

---

## Exit codes

| Exit code | Meaning |
|---|---|
| `0` | The settings were changed, or they were already correct. |
| `1` | Audit mode only: the endpoint does not match the selected settings. Nothing was changed. |
| `2` | A parameter value was blank or not recognized. |
| `3` | The time zone change failed, or the check after the change did not match. |
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
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Set-USTimeZone.ps1 "$1" "$2"
      ```
    - **Command Timeout:** `5` minutes. The script normally finishes in a few seconds.
5. Under **Files**, click **Add**, choose **Local File**, and upload `Set-USTimeZone.ps1`.
6. Expand **Parameters**. Under **Parameter Inputs**, add a **Drop-Down List** parameter. It shows in the list as `$1`.
    - **Label:** `Time Zone`
    - **Provide Help Text** (optional): select it and enter `Time zone to set on the endpoint.`
    - **Values:** add one entry for each value, in this order:
      `Eastern`, `Central`, `Mountain`, `Arizona`, `Pacific`, `Alaska`, `Hawaii`, `PuertoRico`
7. Add a **Checkbox** parameter. It shows in the list as `$2`.
    - **Label:** `Automatic Time Zone`
    - **Provide Help Text:** select it and enter `Checked turns automatic time zone on. Unchecked turns it off.`
    - **Selected:** leave this cleared. **Selected** makes the box checked by default, which would turn automatic time zone on unless the operator remembers to clear it.
8. In the **Preview** panel on the right, confirm you see the **Time Zone** drop-down followed by the **Automatic Time Zone** checkbox.
9. Click **Save**.

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
6. Expand **Parameters**. Under **Parameter Inputs**, add the same **Drop-Down List** parameter as the Windows package, with the same label and the same eight values. It shows in the list as `$1`. This package has no checkbox.
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
6. Windows package only: check **Automatic Time Zone** to turn it on, or leave it unchecked to turn it off.
7. Under the schedule, leave it as a one-time action.
8. Click **Show preview to continue**, review the targets, then click **Deploy Action**.

Deploy the Windows package only to Windows computers, and the Linux and macOS package only to non-Windows computers. The filters in step 1 take care of that.

---

## View the results

### One endpoint

1. Open the action from **Administration** > **Actions** > **Action History**.
2. Select an endpoint that shows **Completed**.
3. Open its action log. The script output appears between the `Command Line` line and the `Completed` line.

Time zone changed, automatic time zone turned off:

```
2026-09-23 11:45:20 Host: web-01 | Zone: Pacific Standard Time -> Eastern Standard Time | Automatic time zone: Enabled -> Disabled
2026-09-23 11:45:20 Automatic time zone disabled (tzautoupdate Start=4).
2026-09-23 11:45:20 Zone changed from 'Pacific Standard Time' to 'Eastern Standard Time'.
2026-09-23 11:45:20 SUCCESS
```

Already correct:

```
2026-09-23 11:45:20 Host: web-02 | Zone: Eastern Standard Time -> Eastern Standard Time | Automatic time zone: Disabled -> Disabled
2026-09-23 11:45:20 Automatic time zone already disabled.
2026-09-23 11:45:20 Zone already set to target. No zone change made.
2026-09-23 11:45:20 SUCCESS
```

Automatic time zone turned on:

```
2026-09-23 11:45:20 Host: laptop-07 | Zone: Central Standard Time -> Eastern Standard Time | Automatic time zone: Disabled -> Enabled
2026-09-23 11:45:20 Zone changed from 'Central Standard Time' to 'Eastern Standard Time'.
2026-09-23 11:45:20 Automatic time zone enabled (tzautoupdate Start=3).
2026-09-23 11:45:20 WARNING: With automatic time zone on, Windows can replace this zone based on location.
2026-09-23 11:45:20 SUCCESS
```

### Many endpoints

Ask a question with the built-in **Tanium Action Log** sensor, using the action ID from the top of the log:

```
Get Tanium Action Log[12345] from all machines
```

---

## Audit mode (optional)

Both scripts can check the settings without changing anything. This is useful before a large rollout, to see how many endpoints are actually wrong.

To build an audit version, create a copy of each package with a different name (for example `Set Time Zone (Windows) - Audit Only`) and change only the command:

Windows:
```
cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Set-USTimeZone.ps1 "$1" "$2" -WhatIfOnly
```

Linux and macOS:
```
/bin/bash set-us-timezone.sh "$1" --whatif
```

In audit mode, each endpoint logs `COMPLIANT` (exit code `0`) or `NOT COMPLIANT` (exit code `1`). On Windows, the log also shows which part does not match:

```
2026-09-23 11:45:20 NOT COMPLIANT (zone ok: True, automatic time zone ok: False)
```

In Action History, an exit code of `1` can show as **Failed**. That is expected in audit mode: it means the endpoint does not match the selected settings.

---

## Things to know

- **Parameters arrive URL-encoded.** Both scripts decode the values and strip extra quotes and spaces before matching them.
- **Checking the box can undo the time zone you set.** Once automatic time zone is on and the device can find its location, Windows picks the time zone itself. That is the point of the setting, but it means the `$1` value is only a starting point.
- **Checkbox values.** Tanium sends `1` for checked and `0` for unchecked. The script also accepts `true`/`false`, `yes`/`no`, `on`/`off`, and blank (treated as unchecked), in case the command is run by hand. Any other value stops the script with exit code `2`.
- **Automatic time zone needs location access.** On Windows, if location access is denied on the device, automatic time zone has nothing to work with. The script logs a warning but does not change the location setting, since that is a privacy setting.
- **Running programs may keep the old time zone.** The clock changes right away, but some services and applications that were already running keep logging in the old time zone until they restart. Plan a reboot in the next maintenance window if log timestamps matter.
- **Group Policy or configuration management can undo the change.** If a GPO, Intune profile, or a tool like Ansible also sets the time zone or automatic time zone, the endpoint will switch back the next time that policy applies. Fix the policy first.
- **macOS privacy controls.** On newer macOS versions, `systemsetup` can be blocked. The script falls back to updating `/etc/localtime` directly, and the log shows which method was used.
- **Automatic time zone is not the same as time sync.** Automatic time zone picks the zone. Time sync (NTP) keeps the clock accurate. These packages do not change time sync.

---

## Windows script

```powershell
<#
.SYNOPSIS
    Sets the Windows time zone to a common U.S. zone and controls automatic time zone.
    Built for a Tanium action package.

.DESCRIPTION
    Takes a short zone key from a Tanium drop-down parameter ($1), maps it to the Windows
    time zone ID, applies it with tzutil.exe, and verifies the result.

    The second parameter ($2) comes from a Tanium checkbox and turns "Set time zone
    automatically" on (checked) or off (unchecked). The setting is the Start value of the
    tzautoupdate service: 3 = enabled, 4 = disabled.

    Valid zone keys ($1):
        Eastern, Central, Mountain, Arizona, Pacific, Alaska, Hawaii, PuertoRico

    Automatic time zone ($2):
        Checked    (1, true, yes, on, enable)  Set the zone, then turn automatic time zone
                   on. Windows may later replace the zone based on location.
        Unchecked  (0, false, no, off, disable, or blank)  Turn automatic time zone off,
                   then set the zone.

.PARAMETER Zone
    One of the zone keys above. Case-insensitive. Passed by position ($1).

.PARAMETER AutoTimeZone
    Checkbox value. Checked = on, unchecked or blank = off. Passed by position ($2).

.PARAMETER WhatIfOnly
    Report current and target settings, change nothing. Exit 0 if compliant, 1 if not.

.NOTES
    Tanium command line:
        cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Set-USTimeZone.ps1 "$1" "$2"

    Exit codes:
        0  Success, or already compliant
        1  WhatIfOnly: not compliant
        2  Invalid or missing parameter
        3  tzutil failed or verification did not match
        4  Unexpected error
#>
[CmdletBinding()]
param(
    [string]$Zone,
    [string]$AutoTimeZone,
    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message)
    Write-Output ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

# Tanium can URL-encode parameter values. Decode and normalize before matching.
function ConvertTo-Key {
    param([string]$Value)
    if (-not $Value) { return '' }
    return ([uri]::UnescapeDataString($Value).Trim().Trim('"', "'").ToLower() -replace '\s', '')
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

$TzAutoKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate'

function Get-AutoTimeZoneState {
    if (-not (Test-Path $TzAutoKey)) { return 'NotAvailable' }
    $start = (Get-ItemProperty -Path $TzAutoKey -Name Start -ErrorAction SilentlyContinue).Start
    if ($null -eq $start) { return 'NotAvailable' }
    if ($start -eq 4) { return 'Disabled' }
    return 'Enabled'
}

function Set-AutoTimeZoneState {
    param([ValidateSet('Enabled', 'Disabled')][string]$State)
    $value = if ($State -eq 'Enabled') { 3 } else { 4 }
    Set-ItemProperty -Path $TzAutoKey -Name Start -Value $value -Type DWord
}

try {
    # ---- Validate input ----
    $zoneKey = ConvertTo-Key $Zone
    if (-not $zoneKey -or -not $ZoneMap.ContainsKey($zoneKey)) {
        Write-Log "ERROR: Invalid or missing zone '$Zone'. Valid: $((($ZoneMap.Keys | Sort-Object) -join ', '))"
        exit 2
    }

    # Checkbox: accept the common ways a checked or unchecked box can arrive.
    $autoKey = ConvertTo-Key $AutoTimeZone
    if ($autoKey -in @('1', 'true', 'yes', 'on', 'checked', 'enable', 'enabled')) {
        $autoKey = 'enable'
    } elseif ($autoKey -in @('', '0', 'false', 'no', 'off', 'unchecked', 'disable', 'disabled')) {
        $autoKey = 'disable'
    } else {
        Write-Log "ERROR: Invalid automatic time zone value '$AutoTimeZone'. Expected a checkbox value such as 1/0 or true/false."
        exit 2
    }

    $targetId   = $ZoneMap[$zoneKey]
    $targetAuto = if ($autoKey -eq 'enable') { 'Enabled' } else { 'Disabled' }

    # Tanium client may run 32-bit on 64-bit Windows. Use Sysnative so we hit the real tzutil.
    $tzutil = Join-Path $env:WINDIR 'Sysnative\tzutil.exe'
    if (-not (Test-Path $tzutil)) { $tzutil = Join-Path $env:WINDIR 'System32\tzutil.exe' }

    $currentId   = (& $tzutil /g).Trim()
    $currentAuto = Get-AutoTimeZoneState
    Write-Log "Host: $env:COMPUTERNAME | Zone: $currentId -> $targetId | Automatic time zone: $currentAuto -> $targetAuto"

    # ---- Audit mode ----
    if ($WhatIfOnly) {
        $zoneOk = ($currentId -eq $targetId)
        $autoOk = ($currentAuto -eq 'NotAvailable') -or ($currentAuto -eq $targetAuto)
        if ($zoneOk -and $autoOk) { Write-Log 'COMPLIANT'; exit 0 }
        Write-Log ("NOT COMPLIANT (zone ok: {0}, automatic time zone ok: {1})" -f $zoneOk, $autoOk)
        exit 1
    }

    # ---- Disable automatic time zone BEFORE setting the zone, so it cannot flip it back ----
    if ($targetAuto -eq 'Disabled') {
        if ($currentAuto -eq 'NotAvailable') {
            Write-Log 'Automatic time zone is not available on this system. Skipped.'
        } elseif ($currentAuto -eq 'Disabled') {
            Write-Log 'Automatic time zone already disabled.'
        } else {
            Set-AutoTimeZoneState -State Disabled
            Write-Log 'Automatic time zone disabled (tzautoupdate Start=4).'
        }
    }

    # ---- Set the zone ----
    if ($currentId -eq $targetId) {
        Write-Log 'Zone already set to target. No zone change made.'
    } else {
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
        Write-Log "Zone changed from '$currentId' to '$newId'."
    }

    # ---- Enable automatic time zone AFTER setting the zone ----
    if ($targetAuto -eq 'Enabled') {
        if ($currentAuto -eq 'NotAvailable') {
            Write-Log 'Automatic time zone is not available on this system. Skipped.'
        } else {
            if ($currentAuto -eq 'Enabled') {
                Write-Log 'Automatic time zone already enabled.'
            } else {
                Set-AutoTimeZoneState -State Enabled
                Write-Log 'Automatic time zone enabled (tzautoupdate Start=3).'
            }
            Write-Log 'WARNING: With automatic time zone on, Windows can replace this zone based on location.'

            # Automatic time zone needs location access. Report it, but do not change a privacy setting.
            $locKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
            $loc = (Get-ItemProperty -Path $locKey -Name Value -ErrorAction SilentlyContinue).Value
            if ($loc -eq 'Deny') {
                Write-Log 'WARNING: Location access is denied on this device, so automatic time zone will not detect a location.'
            }
        }
    }

    Write-Log 'SUCCESS'
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
# Built for a Tanium action package.
# POSIX sh (runs under /bin/sh or /bin/bash, including macOS bash 3.2).
#
# Usage:
#   set-us-timezone.sh <Zone> [--whatif]
#
# Zone ($1):
#   Eastern, Central, Mountain, Arizona, Pacific, Alaska, Hawaii, PuertoRico
#
# Automatic time zone is not changed by this script.
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

WHATIF=0
for a in "$@"; do [ "$a" = "--whatif" ] && WHATIF=1; done

RAW="$1"

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
