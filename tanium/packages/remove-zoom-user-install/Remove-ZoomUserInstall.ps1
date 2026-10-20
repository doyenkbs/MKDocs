######################################################################
# Remove Zoom User Install (Tanium package)
#
# Tanium package command:
#   cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-ZoomUserInstall.ps1 "$1"
#
# $1  Close Zoom   No (or blank) or Yes. Yes closes Zoom for the user before
#                  removing it. Any meeting in progress is dropped.
#
# Runs as SYSTEM. Removes the per-user copy of Zoom (installed under
# %APPDATA%\Zoom\bin) from every user profile, signed in or not.
#
# Both the per-user copy and the system-wide (MSI) copy keep user data in
# AppData\Roaming\Zoom and AppData\Local\Zoom. Only the per-user copy puts
# program files there. So:
#   - A profile counts as having the per-user copy only when a Zoom.exe is
#     found under those folders. Profiles with data folders only are left alone.
#   - If a system-wide Zoom is installed (Program Files\Zoom\bin\Zoom.exe),
#     only the per-user program folders are deleted (bin, bin_*, uninstall, and
#     any other subfolder that contains an .exe). The data folders stay, because
#     the system-wide copy uses them.
#   - If no system-wide Zoom is installed, both Zoom folders are deleted.
#
# For each profile with the per-user copy:
#   1. Deletes the folders above.
#   2. Deletes Start menu and desktop shortcuts that point into what was deleted.
#   3. Deletes the per-user uninstall entry (ZoomUMX) and the Zoom Run value
#      from the user's registry. Signed-out users' registry hives are loaded
#      offline for this, then unloaded. Every signed-out hive is checked, so
#      entries left by a folder deleted by hand are cleaned too.
#
# The system-wide copy is only checked for, never changed, and nothing is
# installed.
#
# Exit codes (when more than one applies, the highest-priority code wins:
# 6, then 1, then 3):
#   0  Removed from every profile that had it, or no profile has it
#   1  At least one profile could not be fully cleaned
#   2  Invalid parameter. Nothing changed.
#   3  At least one user was skipped because Zoom was open (Close Zoom = No)
#   5  Not running as SYSTEM or an administrator. Nothing changed.
#   6  A registry hive could not be unloaded. Restart the endpoint before
#      that user signs in.
######################################################################

param(
    [string]$CloseZoom = ""
)

# Restart as 64-bit if the Tanium client started 32-bit PowerShell.
# The raw (still URL-encoded) value is passed on, so it is decoded only once.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($CloseZoom) { $argList += @('-CloseZoom', $CloseZoom) }
    & $ps64 @argList
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'

$RelZoomDirs     = @('AppData\Roaming\Zoom', 'AppData\Local\Zoom')
$RelStartMenu    = 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs'
$RelDesktop      = 'Desktop'
$RunKeyRel       = 'Software\Microsoft\Windows\CurrentVersion\Run'
$UninstallKeyRel = 'Software\Microsoft\Windows\CurrentVersion\Uninstall'
$ZoomPathMatch   = '*\AppData\Roaming\Zoom\*'
$MountName       = 'ZOOM_CLEANUP'
$MountPs         = "Registry::HKEY_USERS\$MountName"

