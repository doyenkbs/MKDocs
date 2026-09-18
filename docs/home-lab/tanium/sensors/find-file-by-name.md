---
tags:
  - Tanium
  - PowerShell
  - Sensors
  - File Search
  - Endpoint Management
---

# Find File by Name (Sensor)

A parameterized Tanium sensor that searches one or more folders on Windows endpoints for a file by name or wildcard. It returns the full path and last modified date of every match directly in Interact.

Use this sensor for quick lookups in a known folder, such as `C:\Users` or `C:\inetpub`. Every time a question with this sensor is asked, the search runs again, so it has to finish in seconds.

Full-drive searches are not allowed in this sensor. In testing, a full-drive search on a Windows server took about 80 seconds, which is too long for a sensor. For full-drive searches, use the [Find File by Name package](../packages/find-file-by-name.md).

---

## What it returns

Results come back in Interact in two columns:

| Path | Last Write Time |
|---|---|
| `C:\Users\jdoe\Documents\archive.pst` | `2026-08-14 16:02:11` |
| `C:\Users\asmith\Documents\old-mail.pst` | `2025-11-03 09:47:30` |

Dates use `yyyy-MM-dd HH:mm:ss` in the endpoint's local time, so they look the same on every machine regardless of regional settings.

| Result in the Path column | Meaning |
|---|---|
| One or more paths | The file was found. Up to 100 matches per endpoint. |
| `NOT FOUND` | The search finished and nothing matched. |
| `SEARCH INCOMPLETE` | The time limit (45 seconds by default) was reached. Narrow the search folder. Any paths returned before it stopped are still listed. |
| `SEARCHROOT REQUIRED` | The Search Folder parameter was left blank. |
| `SEARCHROOT NOT FOUND` | None of the folders given exist on that endpoint. |
| `INVALID FILENAME` | The file name was blank, contained a path, or was only wildcards such as `*` or `*.*`. |

---

## Requirements

- Windows endpoints with PowerShell 5.1.
- A Tanium account with permission to create sensors in a content set.

---

## Parameters

| Key | Required | What to enter |
|---|---|---|
| `FileName` | Yes | A file name or wildcard. Examples: `hosts`, `*.pst`, `*jquery*.js` |
| `SearchRoot` | Yes | One or more folders separated by `;`. Examples: `C:\Users`, `C:\inetpub;D:\Web` |
| `MaxSeconds` | No | How long to search before giving up. Blank = 45. Keep it lower than the sensor's timeout. |

The script reads each parameter through a placeholder such as `||FileName||`. The **Key** you enter when creating each parameter must match the placeholder exactly, including capitalization.

---

## Create the sensor

Menu labels can differ slightly between Tanium versions.

