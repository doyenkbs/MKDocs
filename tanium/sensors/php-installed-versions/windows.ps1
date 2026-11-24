# Tanium sensor: PHP - Installed Versions (Windows)
#
# Sensor settings
#   Script type : PowerShell
#   Parameters  : none
#   Result type : Text, split into columns, delimiter |
#   Columns     : PHP Path | Type | Version | Package | Running
#                 (all Text)
#
# Finds php.exe, php-cgi.exe, phpdbg.exe, and the Apache PHP module (php*apache2*.dll).
# It looks in the usual PHP folders (C:\PHP, Program Files\PHP, IIS Express, XAMPP,
# WampServer, Laragon, C:\tools), in the folders on the system PATH, in the PHP folders
# that IIS uses, and in running processes.
# For each file it returns the PHP version, the installer from the installed programs
# list, and whether a process uses the file now.
# Skips php-win.exe (the same PHP as php.exe, without a console window).
# Pure PowerShell. No Python or Incident Response tools required.
# Read-only: nothing on the endpoint is changed.

$sw       = [Diagnostics.Stopwatch]::StartNew()
$budgetMs = 20000   # keep below the sensor timeout (30 seconds)

$rows    = New-Object 'System.Collections.Generic.List[string]'
$partial = $false

# A | inside a value would split the row into the wrong columns.
function Clean([string]$text) {
    if ($text) { (($text -replace '[\r\n]+', ' ') -replace '\|', '/').Trim() } else { '' }
}

# The kind of PHP file, from its name. Empty means "not a PHP file to report".
function Get-PhpType([string]$path) {
    $name = [IO.Path]::GetFileName($path).ToLowerInvariant()
    if ($name -eq 'php.exe')               { return 'CLI' }
    if ($name -eq 'php-cgi.exe')           { return 'CGI' }
    if ($name -eq 'phpdbg.exe')            { return 'Debugger' }
    if ($name -like 'php*apache2*.dll')    { return 'Apache module' }
    return ''
}

