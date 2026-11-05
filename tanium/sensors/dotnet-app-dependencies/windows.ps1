<#
.SYNOPSIS
    Tanium sensor: .NET App Dependencies (Windows)

.DESCRIPTION
    Lists the applications on this machine that depend on a .NET (Core / 5+) shared
    runtime, plus self-contained apps that carry their own copy of the runtime.

    Each app declares what it needs in <app>.runtimeconfig.json. The sensor reads that
    file, then works out which installed runtime the app would actually load, using the
    same roll-forward rules the .NET host uses. That answers two questions:
      1. If I remove runtime X, which apps stop starting?
      2. Which apps bundle their own runtime, so patching the shared runtime will not fix them?

    .NET Framework is not covered. It is an OS component and cannot be removed per app.

    Where it looks (in priority order, so a time-out still covers the important places):
      IIS site and application folders (applicationHost.config)
      Windows service executables (registry ImagePath, including dotnet.exe app.dll services)
      Program Files, Program Files (x86), ProgramData (except ProgramData\Microsoft), C:\inetpub
      Each user profile's AppData\Local\Programs and .dotnet\tools
      Other fixed drives (shallow scan)

    Read-only. No network calls. No WMI. Safe under 32-bit or 64-bit PowerShell.

    Output, one row per app per framework, pipe-delimited:
      Framework|Requested|RollForward|ResolvesTo|Deployment|Arch|Category|Context|AppPath

    Deployment values:
      FrameworkDependent  loads a shared runtime from the machine's dotnet install
      PrivateRuntime      loads a runtime the product ships in its own folder (Context shows where)
      SelfContained       the runtime is bundled with the app itself

    ResolvesTo = "None installed" means neither the shared install nor a private runtime in the
    app's folder tree can satisfy the app: it will fail to start today.
    Visual Studio install trees are skipped (the VS Installer services them). Other developer
    tools (.nuget, .vscode, JetBrains, .dotnet\tools) are collapsed to one row per product.
#>

$ErrorActionPreference = 'SilentlyContinue'

# ---- Tunables ---------------------------------------------------------------
$TimeBudgetSec   = 40     # stop scanning after this many seconds and report a partial result
$MaxDepth        = 5      # folder depth under Program Files, ProgramData and user Programs folders
                          # (.NET apps keep runtimeconfig.json next to the exe, usually 2 to 4 levels down)
$WebDepth        = 8      # folder depth under IIS site folders
$ExtraDriveDepth = 4      # folder depth for non-system fixed drives (D:\, E:\ ...)
$MaxDirsPerRoot  = 15000  # stop one huge folder tree (agent queues, caches) from using the whole budget
# -----------------------------------------------------------------------------

$sw         = [System.Diagnostics.Stopwatch]::StartNew()
$cmp        = [System.StringComparer]::OrdinalIgnoreCase
$incomplete = New-Object 'System.Collections.Generic.HashSet[string]' ($cmp)

# Real paths even when Tanium runs the sensor in 32-bit PowerShell
$pf64  = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$pf86  = ${env:ProgramFiles(x86)}
$sys32 = if (Test-Path "$env:windir\Sysnative") { "$env:windir\Sysnative" } else { "$env:windir\System32" }
$osArch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$osArch = switch ($osArch) { 'AMD64' { 'x64' } 'ARM64' { 'arm64' } default { 'x86' } }

function Get-RegValue([string]$subKey, [string]$name, [Microsoft.Win32.RegistryView]$view) {
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
        $key  = $base.OpenSubKey($subKey)
        if ($key) { $v = $key.GetValue($name); $key.Close(); return $v }
    } catch {}
    return $null
}

function ConvertTo-Ver([string]$s) {
    if ($s -match '^(\d+)\.(\d+)\.(\d+)(-.+)?$') {
        return New-Object psobject -Property @{
            V    = [version]("{0}.{1}.{2}" -f $matches[1], $matches[2], $matches[3])
            Pre  = [bool]$matches[4]
            Text = $s
        }
    }
    return $null
}

