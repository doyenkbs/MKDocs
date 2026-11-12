<#
.SYNOPSIS
    Tanium package entry point. Frees disk space on this computer and for the people signed in to it.

.DESCRIPTION
    The Tanium Client runs this script as SYSTEM. It does two kinds of work.

    A. Computer-wide cleanup, done by this script. It runs even when nobody is signed in.
         Always:
           - Windows temp folder (C:\Windows\Temp): files older than 7 days
           - Windows error report files (C:\ProgramData\Microsoft\Windows\WER)
           - Delivery Optimization cache
         Only when switched on:
           - Windows Update download folder (C:\Windows\SoftwareDistribution\Download)
           - Crash dump files older than 7 days
           - C:\Windows.old (the previous Windows version kept after an upgrade), removed
             with Windows' own Disk Cleanup "Previous Windows installation(s)" option

    B. Per-person cleanup, done by Invoke-UserDiskCleanup.ps1. SYSTEM has no desktop, cannot
       show a message to a person, and is not signed in to anyone's OneDrive. So this script
       copies that second script to a folder standard users can read but not change
       ("C:\Program Files\DiskCleanup") and starts it inside each signed-in person's own
       session with a one-time scheduled task that uses the person's normal rights.
         - The person's temp folder: files older than 7 days
         - Browser caches (only when switched on)
         - OneDrive: files not used for a set number of days become online-only
         - Recycle Bin: the person is asked before items older than a set number of days are removed

.PARAMETER OneDriveDays
    $1  OneDrive files not used for this many days are set to online-only. Default 14.
.PARAMETER RecycleBinDays
    $2  The person is asked about Recycle Bin items deleted more than this many days ago. Default 30.
.PARAMETER PromptTimeoutSeconds
    $3  How long the Recycle Bin question stays on screen. No answer counts as "no". Default 300.
.PARAMETER CleanWindowsUpdateDownloads
    $4  Yes or No. Empty the Windows Update download folder. Default No.
.PARAMETER CleanCrashDumps
    $5  Yes or No. Remove crash dump files older than 7 days. Default No.
.PARAMETER CleanBrowserCaches
    $6  Yes or No. Empty the Chrome, Edge, and Firefox caches of signed-in people. Default No.
.PARAMETER RemoveWindowsOld
    $7  Yes or No. Remove C:\Windows.old. After this the computer cannot go back to the
        previous Windows version. Default No.

.NOTES
    Tanium command line:
      cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Invoke-DiskCleanup.ps1 "$1" "$2" "$3" "$4" "$5" "$6" "$7"

    Exit codes:
      0 = finished (this includes "nobody signed in" and "the person said no")
      1 = something failed (see the action log)
      2 = the per-person cleanup did not finish in time for at least one person and was stopped
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$OneDriveDays = '14',
    [Parameter(Position = 1)][string]$RecycleBinDays = '30',
    [Parameter(Position = 2)][string]$PromptTimeoutSeconds = '300',
    [Parameter(Position = 3)][string]$CleanWindowsUpdateDownloads = 'No',
    [Parameter(Position = 4)][string]$CleanCrashDumps = 'No',
    [Parameter(Position = 5)][string]$CleanBrowserCaches = 'No',
    [Parameter(Position = 6)][string]$RemoveWindowsOld = 'No'
)

$ErrorActionPreference = 'Stop'

# Empty values from Tanium fall back to the defaults.
if ([string]::IsNullOrWhiteSpace($OneDriveDays))                { $OneDriveDays = '14' }
if ([string]::IsNullOrWhiteSpace($RecycleBinDays))              { $RecycleBinDays = '30' }
if ([string]::IsNullOrWhiteSpace($PromptTimeoutSeconds))        { $PromptTimeoutSeconds = '300' }
if ([string]::IsNullOrWhiteSpace($CleanWindowsUpdateDownloads)) { $CleanWindowsUpdateDownloads = 'No' }
if ([string]::IsNullOrWhiteSpace($CleanCrashDumps))             { $CleanCrashDumps = 'No' }
if ([string]::IsNullOrWhiteSpace($CleanBrowserCaches))          { $CleanBrowserCaches = 'No' }
if ([string]::IsNullOrWhiteSpace($RemoveWindowsOld))            { $RemoveWindowsOld = 'No' }

