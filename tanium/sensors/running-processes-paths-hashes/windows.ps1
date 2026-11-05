# Running Processes - Paths - Hashes (Windows)
# Pure PowerShell. No Python or Incident Response tools required.
# Output: <executable path>|#<hash>   (hash empty when HashType = NONE)
# When running as 32-bit on 64-bit Windows, System32 reads go through Sysnative
# so the real 64-bit file is hashed, not the SysWOW64 copy.

$ErrorActionPreference = 'SilentlyContinue'
$sep      = '|#'
$maxBytes = 1GB

# Parameter (Tanium URL-encodes parameter values)
$hashType = [uri]::UnescapeDataString('||HashType||')
if ([string]::IsNullOrWhiteSpace($hashType) -or $hashType -like '*HashType*') { $hashType = 'MD5' }
$hashType = $hashType.Trim().ToUpper()

if (@('MD5','SHA1','SHA256','NONE') -notcontains $hashType) {
    Write-Output "Error: Unsupported HashType '$hashType'. Use MD5, SHA1, SHA256, or NONE."
    exit
}

# WOW64 redirection handling
$is32on64  = [bool]$env:PROCESSOR_ARCHITEW6432
$sys32     = Join-Path $env:windir 'System32'
$sysnative = Join-Path $env:windir 'Sysnative'

function Get-ReadPath {
    param([string]$Path)
    if ($is32on64 -and $Path.StartsWith($sys32, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $sysnative + $Path.Substring($sys32.Length)
    }
    return $Path
}

function Get-FileHashSafe {
    param([string]$Path, [string]$Algorithm)
    $algo = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]'ReadWrite, Delete')
    try {
        ([System.BitConverter]::ToString($algo.ComputeHash($fs))).Replace('-', '').ToLower()
    }
    finally {
        $fs.Dispose()
        $algo.Dispose()
    }
}

try {
    $procs = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop
}
catch {
    try { $procs = Get-WmiObject -Class Win32_Process -ErrorAction Stop }
    catch {
        Write-Output "Error: Unable to query Win32_Process: $($_.Exception.Message)"
        exit
    }
}

$paths = $procs |
    Where-Object { $_.ExecutablePath } |
    Select-Object -ExpandProperty ExecutablePath |
    Sort-Object -Unique

foreach ($p in $paths) {
    if ($hashType -eq 'NONE') {
        Write-Output "$p$sep"
        continue
    }
    try {
        $readPath = Get-ReadPath -Path $p
        $item = Get-Item -LiteralPath $readPath -ErrorAction Stop
        if ($item.Length -gt $maxBytes) {
            Write-Output "Error hashing ${p}: file exceeds 1 GB"
            continue
        }
        $h = Get-FileHashSafe -Path $readPath -Algorithm $hashType
        Write-Output "$p$sep$h"
    }
    catch {
        Write-Output "Error hashing ${p}: $($_.Exception.Message)"
    }
}
