######################################################################
# Remove VS Code User Install, Signed-In Users (Tanium package)
#
# Tanium package command:
#   cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-VSCodeUserInstall.ps1 "$1"
#
# $1  Close VS Code   No (or blank) or Yes. Yes closes VS Code for the user
#                     before uninstalling. Unsaved work can be lost.
#
# Runs as SYSTEM. For each signed-in user who has the per-user copy of
# VS Code (the "User" installer, under %LOCALAPPDATA%\Programs), runs that
# user's own unins000.exe in the user's session through a one-time
# scheduled task. Running it as the user removes both the files and the
# uninstall entry in the user's registry. Running it as SYSTEM would leave
# the registry entry behind.
#
# Profiles that are not signed in are reported, not changed. Use
# Remove-VSCodeUserInstallOffline.ps1 for those.
#
# Exit codes (when more than one applies, the lowest non-zero code wins):
#   0  Removed for every signed-in user who had it, or no profile has it
#   1  The uninstall could not start, or finished with the install still present
#   2  Invalid parameter
#   3  At least one user was skipped because VS Code was open (Close VS Code = No)
#   4  Profiles that are not signed in still have it. Use the signed-out package.
#   5  Not running as SYSTEM or an administrator
######################################################################

param(
    [string]$CloseCode = ""
)

# Restart as 64-bit if the Tanium client started 32-bit PowerShell.
# The raw (still URL-encoded) value is passed on, so it is decoded only once.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($CloseCode) { $argList += @('-CloseCode', $CloseCode) }
    & $ps64 @argList
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'

$RelInstallDir   = 'AppData\Local\Programs\Microsoft VS Code'
$UninstallKeyRel = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{771FD6B0-FA20-440A-A002-3B3BAC16DC50}_is1'
$UninstallerArgs = '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES'
$TaskPrefix      = 'VSCodeUserUninstall_'
$WaitMinutes     = 5

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

function Get-ProcessOwnerSid {
    param ($Process)
    try { return (Invoke-CimMethod -InputObject $Process -MethodName GetOwnerSid).Sid } catch { return $null }
}

function Join-OrNone {
    param ([string[]]$Items)
    if ($Items -and $Items.Count -gt 0) { return ($Items -join ', ') }
    return 'none'
}

# --- Validate parameter -------------------------------------------------------
$closeValue = ConvertFrom-TaniumParam $CloseCode
Write-Log "Close VS Code parameter: '$closeValue'"

if (-not $closeValue -or $closeValue -eq 'No') {
    $forceClose = $false
} elseif ($closeValue -eq 'Yes') {
    $forceClose = $true
} else {
    Write-Log "Unknown Close VS Code value '$closeValue'. Use No (or leave it blank), or Yes." 'ERROR'
    exit 2
}

# --- Elevation check ----------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Not running as SYSTEM or an administrator. Other users' profiles and scheduled tasks cannot be managed. Nothing changed." 'ERROR'
    exit 5
}

# --- Profiles that have the per-user copy -------------------------------------
$profiles    = @(Get-CimInstance -ClassName Win32_UserProfile -Filter "Special=False" | Where-Object { $_.LocalPath })
$withInstall = @($profiles | Where-Object { Test-Path -LiteralPath (Join-Path $_.LocalPath $RelInstallDir) })

if ($withInstall.Count -eq 0) {
    Write-Log "No profile has the VS Code user install. Nothing to do."
    exit 0
}
Write-Log ("Profiles with the VS Code user install: {0}" -f $withInstall.Count)

# --- Signed-in users (owners of explorer.exe) ---------------------------------
$signedIn = @{}
foreach ($p in @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'")) {
    $sid = Get-ProcessOwnerSid $p
    if (-not $sid -or $signedIn.ContainsKey($sid)) { continue }
    try {
        $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwner
        if ($owner.User) { $signedIn[$sid] = "{0}\{1}" -f $owner.Domain, $owner.User }
    } catch { }
}

$codeProcs = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='Code.exe'")

$started     = @()
$removed     = @()
$skipped     = @()
$notSignedIn = @()
$failed      = @()