1. In the Tanium Console, go to **Administration** > **Content** > **Sensors**.
2. Click **Create Sensor**.
3. Fill in the general fields:
   - **Sensor Name:** `Find File by Name` (add your team's prefix if you use one). Avoid brackets, quotes, and `|` in the name, since Interact uses those characters in questions.
   - **Description:** `Searches the given folders for a file name or wildcard. Returns full path and last modified date.`
   - **Content Set:** the content set your team uses for custom content.
   - **Category:** `File System` or your team's custom category.
   - **Result Type:** `Text`.
   - **Max Sensor Age:** `10 minutes`. Results are reused for this long before the search runs again.
4. Enable **Split into multiple columns**:
   - **Delimiter:** `|`
   - **Column 1:** name `Path`, type `Text`
   - **Column 2:** name `Last Write Time`, type `Text`
5. Under **Parameters**, click **Add** three times and create:

   | Key | Label | Type |
   |---|---|---|
   | `FileName` | File Name | Text Input |
   | `SearchRoot` | Search Folder (separate with ;) | Text Input |
   | `MaxSeconds` | Max Seconds (optional) | Text Input |

6. Under the **Windows** script tab:
   - **Script Type:** `PowerShell`
   - **Script:** paste the script at the bottom of this page.
7. Set the sensor **Timeout** to `60` seconds, which is above the script's default 45-second limit, so the script can return `SEARCH INCOMPLETE` before Tanium stops it.
8. Click **Save**.

---

## Ask a question

1. In **Interact**, type:
   ```
   Get Find File by Name from all machines
   ```
2. Interact shows a field for each parameter. Enter:
   - **File Name:** `*.pst`
   - **Search Folder:** `C:\Users`
   - **Max Seconds:** leave blank.
3. Click **Search**.

You can also type the parameters directly, in the order they were defined:

```
Get Find File by Name[*.pst,C:\Users,] from all machines
```

To see which computers have the file, add the computer name:

```
Get Computer Name and Find File by Name[*.pst,C:\Users,] from all machines
```

---

## Things to know

- **Parameters arrive URL-encoded.** Tanium passes `*.pst` to the script as `%2a%2epst`. The script decodes it before searching.
- **Keep the search folder narrow.** `C:\Users` or `C:\ProgramData` usually finishes in a few seconds. `C:\` will usually hit the time limit.
- **Limits:** 100 matches per endpoint and 45 seconds of search time by default.
- **Linked folders are skipped.** Junctions and symbolic links point to folders that are already searched, so following them would only produce duplicates.
- **Results are cached.** Asking the same question again within the Max Sensor Age returns the saved results. If a file was just created or deleted, wait for the age to expire or ask with a different parameter value.

---

## Script

```powershell
# Tanium sensor: Find File by Name
#
# Sensor settings
#   Script type : PowerShell (Windows)
#   Parameters  : FileName   (required, e.g. *.pst)
#                 SearchRoot (required, folders separated by ;  e.g. C:\Users;D:\Data)
#                 MaxSeconds (optional, default 45; keep under the sensor timeout)
#   Result type : String, split into columns, delimiter |
#   Columns     : Path | Last Write Time
#
# Full-drive searches are not allowed here because they take too long for a sensor.
# Use the Find File by Name package for full-drive searches.

$FileName   = [Uri]::UnescapeDataString('||FileName||').Trim().Trim('"')
$SearchRoot = [Uri]::UnescapeDataString('||SearchRoot||').Trim().Trim('"')
$maxSecText = [Uri]::UnescapeDataString('||MaxSeconds||').Trim()

$maxSec = 45
if ($maxSecText -match '^\d+$' -and [int]$maxSecText -gt 0) { $maxSec = [int]$maxSecText }
$maxResults = 100

if (-not $FileName -or $FileName -notmatch '^[^\\/:"<>|]+$' -or $FileName -match '^[\*\?\.\s]+$') {
    Write-Output 'INVALID FILENAME|'
    exit
}

if (-not $SearchRoot) {
    Write-Output 'SEARCHROOT REQUIRED|'
    exit
}

$roots = $SearchRoot.Split(';') | ForEach-Object { $_.Trim() } |
         Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }

if (-not $roots) {
    Write-Output 'SEARCHROOT NOT FOUND|'
    exit
}

$found   = New-Object 'System.Collections.Generic.List[string]'
$pending = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
foreach ($r in $roots) { $pending.Push([IO.DirectoryInfo]$r) }

$reparse  = [IO.FileAttributes]::ReparsePoint
$useLike  = $FileName -notmatch '[\[\]]'
$limit    = [TimeSpan]::FromSeconds($maxSec)
$timedOut = $false
$sw       = [Diagnostics.Stopwatch]::StartNew()

:walk while ($pending.Count -gt 0) {
    if ($sw.Elapsed -ge $limit) { $timedOut = $true; break }
    $dir = $pending.Pop()

    try {
        foreach ($f in $dir.EnumerateFiles($FileName)) {
            if ($useLike -and $f.Name -notlike $FileName) { continue }
            $found.Add(('{0}|{1:yyyy-MM-dd HH:mm:ss}' -f $f.FullName, $f.LastWriteTime))
            if ($found.Count -ge $maxResults) { break walk }
        }
    } catch { }

    try {
        foreach ($d in $dir.EnumerateDirectories()) {
            if (($d.Attributes -band $reparse) -eq 0) { $pending.Push($d) }
        }
    } catch { }
}

if ($found.Count -gt 0) { $found | Write-Output }
elseif (-not $timedOut) { Write-Output 'NOT FOUND|' }

if ($timedOut) { Write-Output 'SEARCH INCOMPLETE|' }
```
