# Tanium sensor: Java Scheduled Tasks (v2, Task Scheduler COM API, no WMI dependency)
# Returns one row per scheduled task action that launches Java:
# Task|State|Run As|Last Run|Command
# Matches java.exe, javaw.exe, javaws.exe, .jar and .jnlp in the action, and also
# looks inside .bat/.cmd/.ps1/.vbs scripts (under 1 MB) that the task runs.

$pattern   = '(?i)\bjava(w|ws)?(\.exe)?\b(?!script)|\.jar\b|\.jnlp\b'
$stateName = @{ 0 = 'Unknown'; 1 = 'Disabled'; 2 = 'Queued'; 3 = 'Ready'; 4 = 'Running' }
$wow64     = [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess
$rows      = New-Object System.Collections.Generic.List[string]

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

try {
    $svc = New-Object -ComObject 'Schedule.Service'
    $svc.Connect()
    $tasks = @(Get-AllTasks ($svc.GetFolder('\')))
} catch {
    'Error: ' + ($_.Exception.Message -replace '\|', '/') + '|N/A|N/A|N/A|N/A'
    exit 0
}

foreach ($t in $tasks) {
    try { $def = $t.Definition } catch { continue }

    foreach ($a in $def.Actions) {
        if ($a.Type -ne 0) { continue }                         # 0 = start a program

        $exe = Expand-TaskPath "$($a.Path)"
        $cmd = ("$exe $($a.Arguments)").Trim()
        $hit = $cmd -match $pattern

        # Task runs a script: check whether the script itself calls Java
        if (-not $hit -and $exe -match '(?i)\.(bat|cmd|ps1|vbs)$' -and (Test-Path -LiteralPath $exe)) {
            $file = Get-Item -LiteralPath $exe -ErrorAction SilentlyContinue
            if ($file -and $file.Length -lt 1MB) {
                $body = Get-Content -LiteralPath $exe -Raw -ErrorAction SilentlyContinue
                if ($body -match $pattern) { $hit = $true; $cmd += ' [script calls Java]' }
            }
        }

        if ($hit) {
            $last = 'Never'
            $lr = $t.LastRunTime
            if ($lr -and $lr.Year -gt 1999) { $last = $lr.ToString('yyyy-MM-dd HH:mm') }
            $rows.Add(('{0}|{1}|{2}|{3}|{4}' -f $t.Path, $stateName[[int]$t.State],
                $def.Principal.UserId, $last, ($cmd -replace '\|', '/')))
        }
    }
}

if ($rows.Count) { $rows | Sort-Object -Unique }
else { 'No Java scheduled tasks|N/A|N/A|N/A|N/A' }
