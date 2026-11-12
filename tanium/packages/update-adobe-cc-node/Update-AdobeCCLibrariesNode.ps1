######################################################################
# Update Node.js in Adobe CC Libraries (Node 22) - CVE-2026-111497 (Tanium package)
# Files: Update-AdobeCCLibrariesNode.ps1, node.exe (22.23.4 win-x64)
# Exit: 0 updated/nothing to do, 1 failed (original restored),
#       2 skipped, 3 bad package node.exe, 5 not admin
######################################################################

# Restart as 64-bit if the Tanium client started 32-bit PowerShell.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'

# ----- Settings for this package. Edit only this block. -------------
$Component  = 'Adobe Creative Cloud Libraries'
$TargetPath = Join-Path $env:CommonProgramFiles 'Adobe\Creative Cloud Libraries\libs\node.exe'
$NodeMajor  = 22
$FixedVer   = [version]'22.23.4'
# ---------------------------------------------------------------------

$Payload   = Join-Path $PSScriptRoot 'node.exe'
$TargetDir = Split-Path -Parent $TargetPath

function Write-Log {
    param ([string]$Message, [string]$Level = 'INFO')
    Write-Output ("{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

# File version as Major.Minor.Build (node.exe reports 22.23.2.0, we use 22.23.2).
function Get-NodeVersion {
    param ([string]$Path)
    $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    return [version]::new($vi.FileMajorPart, $vi.FileMinorPart, $vi.FileBuildPart)
}

# Reads the PE header to tell x64 from ARM64 or 32-bit. Opens the file with
# full sharing so it also works while node.exe is running.
function Get-PeMachine {
    param ([string]$Path)
    $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        if ($br.ReadUInt16() -ne 0x5A4D) { return 'NotPE' }
        $fs.Position = 0x3C
        $fs.Position = $br.ReadInt32()
        if ($br.ReadUInt32() -ne 0x00004550) { return 'NotPE' }
        $machine = [int]$br.ReadUInt16()
        switch ($machine) {
            0x8664  { return 'x64' }
            0xAA64  { return 'ARM64' }
            0x014C  { return 'x86' }
            default { return ('Other(0x{0:X4})' -f $machine) }
        }
    } finally {
        $fs.Dispose()
    }
}

# Deletes a file at the next restart (used when the old node.exe is still running).
function Remove-AtRestart {
    param ([string]$Path)
    if (-not ('NodeFix.Native' -as [type])) {
        Add-Type -Namespace NodeFix -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);
'@
    }
    # 4 = MOVEFILE_DELAY_UNTIL_REBOOT. PowerShell turns $null into an empty
    # string here, which makes the call fail; [NullString]::Value passes a real null.
    return [NodeFix.Native]::MoveFileEx($Path, [NullString]::Value, 4)
}

function Get-NodeProcessesInFolder {
    @(Get-CimInstance -ClassName Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and ((Split-Path -Parent $_.ExecutablePath) -ieq $TargetDir) })
}

# ----- 0. Must be SYSTEM or admin -----------------------------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin  = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not ($identity.IsSystem -or $isAdmin)) {
    Write-Log 'Must run as SYSTEM or an administrator. Nothing changed.' 'ERROR'
    exit 5
}

Write-Log "Component: $Component"
Write-Log "Target:    $TargetPath"

# ----- 1. Is the Adobe component installed? -------------------------
if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
    Write-Log 'node.exe not found at the target path. Nothing to do.'
    exit 0
}

# Clean up old copies left by an earlier run that were still in use then.
foreach ($leftover in @(Get-ChildItem -LiteralPath $TargetDir -Filter 'node-*.replaced' -File -ErrorAction SilentlyContinue)) {
    try {
        Remove-Item -LiteralPath $leftover.FullName -Force
        Write-Log "Deleted leftover file from an earlier run: $($leftover.Name)"
    } catch {
        if (Remove-AtRestart $leftover.FullName) {
            Write-Log "Leftover file $($leftover.Name) is still in use. It will be deleted at the next restart." 'WARN'
        } else {
            Write-Log "Leftover file $($leftover.Name) is still in use and could not be set to delete at restart." 'WARN'
        }
    }
}

