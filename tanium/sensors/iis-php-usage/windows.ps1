# Tanium sensor: IIS - PHP Usage
# Returns one row per IIS site:
# Site|State|PHP Folder|PHP Version|PHP Files|PHP Requests|Last PHP Request
#
# PHP Folder and PHP Version come from the *.php handler that applies to the site
# (site web.config first, then a <location> section in applicationHost.config, then
# server level) and the file version of the php-cgi.exe it points to.
# PHP Requests counts W3C log lines whose cs-uri-stem is a .php URL in the last
# ||Days|| days (default 7, 1 to 30). Last PHP Request is in UTC, as IIS logs it.
#
# Status rows:
#   Not Applicable   IIS is not installed
#   None             IIS is installed but has no sites
#   Error: <reason>  The IIS configuration could not be read
# Counts that hit the time limit end with " (partial)".

$sw       = [Diagnostics.Stopwatch]::StartNew()
$budgetMs = 45000
$colCount = 7

function Out-Status([string]$Status) { $Status + ('|N/A' * ($colCount - 1)) }
function Clean([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'None' }
    return ($Value -replace '[\|\r\n]', '/').Trim()
}

# --- Parameter -----------------------------------------------------------------
$daysRaw = [System.Uri]::UnescapeDataString('||Days||').Trim()
$days = 7
if ($daysRaw -match '^\d+$') { $days = [int]$daysRaw }
if ($days -lt 1)  { $days = 1 }
if ($days -gt 30) { $days = 30 }
$sinceUtc  = [DateTime]::UtcNow.Date.AddDays(-($days - 1))
$sinceDate = $sinceUtc.ToString('yyyy-MM-dd')

# --- IIS config ------------------------------------------------------------------
# Use Sysnative when running as a 32-bit process so System32 is not redirected to SysWOW64.
$sysDir  = if (Test-Path "$env:windir\Sysnative") { "$env:windir\Sysnative" } else { "$env:windir\System32" }
$appHost = Join-Path $sysDir 'inetsrv\config\applicationHost.config'
$appCmd  = Join-Path $sysDir 'inetsrv\appcmd.exe'

if (-not (Test-Path -LiteralPath $appHost)) { Out-Status 'Not Applicable'; exit 0 }

try {
    [xml]$cfg = Get-Content -LiteralPath $appHost -Raw -ErrorAction Stop
} catch {
    Out-Status 'Error: cannot read applicationHost.config'
    exit 0
}

$sitesNode = $cfg.configuration.'system.applicationHost'.sites
$siteList  = @($sitesNode.site | Where-Object { $_ })
if ($siteList.Count -eq 0) { Out-Status 'None'; exit 0 }

# Site state is not stored in applicationHost.config, so ask appcmd.
$siteState = @{}
try {
    [xml]$sx = (& $appCmd list site /xml 2>$null) -join "`n"
    foreach ($s in @($sx.appcmd.SITE)) {
        if ($s) { $siteState[[string]$s.'SITE.NAME'] = [string]$s.state }
    }
} catch { }

$logRoot = [string]$sitesNode.siteDefaults.logFile.directory
if ([string]::IsNullOrWhiteSpace($logRoot)) { $logRoot = '%SystemDrive%\inetpub\logs\LogFiles' }

# --- Helpers -----------------------------------------------------------------------
function Get-PhpProcessor($HandlersNode) {
    if (-not $HandlersNode) { return $null }
    foreach ($h in @($HandlersNode.add)) {
        if ($h -and ([string]$h.path -ieq '*.php') -and $h.scriptProcessor) {
            return ([string]$h.scriptProcessor -split '\|')[0].Trim()
        }
    }
    return $null
}

function Get-PhpVersion([string]$Exe) {
    $e = [Environment]::ExpandEnvironmentVariables($Exe)
    if (-not (Test-Path -LiteralPath $e)) { return 'Missing' }
    $v = (Get-Item -LiteralPath $e).VersionInfo.FileVersion
    if ([string]::IsNullOrWhiteSpace($v)) { return 'Unknown' }
    return $v.Trim()
}