try {
    # In a 32-bit PowerShell on 64-bit Windows, $env:ProgramFiles points to the x86 folder.
    $pf64 = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
    $pf86 = ${env:ProgramFiles(x86)}
    $sd   = $env:SystemDrive
    # Use Sysnative when running as a 32-bit process so System32 is not redirected to SysWOW64.
    $sysDir = if (Test-Path "$env:windir\Sysnative") { "$env:windir\Sysnative" } else { "$env:windir\System32" }

    # --- Find the PHP files ------------------------------------------------------
    $found = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    function Add-PhpFolder([string]$folder) {
        if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) { return }
        foreach ($f in @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -like 'php*' })) {
            if (Get-PhpType $f.FullName) { [void]$found.Add($f.FullName) }
        }
    }

    # 1. Usual PHP folders. A * matches one folder level, for example C:\PHP\8.3.
    $patterns = @(
        "$sd\PHP", "$sd\PHP\*",
        "$pf64\PHP", "$pf64\PHP\*",
        "$pf64\IIS Express\PHP\*",
        "$sd\xampp\php",
        "$sd\wamp64\bin\php\*", "$sd\wamp\bin\php\*",
        "$sd\laragon\bin\php\*",
        "$sd\tools\php*"
    )
    if ($pf86) { $patterns += @("$pf86\PHP", "$pf86\PHP\*", "$pf86\IIS Express\PHP\*") }
    foreach ($pattern in $patterns) {
        foreach ($dir in @(Get-Item -Path $pattern -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer })) {
            Add-PhpFolder $dir.FullName
        }
    }

    # 2. Folders on the system PATH.
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    foreach ($entry in @($machinePath -split ';')) {
        $dir = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"'))
        if ($dir -and (Test-Path -LiteralPath (Join-Path $dir 'php.exe'))) { Add-PhpFolder $dir }
    }

    # 3. PHP folders that IIS uses (FastCGI applications).
    $appHost = Join-Path $sysDir 'inetsrv\config\applicationHost.config'
    if (Test-Path -LiteralPath $appHost) {
        try {
            [xml]$cfg = Get-Content -LiteralPath $appHost -Raw -ErrorAction Stop
            foreach ($app in @($cfg.configuration.'system.webServer'.fastCgi.application)) {
                if ($app -and $app.fullPath) {
                    Add-PhpFolder (Split-Path -Path ([Environment]::ExpandEnvironmentVariables([string]$app.fullPath)) -Parent)
                }
            }
        } catch { }
    }

    # 4. Running processes. This finds PHP in folders that are not in the lists above.
    $procPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $procsRead = $true
    $procs = $null
    try { $procs = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop }
    catch {
        try { $procs = Get-WmiObject -Class Win32_Process -ErrorAction Stop } catch { $procsRead = $false }
    }
    foreach ($p in @($procs)) {
        if (-not $p -or -not $p.ExecutablePath) { continue }
        [void]$procPaths.Add($p.ExecutablePath)
        if (Get-PhpType $p.ExecutablePath) { Add-PhpFolder (Split-Path -Path $p.ExecutablePath -Parent) }
    }

    # --- Installed programs list (both registry views) -------------------------
    $installs = New-Object 'System.Collections.Generic.List[object]'
    $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    foreach ($root in 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                      'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
        $rk = $hklm.OpenSubKey($root)
        if (-not $rk) { continue }
        foreach ($sub in $rk.GetSubKeyNames()) {
            $sk = $rk.OpenSubKey($sub)
            if (-not $sk) { continue }
            $loc  = ([string]$sk.GetValue('InstallLocation')).Trim().Trim('"').TrimEnd('\')
            $name = ([string]$sk.GetValue('DisplayName')).Trim()
            $ver  = ([string]$sk.GetValue('DisplayVersion')).Trim()
            $sk.Close()
            # A location such as C:\ or C:\Program Files would match every folder on the drive.
            if (-not $loc -or -not $name) { continue }
            if (($loc -split '\\').Count -lt 2) { continue }
            if (@($pf64, $pf86, $env:windir) -contains $loc) { continue }
            $label = if ($ver -and $name -notlike "*$ver*") { "$name $ver" } else { $name }
            $installs.Add([pscustomobject]@{ Location = $loc; Label = $label })
        }
        $rk.Close()
    }
    $hklm.Close()

    # The installer whose folder holds this file (the deepest match wins).
    function Get-Installer([string]$folder) {
        $best = $null
        foreach ($i in $installs) {
            if ($folder -ieq $i.Location -or $folder.StartsWith($i.Location + '\', [StringComparison]::OrdinalIgnoreCase)) {
                if (-not $best -or $i.Location.Length -gt $best.Location.Length) { $best = $i }
            }
        }
        if ($best) { return $best.Label }
        return 'No package'
    }

    # Is an Apache process using this PHP module now?
    function Get-ModuleState([string]$dll) {
        $state = 'No'
        foreach ($p in [Diagnostics.Process]::GetProcessesByName('httpd')) {
            try {
                foreach ($m in $p.Modules) { if ($m.FileName -ieq $dll) { return 'Yes' } }
            } catch { $state = 'Unknown' }   # a 32-bit process cannot read a 64-bit process
        }
        return $state
    }

    # --- One row for each PHP file ------------------------------------------------
    foreach ($file in ($found | Sort-Object)) {
        if ($sw.ElapsedMilliseconds -gt $budgetMs) { $partial = $true; break }

        $type = Get-PhpType $file

        $ver = 'Unknown'
        try {
            $vi = (Get-Item -LiteralPath $file -ErrorAction Stop).VersionInfo
            foreach ($v in @($vi.ProductVersion, $vi.FileVersion)) {
                if ($v -match '\d+\.\d+\.\d+') { $ver = $Matches[0]; break }
            }
        } catch { }

        $pkg = Get-Installer (Split-Path -Path $file -Parent)

        if ($type -eq 'Apache module') { $run = Get-ModuleState $file }
        elseif (-not $procsRead)       { $run = 'Unknown' }
        elseif ($procPaths.Contains($file)) { $run = 'Yes' }
        else                           { $run = 'No' }

        $rows.Add(('{0}|{1}|{2}|{3}|{4}' -f (Clean $file), $type, (Clean $ver), (Clean $pkg), $run))
    }
} catch {
    # The reasons come from a fixed list, so the results can be filtered.
    Write-Output 'Error: Unexpected failure||||'
    exit 0
}

# --- Output: never empty ------------------------------------------------------
#   None            no PHP found
#   Error: <reason> something failed
if ($rows.Count) { $rows | Sort-Object -Unique }
if ($partial) { Write-Output 'Error: Time limit reached, results incomplete||||' }
if ($rows.Count -eq 0 -and -not $partial) { Write-Output 'None||||' }
