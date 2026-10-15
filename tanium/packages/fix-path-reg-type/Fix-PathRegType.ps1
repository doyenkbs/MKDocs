<#
.SYNOPSIS
    Converts the machine Path registry value from REG_SZ to REG_EXPAND_SZ
    without changing its data. Built for a Tanium package.

.DESCRIPTION
    Tanium package command:
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Fix-PathRegType.ps1

    Value fixed:
      HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment\Path

    The data is read raw, so %SystemRoot% stays %SystemRoot% and is never
    replaced with C:\Windows. The value is overwritten in place with one call,
    never deleted and recreated. The whole Environment key is exported to
    C:\Windows\Temp\Environment_Path_backup.reg before anything is written.

    HKLM\SYSTEM is not redirected for 32-bit processes, so the script works
    from 32-bit or 64-bit PowerShell.

    Exit codes:
      0  Converted to REG_EXPAND_SZ, or it already was REG_EXPAND_SZ
      1  Write or verification failed. Restore from the backup
      2  Backup failed. Nothing changed
      3  Path is missing, empty, or an unexpected type. Nothing changed
#>

$keyPath = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$backup  = 'C:\Windows\Temp\Environment_Path_backup.reg'
$noExpand = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
$expandKind = [Microsoft.Win32.RegistryValueKind]::ExpandString

function Write-Log {
    param ([string]$Message, [string]$Level = 'INFO')
    Write-Output ("{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

$key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($keyPath, $true)
if (-not $key) {
    Write-Log "Could not open HKLM\$keyPath for writing. Is the script running as SYSTEM or an administrator?" 'ERROR'
    exit 3
}

try {
    # --- Read the current type and raw data ----------------------------------
    if ($key.GetValueNames() -notcontains 'Path') {
        Write-Log 'Path value does not exist. Nothing changed.' 'ERROR'
        exit 3
    }
    $kind = $key.GetValueKind('Path')
    $raw  = $key.GetValue('Path', $null, $noExpand)
    Write-Log "Current type: $kind"

    if ($kind -eq $expandKind) {
        Write-Log 'Path is already REG_EXPAND_SZ. Nothing to do.'
        exit 0
    }
    if ($kind -ne [Microsoft.Win32.RegistryValueKind]::String) {
        Write-Log "Path is $kind, which this script does not handle. Nothing changed." 'ERROR'
        exit 3
    }
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Write-Log 'Path is empty. Nothing changed.' 'ERROR'
        exit 3
    }
    Write-Log ("Path has {0} entries. Contains variables: {1}" -f ($raw -split ';' | Where-Object { $_ }).Count, ($raw -match '%'))

    # --- Back up the whole Environment key -----------------------------------
    & reg.exe export "HKLM\$keyPath" $backup /y 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backup)) {
        Write-Log "Backup to $backup failed (reg.exe exit $LASTEXITCODE). Nothing changed." 'ERROR'
        exit 2
    }
    Write-Log "Backup saved: $backup"

    # --- Overwrite in place with the new type --------------------------------
    try {
        $key.SetValue('Path', $raw, $expandKind)
    } catch {
        Write-Log "Write failed: $($_.Exception.Message)" 'ERROR'
        exit 1
    }

    # --- Verify --------------------------------------------------------------
    $newKind = $key.GetValueKind('Path')
    $newRaw  = $key.GetValue('Path', $null, $noExpand)
    if ($newKind -eq $expandKind -and $newRaw -ceq $raw) {
        Write-Log 'Converted Path from REG_SZ to REG_EXPAND_SZ. Data unchanged.'
        Write-Log 'Running processes keep their old environment until they restart or the machine reboots.'
        exit 0
    }
    Write-Log "Verification failed. Type is now $newKind, data matches: $($newRaw -ceq $raw). Restore from $backup." 'ERROR'
    exit 1
}
finally {
    $key.Close()
}
