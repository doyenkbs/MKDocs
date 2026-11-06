# Tanium sensor: Java - Install Usage - Prefetch
# One row per Java on the endpoint: which Java it is, how it was installed, and when it last ran.
# Windows Prefetch names each file <EXE>-<HASH>.pf, where HASH comes from the full path of the
# program that ran. The script works out that hash for every Java folder it finds, so each Java
# run is tied to the exact Java that ran it. Read-only: no WMI, no compiled code, no files written.
# Columns: Java Home|Version|Installed By|Installed On|Last Run|Days Ago|Usage|Launchers|Uninstall Command
# Version 1.1: one row per Java (no app/jre duplicates), Tanium Comply Java named, user profiles searched,
# Prefetch that is switched on but not being written is reported instead of trusted

$ErrorActionPreference = 'SilentlyContinue'
$NA = 'N/A'

function Out-Row([string[]]$v) {
    ($v | ForEach-Object { (("$_" -replace '[\r\n]+', ' ') -replace '\|', '/').Trim() }) -join '|'
}

try {
    $sw         = [Diagnostics.Stopwatch]::StartNew()
    $searchSecs = 15
    $MOD        = [long]4294967296
    $LOW16      = [long]65535
    $wow64      = [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess
    $win        = $env:SystemRoot
    $sysDrive   = $env:SystemDrive.ToUpperInvariant()
    $pf64       = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
    $pf86       = ${env:ProgramFiles(x86)}
    $launchers  = @('JAVA.EXE', 'JAVAW.EXE', 'JAVAWS.EXE', 'JP2LAUNCHER.EXE')
    $incomplete = $false

    # ---------- Prefetch hash helpers (Windows Vista and later) ----------
    $pow = New-Object 'System.Collections.Generic.List[long]'
    $pow.Add(1)
    function Get-Pow([int]$n) {
        while ($pow.Count -le $n) { $pow.Add(($pow[$pow.Count - 1] * 37) % $MOD) }
        return $pow[$n]
    }
    function Get-H0([string]$s) {
        $h = [long]0
        foreach ($c in $s.ToUpperInvariant().ToCharArray()) {
            $v = [long][int]$c
            $h = ($h * 37 + ($v -band 255)) % $MOD
            $h = ($h * 37 + ($v -shr 8)) % $MOD
        }
        return $h
    }
    function MulMod([long]$a, [long]$b) {
        return ((($a -band $LOW16) * $b) + (((($a -shr 16) * $b) -band $LOW16) * 65536)) % $MOD
    }
    function Add-Str([long]$state, [string]$s) {
        return ((MulMod $state (Get-Pow (2 * $s.Length))) + (Get-H0 $s)) % $MOD
    }

    $volState = @{}
    foreach ($n in 1..64) { $volState[$n] = Add-Str 314159 "\DEVICE\HARDDISKVOLUME$n" }
    $lH0 = @{}; $lPow = @{}
    foreach ($l in $launchers) { $lH0[$l] = Get-H0 ('\' + $l); $lPow[$l] = Get-Pow (2 * ($l.Length + 1)) }

    # ---------- Prefetch files ----------
    $pfDir  = Join-Path $win 'Prefetch'
    $pfMode = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' -Name EnablePrefetcher).EnablePrefetcher
    $pfState = 'On'
    $allPf = @()
    if ($pfMode -eq 0) { $pfState = 'Prefetch disabled' }
    elseif (-not (Test-Path -LiteralPath $pfDir)) { $pfState = 'Prefetch folder missing' }
    else {
        try { $allPf = @(Get-ChildItem -LiteralPath $pfDir -Filter '*.pf' -File -ErrorAction Stop) }
        catch { $pfState = 'Prefetch folder unreadable' }
    }
    # Prefetch can be switched on but not written (for example when the SysMain service is off, the
    # default on Windows Server). A running machine writes Prefetch files all day, so no file newer
    # than 3 days means "No runs recorded" would not be trustworthy.
    if ($pfState -eq 'On') {
        $newest = $allPf | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $newest -or ((Get-Date) - $newest.LastWriteTime).TotalDays -gt 3) { $pfState = 'Prefetch not recording' }
    }

    $pfByKey = @{}     # 'JAVAW.EXE|4A2EFA53' -> run record
    $byExe   = @{}     # 'CMD.EXE' -> list of hashes, used to find the system volume number
    foreach ($f in $allPf) {
        if ($f.Name -notmatch '^(.+)-([0-9A-F]{8})\.pf$') { continue }
        $exe = $Matches[1].ToUpperInvariant(); $hex = $Matches[2].ToUpperInvariant()
        if (-not $byExe.ContainsKey($exe)) { $byExe[$exe] = New-Object 'System.Collections.Generic.HashSet[string]' }
        [void]$byExe[$exe].Add($hex)
        if ($launchers -contains $exe) {
            $pfByKey["$exe|$hex"] = [pscustomobject]@{ Launcher = $exe; LastRun = $f.LastWriteTime; Owner = $null; Via = '' }
        }
    }

    # Find the volume number of the system drive from Prefetch files of standard Windows programs
    $driveVol = @{}
    $winRel = $win.Substring(2)
    $calib = @(
        "$winRel\System32\conhost.exe", "$winRel\System32\cmd.exe", "$winRel\explorer.exe",
        "$winRel\System32\WindowsPowerShell\v1.0\powershell.exe", "$winRel\SysWOW64\WindowsPowerShell\v1.0\powershell.exe",
        "$winRel\System32\wbem\WmiPrvSE.exe", "$winRel\System32\taskhostw.exe", "$winRel\System32\msiexec.exe",
        "$winRel\System32\reg.exe", "$winRel\System32\sc.exe", "$winRel\System32\RuntimeBroker.exe"
    )
    :calibLoop foreach ($rel in $calib) {
        $exe = [IO.Path]::GetFileName($rel).ToUpperInvariant()
        if (-not $byExe.ContainsKey($exe)) { continue }
        $h0 = Get-H0 $rel; $p = Get-Pow (2 * $rel.Length)
        foreach ($n in 1..64) {
            $h = ((MulMod $volState[$n] $p) + $h0) % $MOD
            if ($byExe[$exe].Contains($h.ToString('X8'))) { $driveVol[$sysDrive] = $n; break calibLoop }
        }
    }

    # ---------- Java on disk ----------
    function Get-FsPath([string]$p) {
        if ($wow64) { return ($p -replace '(?i)^([A-Z]:\\Windows)\\System32(\\|$)', '$1\Sysnative$2') }
        return $p
    }
    function Test-HasJava([string]$dir) {
        $fs = Get-FsPath $dir
        return ([IO.File]::Exists("$fs\java.exe") -or [IO.File]::Exists("$fs\javaw.exe"))
    }
    function Get-SubDirs([string]$p) {
        try { return [IO.Directory]::GetDirectories($p) } catch { return @() }
    }

    $entries = @{}   # home (case-insensitive) -> entry
    # -Always keeps a known path even when it is not on disk, so runs from it can still be named
    function Add-Entry([string]$jh, [string]$kind, [switch]$Always) {
        if (-not $jh) { return }
        $jh = $jh.Trim().Trim('"').TrimEnd('\')
        if ($jh.Length -lt 3) { return }
        if ($kind -ne 'Folder') {
            # Use the folder that holds bin\java.exe, so an application folder and its jre subfolder are one row
            if (-not (Test-HasJava "$jh\bin") -and (Test-HasJava "$jh\jre\bin")) { $jh = "$jh\jre" }
            # A JDK's own jre subfolder belongs to the JDK
            if ($jh -match '(?i)\\jre$' -and (Test-HasJava ((Split-Path -Parent $jh) + '\bin'))) { $jh = Split-Path -Parent $jh }
        }
        if ($entries.ContainsKey($jh)) { return }
        if ($kind -eq 'Folder') { $dirs = @($jh) } else { $dirs = @("$jh\bin", "$jh\jre\bin") }
        $exists = @($dirs | Where-Object { Test-HasJava $_ }).Count -gt 0
        if (-not $exists -and -not $Always) { return }
        $entries[$jh] = [pscustomobject]@{
            Home = $jh; Kind = $kind; Dirs = $dirs; Exists = $exists; Version = $NA; InstalledBy = ''; InstalledOn = $NA
            Uninstall = 'None registered'; Runs = New-Object System.Collections.ArrayList
        }
    }

    # Installer entries, JavaSoft registry, and Tanium Comply's own Java
    $uninst = New-Object System.Collections.ArrayList
    $jsHomes = New-Object System.Collections.ArrayList
    $taniumHomes = New-Object System.Collections.ArrayList
    foreach ($view in 'Registry64', 'Registry32') {
        $base = $null
        try { $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view) } catch { continue }
        $uk = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
        if ($uk) {
            foreach ($name in $uk.GetSubKeyNames()) {
                $sk = $uk.OpenSubKey($name); if (-not $sk) { continue }
                $dn = [string]$sk.GetValue('DisplayName')
                $loc = ([string]$sk.GetValue('InstallLocation')).Trim().Trim('"').TrimEnd('\')
                if ($dn -match '(?i)java|jdk|jre|openjdk|corretto|temurin|zulu|semeru|liberica' -and $loc) {
                    $cmd = 'None registered'
                    $us = [string]$sk.GetValue('UninstallString'); $qs = [string]$sk.GetValue('QuietUninstallString')
                    if ($name -match '^\{[0-9A-Fa-f-]{36}\}$' -and ($us -match '(?i)msiexec' -or $sk.GetValue('WindowsInstaller') -eq 1)) {
                        $cmd = "MsiExec.exe /X$name /qn /norestart"
                    } elseif ($qs) { $cmd = $qs } elseif ($us) { $cmd = $us }
                    [void]$uninst.Add([pscustomobject]@{ Name = $dn; Loc = $loc; Date = [string]$sk.GetValue('InstallDate'); Cmd = $cmd })
                }
                $sk.Close()
            }
            $uk.Close()
        }
        foreach ($jk in 'SOFTWARE\JavaSoft\Java Runtime Environment', 'SOFTWARE\JavaSoft\Java Development Kit', 'SOFTWARE\JavaSoft\JRE', 'SOFTWARE\JavaSoft\JDK') {
            $k = $base.OpenSubKey($jk); if (-not $k) { continue }
            foreach ($v in $k.GetSubKeyNames()) {
                $vk = $k.OpenSubKey($v); if ($vk) { [void]$jsHomes.Add([string]$vk.GetValue('JavaHome')); $vk.Close() }
            }
            $k.Close()
        }
        $tk = $base.OpenSubKey('SOFTWARE\Tanium\Tanium Client')
        if ($tk) { $tp = [string]$tk.GetValue('Path'); if ($tp) { [void]$taniumHomes.Add("$tp\extensions\comply\jre") }; $tk.Close() }
        $base.Close()
    }
    [void]$taniumHomes.Add("$pf86\Tanium\Tanium Client\extensions\comply\jre")
    [void]$taniumHomes.Add("$pf64\Tanium\Tanium Client\extensions\comply\jre")
    foreach ($t in $taniumHomes) { Add-Entry $t 'Tanium' -Always }
    foreach ($u in $uninst) { Add-Entry $u.Loc 'Install' }
    foreach ($j in $jsHomes) { Add-Entry $j 'Install' }

    # Running Java processes (finds Java bundled inside applications)
    foreach ($p in Get-Process -Name java, javaw, javaws, jp2launcher) {
        $path = $p.Path
        if ($path) {
            $dir = Split-Path -Parent $path
            if ((Split-Path -Leaf $dir) -eq 'bin') { Add-Entry (Split-Path -Parent $dir) 'Install' } else { Add-Entry $dir 'Folder' }
        }
    }

    # Oracle javapath folders and old copies in the Windows folder: java.exe sits in the folder itself
    $pathRoots = @("$pf64\Common Files\Oracle\Java", "$pf86\Common Files\Oracle\Java", "$env:ProgramData\Oracle\Java")
    foreach ($r in $pathRoots) { foreach ($d in Get-SubDirs $r) { Add-Entry $d 'Folder' } }
    foreach ($d in "$win\System32", "$win\SysWOW64") { Add-Entry $d 'Folder' }

    # Folder search: Program Files 2 levels deep, other folders on each fixed drive 3 levels deep
    function Search-Homes([string]$root, [int]$depth) {
        if ($depth -le 0 -or $sw.Elapsed.TotalSeconds -gt $searchSecs) {
            if ($depth -gt 0) { $script:incomplete = $true }
            return
        }
        foreach ($d in Get-SubDirs $root) {
            if ($sw.Elapsed.TotalSeconds -gt $searchSecs) { $script:incomplete = $true; return }
            Add-Entry $d 'Install'
            Search-Homes $d ($depth - 1)
        }
    }
    foreach ($r in @($pf64, $pf86) | Select-Object -Unique) { if ($r) { Search-Homes $r 2 } }
    # Folders already searched (system drive) or that never hold Java
    $skip    = @('$Recycle.Bin', 'System Volume Information', 'Recovery', 'PerfLogs', 'Config.Msi', 'MSOCache', 'Documents and Settings')
    $skipSys = @('Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users')
    foreach ($drv in [IO.DriveInfo]::GetDrives()) {
        if ($drv.DriveType -ne 'Fixed' -or -not $drv.IsReady) { continue }
        $isSys = $drv.Name.Substring(0, 2).ToUpperInvariant() -eq $sysDrive
        foreach ($d in Get-SubDirs $drv.RootDirectory.FullName) {
            $leaf = Split-Path -Leaf $d
            if ($skip -contains $leaf -or ($isSys -and $skipSys -contains $leaf)) { continue }
            if ($sw.Elapsed.TotalSeconds -gt $searchSecs) { $incomplete = $true; break }
            Add-Entry $d 'Install'
            Search-Homes $d 2
        }
    }

    # User profiles: per-user JDKs (.jdks), VS Code Java runtimes, and apps under AppData\Local\Programs
    $usersDir = Join-Path $env:SystemDrive 'Users'
    foreach ($up in Get-SubDirs $usersDir) {
        if ((Split-Path -Leaf $up) -match '^(Public|Default|Default User|All Users)$') { continue }
        if ($sw.Elapsed.TotalSeconds -gt $searchSecs) { $incomplete = $true; break }
        foreach ($d in Get-SubDirs "$up\.jdks") { Add-Entry $d 'Install' }
        foreach ($x in Get-SubDirs "$up\.vscode\extensions") { foreach ($d in Get-SubDirs "$x\jre") { Add-Entry $d 'Install' } }
        Search-Homes "$up\AppData\Local\Programs" 2
    }

    # ---------- Details for each Java ----------
    foreach ($e in $entries.Values) {
        foreach ($d in $e.Dirs) {
            $fs = Get-FsPath $d
            foreach ($x in 'java.exe', 'javaw.exe') {
                if ($e.Version -eq $NA -and [IO.File]::Exists("$fs\$x")) {
                    $fv = (Get-Item -LiteralPath "$fs\$x").VersionInfo.FileVersion
                    if ($fv) { $e.Version = ($fv -replace ',', '.' -replace '\s', '') }
                }
            }
        }
        $best = $null
        foreach ($u in $uninst) {
            if ($e.Home -eq $u.Loc -or $e.Home.StartsWith($u.Loc + '\', [StringComparison]::OrdinalIgnoreCase)) {
                if (-not $best -or $u.Loc.Length -gt $best.Loc.Length) { $best = $u }
            }
        }
        switch ($e.Kind) {
            'Tanium' { $e.InstalledBy = 'Tanium Comply (do not remove)' }
            'Folder' {
                if ($e.Home -match '(?i)\\Oracle\\Java\\') { $e.InstalledBy = 'Oracle javapath (runs the default Java)' }
                elseif ($e.Home -match '(?i)^[A-Z]:\\Windows\\') { $e.InstalledBy = 'Copy in Windows folder' }
                else { $e.InstalledBy = 'No installer entry' }
            }
            default { if ($best) { $e.InstalledBy = $best.Name } else { $e.InstalledBy = 'No installer entry' } }
        }
        if ($best) {
            $e.Uninstall = $best.Cmd
            if ($best.Date -match '^(\d{4})(\d{2})(\d{2})$') { $e.InstalledOn = "$($Matches[1])-$($Matches[2])-$($Matches[3])" }
        }
        if ($e.InstalledOn -eq $NA -and $e.Kind -ne 'Folder') {
            $ct = (Get-Item -LiteralPath (Get-FsPath $e.Home)).CreationTime
            if ($ct) { $e.InstalledOn = $ct.ToString('yyyy-MM-dd') }
        }
    }

    # ---------- Tie each Java run to the Java that ran it ----------
    function Find-Runs($e) {
        foreach ($d in $e.Dirs) {
            if ($d -notmatch '^[A-Za-z]:\\') { continue }
            $drive = $d.Substring(0, 2).ToUpperInvariant(); $rel = $d.Substring(2)
            $h0 = Get-H0 $rel; $p = Get-Pow (2 * $rel.Length)
            if ($driveVol.ContainsKey($drive)) { $vols = @($driveVol[$drive]) } else { $vols = 1..64 }
            foreach ($n in $vols) {
                $st = ((MulMod $volState[$n] $p) + $h0) % $MOD
                foreach ($l in $launchers) {
                    $h = ((MulMod $st $lPow[$l]) + $lH0[$l]) % $MOD
                    $key = $l + '|' + $h.ToString('X8')
                    if ($pfByKey.ContainsKey($key) -and -not $pfByKey[$key].Owner) {
                        $pfByKey[$key].Owner = $e
                        $driveVol[$drive] = $n
                    }
                }
            }
        }
    }
    if ($pfByKey.Count -gt 0) { foreach ($e in $entries.Values) { Find-Runs $e } }

    # Runs from Java folders that no longer exist: try the standard Oracle folder names
    $open = @($pfByKey.Values | Where-Object { -not $_.Owner })
    if ($open.Count -gt 0 -and $driveVol.ContainsKey($sysDrive) -and $sw.Elapsed.TotalSeconds -lt 25) {
        $want = @($open | ForEach-Object { $_.Launcher } | Select-Object -Unique)
        $sysState = $volState[$driveVol[$sysDrive]]
        $pad = { param($a, $b) $a..$b | ForEach-Object { if ($_ -lt 10) { "0$_" } else { "$_" } } }
        $groups = @(
            @{ Prefix = '\Java\jre1.8.0_'; Major = '8'; Us = (& $pad 1 600); Tails = @('\bin') },
            @{ Prefix = '\Java\jdk1.8.0_'; Major = '8'; Us = (& $pad 1 600); Tails = @('\bin', '\jre\bin') },
            @{ Prefix = '\Java\jre1.7.0_'; Major = '7'; Us = (& $pad 1 121); Tails = @('\bin') },
            @{ Prefix = '\Java\jdk1.7.0_'; Major = '7'; Us = (& $pad 1 121); Tails = @('\bin', '\jre\bin') },
            @{ Prefix = '\Java\jre1.6.0_'; Major = '6'; Us = (& $pad 1 45);  Tails = @('\bin') },
            @{ Prefix = '\Java\jdk1.6.0_'; Major = '6'; Us = (& $pad 1 45);  Tails = @('\bin', '\jre\bin') },
            @{ Prefix = '\Java\'; Major = ''; Us = @('jre6', 'jre7', 'jre8', 'jre-1.8', 'jdk-1.8'); Tails = @('\bin') }
        )
        foreach ($root in @($pf64, $pf86) | Select-Object -Unique) {
            if (-not $root -or $root.Substring(0, 2).ToUpperInvariant() -ne $sysDrive) { continue }
            $rootRel = $root.Substring(2)
            foreach ($g in $groups) {
                $base = Add-Str $sysState ($rootRel + $g.Prefix)
                foreach ($us in $g.Us) {
                    foreach ($tail in $g.Tails) {
                        $st = $base
                        foreach ($c in "$us$tail".ToUpperInvariant().ToCharArray()) {
                            $v = [long][int]$c
                            $st = ($st * 37 + ($v -band 255)) % $MOD
                            $st = ($st * 37 + ($v -shr 8)) % $MOD
                        }
                        foreach ($l in $want) {
                            $pw = $lPow[$l]
                            $h = ((($st -band $LOW16) * $pw) + (((($st -shr 16) * $pw) -band $LOW16) * 65536) + $lH0[$l]) % $MOD
                            $key = $l + '|' + $h.ToString('X8')
                            if ($pfByKey.ContainsKey($key) -and -not $pfByKey[$key].Owner) {
                                $jh = $root + $g.Prefix + $us
                                if (-not $entries.ContainsKey($jh)) {
                                    # Same style as the file version of an installed build: 8u503 -> 8.0.5030
                                    $ver = if ($g.Major) { '{0}.0.{1}0' -f $g.Major, [int]$us } else { $NA }
                                    $entries[$jh] = [pscustomobject]@{
                                        Home = $jh; Kind = 'Removed'; Dirs = @(); Exists = $false; Version = $ver
                                        InstalledBy = 'Removed (folder no longer exists)'; InstalledOn = $NA
                                        Uninstall = $NA; Runs = New-Object System.Collections.ArrayList
                                    }
                                }
                                $pfByKey[$key].Owner = $entries[$jh]
                            }
                        }
                    }
                }
            }
        }
    }

    # javapath and Windows-folder copies run the same build as an installed Java: credit the run to it
    foreach ($r in $pfByKey.Values) {
        $o = $r.Owner
        if ($o -and $o.Kind -eq 'Folder' -and $o.Version -ne $NA) {
            $twin = @($entries.Values | Where-Object { $_.Kind -eq 'Install' -and $_.Version -eq $o.Version })
            if ($twin.Count -eq 1) { $r.Owner = $twin[0]; $r.Via = ' (javapath)' }
        }
    }
    foreach ($r in $pfByKey.Values) { if ($r.Owner) { [void]$r.Owner.Runs.Add($r) } }

    # ---------- Output ----------
    $today = (Get-Date).Date
    $rows = New-Object System.Collections.ArrayList
    foreach ($e in $entries.Values) {
        if ($e.Runs.Count -eq 0 -and ($e.Kind -eq 'Tanium' -or $e.Kind -eq 'Folder') -and -not ($e.Exists -and $e.InstalledBy -match '^(Copy in Windows folder|Tanium)')) { continue }
        $last = $NA; $days = $NA; $names = 'None'
        if ($e.Runs.Count -gt 0) {
            $max = ($e.Runs | Sort-Object LastRun -Descending | Select-Object -First 1).LastRun
            $last = $max.ToString('yyyy-MM-dd'); $days = [int]($today - $max.Date).TotalDays
            $names = (($e.Runs | ForEach-Object { $_.Launcher.ToLowerInvariant().Replace('.exe', '') + $_.Via }) | Sort-Object -Unique) -join ', '
        }
        if ($pfState -ne 'On') { $usage = "Unknown ($pfState)" }
        elseif ($e.Runs.Count -eq 0) { $usage = 'No runs recorded'; $last = 'Never' }
        else {
            if ($e.Kind -eq 'Removed') { $usage = 'Ran before removal' }
            elseif ($e.InstalledOn -ne $NA -and $last -eq $e.InstalledOn) { $usage = 'Ran only on install day' }
            elseif ($e.InstalledOn -ne $NA -and $last -lt $e.InstalledOn) { $usage = 'Last ran before this install' }
            else { $usage = 'Ran after install' }
        }
        [void]$rows.Add((Out-Row @($e.Home, $e.Version, $e.InstalledBy, $e.InstalledOn, $last, $days, $usage, $names, $e.Uninstall)))
    }
    foreach ($r in $pfByKey.Values | Where-Object { -not $_.Owner }) {
        $days = [int]($today - $r.LastRun.Date).TotalDays
        [void]$rows.Add((Out-Row @('Not matched', $NA, 'Not matched', $NA, $r.LastRun.ToString('yyyy-MM-dd'), $days,
            'Ran from a folder that was not found', $r.Launcher.ToLowerInvariant().Replace('.exe', ''), $NA)))
    }
    if ($incomplete) { [void]$rows.Add((Out-Row @('Scan incomplete', $NA, $NA, $NA, $NA, $NA, 'Folder search stopped at the time limit', $NA, $NA))) }

    if ($rows.Count -eq 0) { Out-Row @('None', $NA, $NA, $NA, $NA, $NA, $NA, $NA, $NA) }
    else { $rows | Sort-Object -Unique }
}
catch {
    Out-Row @('Error: Script failed', $NA, $NA, $NA, $NA, $NA, $_.Exception.Message, $NA, $NA)
}