# ---- Installed shared runtimes ---------------------------------------------
# Key: "<arch>|<framework name>"  Value: list of version objects
$installed   = @{}
$dotnetRoots = New-Object 'System.Collections.Generic.HashSet[string]' ($cmp)
$archList    = @('x64', 'x86')
if ($osArch -eq 'arm64') { $archList = @('arm64', 'x64', 'x86') }

foreach ($arch in $archList) {
    $root = Get-RegValue "SOFTWARE\dotnet\Setup\InstalledVersions\$arch" 'InstallLocation' ([Microsoft.Win32.RegistryView]::Registry32)
    if (-not $root) {
        $root = switch ($arch) {
            'x86'   { if ($pf86) { Join-Path $pf86 'dotnet' } }
            'x64'   { if ($osArch -eq 'arm64') { Join-Path $pf64 'dotnet\x64' } else { Join-Path $pf64 'dotnet' } }
            'arm64' { Join-Path $pf64 'dotnet' }
        }
    }
    if (-not $root -or -not [System.IO.Directory]::Exists($root)) { continue }
    $root = $root.TrimEnd('\')
    [void]$dotnetRoots.Add($root)
    $shared = Join-Path $root 'shared'
    if (-not [System.IO.Directory]::Exists($shared)) { continue }
    foreach ($fwDir in [System.IO.Directory]::GetDirectories($shared)) {
        $fwName = [System.IO.Path]::GetFileName($fwDir)
        foreach ($verDir in [System.IO.Directory]::GetDirectories($fwDir)) {
            # Skip folders left behind by an uninstall
            if ([System.IO.Directory]::GetFiles($verDir, '*.dll').Length -eq 0) { continue }
            $v = ConvertTo-Ver ([System.IO.Path]::GetFileName($verDir))
            if (-not $v) { continue }
            $k = "$arch|$fwName"
            if (-not $installed.ContainsKey($k)) { $installed[$k] = New-Object System.Collections.ArrayList }
            [void]$installed[$k].Add($v)
        }
    }
}

# ---- Roll-forward (mirrors the .NET host rules) ----------------------------
function Select-MinorRoll($ge, $r, [bool]$allowMajor) {
    $pool = @($ge | Where-Object { $_.V.Major -eq $r.Major })
    if ($pool.Count -eq 0 -and $allowMajor) {
        $higher = @($ge | Where-Object { $_.V.Major -gt $r.Major })
        if ($higher.Count -gt 0) {
            $m    = ($higher | Sort-Object { $_.V } | Select-Object -First 1).V.Major
            $pool = @($higher | Where-Object { $_.V.Major -eq $m })
        }
    }
    if ($pool.Count -eq 0) { return $null }
    $sameMinor = @($pool | Where-Object { $_.V.Major -eq $r.Major -and $_.V.Minor -eq $r.Minor })
    if ($sameMinor.Count -gt 0) { return ($sameMinor | Sort-Object { $_.V } -Descending | Select-Object -First 1) }
    $lowMinor = ($pool | Sort-Object { $_.V } | Select-Object -First 1).V.Minor
    return ($pool | Where-Object { $_.V.Minor -eq $lowMinor } | Sort-Object { $_.V } -Descending | Select-Object -First 1)
}

function Resolve-Framework([string]$arch, [string]$fwName, $req, [string]$rollForward) {
    $cands = @()
    if ($installed.ContainsKey("$arch|$fwName")) { $cands = @($installed["$arch|$fwName"]) }
    $pick = Select-Candidate $cands $req $rollForward
    if ($pick) { return $pick.Text }
    return $null
}

function Select-Candidate($cands, $req, [string]$rollForward) {
    # Release builds are preferred; previews only count if the app asked for a preview
    $cands = @($cands | Where-Object { $req.Pre -or -not $_.Pre })
    $r  = $req.V
    $ge = @($cands | Where-Object { $_.V -ge $r })
    $pick = switch ($rollForward.ToLowerInvariant()) {
        'disable'     { $cands | Where-Object { $_.Text -eq $req.Text } | Select-Object -First 1 }
        'latestpatch' { $ge | Where-Object { $_.V.Major -eq $r.Major -and $_.V.Minor -eq $r.Minor } | Sort-Object { $_.V } -Descending | Select-Object -First 1 }
        'latestminor' { $ge | Where-Object { $_.V.Major -eq $r.Major } | Sort-Object { $_.V } -Descending | Select-Object -First 1 }
        'latestmajor' { $ge | Sort-Object { $_.V } -Descending | Select-Object -First 1 }
        'major'       { Select-MinorRoll $ge $r $true }
        default       { Select-MinorRoll $ge $r $false }   # Minor is the .NET default
    }
    return $pick
}

# ---- Private runtimes shipped inside an app's own folder tree ----------------
# Some products (SSMS 21 and other Visual Studio shell apps, for example) carry a private
# .NET runtime, laid out like a normal dotnet folder (host\fxr + shared\<framework>\<version>),
# and point their own processes at it. Only checked when the shared runtime cannot satisfy
# the app, so it never hides a real dependency on the shared install.
$privateByDir = @{}
function Test-DotNetRoot([string]$d) {
    [System.IO.Directory]::Exists((Join-Path $d 'host\fxr')) -and [System.IO.Directory]::Exists((Join-Path $d 'shared'))
}
function Get-PrivateRoots([string]$appDir) {
    if ($privateByDir.ContainsKey($appDir)) { return $privateByDir[$appDir] }
    $roots = New-Object System.Collections.ArrayList
    $a = $appDir
    for ($level = 0; $level -le 5 -and $a; $level++) {
        if ($stopDirs.Contains($a.TrimEnd('\'))) { break }     # never climb into Program Files itself
        if (Test-DotNetRoot $a) { [void]$roots.Add($a) }
        $dn = Join-Path $a 'dotnet'
        if ([System.IO.Directory]::Exists($dn)) {
            # Look a few levels inside <ancestor>\dotnet for a runtime root (e.g. dotnet\net8.0\runtime)
            $q = New-Object System.Collections.Queue
            $q.Enqueue(@($dn, 0))
            while ($q.Count -gt 0) {
                $it = $q.Dequeue(); $d = $it[0]
                if (Test-DotNetRoot $d) { if (-not $roots.Contains($d)) { [void]$roots.Add($d) }; continue }
                if ($it[1] -ge 3) { continue }
                try { foreach ($s in [System.IO.Directory]::GetDirectories($d)) { $q.Enqueue(@($s, ($it[1] + 1))) } } catch {}
            }
        }
        $a = [System.IO.Path]::GetDirectoryName($a)
    }
    $privateByDir[$appDir] = $roots
    return $roots
}
function Get-RootVersions([string]$root, [string]$fwName) {
    $list = @()
    $fwDir = Join-Path $root "shared\$fwName"
    if (-not [System.IO.Directory]::Exists($fwDir)) { return $list }
    foreach ($verDir in [System.IO.Directory]::GetDirectories($fwDir)) {
        if ([System.IO.Directory]::GetFiles($verDir, '*.dll').Length -eq 0) { continue }
        $v = ConvertTo-Ver ([System.IO.Path]::GetFileName($verDir))
        if ($v) { $list += $v }
    }
    return $list
}

# ---- App architecture from the apphost .exe PE header ----------------------
function Get-PEArch([string]$path) {
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        $br = New-Object System.IO.BinaryReader($fs)
        if ($br.ReadUInt16() -ne 0x5A4D) { return $null }      # 'MZ'
        $fs.Position = 0x3C
        $pe = $br.ReadInt32()
        if ($pe -le 0 -or $pe -gt ($fs.Length - 6)) { return $null }
        $fs.Position = $pe + 4
        switch ($br.ReadUInt16()) { 0x8664 { 'x64' } 0x014C { 'x86' } 0xAA64 { 'arm64' } default { $null } }
    } catch { $null } finally { if ($fs) { $fs.Close() } }
}

# ---- Context: IIS sites and Windows services -------------------------------
$iisPaths = @{}   # physical path (with trailing \) -> "IIS: Site/app"
$appHost  = Join-Path $sys32 'inetsrv\config\applicationHost.config'
if (Test-Path $appHost) {
    try {
        [xml]$x = [System.IO.File]::ReadAllText($appHost)
        foreach ($site in $x.configuration.'system.applicationHost'.sites.site) {
            foreach ($app in @($site.application)) {
                foreach ($vd in @($app.virtualDirectory)) {
                    if (-not $vd.physicalPath) { continue }
                    $p = [Environment]::ExpandEnvironmentVariables($vd.physicalPath).TrimEnd('\') + '\'
                    $label = "IIS: $($site.name)$($app.path)".TrimEnd('/')
                    if (-not $iisPaths.ContainsKey($p)) { $iisPaths[$p] = $label }
                }
            }
        }
    } catch {}
}
$iisKeys = @($iisPaths.Keys | Sort-Object { $_.Length } -Descending)

$svcDirs = New-Object 'System.Collections.Generic.Dictionary[string,string]' ($cmp)
try {
    $svcRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Services')
    foreach ($svc in $svcRoot.GetSubKeyNames()) {
        $k = $svcRoot.OpenSubKey($svc)
        if (-not $k) { continue }
        $img = [string]$k.GetValue('ImagePath', $null, 'DoNotExpandEnvironmentNames')
        $k.Close()
        if (-not $img) { continue }
        $img = [Environment]::ExpandEnvironmentVariables($img)
        $exe = $null
        if ($img -match '^\s*"([^"]+)"') { $exe = $matches[1] }
        elseif ($img -match '^\s*(.+?\.exe)(\s|$)') { $exe = $matches[1] }
        if (-not $exe -or $exe -notmatch '^[A-Za-z]:\\') { continue }
        # Service hosted by dotnet.exe: the app is the .dll argument
        if ([System.IO.Path]::GetFileName($exe) -ieq 'dotnet.exe' -and $img -match '"?([A-Za-z]:\\[^"]+?\.dll)"?') { $exe = $matches[1] }
        if ($exe.StartsWith($env:windir, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $dir = [System.IO.Path]::GetDirectoryName($exe)
        if (-not $dir) { continue }
        if ($svcDirs.ContainsKey($dir)) { $svcDirs[$dir] = $svcDirs[$dir] + ',' + $svc } else { $svcDirs[$dir] = $svc }
    }
    $svcRoot.Close()
} catch {}

# ---- Filesystem walk --------------------------------------------------------
$visited   = New-Object 'System.Collections.Generic.HashSet[string]' ($cmp)
$found     = New-Object 'System.Collections.Generic.HashSet[string]' ($cmp)
$skipPaths = New-Object 'System.Collections.Generic.HashSet[string]' ($cmp)
$stopDirs  = New-Object 'System.Collections.Generic.HashSet[string]' ($cmp)   # private-runtime search never climbs past these
foreach ($p in @($pf64, $pf86, $env:ProgramData, $env:SystemDrive)) { if ($p) { [void]$stopDirs.Add($p.TrimEnd('\')) } }
foreach ($p in @($env:windir, (Join-Path $pf64 'WindowsApps'), (Join-Path $env:ProgramData 'Microsoft')) + @($dotnetRoots)) { if ($p) { [void]$skipPaths.Add($p.TrimEnd('\')) } }
# Visual Studio trees hold hundreds of test-host templates (one per .NET version, never run as
# apps) and are serviced by the VS Installer, so they are skipped: noise, and most of the scan time.
$skipNames = @('$recycle.bin', 'system volume information', 'winsxs', 'node_modules', '.git', 'package cache',
               'microsoft visual studio', 'visualstudio', 'windows defender', 'windows defender advanced threat protection')

function Invoke-Scan([string]$root, [int]$maxDepth) {
    if (-not $root -or -not [System.IO.Directory]::Exists($root)) { return }
    # Keep "D:\" intact; "D:" would mean the current folder on drive D
    $start = if ($root.Length -gt 3) { $root.TrimEnd('\') } else { $root }
    $stack = New-Object System.Collections.Stack
    $stack.Push(@((New-Object System.IO.DirectoryInfo $start), 0))
    $count = 0
    while ($stack.Count -gt 0) {
        if ($sw.Elapsed.TotalSeconds -gt $TimeBudgetSec -or $count -ge $MaxDirsPerRoot) { [void]$incomplete.Add($start); return }
        $item = $stack.Pop(); $di = $item[0]; $depth = $item[1]
        $dir = if ($di.FullName.Length -gt 3) { $di.FullName.TrimEnd('\') } else { $di.FullName }
        if ($skipPaths.Contains($dir)) { continue }
        if (-not $visited.Add($dir)) { continue }
        $count++
        try {
            foreach ($f in [System.IO.Directory]::GetFiles($dir, '*.runtimeconfig.json')) {
                if (-not $f.EndsWith('.runtimeconfig.json', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                if ([System.IO.Path]::GetFileName($f) -like 'testhost*') { continue }   # test runner templates
                [void]$found.Add($f)
            }
        } catch {}
        if ($depth -ge $maxDepth) { continue }
        $subs = $null
        try { $subs = $di.GetDirectories() } catch { continue }   # DirectoryInfo carries attributes: no extra call per folder
        foreach ($s in $subs) {
            if ($s.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            if ($skipNames -contains $s.Name.ToLowerInvariant()) { continue }
            $stack.Push(@($s, ($depth + 1)))
        }
    }
}

# Highest-value places first
foreach ($p in $iisKeys)       { Invoke-Scan $p $WebDepth }
foreach ($p in $svcDirs.Keys)  { Invoke-Scan $p 2 }
foreach ($p in @($pf64, $pf86, $env:ProgramData, "$env:SystemDrive\inetpub")) { Invoke-Scan $p $MaxDepth }

try {
    $pl = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList')
    foreach ($sid in $pl.GetSubKeyNames()) {
        if ($sid -notmatch '^S-1-5-21-') { continue }
        $k = $pl.OpenSubKey($sid); $prof = [string]$k.GetValue('ProfileImagePath'); $k.Close()
        if (-not $prof) { continue }
        $prof = [Environment]::ExpandEnvironmentVariables($prof)
        Invoke-Scan (Join-Path $prof 'AppData\Local\Programs') $MaxDepth
        Invoke-Scan (Join-Path $prof '.dotnet\tools') $MaxDepth
    }
    $pl.Close()
} catch {}

foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
    if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady) { continue }
    if ($d.Name.TrimEnd('\') -ieq $env:SystemDrive) { continue }
    Invoke-Scan $d.RootDirectory.FullName $ExtraDriveDepth
}

# ---- Build rows -------------------------------------------------------------
$devRegex = '\\Microsoft Visual Studio\\|\\ServiceHub\\|\\BuildTools\\|\\testhost|\\\.nuget\\|\\\.vscode\\|\\\.dotnet\\tools\\|\\JetBrains\\|\\Microsoft SDKs\\'

function Get-Context([string]$dir, [string]$file) {
    $d = $dir.TrimEnd('\') + '\'
    foreach ($k in $iisKeys) { if ($d.StartsWith($k, [System.StringComparison]::OrdinalIgnoreCase)) { return @('IIS', $iisPaths[$k], $file) } }
    if ($svcDirs.ContainsKey($dir.TrimEnd('\'))) { return @('Service', ('Service: ' + $svcDirs[$dir.TrimEnd('\')]), $file) }
    if ($file -match $devRegex) {
        # Collapse developer tools to one row per product
        $rootPath = $dir
        if     ($file -match '^(.*?\\Microsoft Visual Studio\\[^\\]+\\[^\\]+)') { $rootPath = $matches[1] }
        elseif ($file -match '^(.*?\\JetBrains\\[^\\]+)')                      { $rootPath = $matches[1] }
        elseif ($file -match '^(.*?\\\.(nuget|vscode))\\')                     { $rootPath = $matches[1] }
        elseif ($file -match '^(.*?\\\.dotnet\\tools)\\')                      { $rootPath = $matches[1] }
        return @('DevTool', '', $rootPath)
    }
    return @('App', '', $file)
}

$rows = New-Object 'System.Collections.Generic.HashSet[string]' ($cmp)
foreach ($file in $found) {
    $dir     = [System.IO.Path]::GetDirectoryName($file)
    $ctx     = Get-Context $dir $file
    $appName = [System.IO.Path]::GetFileName($file) -replace '\.runtimeconfig\.json$', ''
    $exe     = Join-Path $dir ($appName + '.exe')
    $arch    = $null
    if ([System.IO.File]::Exists($exe)) { $arch = Get-PEArch $exe }
    $archLabel = if ($arch) { $arch } else { "$osArch (dotnet.exe)" }
    if (-not $arch) { $arch = $osArch }

    $ro = $null
    try { $ro = ([System.IO.File]::ReadAllText($file) | ConvertFrom-Json).runtimeOptions } catch {}
    if (-not $ro) {
        [void]$rows.Add(('Unreadable runtimeconfig|||||{0}|{1}|{2}|{3}' -f $archLabel, $ctx[0], $ctx[1], $ctx[2]))
        continue
    }

    $appRoll = 'Minor'
    if ($ro.rollForward) { $appRoll = [string]$ro.rollForward }
    elseif ($null -ne $ro.rollForwardOnNoCandidateFx) {
        $appRoll = switch ([int]$ro.rollForwardOnNoCandidateFx) { 0 { 'LatestPatch' } 2 { 'Major' } default { 'Minor' } }
    }

    if ($ro.includedFrameworks) {
        foreach ($fw in @($ro.includedFrameworks)) {
            [void]$rows.Add(('{0}|{1}|n/a|{1} (bundled)|SelfContained|{2}|{3}|{4}|{5}' -f $fw.name, $fw.version, $archLabel, $ctx[0], $ctx[1], $ctx[2]))
        }
        continue
    }

    $fws = @()
    if ($ro.frameworks) { $fws = @($ro.frameworks) } elseif ($ro.framework) { $fws = @($ro.framework) }
    foreach ($fw in $fws) {
        if (-not $fw.name -or -not $fw.version) { continue }
        $req  = ConvertTo-Ver ([string]$fw.version)
        $roll = if ($fw.rollForward) { [string]$fw.rollForward } else { $appRoll }
        $deploy  = 'FrameworkDependent'
        $context = $ctx[1]
        if (-not $req) {
            $res = 'Unparsed version'
        } else {
            $res = Resolve-Framework $arch $fw.name $req $roll
            if (-not $res) {
                # Shared runtime cannot satisfy it: check for a runtime the app ships itself
                foreach ($pr in (Get-PrivateRoots $dir)) {
                    $pick = Select-Candidate (Get-RootVersions $pr $fw.name) $req $roll
                    if ($pick) {
                        $res     = "$($pick.Text) (private)"
                        $deploy  = 'PrivateRuntime'
                        $context = (@($ctx[1], "Runtime: $pr") | Where-Object { $_ }) -join '; '
                        break
                    }
                }
                if (-not $res) { $res = 'None installed' }
            }
        }
        [void]$rows.Add(('{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}' -f $fw.name, $fw.version, $roll, $res, $deploy, $archLabel, $ctx[0], $context, $ctx[2]))
    }
}

if ($incomplete.Count -gt 0) {
    [void]$rows.Add(('Scan incomplete||||||||Not fully scanned: {0} ({1} folders, {2:N0}s)' -f (($incomplete | Sort-Object) -join '; '), $visited.Count, $sw.Elapsed.TotalSeconds))
}
if ($rows.Count -eq 0) {
    Write-Output 'None found||||||||'
} else {
    $rows | Sort-Object | ForEach-Object { Write-Output $_ }
}
