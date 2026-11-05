<#
.SYNOPSIS
    Removes one or more third-party driver packages from the DriverStore, matched by FileRepository folder name.

.DESCRIPTION
    For each folder name, resolves the oem##.inf published name for
    C:\Windows\System32\DriverStore\FileRepository\<FolderName>
    and runs pnputil /delete-driver against it WITHOUT /force.
    pnputil refuses to remove a package that a device is currently using.

    Folder names must look like <name>.inf_<arch>_<16 hex>, for example:
        iclsclient.inf_amd64_c25dbc60ad3b371a
    Wildcards are rejected.

    Per-folder result codes (the script exits with the highest code seen):
        0 = package deleted, or folder and package already gone
        1 = folder exists but no registered package points to it (orphaned, nothing deleted)
        2 = pnputil refused the delete (package most likely in use)
        3 = script error (bad folder name or driver lookup failed)
        4 = pnputil reported success but the folder is still present

    Log: C:\Windows\Temp\Remove-DriverStorePackage.log

.PARAMETER FolderNames
    One or more FileRepository folder names, comma-separated.
    Example: iclsclient.inf_amd64_c25dbc60ad3b371a,iclsclient.inf_amd64_9877bfa47b14db1d
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$FolderNames
)

# Relaunch in 64-bit PowerShell if started from a 32-bit host (avoids System32 redirection)
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:windir 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path -FolderNames $FolderNames
    exit $LASTEXITCODE
}

$LogPath = Join-Path $env:windir 'Temp\Remove-DriverStorePackage.log'

function Write-Log {
    param([string]$Message)
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Output $line
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
}

$pattern = '^(?<inf>[a-z0-9_\-\.]+\.inf)_(amd64|x86|arm64|wow64)_[0-9a-f]{16}$'

# Tanium URL-encodes package parameter values (. -> %2e, _ -> %5f, , -> %2c). Decode before parsing.
$decoded = [System.Uri]::UnescapeDataString($FolderNames)
if ($decoded -ne $FolderNames) { Write-Log "Decoded parameter: $decoded" }

$targets = @($decoded -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })

if ($targets.Count -eq 0) {
    Write-Log 'ERROR: No folder names supplied.'
    exit 3
}

foreach ($t in $targets) {
    if ($t -notmatch $pattern) {
        Write-Log "ERROR: '$t' is not a valid FileRepository folder name. Nothing was deleted."
        exit 3
    }
}

try {
    $allDrivers = @(Get-WindowsDriver -Online -ErrorAction Stop)
}
catch {
    Write-Log "ERROR: Get-WindowsDriver failed: $($_.Exception.Message)"
    exit 3
}

$pnputil   = Join-Path $env:windir 'System32\pnputil.exe'
$worstCode = 0

foreach ($folderName in $targets) {
    $null    = $folderName -match $pattern
    $infName = $Matches['inf']
    $folderPath = Join-Path $env:windir "System32\DriverStore\FileRepository\$folderName"
    Write-Log "Target folder: $folderPath"

    $match = @($allDrivers | Where-Object { $_.OriginalFileName -like "*\$folderName\$infName" })

    if ($match.Count -eq 0) {
        if (Test-Path -LiteralPath $folderPath) {
            Write-Log "RESULT [$folderName]: Folder exists but no registered package points to it (orphaned). Nothing deleted."
            $code = 1
        }
        else {
            Write-Log "RESULT [$folderName]: Folder and package are not present. Nothing to do."
            $code = 0
        }
        if ($code -gt $worstCode) { $worstCode = $code }
        continue
    }

    $code = 0
    foreach ($pkg in $match) {
        $oem = $pkg.Driver
        Write-Log "Found $oem for $folderName (version $($pkg.Version), date $($pkg.Date))"

        $out = & $pnputil /delete-driver $oem 2>&1 | Out-String
        $pnpCode = $LASTEXITCODE
        Write-Log "pnputil exit code $pnpCode. Output: $($out.Trim())"

        if ($pnpCode -ne 0) {
            Write-Log "RESULT [$folderName]: pnputil refused to delete $oem. It is most likely in use."
            $code = 2
        }
    }

    if ($code -eq 0) {
        if (Test-Path -LiteralPath $folderPath) {
            Write-Log "RESULT [$folderName]: pnputil reported success but the folder is still present."
            $code = 4
        }
        else {
            Write-Log "RESULT [$folderName]: Driver package deleted and folder removed."
        }
    }

    if ($code -gt $worstCode) { $worstCode = $code }
}

Write-Log "Finished. Exit code $worstCode."
exit $worstCode
