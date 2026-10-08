<#
.SYNOPSIS
    Deletes a single file on the endpoint. Built for a Tanium package.

.DESCRIPTION
    Tanium package command:
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-File.ps1 "$1" "$2"

    $1  File Path      Full local path of the file to delete, e.g. C:\ProgramData\OldApp\old.dll
    $2  Confirm Name   Must match the file's name exactly, e.g. old.dll (not case sensitive)

    Folders are rejected. Use Remove-Folder.ps1 for folders.

    Exit codes:
      0  File deleted, or it was already gone
      1  Delete failed (usually the file is locked or in use)
      2  Invalid or missing file path, or the path is a folder
      3  Confirmation did not match the file name, nothing deleted
      4  Path is in a protected location or is a symlink, nothing deleted
#>
param (
    [string]$FilePath = "",
    [string]$ConfirmName = ""
)

# Run as 64-bit so C:\Windows\System32 is not redirected to SysWOW64.
# The raw (still URL-encoded) values are passed on, so they are decoded only once.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($FilePath)    { $argList += @('-FilePath', $FilePath) }
    if ($ConfirmName) { $argList += @('-ConfirmName', $ConfirmName) }
    & $ps64 @argList
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'

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

$path    = ConvertFrom-TaniumParam $FilePath
$confirm = ConvertFrom-TaniumParam $ConfirmName

Write-Log "Requested file: '$path'"
Write-Log "Confirmation value: '$confirm'"

# --- Validate the path --------------------------------------------------------
if (-not $path) {
    Write-Log "File Path is empty. Nothing deleted." 'ERROR'
    exit 2
}
if ($path -notmatch '^[A-Za-z]:\\') {
    Write-Log "File Path must be a full local path like C:\Folder\file.txt. UNC and relative paths are not allowed." 'ERROR'
    exit 2
}
if ($path -match '[\*\?]' -or $path.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0) {
    Write-Log "File Path contains wildcards or invalid characters." 'ERROR'
    exit 2
}
if ($path.EndsWith('\')) {
    Write-Log "File Path ends with a backslash, which points to a folder. Use Remove-Folder.ps1 for folders." 'ERROR'
    exit 2
}
try {
    # Normalizes ..\ segments and duplicate slashes so the protected-location check can't be bypassed
    $full = [IO.Path]::GetFullPath($path)
} catch {
    Write-Log "File Path could not be resolved: $($_.Exception.Message)" 'ERROR'
    exit 2
}
Write-Log "Resolved file: '$full'"

$parent = Split-Path -Path $full -Parent
$leaf   = Split-Path -Path $full -Leaf

# --- Protected locations ------------------------------------------------------
# Any file inside these trees is refused
$protectedTrees = @(@(
    (Join-Path $env:SystemRoot 'System32')
    (Join-Path $env:SystemRoot 'SysWOW64')
    (Join-Path $env:SystemRoot 'SysNative')
    (Join-Path $env:SystemRoot 'WinSxS')
    (Join-Path $env:SystemRoot 'Boot')
    (Join-Path $env:SystemDrive 'Boot')
    (Join-Path $env:SystemDrive 'Recovery')
) | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } | Select-Object -Unique)

# Files sitting directly in these folders are refused (bootmgr, pagefile.sys, explorer.exe, etc.)
$protectedFolders = @(@(
    "$env:SystemDrive\"
    $env:SystemRoot
) | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } | Select-Object -Unique)

# Tanium Client install folder (64-bit and 32-bit registry locations)
$taniumDir = $null
foreach ($key in 'HKLM:\SOFTWARE\Tanium\Tanium Client', 'HKLM:\SOFTWARE\WOW6432Node\Tanium\Tanium Client') {
    try {
        $taniumDir = (Get-ItemProperty -Path $key -Name Path -ErrorAction Stop).Path.TrimEnd('\')
        break
    } catch { }
}
if ($taniumDir) { $protectedTrees += $taniumDir }

$cmp = [StringComparison]::OrdinalIgnoreCase
$parentTrimmed = $parent.TrimEnd('\')
$blockReason = $null

foreach ($t in $protectedTrees) {
    if ($full.StartsWith("$t\", $cmp)) { $blockReason = "inside protected folder ($t)"; break }
}
if (-not $blockReason) {
    foreach ($f in $protectedFolders) {
        if ($parentTrimmed.Equals($f, $cmp)) { $blockReason = "file directly in protected folder ($f\)"; break }
    }
}

if ($blockReason) {
    Write-Log "Refusing to delete '$full': $blockReason. Nothing deleted." 'ERROR'
    exit 4
}

# --- Confirmation (friction layer) --------------------------------------------
if ($confirm -ne $leaf) {
    Write-Log "Confirmation '$confirm' does not match file name '$leaf'. Nothing deleted." 'ERROR'
    exit 3
}
Write-Log "Confirmation matched file name '$leaf'."

# --- Target checks ------------------------------------------------------------
if (-not (Test-Path -LiteralPath $full)) {
    Write-Log "File not found. Nothing to do."
    exit 0
}

$item = Get-Item -LiteralPath $full -Force
if ($item.PSIsContainer) {
    Write-Log "'$full' is a folder, not a file. Use Remove-Folder.ps1 for folders. Nothing deleted." 'ERROR'
    exit 2
}
if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    Write-Log "'$full' is a symbolic link. Refusing to delete." 'ERROR'
    exit 4
}

# --- Delete -------------------------------------------------------------------
Write-Log ("Deleting '{0}' ({1:N0} bytes, modified {2:yyyy-MM-dd HH:mm}, attributes: {3})." -f $full, $item.Length, $item.LastWriteTime, $item.Attributes)

try {
    # -Force also removes read-only, hidden, and system files
    Remove-Item -LiteralPath $full -Force -ErrorAction Stop
} catch {
    Write-Log "Delete error: $($_.Exception.Message)" 'ERROR'
}

if (Test-Path -LiteralPath $full) {
    Write-Log "File still exists. It is most likely locked by a running process or service." 'ERROR'
    exit 1
}

Write-Log "File deleted."
exit 0
