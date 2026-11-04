# Tanium sensor: Scheduled Tasks by Command (parameterized)
# Parameters:
#   Match       - text to find, case-insensitive plain text, minimum 3 characters (e.g. java, python, D:\Scripts, backup.ps1)
#   ScanScripts - Yes/No. Yes also searches inside .bat/.cmd/.ps1/.vbs files (under 1 MB) that a task runs.
#   LastRun     - Age/Day/Exact. Age returns buckets (0-7 days, 8-30 days, 31-90 days, 91-365 days,
#                 Over 1 year) so rows merge across machines. Day and Exact return dates.
# Matches against the task path/name and the action command line.
# Uses the Task Scheduler COM API, so it does not depend on WMI.
# Output: Task|State|Run As|Last Run|Command

$match   = [System.Uri]::UnescapeDataString('||Match||').Trim()
$scanArg = [System.Uri]::UnescapeDataString('||ScanScripts||').Trim()
$maxRows = 500

$na = '|N/A|N/A|N/A|N/A'
if ($match -match '^\|\|\w+\|\|$') { 'Error: Match parameter was not provided' + $na; exit 0 }
if ($match.Length -lt 3)           { 'Error: Match must be at least 3 characters' + $na; exit 0 }
$scanScripts = $scanArg -ne 'No'

# LastRun: Age (default, buckets that merge across machines), Day, or Exact (to the minute)
$lastMode = [System.Uri]::UnescapeDataString('||LastRun||').Trim()
if (@('Age', 'Day', 'Exact') -notcontains $lastMode) { $lastMode = 'Age' }

$stateName = @{ 0 = 'Unknown'; 1 = 'Disabled'; 2 = 'Queued'; 3 = 'Ready'; 4 = 'Running' }
$wow64     = [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess
$rows      = New-Object System.Collections.Generic.List[string]

function Test-Match([string]$s) {
    return ($s -and $s.IndexOf($match, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Expand-TaskPath([string]$p) {
    $p = $p.Trim().Trim('"')
    if ($wow64 -and $env:ProgramW6432) { $p = $p -replace '(?i)%ProgramFiles%', $env:ProgramW6432 }
    $p = [Environment]::ExpandEnvironmentVariables($p)
    if ($wow64) { $p = $p -replace '(?i)\\System32\\', '\Sysnative\' }   # see the real System32 from 32-bit PowerShell
    return $p
}

function Get-AllTasks($folder) {
    $folder.GetTasks(1)                                        # 1 = include hidden tasks
    foreach ($sub in $folder.GetFolders(0)) { Get-AllTasks $sub }
}

function Clean([string]$s) { return (($s -replace '[\r\n]+', ' ') -replace '\|', '/').Trim() }

try {
    $svc = New-Object -ComObject 'Schedule.Service'
    $svc.Connect()
    $tasks = @(Get-AllTasks ($svc.GetFolder('\')))
} catch {
    'Error: ' + (Clean $_.Exception.Message) + $na
    exit 0
}

:taskLoop foreach ($t in $tasks) {
    try { $def = $t.Definition } catch { continue }

    foreach ($a in $def.Actions) {
        $exe = ''; $cmd = $null
        switch ([int]$a.Type) {
            0 { $exe = Expand-TaskPath "$($a.Path)"; $cmd = ("$exe $($a.Arguments)").Trim() }   # start a program
            5 { $exe = ''; $cmd = "COM handler $($a.ClassId) $($a.Data)".Trim() }              # COM handler
        }
        if (-not $cmd) { continue }                                                              # deprecated email/message actions

        $hit = (Test-Match $cmd) -or (Test-Match $t.Path)

        # Search inside scripts the task runs: the program itself or a script named in the arguments
        if (-not $hit -and $scanScripts -and $a.Type -eq 0) {
            $candidates = @($exe)
            foreach ($m in [regex]::Matches("$($a.Arguments)", '(?i)"([^"]+\.(?:bat|cmd|ps1|vbs))"|([^\s"]+\.(?:bat|cmd|ps1|vbs))')) {
                if ($m.Groups[1].Success) { $candidates += $m.Groups[1].Value } else { $candidates += $m.Groups[2].Value }
            }
            foreach ($c in $candidates) {
                if ($c -notmatch '(?i)\.(bat|cmd|ps1|vbs)"?$') { continue }
                $p = Expand-TaskPath $c
                if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
                $file = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
                if ($file -and $file.Length -lt 1MB) {
                    $body = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
                    if (Test-Match $body) {
                        $hit = $true
                        $cmd += ' [script ' + [IO.Path]::GetFileName($p) + ' matches]'
                        break
                    }
                }
            }
        }

        if ($hit) {
            $last = 'Never'
            $lr = $t.LastRunTime
            if ($lr -and $lr.Year -gt 1999) {
                switch ($lastMode) {
                    'Exact' { $last = $lr.ToString('yyyy-MM-dd HH:mm') }
                    'Day'   { $last = $lr.ToString('yyyy-MM-dd') }
                    default {
                        $days = ((Get-Date) - $lr).TotalDays
                        if     ($days -le 7)   { $last = '0-7 days' }
                        elseif ($days -le 30)  { $last = '8-30 days' }
                        elseif ($days -le 90)  { $last = '31-90 days' }
                        elseif ($days -le 365) { $last = '91-365 days' }
                        else                   { $last = 'Over 1 year' }
                    }
                }
            }
            $rows.Add(('{0}|{1}|{2}|{3}|{4}' -f (Clean $t.Path), $stateName[[int]$t.State],
                (Clean "$($def.Principal.UserId)"), $last, (Clean $cmd)))

            if ($rows.Count -ge $maxRows) { $rows.Add('Max rows reached' + $na); break taskLoop }
        }
    }
}

if ($rows.Count) { $rows | Sort-Object -Unique }
else { 'No matching scheduled tasks' + $na }