function Get-PhpFileCount([string[]]$Roots) {
    $count = 0
    $stack = New-Object System.Collections.Generic.Stack[string]
    foreach ($r in $Roots) { if (Test-Path -LiteralPath $r) { $stack.Push($r) } }
    while ($stack.Count -gt 0) {
        if ($sw.ElapsedMilliseconds -gt $budgetMs) { return "$count (partial)" }
        $d = $stack.Pop()
        try { foreach ($f in [IO.Directory]::EnumerateFiles($d, '*.php')) { $count++ } } catch { }
        try {
            foreach ($sub in ([IO.DirectoryInfo]$d).EnumerateDirectories()) {
                if (-not ($sub.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $stack.Push($sub.FullName) }
            }
        } catch { }
    }
    return "$count"
}

function Get-PhpRequests([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { return @('No logs', 'No logs') }
    $files = @(Get-ChildItem -LiteralPath $Dir -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -ge $sinceUtc } | Sort-Object Name)
    if ($files.Count -eq 0) { return @('0', 'None') }

    $phpRx   = [regex]'(?i)\.php($|/)'
    $hits    = 0
    $last    = 'None'
    $partial = $false
    $n       = 0

    foreach ($f in $files) {
        $iStem = -1; $iDate = -1; $iTime = -1
        $fs = $null; $sr = $null
        try {
            # IIS keeps today's log open for writing, so open it with shared read/write.
            $fs = New-Object IO.FileStream($f.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            $sr = New-Object IO.StreamReader($fs)
            while ($null -ne ($line = $sr.ReadLine())) {
                $n++
                if (($n % 5000) -eq 0 -and $sw.ElapsedMilliseconds -gt $budgetMs) { $partial = $true; break }
                if ($line.StartsWith('#')) {
                    if ($line.StartsWith('#Fields:')) {
                        $fields = $line.Substring(8).Trim() -split ' '
                        $iStem = [array]::IndexOf($fields, 'cs-uri-stem')
                        $iDate = [array]::IndexOf($fields, 'date')
                        $iTime = [array]::IndexOf($fields, 'time')
                    }
                    continue
                }
                if ($iStem -lt 0) { continue }
                $p = $line.Split(' ')
                if ($p.Count -le $iStem) { continue }
                if ($iDate -ge 0 -and $p.Count -gt $iDate -and $p[$iDate] -lt $sinceDate) { continue }
                if ($phpRx.IsMatch($p[$iStem])) {
                    $hits++
                    $when = if ($iDate -ge 0 -and $iTime -ge 0 -and $p.Count -gt $iTime) { "$($p[$iDate]) $($p[$iTime]) UTC " } else { '' }
                    $last = $when + $p[$iStem]
                }
            }
        } catch { }
        finally {
            if ($sr) { $sr.Dispose() } elseif ($fs) { $fs.Dispose() }
        }
        if ($partial) { break }
    }

    $count = if ($partial) { "$hits (partial)" } else { "$hits" }
    return @($count, $last)
}

# --- Handler mappings ----------------------------------------------------------------
$serverProc = Get-PhpProcessor $cfg.configuration.'system.webServer'.handlers
$locProc = @{}
foreach ($loc in @($cfg.configuration.location)) {
    if ($loc -and $loc.'system.webServer') {
        $p = Get-PhpProcessor $loc.'system.webServer'.handlers
        if ($p) { $locProc[([string]$loc.path).TrimEnd('/')] = $p }
    }
}

# --- One row per site ----------------------------------------------------------------
try {
    foreach ($site in $siteList) {
        $name  = [string]$site.name
        $state = if ($siteState.ContainsKey($name)) { $siteState[$name] } else { 'Unknown' }

        # Physical paths of every virtual directory in the site
        $paths = @($site.application | ForEach-Object { $_.virtualDirectory } | Where-Object { $_ } |
            ForEach-Object { [Environment]::ExpandEnvironmentVariables([string]$_.physicalPath) } |
            Where-Object { $_ } | Select-Object -Unique)

        # Root virtual directory of the root application, for the site web.config
        $rootApp  = @($site.application | Where-Object { $_ -and [string]$_.path -eq '/' }) | Select-Object -First 1
        $rootVdir = if ($rootApp) { @($rootApp.virtualDirectory | Where-Object { $_ -and [string]$_.path -eq '/' }) | Select-Object -First 1 } else { $null }
        $rootPath = if ($rootVdir) { [Environment]::ExpandEnvironmentVariables([string]$rootVdir.physicalPath) } else { $null }

        # Which php-cgi.exe handles *.php for this site
        $proc = $null
        if ($rootPath) {
            $wc = Join-Path $rootPath 'web.config'
            if (Test-Path -LiteralPath $wc) {
                try {
                    [xml]$wx = Get-Content -LiteralPath $wc -Raw -ErrorAction Stop
                    $proc = Get-PhpProcessor $wx.configuration.'system.webServer'.handlers
                } catch { }
            }
        }
        if (-not $proc -and $locProc.ContainsKey($name)) { $proc = $locProc[$name] }
        if (-not $proc) { $proc = $serverProc }

        if ($proc) {
            $phpFolder  = Split-Path -Path ([Environment]::ExpandEnvironmentVariables($proc)) -Parent
            $phpVersion = Get-PhpVersion $proc
        } else {
            $phpFolder  = 'None'
            $phpVersion = 'None'
        }

        $phpFiles = Get-PhpFileCount $paths

        $siteLogRoot = [string]$site.logFile.directory
        if ([string]::IsNullOrWhiteSpace($siteLogRoot)) { $siteLogRoot = $logRoot }
        $siteLogDir = Join-Path ([Environment]::ExpandEnvironmentVariables($siteLogRoot)) "W3SVC$($site.id)"
        $req = Get-PhpRequests $siteLogDir

        (@($name, $state, $phpFolder, $phpVersion, $phpFiles, $req[0], $req[1]) | ForEach-Object { Clean "$_" }) -join '|'
    }
} catch {
    Out-Status ('Error: ' + (Clean $_.Exception.Message))
}
exit 0
