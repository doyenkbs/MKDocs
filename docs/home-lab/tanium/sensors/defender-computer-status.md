---
tags:
  - Tanium
  - Sensors
  - Microsoft Defender
  - PowerShell
---

# Defender - Computer Status (Sensor)

This page shows how to create the **Defender - Computer Status** sensor by hand in the Tanium Console.

**What it returns:** one row per Windows endpoint with Defender's running mode (Normal, Passive, EDR Block Mode), whether the antivirus and real-time protection are on, tamper protection, the platform version, and how old the signatures are.

It is built from `Get-MpComputerStatus`. Running that cmdlet raw through a sensor returns 40+ properties as separate lines, which can't be sorted or filtered. This sensor picks the useful ones and returns them as columns.

!!! note "Use it with the built-in sensor"
    `Get-MpComputerStatus` only answers when the `WinDefend` service is running. On machines where Defender is stopped (common when another antivirus is installed), this sensor returns `Error: Service not running`. For versions on those machines, use the built-in **Microsoft Defender AntiMalware Details** sensor, which reads them even when the service is stopped. See [Defender Vulnerability Remediation](../remediation/defender-vulnerabilities.md) for how the two are used together.

!!! note "Test status"
    Tested on Windows 11 Pro with Windows PowerShell 5.1, run from a PowerShell prompt as the signed-in user. It has not yet been run through Tanium as SYSTEM.

---

## Before you start

- You need a role that can create sensors in the content set you plan to use.
- If a sensor named **Defender - Computer Status** already exists, edit it instead of creating a second one. Sensor names must be unique.
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
| Name | `Defender - Computer Status` |
| Description | Returns Microsoft Defender running mode, antivirus and real-time protection state, tamper protection, platform version, and signature version and age. Returns Not Applicable when Defender is not installed and Error: Service not running when the WinDefend service is stopped. |
| Content Set | Your own custom content set (for example the one you use for lab or custom sensors) |

### Step 3: Settings section

| Field | Value |
|---|---|
| Category | Miscellaneous (or any category you use for custom sensors) |
| Result Type | Text |
| Max Sensor Age | `1` and set the unit dropdown to **Hours**. Signatures update a few times a day, so an hour is fresh enough |
| Max String Age | Leave **Enable** unchecked |
| Max Strings | Leave **Enable** unchecked |
| Ignore case in result values | Checked |
| Hide this sensor from sensor lists and parse results | Unchecked |
| Split into multiple columns | Checked |

### Step 4: Column settings

After you check **Split into multiple columns**:

1. Set **Delimiter** to `|` (the pipe character, Shift + Backslash on a US keyboard).
2. Add these 9 columns in this order. The order must match, because the script returns the values in this order.

| Index | Column Name | Value Type | Ignore case | Hidden |
|---|---|---|---|---|
| 0 | Running Mode | Text | Checked | Unchecked |
| 1 | Service Enabled | Text | Checked | Unchecked |
| 2 | AV Enabled | Text | Checked | Unchecked |
| 3 | Real-Time Protection | Text | Checked | Unchecked |
| 4 | Tamper Protected | Text | Checked | Unchecked |
| 5 | Platform Version | Version | Checked | Unchecked |
| 6 | Signature Version | Version | Checked | Unchecked |
| 7 | Signature Last Updated | Text | Checked | Unchecked |
| 8 | Signature Age (Days) | Integer | Checked | Unchecked |

The console does not have a **String** type. Use **Text**.

### Step 5: Parameters section

Leave it empty. This sensor has no parameters.

### Step 6: Scripts section

For each platform in the table: click the platform tab on the left, check **Enable sensor for [platform] platform**, set **Query Type** in the top right, click inside the script editor, press **Ctrl + A**, press **Delete**, then paste the script for that platform.

| Platform | Enable | Query Type | Script |
|---|---|---|---|
| Windows | Checked | PowerShell | Windows script below |
| Linux | Checked | UnixShell | Stub below, returns Not Applicable |
| Mac | Checked | UnixShell | Stub below, returns Not Applicable |

=== "Windows (PowerShell)"

    ```powershell
    --8<-- "tanium/sensors/defender-computer-status/windows.ps1"
    ```

=== "Linux (UnixShell)"

    ```sh
    #!/bin/sh
    echo "Not Applicable"
    ```

=== "Mac (UnixShell)"

    ```sh
    #!/bin/sh
    echo "Not Applicable"
    ```

### Step 7: Save

1. Scroll to the bottom of the page and click **Save**.
2. If the console reports that the name already exists, cancel and edit the existing sensor.

### Step 8: Test on a few machines first

1. Go to **Interact**.
2. In the question bar, enter `Get Computer Name and Defender - Computer Status from all machines with Computer Name contains "<hostname>"`, replacing `<hostname>` with a Windows machine where Defender is running.
3. Check the results:
    - You see 9 columns. If everything is in one column with `|` inside the value, the column split was not saved. Edit the sensor and recheck Step 4.
    - Running Mode shows `Normal` or `Passive`, and Platform Version shows a value like `4.18.26080.4`.

Example result (values are illustrative):

```
Normal|True|True|True|True|4.18.26080.4|1.459.601.0|2026-10-07 04:47|1
```

---

## Reading the results

| Column | What it tells you |
|---|---|
| Running Mode | `Normal` (Defender is the active antivirus), `Passive` (another antivirus is primary, Defender still updates), `EDR Block Mode`, `SxS Passive Mode`, or one of the status values below |
| Service Enabled | Whether the Defender antimalware service is enabled |
| AV Enabled | Whether antivirus protection is on |
| Real-Time Protection | Whether real-time scanning is on |
| Tamper Protected | Whether tamper protection is on |
| Platform Version | The Defender antimalware platform version, for example `4.18.26080.4`. This is the version most Defender CVEs are fixed in |
| Signature Version | The security intelligence version |
| Signature Last Updated | When signatures last updated, in the endpoint's local time |
| Signature Age (Days) | Days since the last signature update. Above 7 usually means updates are failing |

### Status values

When the sensor can't read Defender, the first column holds one of these and the other columns show `N/A`:

| Running Mode | Meaning |
|---|---|
| `Not Applicable` | The `WinDefend` service does not exist. Defender was removed, or the endpoint is not Windows |
| `Error: Service not running` | `WinDefend` exists but is stopped, usually because another antivirus is installed. Use **Microsoft Defender AntiMalware Details** for versions |
| `Error: Status unavailable` | `WinDefend` is running but `Get-MpComputerStatus` failed. Check the Defender WMI provider on that machine |

---

## Limits

- No engine version column. The built-in **Microsoft Defender AntiMalware Details** sensor already returns Engine Version and Product Version, so this sensor doesn't repeat them.
- Signature Last Updated is returned as Text, so it sorts as text. `yyyy-MM-dd HH:mm` sorts correctly as text anyway.
- Read-only. The sensor never changes anything on the endpoint.
