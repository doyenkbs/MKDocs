<#
.SYNOPSIS
    Restores an IIS configuration backup by name. Built for a Tanium package.

.DESCRIPTION
    Usage: Restore-IISConfigBackup.ps1 "<backup name>"
    Example: Restore-IISConfigBackup.ps1 "PHP-Cleanup-20261105-094747"

    Restores the whole IIS configuration as it was when the backup was taken,
    using appcmd restore backup. Lists the available backups when the name is not found.

.NOTES
    Exit codes:
      0  Restored
      1  Failed (appcmd returned an error)
      2  Blocked: name missing or invalid, backup not found, or IIS not installed
    Log: C:\Windows\Temp\Restore-IISConfigBackup.log (also written to stdout)
#>

param([string]$BackupName)

$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $env:windir 'Temp\Restore-IISConfigBackup.log'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 's'), $Level, $Message
    Write-Output $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

try {
    # Tanium passes parameters URL-encoded (a hyphen arrives as %2d), so decode it first.
    $BackupName = [System.Uri]::UnescapeDataString([string]$BackupName).Trim().Trim('"')
    Write-Log "Start. Backup name: $BackupName"

    if ($BackupName -notmatch '^[A-Za-z0-9._-]+$') {
        Write-Log 'Blocked: backup name is empty or has characters other than letters, numbers, dot, underscore, and hyphen.' 'ERROR'
        exit 2
    }

    # Use Sysnative when running as a 32-bit process so System32 is not redirected to SysWOW64.
    $sysDir    = if (Test-Path "$env:windir\Sysnative") { "$env:windir\Sysnative" } else { "$env:windir\System32" }
    $appCmd    = Join-Path $sysDir 'inetsrv\appcmd.exe'
    $backupDir = Join-Path $sysDir 'inetsrv\backup'

    if (-not (Test-Path -LiteralPath $appCmd)) {
        Write-Log 'Blocked: IIS is not installed.' 'ERROR'
        exit 2
    }

    if (-not (Test-Path -LiteralPath (Join-Path $backupDir $BackupName))) {
        Write-Log "Blocked: backup '$BackupName' not found in $backupDir." 'ERROR'
        $available = @(Get-ChildItem -LiteralPath $backupDir -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -ExpandProperty Name)
        if ($available.Count -gt 0) {
            Write-Log "Available backups (newest first): $($available -join ', ')"
        } else {
            Write-Log 'No IIS backups exist on this endpoint.'
        }
        exit 2
    }

    $out  = & $appCmd restore backup $BackupName 2>&1
    $text = ($out | ForEach-Object { "$_" }) -join ' '
    Write-Log "appcmd restore backup $BackupName => exit $LASTEXITCODE | $text"

    if ($LASTEXITCODE -ne 0) {
        Write-Log 'Restore failed.' 'ERROR'
        exit 1
    }

    Write-Log 'Restored. Exit 0.'
    exit 0
}
catch {
    Write-Log "Failed: $($_.Exception.Message)" 'ERROR'
    exit 1
}
