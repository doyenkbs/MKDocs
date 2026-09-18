---
tags:
  - Tanium
  - PowerShell
  - Packages
  - File Search
  - Endpoint Management
---

# Find File by Name (Package)

A parameterized Tanium package that searches Windows endpoints for a file by name or wildcard and returns the full path and last modified date of every match.

Use this package when:

- Custom sensor creation is not available in your environment, or
- You need to search entire drives. A full-drive search can take a minute or more, which is too long for a sensor.

For quick lookups in a known folder, use the [Find File by Name sensor](../sensors/find-file-by-name.md) instead.

---

## What it returns

The results are written to the action log on each endpoint, one line per match:

```
C:\inetpub\wwwroot\app\scripts\jquery-3.4.1.min.js|2023-03-31 08:18:52
C:\Temp\backup\jquery-3.4.1.min.js|2023-03-31 08:18:52
```

Format: `<full path>|<last modified date>`. Dates use `yyyy-MM-dd HH:mm:ss` in the endpoint's local time, so they look the same on every machine regardless of regional settings.

| Output | Meaning |
|---|---|
| One or more paths | The file was found. Every match is listed. |
| `NOT FOUND` | The search finished and nothing matched. |
| `SEARCH INCOMPLETE` | The 20-minute limit was reached. Any paths above this line were found before it stopped. |
| `SEARCHROOT NOT FOUND` | None of the folders given in the second parameter exist on that endpoint. |
| `ERROR\|Invalid FileName...` | The file name was blank, contained a path, or was only wildcards such as `*` or `*.*`. |

---

## Requirements

- Windows endpoints with PowerShell 5.1.
- A Tanium account with permission to create packages in a content set and deploy actions to the target computers.

---

## Parameters

| Parameter | Passed as | Required | What to enter |
|---|---|---|---|
| File Name | `$1` | Yes | A file name or wildcard. Examples: `hosts`, `*.pst`, `*jquery*.js`, `report_2026*.xlsx` |
| Search Folder | `$2` | No | One or more folders separated by `;`. Leave blank to search every fixed drive (C:, D:, and so on). |

Search Folder examples:

| Input | What gets searched |
|---|---|
| *(blank)* | All fixed drives. Slowest option. |
| `C:\Users` | Only `C:\Users` and everything under it. |
| `C:\Users;D:\Data` | Both folders. |

Tanium replaces `$1` and `$2` in the command line with the values you enter, in the order the parameters are defined in the package. File Name must be the first parameter and Search Folder the second.

---

## Create the package

Menu labels can differ slightly between Tanium versions.

1. Save the script at the bottom of this page as `Find-FileByName-Package.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package**.
4. Fill in the fields:
   - **Package Display Name:** `Find File by Name` (add your team's prefix if you use one).
   - **Content Set:** the content set your team uses for custom content.
   - **Command:**
     ```
     cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Find-FileByName-Package.ps1 -FileName "$1" -SearchRoot "$2"
     ```
   - **Command Timeout:** `25` minutes. This must be longer than the script's own 20-minute limit, so the script can report `SEARCH INCOMPLETE` before Tanium stops it.
5. Under **Files**, click **Add**, choose **Local File**, and upload `Find-FileByName-Package.ps1`.
6. Under **Parameter Inputs**, click **Add** and choose **Text Input**:
   - **Label:** `File Name`
   - **Help text:** `File name or wildcard, for example *.pst`
7. Click **Add** again and choose **Text Input**:
   - **Label:** `Search Folder (optional, separate with ;)`
   - **Help text:** `Leave blank to search all fixed drives`
8. Click **Save**.

---

## Deploy the package

1. In **Interact**, ask a question that returns the computers you want to search. Example:
   ```
   Get Computer Name from all machines with Computer Name contains "web"
   ```
2. Select the computers in the results grid.
3. Click **Deploy Action**.
4. In **Deployment Package**, search for and select `Find File by Name`.
5. Enter the **File Name**, and optionally the **Search Folder**.
6. Under the schedule, leave it as a one-time action.
7. For a large number of endpoints, set **Distribute over** to spread the start times. A full-drive search reads every folder on the disk, and starting it on thousands of machines at once causes a spike in disk activity.
8. Click **Show preview to continue**, review the targets, then click **Deploy Action**.

---

## View the results

### One endpoint

1. Open the action from **Administration** > **Actions** > **Action History**.
2. Select an endpoint that shows **Completed**.
3. Open its action log. The matches appear between the `Command Line` line and the `Completed` line:

```
006|...|Command Line: cmd.exe /d /c powershell.exe ... -FileName "%2ajquery%2a%2ejs" -SearchRoot ""
007|C:\Temp\new\jquery-3.7.1.min.js|2026-09-10 21:05:53
008|C:\Temp\backup\jquery-3.4.1.min.js|2023-03-31 08:18:52
011|...|Completed.
```

### Many endpoints

Reading logs one endpoint at a time gets slow. Ask a question with the built-in **Tanium Action Log** sensor, using the action ID from the top of the log:

```
Get Tanium Action Log[12345] from all machines
```

---

## Things to know

- **Parameters arrive URL-encoded.** Tanium passes `*jquery*.js` to the script as `%2ajquery%2a%2ejs`. The script decodes it before searching.
- **It runs as 64-bit.** If the Tanium client starts 32-bit PowerShell, the script restarts itself as 64-bit. Without this, a search under `C:\Windows\System32` would return the contents of `C:\Windows\SysWOW64` instead.
- **Run time depends on the disk.** In testing, a full-drive search on a Windows server took about 80 seconds. A search limited to one folder usually finishes in a few seconds.
- **Limits:** 5,000 matches per endpoint and 20 minutes of search time. Both can be changed with the `MaxResults` and `MaxMinutes` values at the top of the script.
- **It runs at below-normal priority** to reduce the impact on users.
- **Linked folders are skipped.** Junctions and symbolic links (for example `C:\Documents and Settings`) point to folders that are already searched, so following them would only produce duplicates.
- **Some duplicates are real copies.** For example, IIS keeps compressed copies of web files under `C:\inetpub\temp\IIS Temporary Compressed Files`. Those show up as separate matches with upper-case paths.

---

## Script

```powershell
<#
.SYNOPSIS
    Tanium package: find files by name and report full path and last write time.