# If the Tanium Client started the 32-bit PowerShell on 64-bit Windows, start again in the
# 64-bit one. The 32-bit one sees a different Program Files and a different System32.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:windir 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $powershell64) {
        & $powershell64 -ExecutionPolicy Bypass -NoProfile -NonInteractive -File $PSCommandPath `
            $OneDriveDays $RecycleBinDays $PromptTimeoutSeconds $CleanWindowsUpdateDownloads $CleanCrashDumps $CleanBrowserCaches $RemoveWindowsOld
        exit $LASTEXITCODE
    }
}

# ----------------------------------------------------------------------------------------
# Fixed settings
# ----------------------------------------------------------------------------------------
$TempDays           = 7                                   # temp files and crash dumps newer than this are kept
$MaxOneDriveMinutes = 8                                   # time limit for the OneDrive step, per person
$WorkRoot           = Join-Path $env:ProgramFiles 'DiskCleanup'
$UserScriptName     = 'Invoke-UserDiskCleanup.ps1'
$TaskPrefix         = 'DiskCleanup-'
$RunId              = [guid]::NewGuid().ToString('N')     # lets us tell this run's results from an older run
$ExitCode           = 0
$Jobs               = @()

# Folders made by Windows or by an administrator: SYSTEM, Administrators, TrustedInstaller.
$TrustedOwners = @(
    'S-1-5-18',
    'S-1-5-32-544',
    'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
)

$ATTR_READONLY  = 0x00000001
$ATTR_DIRECTORY = 0x00000010
$ATTR_REPARSE   = 0x00000400   # link or other special folder

# ----------------------------------------------------------------------------------------
# General helpers
# ----------------------------------------------------------------------------------------
function Write-Log {
    # Write-Host is used on purpose: it goes to the Tanium action log and does not
    # get mixed into the values that functions return.
    param([string]$Message, [string]$Level = 'INFO')
    Write-Host ('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

function Get-WholeNumber {
    # Turns a Tanium parameter (always text) into a number and checks that it is in range.
    param([string]$Value, [string]$Name, [int]$Min, [int]$Max)
    $number = 0
    if (-not [int]::TryParse($Value.Trim(), [ref]$number)) {
        throw "$Name must be a whole number. Received: '$Value'"
    }
    if ($number -lt $Min -or $number -gt $Max) {
        throw "$Name must be between $Min and $Max. Received: $number"
    }
    return $number
}

function Get-YesNo {
    param([string]$Value, [string]$Name)
    $text = $Value.Trim().ToLowerInvariant()
    if (@('yes', 'y', 'true', '1', 'on') -contains $text)  { return $true }
    if (@('no', 'n', 'false', '0', 'off') -contains $text) { return $false }
    throw "$Name must be Yes or No. Received: '$Value'"
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

function Get-SignedInUser {
    # Every signed-in person has an explorer.exe (the Windows desktop) running under their
    # account. This also finds people connected over Remote Desktop.
    $found = @{}
    $desktops = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue)
    foreach ($desktop in $desktops) {
        try {
            $sid = (Invoke-CimMethod -InputObject $desktop -MethodName GetOwnerSid).Sid
            if ([string]::IsNullOrEmpty($sid)) { continue }
            if ($found.ContainsKey($sid)) { continue }
            # Real people only: local or domain accounts (S-1-5-21-) and Entra ID accounts (S-1-12-1-).
            if ($sid -notmatch '^S-1-(5-21|12-1)-') { continue }
            $owner = Invoke-CimMethod -InputObject $desktop -MethodName GetOwner
            $found[$sid] = [pscustomobject]@{
                Sid  = $sid
                Name = ('{0}\{1}' -f $owner.Domain, $owner.User)
            }
        }
        catch {
            Write-Log ("Could not read the owner of explorer.exe (process {0}): {1}" -f $desktop.ProcessId, $_.Exception.Message) 'WARN'
        }
    }
    return @($found.Values)
}

function Read-ResultLog {
    # The result log is written by the signed-in person, so it is only read as text.
    param([string]$Path)
    try {
        if (-not [System.IO.File]::Exists($Path)) { return @() }
        if ((New-Object System.IO.FileInfo($Path)).Length -gt 1MB) {
            return @('[The result log is larger than expected and was not read.]')
        }
        return @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop)
    }
    catch {
        return @()
    }
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

# ----------------------------------------------------------------------------------------
# Safe file removal
# ----------------------------------------------------------------------------------------
function Get-OwnerSid {
    param([string]$Path)
    try {
        $security = [System.IO.Directory]::GetAccessControl($Path, [System.Security.AccessControl.AccessControlSections]::Owner)
        return $security.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
    }
    catch { return '' }
}

function New-Stats {
    return @{ Removed = 0; Bytes = [long]0; Kept = 0; SkippedFolders = 0 }
}

function Clear-OldFiles {
    # Removes files in $Folder (and the folders below it) that are older than $Cutoff.
    #
    # Two safety rules, because this runs as SYSTEM:
    #   1. A shortcut-to-a-folder (junction or symbolic link) is never followed. Only the
    #      shortcut is removed, never what it points to.
    #   2. With -TrustedOnly, it only goes into folders made by Windows or an administrator.
    #      C:\Windows\Temp lets standard users create folders. Skipping those folders means a
    #      standard user cannot trick this script into deleting something somewhere else.
    param([string]$Folder, [datetime]$Cutoff, [bool]$TrustedOnly, [hashtable]$Stats)

    try { $entries = @((New-Object System.IO.DirectoryInfo($Folder)).GetFileSystemInfos()) }
    catch { $Stats.Kept += 1; return }

    foreach ($entry in $entries) {
        $attributes = [int]$entry.Attributes
        $isFolder   = ($attributes -band $ATTR_DIRECTORY) -ne 0
        $isLink     = (($attributes -band $ATTR_REPARSE) -ne 0) -and [bool]$entry.LinkType

        # Age = the newer of "last changed" and "created". Read before anything inside is removed.
        $newest = $entry.LastWriteTime
        if ($entry.CreationTime -gt $newest) { $newest = $entry.CreationTime }

        if ($isFolder -and -not $isLink) {
            if ($TrustedOnly -and ($TrustedOwners -notcontains (Get-OwnerSid -Path $entry.FullName))) {
                $Stats.SkippedFolders += 1
                continue
            }
            Clear-OldFiles -Folder $entry.FullName -Cutoff $Cutoff -TrustedOnly $TrustedOnly -Stats $Stats
            if ($newest -lt $Cutoff) {
                try { [System.IO.Directory]::Delete($entry.FullName, $false) } catch { }    # only works when it is empty
            }
            continue
        }

        if ($newest -ge $Cutoff) { continue }

        try {
            $size = 0
            if (-not $isFolder) { $size = $entry.Length }
            if ($attributes -band $ATTR_READONLY) {
                $entry.Attributes = [System.IO.FileAttributes]($attributes -band (-bnot $ATTR_READONLY))
            }
            if ($isFolder) { [System.IO.Directory]::Delete($entry.FullName, $false) }       # a shortcut: remove the shortcut only
            else           { [System.IO.File]::Delete($entry.FullName) }
            $Stats.Removed += 1
            $Stats.Bytes   += $size
        }
        catch {
            $Stats.Kept += 1                                                                 # in use or protected
        }
    }
}

function Write-StepResult {
    param([string]$Step, [hashtable]$Stats)
    Write-Log ("{0}: {1} items removed, about {2} freed." -f $Step, $Stats.Removed, (Format-Size $Stats.Bytes))
    if ($Stats.Kept -gt 0) {
        Write-Log ("{0}: {1} items are in use or protected and were left in place." -f $Step, $Stats.Kept)
    }
    if ($Stats.SkippedFolders -gt 0) {
        Write-Log ("{0}: {1} folders made by standard users were skipped." -f $Step, $Stats.SkippedFolders)
    }
}

# ----------------------------------------------------------------------------------------
# Computer-wide cleanup steps
# ----------------------------------------------------------------------------------------
function Clear-WindowsTemp {
    $folder = Join-Path $env:windir 'Temp'
    if (-not [System.IO.Directory]::Exists($folder)) { return }
    $stats = New-Stats
    Clear-OldFiles -Folder $folder -Cutoff (Get-Date).AddDays(-$TempDays) -TrustedOnly $true -Stats $stats
    Write-StepResult -Step ("Windows temp folder (older than {0} days)" -f $TempDays) -Stats $stats
}

function Clear-ErrorReports {
    $stats = New-Stats
    foreach ($name in 'ReportArchive', 'ReportQueue') {
        $folder = Join-Path $env:ProgramData ('Microsoft\Windows\WER\' + $name)
        if ([System.IO.Directory]::Exists($folder)) {
            Clear-OldFiles -Folder $folder -Cutoff ([datetime]::MaxValue) -TrustedOnly $true -Stats $stats
        }
    }
    Write-StepResult -Step 'Windows error reports' -Stats $stats
}

function Clear-DeliveryOptimization {
    $before = Get-FreeBytes
    try {
        # -DisableNameChecking hides the "unapproved verbs" warning. The redirects hide the
        # cmdlet's own "Deleting..." lines, so the action log only shows the result line below.
        Import-Module DeliveryOptimization -DisableNameChecking -ErrorAction Stop 3>$null
        Delete-DeliveryOptimizationCache -Force -ErrorAction Stop 3>$null 6>$null | Out-Null
        Write-Log ("Delivery Optimization cache: emptied, about {0} freed." -f (Format-Size ([math]::Max([long]0, (Get-FreeBytes) - $before))))
    }
    catch {
        Write-Log ("Delivery Optimization cache: could not be emptied on this computer ({0})." -f $_.Exception.Message) 'WARN'
    }
}

function Clear-WindowsUpdateDownloads {
    $folder = Join-Path $env:windir 'SoftwareDistribution\Download'
    if (-not [System.IO.Directory]::Exists($folder)) { return }

    if (Test-RestartPending) {
        Write-Log 'Windows Update downloads: Windows is waiting for a restart to finish installing updates. Skipped. Run again after the restart.' 'WARN'
        return
    }

    # Windows Update keeps these files open, so the service is stopped for a moment.
    $service    = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
    $wasRunning = $service -and $service.Status -eq 'Running'
    try {
        if ($wasRunning) {
            Stop-Service -Name 'wuauserv' -Force -ErrorAction Stop
            $service.WaitForStatus('Stopped', (New-TimeSpan -Seconds 60))
        }
        $stats = New-Stats
        Clear-OldFiles -Folder $folder -Cutoff ([datetime]::MaxValue) -TrustedOnly $false -Stats $stats
        Write-StepResult -Step 'Windows Update downloads' -Stats $stats
    }
    finally {
        if ($wasRunning) {
            try { Start-Service -Name 'wuauserv' -ErrorAction Stop }
            catch { Write-Log ("Windows Update downloads: the Windows Update service could not be started again: {0}" -f $_.Exception.Message) 'WARN' }
        }
    }
}

function Clear-CrashDumps {
    $cutoff = (Get-Date).AddDays(-$TempDays)
    $stats  = New-Stats
    foreach ($name in 'Minidump', 'LiveKernelReports') {
        $folder = Join-Path $env:windir $name
        if ([System.IO.Directory]::Exists($folder)) {
            Clear-OldFiles -Folder $folder -Cutoff $cutoff -TrustedOnly $false -Stats $stats
        }
    }
    $memoryDump = Join-Path $env:windir 'MEMORY.DMP'
    if ([System.IO.File]::Exists($memoryDump)) {
        $file = New-Object System.IO.FileInfo($memoryDump)
        if ($file.LastWriteTime -lt $cutoff) {
            try {
                $size = $file.Length
                [System.IO.File]::Delete($memoryDump)
                $stats.Removed += 1
                $stats.Bytes   += $size
            }
            catch { $stats.Kept += 1 }
        }
    }
    Write-StepResult -Step ("Crash dump files (older than {0} days)" -f $TempDays) -Stats $stats
}

function Remove-WindowsOld {
    # Removes C:\Windows.old with Windows' own Disk Cleanup handler, "Previous Windows
    # installation(s)". This is the same thing as ticking that box in Disk Cleanup or in
    # Settings > System > Storage. Windows knows how to remove its own folder safely: it does
    # not follow the shortcuts-to-folders inside it that point into the live C:\Users, and it
    # handles file paths that are too long for PowerShell.
    #
    #   1. Tell Windows that going back to the previous version is no longer possible.
    #   2. Switch on "Previous Windows installation(s)" (and nothing else) in a private
    #      Disk Cleanup profile, number 731.
    #   3. Run Disk Cleanup with that profile and wait until the folder is gone or time runs out.
    #   4. Remove the profile again.
    $target    = Join-Path ($env:SystemDrive + '\') 'Windows.old'
    $profileId = 731
    $flagName  = 'StateFlags{0:D4}' -f $profileId
    $maxWait   = New-TimeSpan -Minutes 40
    $cachesKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'

    if (-not [System.IO.Directory]::Exists($target)) {
        Write-Log 'Windows.old: the folder does not exist. Nothing to do.'
        return
    }
    $setupRunning = @(Get-Process -Name 'SetupHost', 'SetupPrep', 'Windows10UpgraderApp', 'WindowsUpdateBox' -ErrorAction SilentlyContinue)
    if ($setupRunning.Count -gt 0) {
        Write-Log 'Windows.old: a Windows upgrade is running right now. Left in place.' 'WARN'
        return
    }
    $cleanmgr = Join-Path $env:windir 'System32\cleanmgr.exe'
    if (-not (Test-Path -LiteralPath $cleanmgr)) {
        Write-Log 'Windows.old: Disk Cleanup (cleanmgr.exe) is not on this computer. Left in place.' 'WARN'
        return
    }

    $before = Get-FreeBytes
    $dism   = Join-Path $env:windir 'System32\dism.exe'

    # Step 1
    try {
        & $dism /Online /Remove-OSUninstall 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log 'Windows.old: Windows was told that the previous version can no longer be restored.'
        }
        else {
            Write-Log ("Windows.old: Windows did not confirm that step (DISM code {0}). This is normal when the time to go back has already passed." -f $LASTEXITCODE)
        }
    }
    catch {
        Write-Log ("Windows.old: could not run DISM: {0}" -f $_.Exception.Message) 'WARN'
    }

    $machine = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    $caches  = $machine.OpenSubKey($cachesKey, $true)
    if (-not $caches) {
        Write-Log 'Windows.old: the Disk Cleanup settings were not found in the registry. Left in place.' 'WARN'
        return
    }

    $process = $null
    try {
        # Step 2. Clear profile 731 everywhere first, so only "Previous Installations" runs.
        foreach ($handlerName in $caches.GetSubKeyNames()) {
            $handler = $caches.OpenSubKey($handlerName, $true)
            if ($handler) {
                if ($null -ne $handler.GetValue($flagName)) { $handler.DeleteValue($flagName, $false) }
                $handler.Close()
            }
        }
        $previous = $caches.OpenSubKey('Previous Installations', $true)
        if (-not $previous) {
            Write-Log 'Windows.old: the "Previous Windows installation(s)" cleanup is not available on this computer. Left in place.' 'WARN'
            return
        }
        $previous.SetValue($flagName, 2, [Microsoft.Win32.RegistryValueKind]::DWord)
        $previous.Close()

        # Step 3. Disk Cleanup sometimes keeps running after its work is done, so the script
        # watches the folder instead of waiting for Disk Cleanup to close.
        Write-Log 'Windows.old: Disk Cleanup started. This usually takes 5 to 30 minutes.'
        $process = Start-Process -FilePath $cleanmgr -ArgumentList ('/sagerun:{0}' -f $profileId) -WindowStyle Hidden -PassThru
        $started = Get-Date
        $goneAt  = $null

        while (((Get-Date) - $started) -lt $maxWait) {
            Start-Sleep -Seconds 15
            $folderGone = -not [System.IO.Directory]::Exists($target)
            if ($folderGone -and $process.HasExited) { break }
            if ($folderGone) {
                if (-not $goneAt) { $goneAt = Get-Date }
                if (((Get-Date) - $goneAt).TotalSeconds -ge 60) { break }    # folder gone, give Disk Cleanup a minute to finish
            }
            elseif ($process.HasExited -and ((Get-Date) - $started).TotalSeconds -ge 60) {
                break                                                        # Disk Cleanup closed but the folder is still there
            }
        }
    }
    finally {
        # Step 4. Stop Disk Cleanup if it is still open and remove profile 731.
        if ($process -and -not $process.HasExited) {
            try { $process.Kill() } catch { }
        }
        try {
            $previous = $caches.OpenSubKey('Previous Installations', $true)
            if ($previous) {
                if ($null -ne $previous.GetValue($flagName)) { $previous.DeleteValue($flagName, $false) }
                $previous.Close()
            }
        }
        catch { }
        $caches.Close()
    }

    # Disk Cleanup sometimes leaves the empty Windows.old folder behind. Remove it only if it is
    # completely empty (this call refuses to delete a folder that still has anything in it).
    if ([System.IO.Directory]::Exists($target)) {
        try { [System.IO.Directory]::Delete($target, $false) } catch { }
    }

    $freed = Format-Size ([math]::Max([long]0, (Get-FreeBytes) - $before))
    if ([System.IO.Directory]::Exists($target)) {
        Write-Log ("Windows.old: still there after Disk Cleanup, about {0} freed. Run the package again after a restart. If it stays, open Settings > System > Storage > Temporary files on that computer and check 'Previous Windows installation(s)'." -f $freed) 'WARN'
    }
    else {
        Write-Log ("Windows.old: removed, about {0} freed. This computer can no longer go back to the previous Windows version." -f $freed)
    }
}

function Invoke-Step {
    # Runs one cleanup step. A step that fails is logged and does not stop the other steps.
    param([string]$Name, [scriptblock]$Action)
    try { & $Action }
    catch {
        $script:ExitCode = 1
        Write-Log ("{0} failed: {1}" -f $Name, $_.Exception.Message) 'ERROR'
    }
}

# ----------------------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------------------
try {
    Write-Log 'Disk cleanup started.'

    $odDays      = Get-WholeNumber -Value $OneDriveDays         -Name 'OneDrive days'          -Min 1  -Max 3650
    $rbDays      = Get-WholeNumber -Value $RecycleBinDays       -Name 'Recycle Bin days'       -Min 1  -Max 3650
    $promptLimit = Get-WholeNumber -Value $PromptTimeoutSeconds -Name 'Prompt timeout seconds' -Min 30 -Max 600
    $doWuCache   = Get-YesNo -Value $CleanWindowsUpdateDownloads -Name 'Windows Update downloads'
    $doDumps     = Get-YesNo -Value $CleanCrashDumps             -Name 'Crash dumps'
    $doBrowsers  = Get-YesNo -Value $CleanBrowserCaches          -Name 'Browser caches'
    $doWinOld    = Get-YesNo -Value $RemoveWindowsOld            -Name 'Windows.old'
    $browserText = 'No'
    if ($doBrowsers) { $browserText = 'Yes' }

    Write-Log ("Settings: OneDrive files not used for {0} days, Recycle Bin items older than {1} days, question stays on screen for {2} seconds." -f $odDays, $rbDays, $promptLimit)
    Write-Log ("Options: Windows Update downloads={0}, crash dumps={1}, browser caches={2}, Windows.old={3}" -f $doWuCache, $doDumps, $doBrowsers, $doWinOld)

    $freeBefore = Get-FreeBytes
    Write-Log ("Free space on {0} before: {1}" -f $env:SystemDrive, (Format-Size $freeBefore))

    # Windows decides which OneDrive files are "not used" from each file's last-opened date.
    # This line records whether Windows is keeping that date up to date on this computer.
    try {
        $lastAccess = (& "$env:windir\System32\fsutil.exe" behavior query disablelastaccess | Out-String).Trim()
        if ($lastAccess) { Write-Log ("Last-opened date tracking: {0}" -f $lastAccess) }
    }
    catch {
        Write-Log ("Could not read the last-opened date setting: {0}" -f $_.Exception.Message) 'WARN'
    }

    # ---- Part B first: start the per-person cleanup so it runs while Part A works. ----
    $users = @(Get-SignedInUser)

    if ($users.Count -eq 0) {
        Write-Log 'Nobody is signed in. The per-person steps (temp folder, browser caches, OneDrive, Recycle Bin) are skipped. The computer-wide steps still run.'
    }
    else {
        Write-Log ("Signed-in people found: {0}" -f (($users | ForEach-Object { $_.Name }) -join ', '))

        try {
            $source = Join-Path $PSScriptRoot $UserScriptName
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "$UserScriptName is missing from the package. Add it to the package files."
            }

            # Remove anything left behind by an earlier run that was interrupted.
            Get-ScheduledTask -TaskName ($TaskPrefix + '*') -ErrorAction SilentlyContinue |
                Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $WorkRoot) {
                Remove-Item -LiteralPath $WorkRoot -Recurse -Force
            }

            # Standard users can read this folder but cannot change what is in it.
            New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
            $userScript = Join-Path $WorkRoot $UserScriptName
            Copy-Item -LiteralPath $source -Destination $userScript -Force
            Write-Log ("Copied {0} to {1}" -f $UserScriptName, $WorkRoot)

            $powershellExe = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $index = 0

            foreach ($user in $users) {
                $index++
                try {
                    $userProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID='{0}'" -f $user.Sid)
                    if (-not $userProfile -or [string]::IsNullOrEmpty($userProfile.LocalPath)) {
                        throw 'Could not find the profile folder.'
                    }
                    $resultPath = Join-Path $userProfile.LocalPath 'AppData\Local\DiskCleanup\DiskCleanup.log'
                    $taskName   = '{0}{1}-{2}' -f $TaskPrefix, $RunId.Substring(0, 8), $index

                    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -OneDriveDays {1} -RecycleBinDays {2} -PromptTimeoutSeconds {3} -MaxOneDriveMinutes {4} -TempDays {5} -CleanBrowserCaches {6} -RunId {7} -ResultPath "{8}"' -f `
                        $userScript, $odDays, $rbDays, $promptLimit, $MaxOneDriveMinutes, $TempDays, $browserText, $RunId, $resultPath

                    $action   = New-ScheduledTaskAction -Execute $powershellExe -Argument $arguments
                    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                                    -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew

                    # Run as the signed-in person, inside their session, with their normal rights.
                    try {
                        $principal = New-ScheduledTaskPrincipal -UserId $user.Sid -LogonType Interactive -RunLevel Limited
                        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
                    }
                    catch {
                        # Some systems want the account name instead of the account ID.
                        $principal = New-ScheduledTaskPrincipal -UserId $user.Name -LogonType Interactive -RunLevel Limited
                        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
                    }

                    Start-ScheduledTask -TaskName $taskName
                    Write-Log ("Started the per-person cleanup for {0}." -f $user.Name)

                    $Jobs += [pscustomobject]@{
                        Name       = $user.Name
                        TaskName   = $taskName
                        ResultPath = $resultPath
                        Started    = Get-Date
                        Finished   = $false
                        Outcome    = 'pending'
                    }
                }
                catch {
                    $ExitCode = 1
                    Write-Log ("Could not start the per-person cleanup for {0}: {1}" -f $user.Name, $_.Exception.Message) 'ERROR'
                }
            }
        }
        catch {
            $ExitCode = 1
            Write-Log ("Could not prepare the per-person cleanup: {0}" -f $_.Exception.Message) 'ERROR'
        }
    }

    # ---- Part A: computer-wide cleanup. ----
    Write-Log '---- Computer-wide cleanup ----'
    Invoke-Step -Name 'Windows temp folder'         -Action { Clear-WindowsTemp }
    Invoke-Step -Name 'Windows error reports'       -Action { Clear-ErrorReports }
    Invoke-Step -Name 'Delivery Optimization cache' -Action { Clear-DeliveryOptimization }
    if ($doWuCache) { Invoke-Step -Name 'Windows Update downloads' -Action { Clear-WindowsUpdateDownloads } }
    if ($doDumps)   { Invoke-Step -Name 'Crash dump files'         -Action { Clear-CrashDumps } }
    if ($doWinOld)  { Invoke-Step -Name 'Windows.old'              -Action { Remove-WindowsOld } }

    # ---- Wait for the per-person cleanup and copy its results into the action log. ----
    if ($Jobs.Count -gt 0) {
        $doneMarker = 'DONE {0} status=' -f $RunId
        $maxSeconds = ($MaxOneDriveMinutes * 60) + $promptLimit + 180
        Write-Log 'Waiting for the per-person cleanup to finish.'

        while (@($Jobs | Where-Object { -not $_.Finished }).Count -gt 0) {
            foreach ($job in @($Jobs | Where-Object { -not $_.Finished })) {
                $doneLine = @(Read-ResultLog -Path $job.ResultPath | Where-Object { $_ -like ('*' + $doneMarker + '*') }) | Select-Object -Last 1
                if ($doneLine) {
                    $job.Finished = $true
                    if ($doneLine -like '*status=ok*') { $job.Outcome = 'ok' } else { $job.Outcome = 'error' }
                    continue
                }
                # No result yet. If the task already ended, it ended without finishing its work.
                $secondsRunning = ((Get-Date) - $job.Started).TotalSeconds
                $task = Get-ScheduledTask -TaskName $job.TaskName -ErrorAction SilentlyContinue
                if ($secondsRunning -gt 30 -and (-not $task -or $task.State -ne 'Running')) {
                    $job.Finished = $true
                    $job.Outcome  = 'stopped early'
                }
                elseif ($secondsRunning -gt $maxSeconds) {
                    $job.Finished = $true
                    $job.Outcome  = 'timed out'
                    Stop-ScheduledTask -TaskName $job.TaskName -ErrorAction SilentlyContinue
                }
            }
            if (@($Jobs | Where-Object { -not $_.Finished }).Count -gt 0) { Start-Sleep -Seconds 5 }
        }

        foreach ($job in $Jobs) {
            Write-Log ("---- Results for {0} ({1}) ----" -f $job.Name, $job.Outcome)
            $lines = @(Read-ResultLog -Path $job.ResultPath)
            if ($lines.Count -eq 0) {
                Write-Log '    No result log was found.' 'WARN'
            }
            foreach ($line in ($lines | Select-Object -Last 200)) {
                Write-Host ('    ' + $line)
            }

            switch ($job.Outcome) {
                'ok'        { }
                'timed out' { if ($ExitCode -eq 0) { $ExitCode = 2 }
                              Write-Log ("The per-person cleanup for {0} did not finish in time and was stopped. What it had already done stays done." -f $job.Name) 'WARN' }
                default     { $ExitCode = 1
                              Write-Log ("The per-person cleanup for {0} did not finish cleanly ({1})." -f $job.Name, $job.Outcome) 'ERROR' }
            }
        }
    }

    $freeAfter = Get-FreeBytes
    Write-Log ("Free space on {0} after: {1} (change: {2})" -f $env:SystemDrive, (Format-Size $freeAfter), (Format-Size ([math]::Max([long]0, $freeAfter - $freeBefore))))
    if ($Jobs.Count -gt 0) {
        Write-Log 'OneDrive frees its space in the background, so this number can keep going up for a few minutes.'
    }
}
catch {
    $ExitCode = 1
    Write-Log ("Disk cleanup failed: {0}" -f $_.Exception.Message) 'ERROR'
}
finally {
    # Always remove the scheduled tasks and the working folder.
    foreach ($job in $Jobs) {
        try {
            Stop-ScheduledTask -TaskName $job.TaskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $job.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        }
        catch { }
    }
    try {
        if (Test-Path -LiteralPath $WorkRoot) {
            Remove-Item -LiteralPath $WorkRoot -Recurse -Force -ErrorAction Stop
        }
    }
    catch {
        Write-Log ("Could not remove {0}: {1}" -f $WorkRoot, $_.Exception.Message) 'WARN'
    }
    Write-Log ("Disk cleanup finished with exit code {0}." -f $ExitCode)
}

exit $ExitCode
