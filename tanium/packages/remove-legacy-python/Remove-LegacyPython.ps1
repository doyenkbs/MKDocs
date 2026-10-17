######################################################################
# Remove Legacy Python 3.10 / 3.11 / 3.12 (Tanium package)
#
# Tanium package command:
#   cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Remove-LegacyPython.ps1
#
# Runs as SYSTEM. Removes the Python versions listed in $Minor from:
#   1. All-users installs: runs the installer's own uninstall, then removes
#      any leftover component MSIs and PythonCore registry keys.
#   2. Every user profile, signed in or not: deletes the install folders
#      (AppData\Local\Programs\Python\Python3xx), pip --user folders
#      (AppData\Roaming\Python\Python3xx), Start menu folders, the user's
#      Uninstall and PythonCore registry keys, and the user's PATH entries.
#      Removes the per-user Python Launcher only if it is one of these
#      versions.
#   3. Custom folders: any folder registered as an InstallPath for these
#      versions, and Python* folders at the root of the system drive.
#      A folder is only deleted if python.exe directly inside it is one of
#      these versions.
#
# Not touched: newer Python versions and the all-users Python Launcher
# (C:\Windows\py.exe).
#
# Exit codes (6 wins over 1):
#   0  Removed everything found, or nothing was found
#   1  Something could not be removed, or is still present afterward
#   5  Not running as SYSTEM or an administrator. Nothing changed.
#   6  A user registry hive could not be unloaded. Restart the endpoint
#      before that user signs in.
######################################################################

# Restart as 64-bit if the Tanium client started 32-bit PowerShell.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'

# Minor versions to remove. Edit this list only, everything below follows it.
$Minor = @('10', '11', '12')

$VerRegex  = '3\.(' + ($Minor -join '|') + ')'
$Folders   = @($Minor | ForEach-Object { "Python3$_"; "Python3$_-32" })
$FolderRx  = ($Folders | ForEach-Object { [regex]::Escape($_) }) -join '|'
$MountName = 'PY_CLEANUP'
$MountPs   = "Registry::HKEY_USERS\$MountName"

$MachineUninstall = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$MachineCore = @(
    'HKLM:\SOFTWARE\Python\PythonCore',
    'HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore'
)

$removed      = [System.Collections.Generic.List[string]]::new()
$failed       = [System.Collections.Generic.List[string]]::new()
$stillPresent = [System.Collections.Generic.List[string]]::new()
$checkDirs    = [System.Collections.Generic.List[string]]::new()
$unloadFailed = $false

