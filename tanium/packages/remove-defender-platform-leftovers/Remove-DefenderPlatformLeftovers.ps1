<#
.SYNOPSIS
    Deletes leftover Defender platform folders after the Defender feature is removed. Built for a Tanium package.

.DESCRIPTION
    Tanium package command:
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-DefenderPlatformLeftovers.ps1

    Deletes C:\ProgramData\Microsoft\Windows Defender\Platform. Run it only after
    Remove-WindowsDefender.ps1 has completed and the server has restarted.

    Safety stop: if the WinDefend service still exists, nothing is deleted.

    Exit codes:
      0  Folder deleted, or it was not there
      1  Delete failed, or the folder is still present
      2  WinDefend service still exists, nothing deleted
#>

# Run as 64-bit so paths are not redirected.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

function Write-Log {
    param ([string]$Message, [string]$Level = 'INFO')
    Write-Output ("{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

$platform = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Platform'
Write-Log "Target folder: '$platform'"

# Never delete platform files while Defender is still installed
if (Get-Service -Name 'WinDefend' -ErrorAction SilentlyContinue) {
    Write-Log 'WinDefend service still exists. Remove the Defender feature and restart first. Nothing deleted.' 'ERROR'
    exit 2
}

if (-not (Test-Path -LiteralPath $platform)) {
    Write-Log 'Platform folder not present. Nothing to do.'
    exit 0
}

$versions = @(Get-ChildItem -LiteralPath $platform -Directory -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
Write-Log ("Found version folders: " + $(if ($versions) { $versions -join ', ' } else { '(none)' }))

$deleteErrors = @()
Remove-Item -LiteralPath $platform -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable deleteErrors

if (Test-Path -LiteralPath $platform) {
    # The folders are often locked down by ACL. Take ownership for Administrators and retry.
    Write-Log "First delete attempt left the folder in place ($($deleteErrors.Count) errors). Taking ownership and retrying." 'WARN'
    takeown.exe /F "$platform" /R /A /D Y | Out-Null
    icacls.exe "$platform" /grant '*S-1-5-32-544:(OI)(CI)F' /T /C /Q | Out-Null

    $deleteErrors = @()
    Remove-Item -LiteralPath $platform -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable deleteErrors
}

if (Test-Path -LiteralPath $platform) {
    Write-Log "Folder still present. $($deleteErrors.Count) delete errors." 'ERROR'
    $deleteErrors | Select-Object -First 5 | ForEach-Object {
        Write-Log "  $($_.Exception.Message)" 'ERROR'
    }
    exit 1
}

Write-Log 'Platform folder deleted.'
exit 0