.PACKAGE COMMAND LINE
    cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Find-FileByName-Package.ps1 -FileName "$1" -SearchRoot "$2"

.PACKAGE PARAMETERS
    $1  FileName    File name or wildcard. Examples: hosts   *.pst   invoice_2026*.pdf
    $2  SearchRoot  Optional. One or more folders separated by ;  Blank = all fixed drives.

.OUTPUT
    Written to the action log, one line per match:  <FullPath>|<LastWriteTime>
    "NOT FOUND" when nothing matched.
    "SEARCH INCOMPLETE" only if the time limit was reached.
#>
param(
    [string]$FileName   = '',
    [string]$SearchRoot = '',
    [int]$MaxResults    = 5000,
    [int]$MaxMinutes    = 20
)

# ---- Normalize and validate input (before any relaunch) ----
$FileName   = $FileName.Trim().Trim('"')
$SearchRoot = $SearchRoot.Trim().Trim('"')
if ($FileName   -match '%[0-9A-Fa-f]{2}') { $FileName   = [Uri]::UnescapeDataString($FileName) }
if ($SearchRoot -match '%[0-9A-Fa-f]{2}') { $SearchRoot = [Uri]::UnescapeDataString($SearchRoot) }

if (-not $FileName -or
    $FileName -notmatch '^[^\\/:"<>|]+$' -or      # name only, no path characters
    $FileName -match '^[\*\?\.\s]+$') {            # block *, *.*, ? and similar
    Write-Output 'ERROR|Invalid FileName. Use a file name or wildcard such as *.pst, not a path.'
    exit 1
}

# ---- Run as 64-bit so C:\Windows\System32 is not redirected to SysWOW64 ----
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$PSCommandPath,
                 '-FileName',$FileName,'-MaxResults',$MaxResults,'-MaxMinutes',$MaxMinutes)
    if ($SearchRoot) { $argList += @('-SearchRoot',$SearchRoot) }
    & $ps64 @argList
    exit $LASTEXITCODE
}

# ---- Be gentle on the endpoint ----
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch { }

# ---- Search roots ----
if ($SearchRoot) {
    $roots = $SearchRoot.Split(';') | ForEach-Object { $_.Trim() } |
             Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
    if (-not $roots) {
        Write-Output 'SEARCHROOT NOT FOUND'
        exit 0
    }
} else {
    $roots = [IO.DriveInfo]::GetDrives() |
             Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } |
             ForEach-Object { $_.RootDirectory.FullName }
}

# ---- Directory walk (stack based, skips junctions/symlinks, survives access denied) ----
$found   = New-Object 'System.Collections.Generic.List[string]'
$pending = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
foreach ($r in $roots) { $pending.Push([IO.DirectoryInfo]$r) }

$reparse = [IO.FileAttributes]::ReparsePoint
$useLike = $FileName -notmatch '[\[\]]'   # -like treats [ ] as wildcards, so skip the recheck for those names
$limit   = [TimeSpan]::FromMinutes($MaxMinutes)
$status  = 'Complete'
$sw      = [Diagnostics.Stopwatch]::StartNew()

:walk while ($pending.Count -gt 0) {
    if ($sw.Elapsed -ge $limit) { $status = 'TimedOut'; break }
    $dir = $pending.Pop()

    try {
        foreach ($f in $dir.EnumerateFiles($FileName)) {
            # .NET also matches 8.3 short names and longer extensions (*.txt hits .txte); recheck the real name
            if ($useLike -and $f.Name -notlike $FileName) { continue }
            $found.Add(('{0}|{1:yyyy-MM-dd HH:mm:ss}' -f $f.FullName, $f.LastWriteTime))
            if ($found.Count -ge $MaxResults) { $status = 'Truncated'; break walk }
        }
    } catch { }

    try {
        foreach ($d in $dir.EnumerateDirectories()) {
            if (($d.Attributes -band $reparse) -eq 0) { $pending.Push($d) }
        }
    } catch { }
}
$sw.Stop()

# ---- Output to the action log ----
if ($found.Count -gt 0)          { $found | Write-Output }
elseif ($status -ne 'TimedOut')  { Write-Output 'NOT FOUND' }
if ($status -eq 'TimedOut')      { Write-Output 'SEARCH INCOMPLETE' }
exit 0
```