function Write-Log {
    param ([string]$Message, [string]$Level = 'INFO')
    Write-Output ("{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

function Join-OrNone {
    param ($Items)
    $list = @($Items)
    if ($list.Count -gt 0) { return ($list -join ', ') }
    return 'none'
}

# Windows PowerShell 5.1 turns native stderr into a terminating error when
# ErrorActionPreference is Stop, so reg.exe runs with Continue.
function Invoke-Reg {
    param ([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = (& reg.exe @Arguments 2>&1 | Out-String).Trim()
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ ExitCode = $code; Output = $out }
}

# Open registry handles keep a hive from unloading, so release them and retry.
function Dismount-UserHive {
    for ($i = 1; $i -le 3; $i++) {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        Start-Sleep -Seconds 2
        $r = Invoke-Reg @('unload', "HKU\$MountName")
        if ($r.ExitCode -eq 0) { return $true }
    }
    return $false
}

# All-users uninstall entries for the versions being removed
function Get-LegacyMachineEntries {
    @(Get-ItemProperty $MachineUninstall -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "^Python $VerRegex\.\d+" })
}

function Remove-LoggedPath {
    param ([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try { Remove-Item -LiteralPath $Path -Recurse -Force } catch { }
    if (Test-Path -LiteralPath $Path) {
        Write-Log "Could not delete $Path (a file may be in use)" 'ERROR'
        $failed.Add($Path)
    } else {
        Write-Log "Deleted $Path"
        $removed.Add($Path)
    }
}

function Remove-LoggedKey {
    param ([string]$KeyPath, [string]$Label)
    try { Remove-Item -LiteralPath $KeyPath -Recurse -Force } catch { }
    if (Test-Path -LiteralPath $KeyPath) {
        Write-Log "Could not remove $Label" 'ERROR'
        $failed.Add($Label)
    } else {
        Write-Log "Removed $Label"
        $removed.Add($Label)
    }
}

# True only if python.exe sits directly in the folder and is one of the
# versions being removed. Never a drive root or anything under Windows.
function Test-LegacyPythonDir {
    param ([string]$Dir)
    if (-not $Dir) { return $false }
    $Dir = $Dir.TrimEnd('\')
    if ($Dir -match '^[A-Za-z]:$') { return $false }
    if ($Dir.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    try {
        $exe = Join-Path $Dir 'python.exe'
        if (-not (Test-Path -LiteralPath $exe)) { return $false }
        return ((Get-Item -LiteralPath $exe).VersionInfo.FileVersion -match "^$VerRegex\.")
    } catch {
        return $false
    }
}

function Remove-LegacyPythonDir {
    param ([string]$Dir)
    if (-not (Test-LegacyPythonDir $Dir)) { return }
    $Dir = $Dir.TrimEnd('\')
    $checkDirs.Add($Dir)
    Remove-LoggedPath $Dir
}

# InstallPath values registered under PythonCore for the versions being removed
function Get-CoreInstallPaths {
    param ([string]$CorePath)
    @(Get-ChildItem -LiteralPath $CorePath -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match "^$VerRegex(-32)?$" } |
        ForEach-Object { (Get-ItemProperty -LiteralPath "$($_.PSPath)\InstallPath" -ErrorAction SilentlyContinue).'(default)' } |
        Where-Object { $_ })
}

function Remove-CoreKeys {
    param ([string]$CorePath, [string]$Owner)
    $keys = @(Get-ChildItem -LiteralPath $CorePath -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match "^$VerRegex(-32)?$" })
    foreach ($k in $keys) { Remove-LoggedKey $k.PSPath "$Owner PythonCore\$($k.PSChildName) registry key" }
}

# --- Elevation check ----------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Not running as SYSTEM or an administrator. Nothing changed." 'ERROR'
    exit 5
}

# A hive left mounted by an earlier run would block every load below.
if (Test-Path -LiteralPath $MountPs) {
    Write-Log "A hive from an earlier run is still loaded as HKU\$MountName. Unloading it." 'WARN'
    if (-not (Dismount-UserHive)) {
        Write-Log "Could not unload HKU\$MountName. Restart the endpoint, then run again. Nothing changed." 'ERROR'
        exit 6
    }
}

Write-Log ("Versions to remove: {0}" -f (($Minor | ForEach-Object { "3.$_" }) -join ', '))

# --- 1. All-users installs ----------------------------------------------------
# Read the registered install folders first, because the uninstall removes them.
$machineDirs = @($MachineCore | ForEach-Object { Get-CoreInstallPaths $_ })

$bundles = @(Get-LegacyMachineEntries | Where-Object { $_.DisplayName -match "^Python $VerRegex\.\d+ \((64|32)-bit\)$" })
foreach ($b in $bundles) {
    $cmd = if ($b.QuietUninstallString) { $b.QuietUninstallString } else { $b.UninstallString }
    if ($cmd -match '^"([^"]+)"\s*(.*)$' -and (Test-Path -LiteralPath $Matches[1])) {
        $exe     = $Matches[1]
        $argList = $Matches[2]
        if ($argList -notmatch '/quiet') { $argList = "$argList /quiet" }
        Write-Log "$($b.DisplayName) : running the installer's uninstall"
        try {
            $p = Start-Process -FilePath $exe -ArgumentList $argList -Wait -PassThru
            Write-Log "$($b.DisplayName) : uninstall exit code $($p.ExitCode)"
        } catch {
            Write-Log "$($b.DisplayName) : uninstall could not start. $($_.Exception.Message)" 'ERROR'
        }
    } else {
        Write-Log "$($b.DisplayName) : cached installer not found, removing its MSI components instead" 'WARN'
    }
}

# Component MSIs left behind (or all of them, when the cached installer is gone)
$msis = @(Get-LegacyMachineEntries | Where-Object { $_.WindowsInstaller -eq 1 -and $_.PSChildName -match '^\{[0-9A-Fa-f-]+\}$' })
foreach ($m in $msis) {
    try {
        $p = Start-Process -FilePath msiexec.exe -ArgumentList "/x $($m.PSChildName) /qn /norestart" -Wait -PassThru
        Write-Log "$($m.DisplayName) : MSI uninstall exit code $($p.ExitCode)"
    } catch {
        Write-Log "$($m.DisplayName) : MSI uninstall could not start. $($_.Exception.Message)" 'ERROR'
    }
}

# --- 2. Custom folders ----------------------------------------------------------
foreach ($d in $machineDirs) { Remove-LegacyPythonDir $d }
$rootDirs = @(Get-ChildItem -LiteralPath "$env:SystemDrive\" -Directory -Filter 'python*' -ErrorAction SilentlyContinue)
foreach ($d in $rootDirs) { Remove-LegacyPythonDir $d.FullName }

# PythonCore keys for all users, only once the uninstall entries are gone
if ((Get-LegacyMachineEntries).Count -eq 0) {
    foreach ($c in $MachineCore) { Remove-CoreKeys $c 'All users:' }
}

# --- 3. Every user profile ------------------------------------------------------
$profiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter "Special=False" |
    Where-Object { $_.LocalPath -and (Test-Path -LiteralPath $_.LocalPath) })

foreach ($prof in $profiles) {
    $path   = $prof.LocalPath
    $pyRoot = Join-Path $path 'AppData\Local\Programs\Python'

    # Install folders and pip --user folders
    foreach ($f in $Folders) {
        Remove-LoggedPath (Join-Path $pyRoot $f)
        Remove-LoggedPath (Join-Path $path "AppData\Roaming\Python\$f")
    }

    # Per-user Python Launcher, only if it is one of the versions being removed
    $launcherDir = Join-Path $pyRoot 'Launcher'
    $launcherExe = Join-Path $launcherDir 'py.exe'
    $oldLauncher = $false
    if (Test-Path -LiteralPath $launcherExe) {
        $lv = (Get-Item -LiteralPath $launcherExe).VersionInfo.FileVersion
        if ($lv -match "^$VerRegex\.") {
            $oldLauncher = $true
            Write-Log "$path : per-user Python Launcher is version $lv"
            Remove-LoggedPath $launcherDir
        }
    }

    # The Python folder itself, if nothing is left in it
    if ((Test-Path -LiteralPath $pyRoot) -and -not (Get-ChildItem -LiteralPath $pyRoot -Force -ErrorAction SilentlyContinue)) {
        Remove-LoggedPath $pyRoot
    }

    # Start menu folders, for example "Python 3.11"
    $startMenu = Join-Path $path 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs'
    $menus = @(Get-ChildItem -LiteralPath $startMenu -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^Python $VerRegex$" })
    foreach ($menu in $menus) { Remove-LoggedPath $menu.FullName }

    # Registry: use the live hive for a signed-in user, otherwise load NTUSER.DAT
    $mounted = $false
    if ($prof.Loaded) {
        $hiveName = $prof.SID
    } else {
        $hive = Join-Path $path 'NTUSER.DAT'
        if (-not (Test-Path -LiteralPath $hive)) { continue }
        $load = Invoke-Reg @('load', "HKU\$MountName", $hive)
        if ($load.ExitCode -ne 0) {
            Write-Log "$path : could not load the registry hive. $($load.Output)" 'ERROR'
            $failed.Add("$path (registry)")
            continue
        }
        $hiveName = $MountName
        $mounted  = $true
    }
    $hivePs = "Registry::HKEY_USERS\$hiveName"

    try {
        # Per-user installs in custom folders, found through their InstallPath
        foreach ($d in (Get-CoreInstallPaths "$hivePs\Software\Python\PythonCore")) { Remove-LegacyPythonDir $d }

        # Uninstall entries
        $entries = @(Get-ChildItem -LiteralPath "$hivePs\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue)
        foreach ($e in $entries) {
            $props = Get-ItemProperty -LiteralPath $e.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            $isOldPython   = $props.DisplayName -match "^Python $VerRegex\.\d+"
            $isOldLauncher = $oldLauncher -and $props.DisplayName -eq 'Python Launcher' -and $props.DisplayVersion -match "^$VerRegex\."
            if ($isOldPython -or $isOldLauncher) {
                Remove-LoggedKey $e.PSPath "$path : '$($props.DisplayName)' uninstall entry"
            }
        }

        # PythonCore registration, which py.exe uses to find installs
        Remove-CoreKeys "$hivePs\Software\Python\PythonCore" "$path :"

        # PATH entries, keeping the original value type
        $names = $FolderRx
        if ($oldLauncher) { $names = "$FolderRx|Launcher" }
        $pathRx = "\\(Programs|Roaming)\\Python\\($names)(\\|$)"

        $envKey = [Microsoft.Win32.Registry]::Users.OpenSubKey("$hiveName\Environment", $true)
        if ($envKey) {
            try {
                $raw = $envKey.GetValue('Path', $null, 'DoNotExpandEnvironmentNames')
                if ($raw) {
                    $kind  = $envKey.GetValueKind('Path')
                    $parts = @($raw -split ';' | Where-Object { $_ })
                    $kept  = @($parts | Where-Object { $_ -notmatch $pathRx })
                    if ($kept.Count -lt $parts.Count) {
                        $envKey.SetValue('Path', ($kept -join ';'), $kind)
                        Write-Log ("{0} : removed {1} PATH entries" -f $path, ($parts.Count - $kept.Count))
                    }
                }
            } finally {
                $envKey.Close()
            }
        }
    } catch {
        Write-Log "$path : registry cleanup error. $($_.Exception.Message)" 'ERROR'
        $failed.Add("$path (registry)")
    } finally {
        if ($mounted -and -not (Dismount-UserHive)) {
            Write-Log "$path : could not unload the registry hive. Restart the endpoint before this user signs in." 'ERROR'
            $unloadFailed = $true
        }
    }

    if ($unloadFailed) {
        $failed.Add("$path (hive unload)")
        Write-Log "Stopping, so no other hive is loaded while one is stuck." 'ERROR'
        break
    }
}

# --- 4. Verify ------------------------------------------------------------------
foreach ($e in (Get-LegacyMachineEntries)) { $stillPresent.Add($e.DisplayName) }

$exes = [System.Collections.Generic.List[string]]::new()
foreach ($m in $Minor) {
    $exes.Add((Join-Path $env:ProgramFiles "Python3$m\python.exe"))
    if (${env:ProgramFiles(x86)}) { $exes.Add((Join-Path ${env:ProgramFiles(x86)} "Python3$m-32\python.exe")) }
}
foreach ($prof in $profiles) {
    foreach ($f in $Folders) { $exes.Add((Join-Path $prof.LocalPath "AppData\Local\Programs\Python\$f\python.exe")) }
    $le = Join-Path $prof.LocalPath 'AppData\Local\Programs\Python\Launcher\py.exe'
    if ((Test-Path -LiteralPath $le) -and ((Get-Item -LiteralPath $le).VersionInfo.FileVersion -match "^$VerRegex\.")) {
        $stillPresent.Add($le)
    }
}
foreach ($x in $exes) { if (Test-Path -LiteralPath $x) { $stillPresent.Add($x) } }

$rootDirs = @(Get-ChildItem -LiteralPath "$env:SystemDrive\" -Directory -Filter 'python*' -ErrorAction SilentlyContinue)
foreach ($d in $rootDirs) { $checkDirs.Add($d.FullName) }
foreach ($d in ($checkDirs | Select-Object -Unique)) {
    if (Test-LegacyPythonDir $d) { $stillPresent.Add("$d\python.exe") }
}

# --- Summary --------------------------------------------------------------------
$stillPresentUnique = @($stillPresent | Select-Object -Unique)
Write-Log "Summary:"
Write-Log ("  Removed: {0}" -f (Join-OrNone $removed))
Write-Log ("  Failed: {0}" -f (Join-OrNone $failed))
Write-Log ("  Still present: {0}" -f (Join-OrNone $stillPresentUnique))

if ($unloadFailed) { exit 6 }
if ($failed.Count -gt 0 -or $stillPresentUnique.Count -gt 0) { exit 1 }
exit 0
