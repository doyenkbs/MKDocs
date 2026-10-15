######################################################################
# Remove VS Code User Install, Signed-Out Profiles (Tanium package)
#
# Tanium package command:
#   cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-VSCodeUserInstallOffline.ps1
#
# Runs as SYSTEM. For each profile that is NOT signed in:
#   1. Loads the user's registry hive (NTUSER.DAT) under a temporary name,
#      deletes the VS Code user uninstall entry if present, and unloads it.
#   2. If VS Code was found, deletes the install folder, the user's Start menu
#      folder for VS Code, and the desktop shortcut if it points to the install.
#
# The VS Code uninstaller is not run (it needs the user's session), so a few
# harmless leftovers stay, such as the user PATH entry for VS Code\bin.
# Signed-in profiles are reported, not changed. Use Remove-VSCodeUserInstall.ps1
# for those.
#
# Exit codes (when more than one applies, the highest-priority code wins:
# 6, then 1, then 4):
#   0  Removed from every signed-out profile that had it, or no profile has it
#   1  At least one profile could not be fully cleaned
#   4  Signed-in users still have it. Use the signed-in package.
#   5  Not running as SYSTEM or an administrator
#   6  A registry hive could not be unloaded. Restart the endpoint before
#      that user signs in.
######################################################################

# Restart as 64-bit if the Tanium client started 32-bit PowerShell.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'

$RelInstallDir   = 'AppData\Local\Programs\Microsoft VS Code'
$RelStartMenuDir = 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Visual Studio Code'
$RelDesktopLink  = 'Desktop\Visual Studio Code.lnk'
$UninstallKeyRel = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{771FD6B0-FA20-440A-A002-3B3BAC16DC50}_is1'
$MountName       = 'VSCODE_CLEANUP'
$MountPs         = "Registry::HKEY_USERS\$MountName"

function Write-Log {
    param ([string]$Message, [string]$Level = 'INFO')
    Write-Output ("{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

function Join-OrNone {
    param ([string[]]$Items)
    if ($Items -and $Items.Count -gt 0) { return ($Items -join ', ') }
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

# --- Elevation check ----------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Not running as SYSTEM or an administrator. User registry hives cannot be loaded. Nothing changed." 'ERROR'
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

$profiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter "Special=False" | Where-Object { $_.LocalPath })

$removed      = @()
$failed       = @()
$signedInLeft = @()
$unloadFailed = $false

foreach ($prof in $profiles) {
    $path   = $prof.LocalPath
    $dir    = Join-Path $path $RelInstallDir
    $hasDir = Test-Path -LiteralPath $dir

    if ($prof.Loaded) {
        if ($hasDir) {
            Write-Log ("{0} : user is signed in, skipped. Use the signed-in package." -f $path) 'WARN'
            $signedInLeft += $path
        }
        continue
    }

    $hive = Join-Path $path 'NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $hive)) { continue }

    $profileOk = $true
    $hasKey    = $false

    # --- 1. Uninstall entry in the user's registry hive ------------------------
    # Every signed-out hive is checked, because a folder deleted by hand leaves
    # the entry behind and scanners keep reporting it.
    $load = Invoke-Reg @('load', "HKU\$MountName", $hive)
    if ($load.ExitCode -ne 0) {
        Write-Log ("{0} : could not load the registry hive. {1}" -f $path, $load.Output) 'ERROR'
        $profileOk = $false
    } else {
        try {
            $keyPath = "$MountPs\$UninstallKeyRel"
            $hasKey  = Test-Path -LiteralPath $keyPath
            if ($hasKey) {
                Remove-Item -LiteralPath $keyPath -Recurse -Force
                if (Test-Path -LiteralPath $keyPath) { throw 'The entry is still present after the delete.' }
                Write-Log ("{0} : removed the VS Code uninstall entry from the registry" -f $path)
            }
        } catch {
            Write-Log ("{0} : could not remove the uninstall entry. {1}" -f $path, $_.Exception.Message) 'ERROR'
            $profileOk = $false
        } finally {
            if (-not (Dismount-UserHive)) {
                Write-Log ("{0} : could not unload the registry hive. Restart the endpoint before this user signs in." -f $path) 'ERROR'
                $unloadFailed = $true
            }
        }
    }

    if ($unloadFailed) {
        $failed += $path
        Write-Log "Stopping, so no other hive is loaded while one is stuck." 'ERROR'
        break
    }

    if (-not $hasDir -and -not $hasKey) {
        if (-not $profileOk) { $failed += $path }
        continue
    }

    # --- 2. Files and shortcuts ------------------------------------------------
    $targets = @($dir, (Join-Path $path $RelStartMenuDir))

    # Only remove the desktop shortcut if it points into the per-user install.
    $lnk = Join-Path $path $RelDesktopLink
    if (Test-Path -LiteralPath $lnk) {
        $target = ''
        try { $target = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath } catch { }
        if ($target -and $target.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase)) { $targets += $lnk }
    }

    foreach ($item in $targets) {
        if (-not (Test-Path -LiteralPath $item)) { continue }
        try {
            Remove-Item -LiteralPath $item -Recurse -Force
            Write-Log ("{0} : deleted {1}" -f $path, $item)
        } catch {
            Write-Log ("{0} : could not delete {1}. {2}" -f $path, $item, $_.Exception.Message) 'ERROR'
            $profileOk = $false
        }
    }

    if (Test-Path -LiteralPath $dir) { $profileOk = $false }

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
Write-Log ("  Signed in, skipped: {0}" -f (Join-OrNone $signedInLeft))

if ($unloadFailed)             { exit 6 }
if ($failed.Count -gt 0)       { exit 1 }
if ($signedInLeft.Count -gt 0) { exit 4 }
exit 0