function Write-Log {
    param ([string]$Message, [string]$Level = 'INFO')
    Write-Output ("{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

# Tanium URL-encodes parameter values. Decode, then strip stray whitespace and quotes.
function ConvertFrom-TaniumParam {
    param ([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return ([Uri]::UnescapeDataString($Value)).Trim().Trim('"').Trim()
}

function Join-OrNone {
    param ([string[]]$Items)
    if ($Items -and $Items.Count -gt 0) { return ($Items -join ', ') }
    return 'none'
}

function Test-UnderPath {
    param ([string]$Path, [string[]]$Roots)
    if (-not $Path) { return $false }
    foreach ($r in $Roots) {
        if ($Path.StartsWith($r.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
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

# Removes the Zoom Run value and the per-user uninstall entry under one user's
# registry root. Sets $script:StepFailed on any error. Log lines are written
# straight to output, so the function returns nothing to test.
function Remove-ZoomRegistry {
    param ([string]$Root, [string]$Label)

    $runKey = "$Root\$RunKeyRel"
    if (Test-Path -LiteralPath $runKey) {
        $skip = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')
        $item = Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue
        if ($item) {
            foreach ($prop in @($item.PSObject.Properties | Where-Object { $_.Name -notin $skip -and "$($_.Value)" -like $ZoomPathMatch })) {
                try {
                    Remove-ItemProperty -LiteralPath $runKey -Name $prop.Name
                    Write-Log ("{0} : removed Run value '{1}'" -f $Label, $prop.Name)
                } catch {
                    Write-Log ("{0} : could not remove Run value '{1}'. {2}" -f $Label, $prop.Name, $_.Exception.Message) 'ERROR'
                    $script:StepFailed = $true
                }
            }
        }
    }

    $uninstRoot = "$Root\$UninstallKeyRel"
    if (Test-Path -LiteralPath $uninstRoot) {
        $entries = @(Get-ChildItem -LiteralPath $uninstRoot -ErrorAction SilentlyContinue | Where-Object {
            $_.PSChildName -eq 'ZoomUMX' -or "$($_.GetValue('UninstallString'))" -like $ZoomPathMatch
        })
        foreach ($e in $entries) {
            $name = $e.PSChildName
            try {
                Remove-Item -LiteralPath $e.PSPath -Recurse -Force
                if (Test-Path -LiteralPath "$uninstRoot\$name") { throw 'The entry is still present after the delete.' }
                Write-Log ("{0} : removed uninstall entry '{1}'" -f $Label, $name)
            } catch {
                Write-Log ("{0} : could not remove uninstall entry '{1}'. {2}" -f $Label, $name, $_.Exception.Message) 'ERROR'
                $script:StepFailed = $true
            }
        }
    }
}

# Every Zoom.exe in the profile's Zoom folders. The system-wide copy never puts
# one there, so any hit is a per-user copy.
function Get-ZoomExe {
    param ([string]$ProfilePath)
    foreach ($rel in $RelZoomDirs) {
        $root = Join-Path $ProfilePath $rel
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Filter 'Zoom.exe' -File -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Program parts of a per-user copy: bin, bin_* (Zoom alternates between bin and
# bin_00 across updates), uninstall, any other subfolder holding an .exe, and
# .exe files at the top of the Zoom folder. Data folders are not returned.
function Get-ZoomProgramItems {
    param ([string]$ProfilePath)
    foreach ($rel in $RelZoomDirs) {
        $root = Join-Path $ProfilePath $rel
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($item in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue)) {
            if (-not $item.PSIsContainer) {
                if ($item.Extension -eq '.exe') { $item.FullName }
                continue
            }
            if ($item.Name -eq 'bin' -or $item.Name -like 'bin_*' -or $item.Name -eq 'uninstall') { $item.FullName; continue }
            $exe = Get-ChildItem -LiteralPath $item.FullName -Filter '*.exe' -File -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($exe) { $item.FullName }
        }
    }
}

# Deletes the given folders and files, and the shortcuts that point into them.
# Sets $script:StepFailed when a target is left in place.
function Remove-ZoomFiles {
    param ([string]$ProfilePath, [string]$Label, [string[]]$Targets)
    $links = @()
    foreach ($rel in @($RelStartMenu, $RelDesktop)) {
        $dir = Join-Path $ProfilePath $rel
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $recurse = ($rel -eq $RelStartMenu)
        $links += @(Get-ChildItem -LiteralPath $dir -Filter '*.lnk' -File -Recurse:$recurse -Force -ErrorAction SilentlyContinue)
    }
    if ($links.Count -gt 0) {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($lnk in $links) {
            $target = ''
            try { $target = $shell.CreateShortcut($lnk.FullName).TargetPath } catch { }
            if (-not (Test-UnderPath -Path $target -Roots $Targets)) { continue }
            try {
                Remove-Item -LiteralPath $lnk.FullName -Force
                Write-Log ("{0} : deleted {1}" -f $Label, $lnk.FullName)
                $parent = Split-Path $lnk.FullName -Parent
                if ((Split-Path $parent -Leaf) -like 'Zoom*' -and -not (Get-ChildItem -LiteralPath $parent -Force)) {
                    Remove-Item -LiteralPath $parent -Force
                    Write-Log ("{0} : deleted empty folder {1}" -f $Label, $parent)
                }
            } catch {
                Write-Log ("{0} : could not delete {1}. {2}" -f $Label, $lnk.FullName, $_.Exception.Message) 'WARN'
            }
        }
    }

    foreach ($item in $Targets) {
        if (-not (Test-Path -LiteralPath $item)) { continue }
        try {
            Remove-Item -LiteralPath $item -Recurse -Force
            Write-Log ("{0} : deleted {1}" -f $Label, $item)
        } catch {
            Write-Log ("{0} : could not delete {1}. {2}" -f $Label, $item, $_.Exception.Message) 'ERROR'
        }
        if (Test-Path -LiteralPath $item) { $script:StepFailed = $true }
    }
}

# --- Validate parameter -------------------------------------------------------
$closeValue = ConvertFrom-TaniumParam $CloseZoom
Write-Log "Close Zoom parameter: '$closeValue'"

if (-not $closeValue -or $closeValue -eq 'No') {
    $forceClose = $false
} elseif ($closeValue -eq 'Yes') {
    $forceClose = $true
} else {
    Write-Log "Unknown Close Zoom value '$closeValue'. Use No (or leave it blank), or Yes." 'ERROR'
    exit 2
}

# --- Elevation check ----------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Not running as SYSTEM or an administrator. Other users' profiles cannot be changed. Nothing changed." 'ERROR'
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

# --- Profiles -----------------------------------------------------------------
$profiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter "Special=False" | Where-Object { $_.LocalPath } | ForEach-Object {
    [pscustomobject]@{ Path = $_.LocalPath; Sid = $_.SID; Loaded = [bool]$_.Loaded }
})

# Folders left behind by deleted accounts have no registry hive, but can still hold Zoom.exe.
$profilesDir = Join-Path $env:SystemDrive 'Users'
try {
    $profilesDir = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -Name ProfilesDirectory).ProfilesDirectory)
} catch { }
$knownPaths = @($profiles | ForEach-Object { $_.Path })
$excluded   = @('Public', 'Default', 'Default User', 'All Users')
foreach ($d in @(Get-ChildItem -LiteralPath $profilesDir -Directory -Force -ErrorAction SilentlyContinue)) {
    if ($d.Name -in $excluded -or ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $d.FullName -in $knownPaths) { continue }
    $profiles += [pscustomobject]@{ Path = $d.FullName; Sid = $null; Loaded = $false }
}

# --- System-wide copy (checked only, never changed) ---------------------------
$machineExe = @(@($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } |
    ForEach-Object { Join-Path $_ 'Zoom\bin\Zoom.exe' } | Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ })
$keepData = $machineExe.Count -gt 0
if ($keepData) {
    Write-Log ("System-wide Zoom found ({0}). User data folders are kept; only per-user program folders are deleted." -f ($machineExe -join ', '))
} else {
    Write-Log "No system-wide Zoom. Profiles with a per-user copy have both Zoom folders deleted."
}

$zoomProcs = @(Get-CimInstance -ClassName Win32_Process | Where-Object { $_.ExecutablePath -like '*\AppData\*\Zoom\*' })

$removed      = @()
$failed       = @()
$skippedOpen  = @()
$unloadFailed = $false

foreach ($prof in $profiles) {
    $path   = $prof.Path
    $copies = @(Get-ZoomExe -ProfilePath $path)
    foreach ($c in $copies) {
        Write-Log ("{0} : found {1} version {2}" -f $path, $c.FullName, $c.VersionInfo.FileVersion)
    }

    # What to delete: nothing for data-only profiles, program folders only when
    # the system-wide copy uses the data, both Zoom folders otherwise.
    $targets = @()
    if ($copies.Count -gt 0) {
        if ($keepData) {
            $targets = @(Get-ZoomProgramItems -ProfilePath $path)
        } else {
            $targets = @($RelZoomDirs | ForEach-Object { Join-Path $path $_ } | Where-Object { Test-Path -LiteralPath $_ })
        }
    }
    $hasFiles = $targets.Count -gt 0

    # --- Zoom open from what will be deleted ---------------------------------
    $running = @($zoomProcs | Where-Object { Test-UnderPath -Path $_.ExecutablePath -Roots $targets })
    if ($running.Count -gt 0) {
        if (-not $forceClose) {
            Write-Log ("{0} : Zoom is open, skipped. Run again later, or with Close Zoom = Yes." -f $path) 'WARN'
            $skippedOpen += $path
            continue
        }
        foreach ($p in $running) {
            try {
                Stop-Process -Id $p.ProcessId -Force
                Write-Log ("{0} : closed {1} (PID {2})" -f $path, $p.Name, $p.ProcessId)
            } catch {
                Write-Log ("{0} : could not close {1} (PID {2}). {3}" -f $path, $p.Name, $p.ProcessId, $_.Exception.Message) 'WARN'
            }
        }
        Start-Sleep -Seconds 3
    }

    $profileOk = $true

    # --- Registry -------------------------------------------------------------
    if ($prof.Sid -and $prof.Loaded) {
        $root = "Registry::HKEY_USERS\$($prof.Sid)"
        if (Test-Path -LiteralPath $root) {
            $script:StepFailed = $false
            Remove-ZoomRegistry -Root $root -Label $path
            if ($script:StepFailed) { $profileOk = $false }
        }
    } elseif ($prof.Sid) {
        # Every signed-out hive is checked, because a folder deleted by hand
        # leaves the uninstall entry behind and inventory keeps reporting it.
        $hive = Join-Path $path 'NTUSER.DAT'
        if (Test-Path -LiteralPath $hive) {
            $load = Invoke-Reg @('load', "HKU\$MountName", $hive)
            if ($load.ExitCode -ne 0) {
                Write-Log ("{0} : could not load the registry hive. {1}" -f $path, $load.Output) 'ERROR'
                $profileOk = $false
            } else {
                try {
                    $script:StepFailed = $false
                    Remove-ZoomRegistry -Root $MountPs -Label $path
                    if ($script:StepFailed) { $profileOk = $false }
                } finally {
                    if (-not (Dismount-UserHive)) {
                        Write-Log ("{0} : could not unload the registry hive. Restart the endpoint before this user signs in." -f $path) 'ERROR'
                        $unloadFailed = $true
                    }
                }
            }
        }
    }

    if ($unloadFailed) {
        $failed += $path
        Write-Log "Stopping, so no other hive is loaded while one is stuck." 'ERROR'
        break
    }

    if (-not $hasFiles) {
        if (-not $profileOk) { $failed += $path }
        continue
    }

    # --- Files and shortcuts --------------------------------------------------
    $script:StepFailed = $false
    Remove-ZoomFiles -ProfilePath $path -Label $path -Targets $targets
    if ($script:StepFailed) { $profileOk = $false }

    foreach ($exe in @(Get-ZoomExe -ProfilePath $path)) {
        Write-Log ("{0} : still present: {1}" -f $path, $exe.FullName) 'ERROR'
        $profileOk = $false
    }

    if ($profileOk) {
        Write-Log ("{0} : removed" -f $path)
        $removed += $path
    } else {
        Write-Log ("{0} : not fully removed" -f $path) 'ERROR'
        $failed += $path
    }
}

# --- Summary ------------------------------------------------------------------
Write-Log "Summary:"
Write-Log ("  Removed: {0}" -f (Join-OrNone $removed))
Write-Log ("  Failed: {0}" -f (Join-OrNone $failed))
Write-Log ("  Skipped, Zoom open: {0}" -f (Join-OrNone $skippedOpen))

if ($unloadFailed)            { exit 6 }
if ($failed.Count -gt 0)      { exit 1 }
if ($skippedOpen.Count -gt 0) { exit 3 }
exit 0