# ----- 2. Check the package node.exe --------------------------------
if (-not (Test-Path -LiteralPath $Payload -PathType Leaf)) {
    Write-Log "The package node.exe was not found next to the script ($Payload). Nothing changed." 'ERROR'
    exit 3
}
$newVer  = Get-NodeVersion $Payload
$newArch = Get-PeMachine $Payload
Write-Log "Package node.exe:   version $newVer, $newArch"
if ($newVer.Major -ne $NodeMajor -or $newVer -lt $FixedVer -or $newArch -ne 'x64') {
    Write-Log "The package node.exe must be Node $NodeMajor.x, $FixedVer or newer, x64. Nothing changed." 'ERROR'
    exit 3
}
$sig = Get-AuthenticodeSignature -LiteralPath $Payload
Write-Log ("Package node.exe signature: {0}, signed by: {1}" -f $sig.Status, $(if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { 'none' }))

# ----- 3. Check the installed node.exe ------------------------------
$oldVer  = Get-NodeVersion $TargetPath
$oldArch = Get-PeMachine $TargetPath
Write-Log "Installed node.exe: version $oldVer, $oldArch"

if ($oldVer.Major -ne $NodeMajor) {
    Write-Log "Installed node.exe is not Node $NodeMajor.x (version $oldVer). This package only handles Node $NodeMajor.x. Nothing changed." 'WARN'
    exit 2
}
if ($oldVer -ge $FixedVer) {
    Write-Log "Installed node.exe is already $FixedVer or newer. Nothing to do."
    exit 0
}
if ($oldArch -ne 'x64') {
    Write-Log "Installed node.exe is $oldArch, not x64. This package only carries the x64 build. Nothing changed." 'WARN'
    exit 2
}

# ----- 4. Move the old node.exe out of the way ----------------------
$oldName = Join-Path $TargetDir ("node-{0}-{1}.replaced" -f $oldVer, (Get-Date -Format 'yyyyMMddHHmmss'))
$renamed = $false
for ($i = 1; $i -le 5 -and -not $renamed; $i++) {
    try {
        [System.IO.File]::Move($TargetPath, $oldName)
        $renamed = $true
    } catch {
        Write-Log "Try $i of 5 to rename node.exe failed: $($_.Exception.Message)" 'WARN'
        foreach ($p in @(Get-NodeProcessesInFolder | Where-Object { $_.ExecutablePath -ieq $TargetPath })) {
            Write-Log "Stopping node.exe PID $($p.ProcessId) (started by PID $($p.ParentProcessId))" 'WARN'
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
    }
}
if (-not $renamed) {
    Write-Log 'Could not move the old node.exe out of the way. Nothing changed.' 'ERROR'
    exit 1
}
Write-Log "Renamed the old node.exe to $(Split-Path -Leaf $oldName)"

# ----- 5. Copy in the new node.exe and check it ---------------------
try {
    Copy-Item -LiteralPath $Payload -Destination $TargetPath -Force
    $nowVer    = Get-NodeVersion $TargetPath
    $hashMatch = (Get-FileHash -LiteralPath $TargetPath -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $Payload -Algorithm SHA256).Hash
    if ($nowVer -ne $newVer -or -not $hashMatch) {
        throw "Check after copy failed (version $nowVer, file hash match: $hashMatch)"
    }
    Write-Log "Copied in node.exe $newVer and confirmed the file hash."
} catch {
    Write-Log "Copy failed: $($_.Exception.Message). Putting the original back." 'ERROR'
    try {
        if (Test-Path -LiteralPath $TargetPath) { Remove-Item -LiteralPath $TargetPath -Force }
        [System.IO.File]::Move($oldName, $TargetPath)
        Write-Log 'Original node.exe is back in place.'
    } catch {
        Write-Log "Could not put the original back: $($_.Exception.Message). Rename $oldName to node.exe by hand, or repair Creative Cloud." 'ERROR'
    }
    exit 1
}

# ----- 6. Delete the old node.exe -----------------------------------
try {
    Remove-Item -LiteralPath $oldName -Force
    Write-Log 'Deleted the old node.exe.'
} catch {
    if (Remove-AtRestart $oldName) {
        Write-Log 'The old node.exe is still in use by a running Adobe process. It will be deleted at the next restart.'
    } else {
        Write-Log "Could not set $oldName to be deleted at restart. The next run of this package will try again." 'WARN'
    }
}

$stillRunning = @(Get-NodeProcessesInFolder)
if ($stillRunning.Count -gt 0) {
    Write-Log ("{0} node.exe process(es) from this folder are still running the old code (PID {1}). They switch to the new file when Creative Cloud restarts, the user signs out, or the machine restarts." -f $stillRunning.Count, (($stillRunning | ForEach-Object { $_.ProcessId }) -join ', '))
}

Write-Log "Done. $Component node.exe updated from $oldVer to $newVer."
exit 0
