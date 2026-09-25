# Java - Runtime Inventory - Dependencies (Windows)
# Returns EVERY Java runtime, one row per runtime per dependency:
# Java Path|Java Line|Version|Version String|Type|Vendor|Installed By|Uninstall Command|Used By Type|Used By
# No version list is built in; decide what is vulnerable with your scanner or Interact filters.
# Command lines are never returned; only the jar name or main class.
$ErrorActionPreference = 'SilentlyContinue'
$ScanSeconds    = 35
$ExtraScanRoots = @() # e.g. @('D:\Apps')
$sw = [Diagnostics.Stopwatch]::StartNew()
$script:ScanTruncated = $false
function Format-Field([object]$s) {
 if ($null -eq $s) { return '' }
 return ((([string]$s) -replace '[\r\n\t]+', ' ') -replace '\|', '/').Trim()
}
function Norm([string]$p) {
 if ([string]::IsNullOrWhiteSpace($p)) { return $null }
 $p = [Environment]::ExpandEnvironmentVariables($p.Trim().Trim('"').Trim())
 if ($p -notmatch '^[A-Za-z]:\\|^\\\\') { return $null }
 try { $p = [IO.Path]::GetFullPath($p) } catch { return $null }
 return $p.TrimEnd('\')
}
function Test-JavaHome([string]$h) {
 return ([IO.File]::Exists("$h\bin\java.exe") -or [IO.File]::Exists("$h\bin\server\jvm.dll") -or [IO.File]::Exists("$h\bin\client\jvm.dll"))
}
function Get-HomeFromFile([string]$file) {
 $f = Norm $file
 if (-not $f) { return $null }
 $d = [IO.Path]::GetDirectoryName($f)
 if ([IO.Path]::GetFileName($d) -imatch '^(server|client)$') { $d = [IO.Path]::GetDirectoryName($d) }
 if ([IO.Path]::GetFileName($d) -ieq 'bin') { return [IO.Path]::GetDirectoryName($d) }
 return $null
}
function Resolve-Link([string]$f) {
 try {
  $i = Get-Item -LiteralPath $f -Force -ErrorAction Stop
  if ($i.LinkType -and $i.Target) { return [string](@($i.Target)[0]) }
 } catch {}
 return $f
}
function Open-Key($hive, $view, [string]$path) {
 try { return [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view).OpenSubKey($path) } catch { return $null }
}
$Views = @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)
$Pf  = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$Pfx = ${env:ProgramFiles(x86)}
$Pd  = $env:ProgramData
$SysDrive = $env:SystemDrive
$Sys32 = if ([IO.Directory]::Exists("$env:windir\Sysnative")) { "$env:windir\Sysnative" } else { "$env:windir\System32" }
$BadRoots = @($Pf, $Pfx, $Pd, $SysDrive, "$SysDrive\", $env:windir) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\').ToLowerInvariant() }
$Homes = @{}
function Add-Home([string]$path) {
 $h = Norm $path
 if (-not $h) { return }
 if (-not (Test-JavaHome $h)) { return }
 if ([IO.Path]::GetFileName($h) -ieq 'jre') {
  $parent = [IO.Path]::GetDirectoryName($h)
  if ([IO.File]::Exists("$parent\bin\javac.exe") -or [IO.File]::Exists("$parent\release")) { $h = $parent }
 }
 $k = $h.ToLowerInvariant()
 if (-not $Homes.ContainsKey($k)) { $Homes[$k] = $h }
}
$Services = @(Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue)
$Procs    = @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue)
$Apps = New-Object System.Collections.Generic.List[object]
function Read-Uninstall($baseKey) {
 if (-not $baseKey) { return }
 foreach ($n in $baseKey.GetSubKeyNames()) {
  $k = $baseKey.OpenSubKey($n)
  if (-not $k) { continue }
  $dn = [string]$k.GetValue('DisplayName')
  if (-not $dn) { continue }
  $Apps.Add([pscustomobject]@{
   Name      = $dn
   Version   = [string]$k.GetValue('DisplayVersion')
   Location  = (Norm ([string]$k.GetValue('InstallLocation')))
   Uninstall = [string]$k.GetValue('UninstallString')
   Quiet     = [string]$k.GetValue('QuietUninstallString')
   Key       = $n
  })
 }
}
foreach ($v in $Views) { Read-Uninstall (Open-Key 'LocalMachine' $v 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall') }
$Hku = $null
try { $Hku = [Microsoft.Win32.RegistryKey]::OpenBaseKey('Users', 'Default') } catch {}
$UserSids = @()
if ($Hku) { $UserSids = @($Hku.GetSubKeyNames() | Where-Object { $_ -match '^S-1-5-21-[\d-]+$' }) }
foreach ($sid in $UserSids) { Read-Uninstall ($Hku.OpenSubKey("$sid\Software\Microsoft\Windows\CurrentVersion\Uninstall")) }
function Get-UserName([string]$sid) {
 $k = Open-Key 'LocalMachine' 'Registry64' "SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
 if ($k) { $p = [string]$k.GetValue('ProfileImagePath'); if ($p) { return [IO.Path]::GetFileName($p) } }
 return $sid
}
$Unloaded = @()
$plk = Open-Key 'LocalMachine' 'Registry64' 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
if ($plk) {
 foreach ($sid in $plk.GetSubKeyNames()) {
  if ($sid -notmatch '^S-1-5-21-' -or $UserSids -contains $sid) { continue }
  $pp = Norm ([string]$plk.OpenSubKey($sid).GetValue('ProfileImagePath'))
  if ($pp) { $Unloaded += $pp.ToLowerInvariant() }
 }
}
$JavaSoftDefaults = New-Object System.Collections.Generic.List[object]
foreach ($v in $Views) {
 $bits = if ($v -eq 'Registry32') { '32-bit' } else { '64-bit' }
 foreach ($prod in 'Java Runtime Environment', 'Java Development Kit', 'JRE', 'JDK') {
  $k = Open-Key 'LocalMachine' $v "SOFTWARE\JavaSoft\$prod"
  if (-not $k) { continue }
  foreach ($sub in $k.GetSubKeyNames()) {
   $sk = $k.OpenSubKey($sub)
   if ($sk) { Add-Home ([string]$sk.GetValue('JavaHome')) }
  }
  $cur = [string]$k.GetValue('CurrentVersion')
  if ($cur) {
   $ck = $k.OpenSubKey($cur)
   if ($ck) {
    $jh = Norm ([string]$ck.GetValue('JavaHome'))
    if ($jh) { $JavaSoftDefaults.Add([pscustomobject]@{ Home = $jh; Label = "Registered default $prod $cur ($bits JavaSoft registry)" }) }
   }
  }
 }
}
foreach ($a in $Apps) { if ($a.Location) { Add-Home $a.Location } }
$EnvSources = New-Object System.Collections.Generic.List[object]
$mk = Open-Key 'LocalMachine' 'Registry64' 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
if ($mk) {
 foreach ($n in $mk.GetValueNames()) { $EnvSources.Add([pscustomobject]@{ Scope = 'system'; Name = $n; Value = [string]$mk.GetValue($n) }) }
}
foreach ($sid in $UserSids) {
 $uk = $Hku.OpenSubKey("$sid\Environment")
 if ($uk) {
  $un = Get-UserName $sid
  foreach ($n in $uk.GetValueNames()) { $EnvSources.Add([pscustomobject]@{ Scope = "user $un"; Name = $n; Value = [string]$uk.GetValue($n) }) }
 }
}
$SystemJavaHome = $null
foreach ($e in $EnvSources) {
 if ($e.Name -imatch '^(JAVA_HOME|JRE_HOME|JDK_HOME)$') {
  Add-Home $e.Value
  if ($e.Scope -eq 'system' -and $e.Name -ieq 'JAVA_HOME') { $SystemJavaHome = Norm $e.Value }
 }
 elseif ($e.Name -ieq 'Path') {
  foreach ($entry in ($e.Value -split ';')) {
   $d = Norm $entry
   if ($d -and [IO.File]::Exists("$d\java.exe")) { Add-Home (Get-HomeFromFile (Resolve-Link "$d\java.exe")) }
  }
 }
}
$PathJavaHome = $null
foreach ($entry in ([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';')) {
 $d = Norm $entry
 if ($d -and [IO.File]::Exists("$d\java.exe")) { $PathJavaHome = Get-HomeFromFile (Resolve-Link "$d\java.exe"); break }
}
foreach ($p in $Procs) {
 if ($p.ExecutablePath -and $p.Name -imatch '^(java|javaw|javaws|jp2launcher)\.exe$') { Add-Home (Get-HomeFromFile $p.ExecutablePath) }
}
$SkipDirs = @('node_modules', 'WindowsApps', '.git', 'WinSxS', 'Package Cache', 'Installer', 'Windows Defender',
 'Windows Defender Advanced Threat Protection', 'Microsoft Office', 'Windows Kits', 'Reference Assemblies',
 '$Recycle.Bin', 'System Volume Information', 'Temporary Internet Files', 'INetCache',
 'queue', 'diff', 'cache', '.cache', 'logs', 'log', 'temp', 'tmp', '__pycache__', 'site-packages')
function Search-JavaHomes([string]$root, [int]$maxDepth, [string[]]$extraSkip) {
 if (-not $root -or -not [IO.Directory]::Exists($root)) { return }
 $stack = New-Object System.Collections.Stack
 $stack.Push(@($root, 0))
 while ($stack.Count -gt 0) {
  if ($sw.Elapsed.TotalSeconds -gt $ScanSeconds) { $script:ScanTruncated = $true; return }
  $item = $stack.Pop(); $dir = [string]$item[0]; $depth = [int]$item[1]
  if ([IO.Path]::GetFileName($dir) -ieq 'bin') {
   if ([IO.File]::Exists("$dir\java.exe") -or [IO.File]::Exists("$dir\server\jvm.dll") -or [IO.File]::Exists("$dir\client\jvm.dll")) {
    Add-Home ([IO.Path]::GetDirectoryName($dir))
    continue
   }
  }
  if ($depth -ge $maxDepth) { continue }
  $subs = $null
  try { $subs = [IO.Directory]::GetDirectories($dir) } catch { continue }
  if ($subs.Count -gt 300) { continue }
  foreach ($s in $subs) {
   $n = [IO.Path]::GetFileName($s)
   if ($SkipDirs -contains $n) { continue }
   if ($extraSkip -and ($extraSkip -contains $n)) { continue }
   try { if (([IO.File]::GetAttributes($s) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue } } catch { continue }
   $stack.Push(@($s, ($depth + 1)))
  }
 }
}
foreach ($r in $ExtraScanRoots) { Search-JavaHomes $r 7 $null }
Search-JavaHomes $Pf 7 $null
if ($Pfx -and $Pfx -ne $Pf) { Search-JavaHomes $Pfx 7 $null }
Search-JavaHomes $Pd 5 @('Microsoft')
$TopSkip = @('Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', 'Recovery', 'PerfLogs',
 'Config.Msi', 'Documents and Settings', 'MSOCache', '$WinREAgent', '$SysReset', '$Windows.~BT', '$Windows.~WS',
 '$Recycle.Bin', 'System Volume Information')
foreach ($d in @([IO.Directory]::GetDirectories("$SysDrive\"))) {
 if ($TopSkip -contains [IO.Path]::GetFileName($d)) { continue }
 try { if (([IO.File]::GetAttributes($d) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue } } catch { continue }
 Search-JavaHomes $d 6 $null
}
foreach ($drv in [IO.DriveInfo]::GetDrives()) {
 if ($drv.DriveType -ne 'Fixed' -or -not $drv.IsReady) { continue }
 if ($drv.Name.TrimEnd('\') -ieq $SysDrive) { continue }
 Search-JavaHomes $drv.RootDirectory.FullName 6 $null
}
foreach ($u in @([IO.Directory]::GetDirectories("$SysDrive\Users"))) {
 try { if (([IO.File]::GetAttributes($u) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue } } catch { continue }
 Search-JavaHomes "$u\AppData\Local\Programs" 5 $null
 Search-JavaHomes "$u\AppData\Local\JetBrains" 6 $null
 Search-JavaHomes "$u\.jdks" 2 $null
}
function Convert-FileVer([string]$fv) {
 if ($fv -notmatch '^(\d+)\.(\d+)\.(\d+)') { return $null }
 $maj = [int]$matches[1]; $min = [int]$matches[2]; $p = [int]$matches[3]
 if ($maj -le 8) { return [version]("$maj.0." + [int][math]::Floor($p / 10)) }
 return [version]("$maj.$min.$p")
}
function Format-JavaVer([version]$v) {
 if (-not $v) { return 'unknown' }
 if ($v.Major -le 8) { return "$($v.Major)u$($v.Build)" }
 return "$($v.Major).$($v.Minor).$($v.Build)"
}
function Get-JavaInfo([string]$h) {
 $jv = $null; $impl = $null
 if ([IO.File]::Exists("$h\release")) {
  foreach ($line in [IO.File]::ReadAllLines("$h\release")) {
   if ($line -match '^JAVA_VERSION="?([^"]+)"?') { $jv = $matches[1] }
   elseif ($line -match '^IMPLEMENTOR="?([^"]+)"?') { $impl = $matches[1] }
  }
 }
 $file = if ([IO.File]::Exists("$h\bin\java.exe")) { "$h\bin\java.exe" } elseif ([IO.File]::Exists("$h\bin\server\jvm.dll")) { "$h\bin\server\jvm.dll" } else { "$h\bin\client\jvm.dll" }
 $fvi = $null
 try { $fvi = [Diagnostics.FileVersionInfo]::GetVersionInfo($file) } catch {}
 $v = $null
 if ($jv) {
  if ($jv -match '^1\.(\d+)\.\d+(?:_(\d+))?') { $v = [version]("$($matches[1]).0.$([int]$matches[2])") }
  elseif ($jv -match '^(\d+)(?:\.(\d+))?(?:\.(\d+))?') { $v = [version]("$($matches[1]).$([int]$matches[2]).$([int]$matches[3])") }
 }
 if (-not $v -and $fvi) {
  $v = Convert-FileVer $fvi.ProductVersion
  if (-not $v) { $v = Convert-FileVer $fvi.FileVersion }
 }
 if (-not $impl -and $fvi) { $impl = $fvi.CompanyName }
 $display = if ($jv) { $jv } else { Format-JavaVer $v }
 $type = if ([IO.File]::Exists("$h\bin\javac.exe")) { 'JDK' } else { 'JRE' }
 return [pscustomobject]@{ File = $file; Version = $v; Display = $display; Vendor = $impl; Type = $type }
}
$JavaNamePattern = '(?i)\bjava\b|\bjdk\b|\bjre\b|development kit|openjdk|temurin|adoptium|corretto|zulu|liberica|semeru|graalvm|sapmachine|dragonwell'
function Get-UninstallCmd($a) {
 $u = if ($a.Quiet) { $a.Quiet } else { $a.Uninstall }
 if ($u -match '(?i)msiexec(?:\.exe)?"?\s+/[IX]\s*(\{[0-9A-F-]{36}\})') { return "MsiExec.exe /X$($matches[1]) /qn /norestart" }
 if ($u -match '(?i)msiexec' -and $a.Key -match '^\{[0-9A-Fa-f-]{36}\}$') { return "MsiExec.exe /X$($a.Key) /qn /norestart" }
 return $u
}
function Get-Owner([string]$h, $info) {
 $hl = $h.ToLowerInvariant()
 $best = $null
 foreach ($a in $Apps) {
  if (-not $a.Location) { continue }
  $l = $a.Location.ToLowerInvariant()
  if ($BadRoots -contains $l) { continue }
  if ($hl -eq $l -or $hl.StartsWith($l + '\')) {
   if (-not $best -or $a.Location.Length -gt $best.Location.Length) { $best = $a }
  }
 }
 if ($best) {
  if ($best.Name -match $JavaNamePattern -and ($best.Location.ToLowerInvariant() -eq $hl -or $hl.StartsWith($best.Location.ToLowerInvariant() + '\jre'))) {
   return [pscustomobject]@{ Kind = 'Standalone'; By = "$($best.Name) $($best.Version)".Trim(); Uninstall = (Get-UninstallCmd $best); Root = $null }
  }
  return [pscustomobject]@{ Kind = 'Bundled'; By = "Bundled with $($best.Name) $($best.Version)".Trim(); Uninstall = "Update or remove $($best.Name)"; Root = $best.Location }
 }
 $leaf = [IO.Path]::GetFileName($h)
 if ($info.Version -and ($leaf -match '(?i)^(jre|jdk)' -or $h -match '(?i)\\java\\')) {
  $is32 = ($Pfx -and $hl.StartsWith($Pfx.ToLowerInvariant() + '\'))
  foreach ($a in $Apps) {
   if ($a.Name -notmatch $JavaNamePattern) { continue }
   $av = Convert-FileVer $a.Version
   if (-not $av -or $av -ne $info.Version) { continue }
   $aIsJdk = ($a.Name -match '(?i)development kit|\bjdk\b')
   if ($aIsJdk -ne ($info.Type -eq 'JDK')) { continue }
   if ($is32 -and $a.Name -match '64-bit') { continue }
   if (-not $is32 -and $a.Name -match '32-bit') { continue }
   return [pscustomobject]@{ Kind = 'Standalone'; By = "$($a.Name) $($a.Version)".Trim(); Uninstall = (Get-UninstallCmd $a); Root = $null }
  }
 }
 foreach ($u in $Unloaded) {
  if ($hl.StartsWith($u + '\')) { return [pscustomobject]@{ Kind = 'Unknown'; By = 'Unknown (user profile not logged on)'; Uninstall = 'Unknown (user profile not logged on)'; Root = $null } }
 }
 $root = $null
 $parent = [IO.Path]::GetDirectoryName($h)
 if ($leaf -match '(?i)^(jre|jdk|jbr|java|runtime|jvm|jre64|jre32|openjdk)$' -and $parent -and ($BadRoots -notcontains $parent.ToLowerInvariant()) -and ([IO.Path]::GetFileName($parent) -notmatch '(?i)^java$|adoptium|zulu|corretto|openjdk|jdks$')) { $root = $parent }
 $by = if ($root) { "No installer entry (inside $root)" } else { 'No installer entry found' }
 return [pscustomobject]@{ Kind = 'Unknown'; By = $by; Uninstall = 'None registered'; Root = $root }
}
$Runtimes = @{}
foreach ($k in $Homes.Keys) {
 $h = $Homes[$k]
 $info = Get-JavaInfo $h
 $owner = Get-Owner $h $info
 $javaPath = if ([IO.File]::Exists("$h\bin\java.exe")) { "$h\bin\java.exe" } else { $info.File }
 $Runtimes[$k] = [pscustomobject]@{ Home = $h; Path = $javaPath; Info = $info; Owner = $owner }
}
$Deps = New-Object System.Collections.Generic.List[object]
$DepSeen = @{}
function Add-Dep([string]$key, [string]$type, [string]$detail) {
 if (-not $key) { return }
 $id = "$key|$type|$detail".ToLowerInvariant()
 if ($DepSeen.ContainsKey($id)) { return }
 $DepSeen[$id] = $true
 $Deps.Add([pscustomobject]@{ Key = $key; Type = $type; Detail = $detail })
}
function Get-RuntimeKey([string]$path) {
 $p = Norm $path
 if (-not $p) { return $null }
 $pl = $p.ToLowerInvariant()
 $best = $null
 foreach ($k in $Runtimes.Keys) {
  if ($pl -eq $k -or $pl.StartsWith($k + '\')) { if (-not $best -or $k.Length -gt $best.Length) { $best = $k } }
 }
 return $best
}
function Get-RuntimeKeyByRoot([string]$path) {
 $p = Norm $path
 if (-not $p) { return $null }
 $pl = $p.ToLowerInvariant()
 foreach ($k in $Runtimes.Keys) {
  $r = $Runtimes[$k].Owner.Root
  if ($r -and $pl.StartsWith($r.ToLowerInvariant() + '\')) { return $k }
 }
 return $null
}
function Get-RuntimeKeysInText([string]$text) {
 $out = @()
 if (-not $text) { return $out }
 $t = [Environment]::ExpandEnvironmentVariables($text).ToLowerInvariant()
 foreach ($k in $Runtimes.Keys) { if ($t.Contains($k)) { $out += $k } }
 return $out
}
function Get-ExeFromCommand([string]$cmd) {
 if (-not $cmd) { return $null }
 $c = [Environment]::ExpandEnvironmentVariables($cmd.Trim())
 if ($c.StartsWith('"')) { $e = $c.Substring(1); $i = $e.IndexOf('"'); if ($i -gt 0) { return $e.Substring(0, $i) }; return $e }
 if ($c -match '^(.+?\.(exe|bat|cmd|com))(\s|$)') { return $matches[1] }
 return ($c -split '\s+')[0]
}
function Test-BareJava([string]$exe) { return ($exe -and $exe -notmatch '[\\/]' -and $exe -imatch '^javaw?(\.exe)?$') }
$PathKey = if ($PathJavaHome) { Get-RuntimeKey $PathJavaHome } else { $null }
$JavaHomeKey = if ($SystemJavaHome) { Get-RuntimeKey $SystemJavaHome } else { $null }
function Get-JavaAppHint([string]$cmd) {
 if (-not $cmd) { return '' }
 $tokens = @([regex]::Matches($cmd, '"[^"]*"|\S+') | ForEach-Object { $_.Value.Trim('"') })
 for ($i = 1; $i -lt $tokens.Count; $i++) {
  $t = $tokens[$i]
  if ($t -ieq '-jar') { if ($i + 1 -lt $tokens.Count) { return 'jar ' + [IO.Path]::GetFileName($tokens[$i + 1]) }; return '' }
  if ($t -imatch '^(-m|--module)$') { if ($i + 1 -lt $tokens.Count) { return 'module ' + $tokens[$i + 1] }; return '' }
  if ($t -imatch '^(-cp|-classpath|--class-path|-p|--module-path|--add-opens|--add-exports|--add-modules)$') { $i++; continue }
  if ($t.StartsWith('-') -or $t.StartsWith('@')) { continue }
  if ($t -eq 'org.apache.catalina.startup.Bootstrap') { return 'Apache Tomcat (org.apache.catalina.startup.Bootstrap)' }
  return 'class ' + $t
 }
 return ''
}
function Get-RunAs([string]$id) {
 switch ($id) { 'S-1-5-18' { 'SYSTEM' } 'S-1-5-19' { 'LOCAL SERVICE' } 'S-1-5-20' { 'NETWORK SERVICE' } default { $id } }
}
if ($Runtimes.Count -gt 0) {
 foreach ($s in $Services) {
  $label = "$($s.DisplayName) [$($s.Name)] $($s.State), $($s.StartMode)"
  $rawExe = Get-ExeFromCommand $s.PathName
  $key = $null; $how = 'Service'
  if (Test-BareJava $rawExe) { $key = $PathKey; $how = 'Service (java from PATH)' }
  elseif ($rawExe) { $key = Get-RuntimeKey $rawExe }
  if (-not $key) { $hits = @(Get-RuntimeKeysInText $s.PathName); if ($hits.Count) { $key = $hits[0]; $how = 'Service (path in arguments)' } }
  if (-not $key) {
   foreach ($v in $Views) {
    $pk = Open-Key 'LocalMachine' $v "SOFTWARE\Apache Software Foundation\Procrun 2.0\$($s.Name)\Parameters\Java"
    if (-not $pk) { continue }
    $jvm = [string]$pk.GetValue('Jvm')
    if ($jvm -ieq 'auto' -or -not $jvm) {
     foreach ($d in $JavaSoftDefaults) { $kk = Get-RuntimeKey $d.Home; if ($kk) { $key = $kk; $how = 'Service (procrun, Jvm=auto uses registered default)'; break } }
    }
    else { $key = Get-RuntimeKey (Get-HomeFromFile $jvm); if ($key) { $how = 'Service (procrun Jvm setting)' } }
    if ($key) { break }
   }
  }
  if (-not $key -and $rawExe -and [IO.Path]::GetFileName($rawExe) -imatch 'wrapper' -and $s.PathName -match '"([^"]+\.conf)"|(\S+\.conf)') {
   $conf = if ($matches[1]) { $matches[1] } else { $matches[2] }
   if (-not [IO.Path]::IsPathRooted($conf)) { $conf = Join-Path ([IO.Path]::GetDirectoryName($rawExe)) $conf }
   if ([IO.File]::Exists($conf)) {
    $line = [IO.File]::ReadAllLines($conf) | Where-Object { $_ -match '^\s*wrapper\.java\.command\s*=' } | Select-Object -First 1
    if ($line) {
     $jc = ($line -split '=', 2)[1].Trim()
     if (Test-BareJava $jc) { $key = $PathKey } else { $key = Get-RuntimeKey $jc }
     if ($key) { $how = 'Service (Java Service Wrapper .conf)' }
    }
   }
  }
  if (-not $key -and $rawExe) {
   $xmlPath = [IO.Path]::ChangeExtension($rawExe, '.xml')
   if ([IO.File]::Exists($xmlPath)) {
    $xt = [IO.File]::ReadAllText($xmlPath)
    if ($xt -match '<executable>\s*([^<]+?)\s*</executable>') {
     $jc = $matches[1] -replace '(?i)%BASE%', [IO.Path]::GetDirectoryName($rawExe)
     if (Test-BareJava $jc) { $key = $PathKey } else { $key = Get-RuntimeKey $jc }
     if ($key) { $how = 'Service (WinSW .xml)' }
    }
   }
  }
  if ($key) { Add-Dep $key $how $label; continue }
  if ($rawExe -and $rawExe -match '[\\/]') {
   $rk = Get-RuntimeKeyByRoot $rawExe
   if ($rk) { Add-Dep $rk 'Service (same application folder, likely uses it)' $label }
  }
 }
 $SvcByPid = @{}
 foreach ($s in $Services) { if ($s.ProcessId) { $SvcByPid[[int]$s.ProcessId] = $s.Name } }
 foreach ($p in $Procs) {
  if (-not $p.ExecutablePath) { continue }
  $svc = ''
  if ($SvcByPid.ContainsKey([int]$p.ProcessId)) { $svc = " (service $($SvcByPid[[int]$p.ProcessId]))" }
  elseif ($SvcByPid.ContainsKey([int]$p.ParentProcessId)) { $svc = " (started by service $($SvcByPid[[int]$p.ParentProcessId]))" }
  $key = Get-RuntimeKey $p.ExecutablePath
  if ($key) {
   $hint = Get-JavaAppHint $p.CommandLine
   $detail = "$($p.Name) PID $($p.ProcessId)$svc"
   if ($hint) { $detail += " - $hint" }
   Add-Dep $key 'Running Process' $detail
   continue
  }
  $rk = Get-RuntimeKeyByRoot $p.ExecutablePath
  if ($rk) { Add-Dep $rk 'Running Process (same application folder, likely uses it)' "$($p.Name) PID $($p.ProcessId)$svc" }
 }
 $TaskRoot = "$Sys32\Tasks"
 $taskFiles = New-Object System.Collections.Generic.List[string]
 $tstack = New-Object System.Collections.Stack
 if ([IO.Directory]::Exists($TaskRoot)) { $tstack.Push($TaskRoot) }
 while ($tstack.Count -gt 0) {
  $d = [string]$tstack.Pop()
  try { foreach ($f in [IO.Directory]::GetFiles($d)) { $taskFiles.Add($f) } } catch {}
  try { foreach ($sd in [IO.Directory]::GetDirectories($d)) { $tstack.Push($sd) } } catch {}
 }
 foreach ($tf in $taskFiles) {
  $x = New-Object Xml.XmlDocument
  try { $x.Load($tf) } catch { continue }
  $ns = New-Object Xml.XmlNamespaceManager($x.NameTable)
  $ns.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
  $execs = $x.SelectNodes('//t:Actions/t:Exec', $ns)
  if (-not $execs -or $execs.Count -eq 0) { continue }
  $en = $x.SelectSingleNode('//t:Settings/t:Enabled', $ns)
  $state = if ($en -and $en.InnerText -eq 'false') { 'Disabled' } else { 'Enabled' }
  $uid = $x.SelectSingleNode('//t:Principals/t:Principal/t:UserId', $ns)
  $runAs = if ($uid) { Get-RunAs $uid.InnerText } else { 'unknown' }
  $taskName = $tf.Substring($TaskRoot.Length)
  $label = "$taskName - runs as $runAs, $state"
  foreach ($e in $execs) {
   $cn = $e.SelectSingleNode('t:Command', $ns); $an = $e.SelectSingleNode('t:Arguments', $ns)
   $cmd = if ($cn) { $cn.InnerText.Trim().Trim('"') } else { '' }
   $arg = if ($an) { $an.InnerText } else { '' }
   $key = $null; $how = 'Scheduled Task'
   if (Test-BareJava $cmd) { $key = $PathKey; $how = 'Scheduled Task (java from PATH)' }
   elseif ($cmd) { $key = Get-RuntimeKey $cmd }
   if (-not $key) { $hits = @(Get-RuntimeKeysInText $arg); if ($hits.Count) { $key = $hits[0]; $how = 'Scheduled Task (path in arguments)' } }
   if (-not $key) {
    $script = $null
    if ($cmd -match '(?i)\.(bat|cmd|ps1)$') { $script = $cmd }
    elseif ($arg -match '(?i)"?([A-Za-z]:\\[^"]+?\.(bat|cmd|ps1))"?') { $script = $matches[1] }
    $script = if ($script) { [Environment]::ExpandEnvironmentVariables($script) } else { $null }
    if ($script -and [IO.File]::Exists($script) -and (Get-Item -LiteralPath $script).Length -lt 262144) {
     $txt = [IO.File]::ReadAllText($script)
     $hits = @(Get-RuntimeKeysInText $txt)
     if ($hits.Count) { $key = $hits[0] }
     elseif ($txt -match '(?i)%JAVA_HOME%|\$env:JAVA_HOME') { $key = $JavaHomeKey }
     elseif ($txt -match '(?im)(^|[\s"&(])javaw?(\.exe)?\s') { $key = $PathKey }
     if ($key) { $how = "Scheduled Task (via script $([IO.Path]::GetFileName($script)))" }
    }
   }
   if ($key) { Add-Dep $key $how $label }
  }
 }
 foreach ($e in $EnvSources) {
  if ($e.Name -imatch '^(JAVA_HOME|JRE_HOME|JDK_HOME)$') {
   $key = Get-RuntimeKey $e.Value
   if ($key) { Add-Dep $key 'Environment Variable' "$($e.Name.ToUpper()) ($($e.Scope))" }
  }
  elseif ($e.Name -ieq 'Path') {
   $i = 0
   foreach ($entry in ($e.Value -split ';')) {
    $i++
    $d = Norm $entry
    if (-not $d) { continue }
    $key = Get-RuntimeKey $d
    if ($key) { Add-Dep $key 'PATH' "PATH ($($e.Scope)) entry $i"; continue }
    if ([IO.File]::Exists("$d\java.exe")) {
     $t = Resolve-Link "$d\java.exe"
     if ($t -ne "$d\java.exe") { $key = Get-RuntimeKey $t; if ($key) { Add-Dep $key 'PATH' "PATH ($($e.Scope)) entry $i via $d" } }
    }
   }
  }
 }
 foreach ($d in $JavaSoftDefaults) { $key = Get-RuntimeKey $d.Home; if ($key) { Add-Dep $key 'Registry Default' $d.Label } }
 foreach ($v in $Views) {
  $jk = Open-Key 'LocalMachine' $v 'SOFTWARE\Classes\jarfile\shell\open\command'
  if (-not $jk) { continue }
  $jexe = Get-ExeFromCommand ([string]$jk.GetValue(''))
  if ($jexe) { $key = Get-RuntimeKey $jexe; if ($key) { Add-Dep $key 'File Association' '.jar files open with this Java' } }
 }
}
$rows = New-Object System.Collections.Generic.List[string]
foreach ($k in $Runtimes.Keys) {
 $r = $Runtimes[$k]
 $v = $r.Info.Version
 $line = if ($v) { [string]$v.Major } else { 'unknown' }
 $norm = if ($v) { "$($v.Major).$($v.Minor).$($v.Build)" } else { 'unknown' }
 $base = @($r.Path, $line, $norm, $r.Info.Display, $r.Info.Type, $r.Info.Vendor, $r.Owner.By, $r.Owner.Uninstall) | ForEach-Object { Format-Field $_ }
 $mine = @($Deps | Where-Object { $_.Key -eq $k })
 if ($mine.Count -eq 0) {
  $rows.Add((($base + @('None found', 'No service, process, scheduled task, variable, or file association references it')) -join '|'))
 }
 else {
  foreach ($d in $mine) { $rows.Add((($base + @((Format-Field $d.Type), (Format-Field $d.Detail))) -join '|')) }
 }
}
$rows | Sort-Object | Write-Output
if ($script:ScanTruncated) {
 Write-Output ((@('Scan incomplete', '', '', '', '', '', '', '', 'Scan incomplete', "Folder search stopped after $ScanSeconds seconds. Some folders were not checked.")) -join '|')
}
