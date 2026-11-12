<#
.SYNOPSIS
    Tanium package script. Shrinks the Windows component store (C:\Windows\WinSxS) with DISM.

.DESCRIPTION
    Every Windows update leaves the older versions of the files it replaced in the component
    store. This script asks Windows to remove the versions that are no longer needed, using
    the built-in, Microsoft-supported command:

        dism.exe /Online /Cleanup-Image /StartComponentCleanup

    It first asks Windows how much can be freed and writes that to the action log.
    It does not restart the computer.

.PARAMETER ResetBase
    $1  Yes or No. Default No.
    Yes adds /ResetBase. That frees more space, but the updates that are installed right now
    can no longer be uninstalled afterwards. Updates installed later are not affected.

.NOTES
    Tanium command line:
      cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Invoke-ComponentCleanup.ps1 "$1"

    Exit codes:
      0 = cleanup finished
      1 = cleanup failed (see the action log and C:\Windows\Logs\DISM\dism.log)
      2 = skipped because Windows is waiting for a restart. Restart, then run again.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$ResetBase = 'No'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ResetBase)) { $ResetBase = 'No' }

# If the Tanium Client started the 32-bit PowerShell on 64-bit Windows, start again in the
# 64-bit one. DISM has to be the 64-bit version to work on 64-bit Windows.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:windir 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $powershell64) {
        & $powershell64 -ExecutionPolicy Bypass -NoProfile -NonInteractive -File $PSCommandPath $ResetBase
        exit $LASTEXITCODE
    }
}

$ExitCode = 0

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    Write-Host ('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

function Get-FreeBytes {
    return (New-Object System.IO.DriveInfo($env:SystemDrive)).AvailableFreeSpace
}

function Format-Size {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return '{0:N0} bytes' -f $Bytes
}

function Test-RestartPending {
    # True when Windows is waiting for a restart to finish installing updates.
    try {
        $machine = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
        foreach ($keyPath in @(
                'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
                'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
            $key = $machine.OpenSubKey($keyPath)
            if ($key) { $key.Close(); return $true }
        }
    }
    catch { }
    return $false
}

function Write-DismOutput {
    # Copies what DISM said into the action log, without the progress bar lines.
    param($Lines)
    foreach ($line in @($Lines)) {
        $text = ([string]$line).Trim()
        if ($text.Length -eq 0) { continue }
        if ($text -match '^\[[=\s\d\.%]*\]$') { continue }
        Write-Host ('    ' + $text)
    }
}

try {
    Write-Log 'Windows component cleanup started.'

    $text = $ResetBase.Trim().ToLowerInvariant()
    if     (@('yes', 'y', 'true', '1', 'on') -contains $text)  { $useResetBase = $true }
    elseif (@('no', 'n', 'false', '0', 'off') -contains $text) { $useResetBase = $false }
    else   { throw "ResetBase must be Yes or No. Received: '$ResetBase'" }

    if (Test-RestartPending) {
        $ExitCode = 2
        Write-Log 'Windows is waiting for a restart to finish installing updates. The cleanup cannot run until then. Restart this computer, then run the package again.' 'WARN'
    }
    else {
        $dism       = Join-Path $env:windir 'System32\dism.exe'
        $freeBefore = Get-FreeBytes
        Write-Log ("Free space on {0} before: {1}" -f $env:SystemDrive, (Format-Size $freeBefore))

        Write-Log 'Asking Windows how much can be cleaned up (this can take a few minutes).'
        $analysis = & $dism /Online /Cleanup-Image /AnalyzeComponentStore
        Write-DismOutput -Lines $analysis
        if ($LASTEXITCODE -ne 0) {
            Write-Log ("The check ended with DISM code {0}. The cleanup is still attempted." -f $LASTEXITCODE) 'WARN'
        }

        if ($useResetBase) {
            Write-Log 'Starting the cleanup with /ResetBase. Updates that are installed now can no longer be uninstalled afterwards.'
            $output = & $dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase
        }
        else {
            Write-Log 'Starting the cleanup. This can take from a few minutes to more than an hour.'
            $output = & $dism /Online /Cleanup-Image /StartComponentCleanup
        }
        $dismCode = $LASTEXITCODE
        Write-DismOutput -Lines $output

        $freeAfter = Get-FreeBytes
        Write-Log ("Free space on {0} after: {1} (change: {2})" -f $env:SystemDrive, (Format-Size $freeAfter), (Format-Size ([math]::Max([long]0, $freeAfter - $freeBefore))))

        if ($dismCode -eq 0) {
            Write-Log 'The cleanup finished.'
        }
        elseif ($dismCode -eq 3010) {
            Write-Log 'The cleanup finished. Windows asks for a restart to complete it.'
        }
        else {
            $ExitCode = 1
            Write-Log ("The cleanup failed with DISM code {0}. Details are in C:\Windows\Logs\DISM\dism.log on this computer." -f $dismCode) 'ERROR'
        }
    }
}
catch {
    $ExitCode = 1
    Write-Log ("Windows component cleanup failed: {0}" -f $_.Exception.Message) 'ERROR'
}

Write-Log ("Windows component cleanup finished with exit code {0}." -f $ExitCode)
exit $ExitCode