# --- Start the uninstaller in each signed-in user's session --------------------
foreach ($prof in $withInstall) {
    $sid = $prof.SID
    $dir = Join-Path $prof.LocalPath $RelInstallDir

    if (-not $signedIn.ContainsKey($sid)) {
        Write-Log ("{0} : not signed in, skipped. Use the signed-out package for this profile." -f $prof.LocalPath) 'WARN'
        $notSignedIn += $prof.LocalPath
        continue
    }

    $account = $signedIn[$sid]
    $exe     = Join-Path $dir 'unins000.exe'
    $log     = Join-Path $prof.LocalPath 'AppData\Local\Temp\VSCodeUserUninstall.log'

    if (-not (Test-Path -LiteralPath $exe)) {
        Write-Log ("{0} : the install folder exists but unins000.exe is missing. Use the signed-out package after the user signs out." -f $account) 'ERROR'
        $failed += $account
        continue
    }

    $userCode = @($codeProcs | Where-Object { (Get-ProcessOwnerSid $_) -eq $sid })
    if ($userCode.Count -gt 0) {
        if ($forceClose) {
            foreach ($c in $userCode) { Stop-Process -Id $c.ProcessId -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Seconds 5
            Write-Log ("{0} : VS Code was open ({1} processes). Closed it." -f $account, $userCode.Count) 'WARN'
        } else {
            Write-Log ("{0} : VS Code is open, skipped. Ask the user to close it, or run again with Close VS Code = Yes." -f $account) 'WARN'
            $skipped += $account
            continue
        }
    }

    try {
        Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
        $taskName  = $TaskPrefix + ($sid -replace '-', '_')
        $action    = New-ScheduledTaskAction -Execute $exe -Argument ('{0} /LOG="{1}"' -f $UninstallerArgs, $log)
        $taskUser  = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
        $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $taskUser -Settings $settings -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName
        Write-Log ("{0} : uninstall started" -f $account)
        $started += [pscustomobject]@{ Account = $account; Sid = $sid; Exe = $exe; Log = $log; Task = $taskName }
    } catch {
        Write-Log ("{0} : could not start the uninstall task. {1}" -f $account, $_.Exception.Message) 'ERROR'
        $failed += $account
    }
}

# --- Wait for the uninstallers ------------------------------------------------
# The uninstaller hands off to a temporary copy and exits right away, so the task
# result alone does not show when it is done. It is done when unins000.exe is gone.
if ($started.Count -gt 0) {
    Write-Log ("Waiting up to {0} minutes for the uninstaller(s) to finish." -f $WaitMinutes)
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    while ((Get-Date) -lt $deadline -and @($started | Where-Object { Test-Path -LiteralPath $_.Exe }).Count -gt 0) {
        Start-Sleep -Seconds 10
    }
}

# --- Verify each user ---------------------------------------------------------
foreach ($s in $started) {
    $info = Get-ScheduledTaskInfo -TaskName $s.Task -ErrorAction SilentlyContinue
    if ($info) {
        Write-Log ("{0} : task last run {1}, result 0x{2:X}" -f $s.Account, $info.LastRunTime, $info.LastTaskResult)
    }

    $keyPath = "Registry::HKEY_USERS\{0}\{1}" -f $s.Sid, $UninstallKeyRel
    if (Test-Path -LiteralPath $s.Exe) {
        Write-Log ("{0} : still installed after {1} minutes." -f $s.Account, $WaitMinutes) 'ERROR'
        $failed += $s.Account
    } elseif (Test-Path -LiteralPath $keyPath) {
        Write-Log ("{0} : files removed, but the uninstall entry is still in the registry." -f $s.Account) 'ERROR'
        $failed += $s.Account
    } else {
        Write-Log ("{0} : removed" -f $s.Account)
        $removed += $s.Account
    }

    if (Test-Path -LiteralPath $s.Log) {
        Write-Log ("--- last 20 lines of {0} ---" -f $s.Log)
        Get-Content -LiteralPath $s.Log -Tail 20 | ForEach-Object { Write-Output $_ }
    } else {
        Write-Log ("{0} : no uninstaller log. The uninstaller probably never started." -f $s.Account) 'WARN'
    }

    Unregister-ScheduledTask -TaskName $s.Task -Confirm:$false -ErrorAction SilentlyContinue
}

# --- Summary ------------------------------------------------------------------
Write-Log "Summary:"
Write-Log ("  Removed: {0}" -f (Join-OrNone $removed))
Write-Log ("  Failed: {0}" -f (Join-OrNone $failed))
Write-Log ("  Skipped, VS Code open: {0}" -f (Join-OrNone $skipped))
Write-Log ("  Not signed in: {0}" -f (Join-OrNone $notSignedIn))

if ($failed.Count -gt 0)      { exit 1 }
if ($skipped.Count -gt 0)     { exit 3 }
if ($notSignedIn.Count -gt 0) { exit 4 }
exit 0
