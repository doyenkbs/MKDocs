<#
.SYNOPSIS
    Removes the Microsoft Defender Antivirus feature from Windows Server. Built for a Tanium package.

.DESCRIPTION
    Tanium package command:
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-WindowsDefender.ps1

    Removes every installed Windows-Defender* feature:
      Server 2016       Windows-Defender, Windows-Defender-Gui, Windows-Defender-Features
      Server 2019/2022  Windows-Defender

    The script does not restart the server. It returns 3010 so the restart can be
    scheduled through the Tanium action.

    Exit codes:
      0     Removed with no restart needed, or nothing to remove
      3010  Removed, restart required
      1     Removal failed
      2     Not a server OS, nothing done
#>

# Run as 64-bit so the ServerManager module loads from System32.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

function Write-Log {
    param ([string]$Message, [string]$Level = 'INFO')
    Write-Output ("{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

$os = Get-CimInstance -ClassName Win32_OperatingSystem
Write-Log "Operating system: $($os.Caption)"

if ($os.ProductType -eq 1) {
    Write-Log 'Workstation OS detected. Uninstall-WindowsFeature only exists on Windows Server. Nothing done.' 'ERROR'
    exit 2
}

try {
    $installed = @(Get-WindowsFeature -Name 'Windows-Defender*' -ErrorAction Stop | Where-Object { $_.Installed })
}
catch {
    Write-Log "Could not read Windows features: $($_.Exception.Message)" 'ERROR'
    exit 1
}

if ($installed.Count -eq 0) {
    Write-Log 'No Windows Defender features installed. Nothing to remove.'
    exit 0
}

$names = $installed | Select-Object -ExpandProperty Name
Write-Log ("Removing: " + ($names -join ', '))

try {
    $result = Uninstall-WindowsFeature -Name $names -ErrorAction Stop
}
catch {
    Write-Log "Uninstall-WindowsFeature failed: $($_.Exception.Message)" 'ERROR'
    exit 1
}

if (-not $result.Success) {
    Write-Log "Removal failed. ExitCode: $($result.ExitCode)" 'ERROR'
    exit 1
}

if ("$($result.RestartNeeded)" -eq 'Yes') {
    Write-Log 'Removal succeeded. Restart required to finish.'
    exit 3010
}

Write-Log 'Removal succeeded. No restart required.'
exit 0
