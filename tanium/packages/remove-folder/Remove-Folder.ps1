<#
.SYNOPSIS
    Deletes a folder on the endpoint. Built for a Tanium package.

.DESCRIPTION
    Tanium package command:
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-Folder.ps1 "$1" "$2"

    $1  Folder Path    Full local path of the folder to delete, e.g. C:\ProgramData\OldApp
    $2  Confirm Name   Must match the folder's name exactly, e.g. OldApp (not case sensitive)

    Exit codes:
      0  Folder deleted, or it was already gone
      1  Delete failed or items remain (usually locked files)
      2  Invalid or missing folder path
      3  Confirmation did not match the folder name, nothing deleted
      4  Path is protected or is a junction/symlink, nothing deleted
#>
param (
    [string]$FolderPath = "",
    [string]$ConfirmName = ""
)

# Run as 64-bit so C:\Windows\System32 is not redirected to SysWOW64.
# The raw (still URL-encoded) values are passed on, so they are decoded only once.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($FolderPath)  { $argList += @('-FolderPath', $FolderPath) }
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

$path    = ConvertFrom-TaniumParam $FolderPath
$confirm = ConvertFrom-TaniumParam $ConfirmName

Write-Log "Requested folder: '$path'"
Write-Log "Confirmation value: '$confirm'"

# --- Validate the path --------------------------------------------------------
if (-not $path) {
    Write-Log "Folder Path is empty. Nothing deleted." 'ERROR'
    exit 2
}
if ($path -notmatch '^[A-Za-z]:\\') {
    Write-Log "Folder Path must be a full local path like C:\Folder. UNC and relative paths are not allowed." 'ERROR'
    exit 2
}
if ($path -match '[\*\?]' -or $path.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0) {
    Write-Log "Folder Path contains wildcards or invalid characters." 'ERROR'
    exit 2
}
try {
    # Normalizes ..\ segments and duplicate slashes so the protected-path check can't be bypassed
    $full = [IO.Path]::GetFullPath($path).TrimEnd('\')
} catch {
    Write-Log "Folder Path could not be resolved: $($_.Exception.Message)" 'ERROR'
    exit 2
}
Write-Log "Resolved folder: '$full'"

# --- Protected paths ----------------------------------------------------------
$usersDir = Join-Path $env:SystemDrive 'Users'
$protectedPaths = @(
    $env:SystemRoot
    (Join-Path $env:SystemRoot 'System32')
    (Join-Path $env:SystemRoot 'SysWOW64')
    $env:ProgramFiles
    $env:ProgramW6432          # 64-bit Program Files, even if PowerShell runs 32-bit
    ${env:ProgramFiles(x86)}
    $env:ProgramData
    $usersDir
    (Join-Path $usersDir 'Public')
    (Join-Path $usersDir 'Default')
) | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } | Select-Object -Unique

# Tanium Client install folder (64-bit and 32-bit registry locations)
$taniumDir = $null
foreach ($key in 'HKLM:\SOFTWARE\Tanium\Tanium Client', 'HKLM:\SOFTWARE\WOW6432Node\Tanium\Tanium Client') {
    try {
        $taniumDir = (Get-ItemProperty -Path $key -Name Path -ErrorAction Stop).Path.TrimEnd('\')
        break
    } catch { }
}

$cmp = [StringComparison]::OrdinalIgnoreCase
$blockReason = $null

if ($full -match '^[A-Za-z]:$') {
    $blockReason = "drive root"
}
foreach ($p in $protectedPaths) {
    if ($blockReason) { break }
    if ($full.Equals($p, $cmp)) { $blockReason = "protected system folder ($p)" }
    elseif ($p.StartsWith("$full\", $cmp)) { $blockReason = "parent of protected folder ($p)" }
}
if (-not $blockReason -and $taniumDir) {
    if ($full.Equals($taniumDir, $cmp) -or $full.StartsWith("$taniumDir\", $cmp) -or $taniumDir.StartsWith("$full\", $cmp)) {
        $blockReason = "Tanium Client folder ($taniumDir)"
    }
}
if (-not $blockReason -and (Split-Path -Path $full -Parent).Equals($usersDir, $cmp)) {
    $blockReason = "user profile root (remove profiles through Windows, not by deleting the folder)"
}

if ($blockReason) {
    Write-Log "Refusing to delete '$full': $blockReason. Nothing deleted." 'ERROR'
    exit 4
}

# --- Confirmation (friction layer) --------------------------------------------
$leaf = Split-Path -Path $full -Leaf
if ($confirm -ne $leaf) {
    Write-Log "Confirmation '$confirm' does not match folder name '$leaf'. Nothing deleted." 'ERROR'
    exit 3
}
Write-Log "Confirmation matched folder name '$leaf'."

# --- Target checks ------------------------------------------------------------
if (-not (Test-Path -LiteralPath $full)) {
    Write-Log "Folder not found. Nothing to do."
    exit 0
}

$item = Get-Item -LiteralPath $full -Force
if (-not $item.PSIsContainer) {
    Write-Log "'$full' is a file, not a folder. Nothing deleted." 'ERROR'
    exit 2
}
if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    Write-Log "'$full' is a junction or symbolic link. Refusing to delete." 'ERROR'
    exit 4
}

# --- Delete -------------------------------------------------------------------
$itemCount = @(Get-ChildItem -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue).Count
Write-Log "Deleting '$full' ($itemCount items inside)."

$deleteErrors = @()
Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable deleteErrors

if (Test-Path -LiteralPath $full) {
    $remaining = @(Get-ChildItem -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue).Count
    Write-Log "Folder still exists. $remaining items remain. $($deleteErrors.Count) delete errors." 'ERROR'
    $deleteErrors | Select-Object -First 5 | ForEach-Object {
        Write-Log "  $($_.Exception.Message)" 'ERROR'
    }
    if ($deleteErrors.Count -gt 5) { Write-Log "  ...and $($deleteErrors.Count - 5) more." 'ERROR' }
    exit 1
}

Write-Log "Folder deleted."
exit 0
