<#
.SYNOPSIS
    Frees disk space for the signed-in person. Started by Invoke-DiskCleanup.ps1.

.DESCRIPTION
    Runs inside the signed-in person's own session, with their normal rights. It first removes
    files older than -TempDays days from the person's temp folder, the person's own Windows
    error report files, and (only with -CleanBrowserCaches Yes) the browser caches. Then:

      1. OneDrive: files that are stored on this computer and have not been used for
         -OneDriveDays days are set to online-only. This is the same as right-clicking a
         file and choosing "Free up space". The file stays in OneDrive and downloads again
         when it is opened. Files marked "Always keep on this device" are left alone.

      2. Recycle Bin: if it holds items that were deleted more than -RecycleBinDays days
         ago, the person is asked whether to remove them for good. If they say no, close
         the window, or do not answer in time, nothing in the Recycle Bin is touched.
         Newer items are never touched.

    File and folder names are never written to the log. Only counts and sizes are.

.PARAMETER OneDriveDays
    OneDrive files not used for this many days are set to online-only.

.PARAMETER RecycleBinDays
    Only Recycle Bin items deleted more than this many days ago are offered for removal.

.PARAMETER PromptTimeoutSeconds
    How long the Recycle Bin question stays on screen. No answer counts as "no".

.PARAMETER MaxOneDriveMinutes
    Time limit for the OneDrive step. Files not reached are handled on the next run.

.PARAMETER TempDays
    Files in the person's temp folder that are older than this many days are removed.

.PARAMETER CleanBrowserCaches
    Yes or No. Empty the Chrome, Edge, and Firefox caches. Files the browser has open are skipped.

.PARAMETER RunId
    Written on the last line of the log so the calling script knows this run has finished.

.PARAMETER ResultPath
    Log file. Default: %LOCALAPPDATA%\DiskCleanup\DiskCleanup.log
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 3650)][int]$OneDriveDays = 14,
    [ValidateRange(1, 3650)][int]$RecycleBinDays = 30,
    [ValidateRange(10, 3600)][int]$PromptTimeoutSeconds = 300,
    [ValidateRange(1, 120)][int]$MaxOneDriveMinutes = 8,
    [ValidateRange(1, 3650)][int]$TempDays = 7,
    [ValidateSet('Yes', 'No')][string]$CleanBrowserCaches = 'No',
    [string]$RunId = 'manual',
    [string]$ResultPath = (Join-Path $env:LOCALAPPDATA 'DiskCleanup\DiskCleanup.log')
)

$ErrorActionPreference = 'Stop'
$script:HadError = $false

# File markers that Windows uses for cloud files (from the Windows SDK, winnt.h).
$ATTR_HIDDEN      = 0x00000002   # hidden file
$ATTR_SYSTEM      = 0x00000004   # Windows system file
$ATTR_OFFLINE     = 0x00001000   # content is not on this computer
$ATTR_PINNED      = 0x00080000   # "Always keep on this device"
$ATTR_RECALL_DATA = 0x00400000   # online-only, downloads when opened
$ATTR_REPARSE     = 0x00000400   # link or cloud placeholder
$ATTR_DIRECTORY   = 0x00000010

# ----------------------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $ResultPath -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Format-Size {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return '{0:N0} bytes' -f $Bytes
}

function Clear-OldFiles {
    # Removes files in $Folder (and the folders below it) that are older than $Cutoff.
    # A shortcut-to-a-folder (junction or symbolic link) is never followed. Only the shortcut
    # is removed, never what it points to. Files that are in use are left in place.
    param([string]$Folder, [datetime]$Cutoff, [hashtable]$Stats)

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
            Clear-OldFiles -Folder $entry.FullName -Cutoff $Cutoff -Stats $Stats
            if ($newest -lt $Cutoff) {
                try { [System.IO.Directory]::Delete($entry.FullName, $false) } catch { }    # only works when it is empty
            }
            continue
        }

        if ($newest -ge $Cutoff) { continue }

        try {
            $size = 0
            if (-not $isFolder) { $size = $entry.Length }
            if ($attributes -band 1) {
                $entry.Attributes = [System.IO.FileAttributes]($attributes -band (-bnot 1))
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
}

function Invoke-TempCleanup {
    # The person's own temp folder and their own Windows error report files.
    $temp = Join-Path $env:LOCALAPPDATA 'Temp'
    if ([System.IO.Directory]::Exists($temp)) {
        $stats = @{ Removed = 0; Bytes = [long]0; Kept = 0 }
        Clear-OldFiles -Folder $temp -Cutoff (Get-Date).AddDays(-$TempDays) -Stats $stats
        Write-StepResult -Step ("Temp folder (older than {0} days)" -f $TempDays) -Stats $stats
    }

    $stats = @{ Removed = 0; Bytes = [long]0; Kept = 0 }
    foreach ($name in 'ReportArchive', 'ReportQueue') {
        $folder = Join-Path $env:LOCALAPPDATA ('Microsoft\Windows\WER\' + $name)
        if ([System.IO.Directory]::Exists($folder)) {
            Clear-OldFiles -Folder $folder -Cutoff ([datetime]::MaxValue) -Stats $stats
        }
    }
    Write-StepResult -Step 'Windows error reports' -Stats $stats
}

function Invoke-BrowserCacheCleanup {
    # Empties the caches only. Bookmarks, passwords, history, cookies, and sign-ins are not touched.
    # If the browser is open, the files it is using are left in place.
    $stats      = @{ Removed = 0; Bytes = [long]0; Kept = 0 }
    $everything = [datetime]::MaxValue

    $chromiumFolders = @(
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data')
    )
    foreach ($userData in $chromiumFolders) {
        if (-not [System.IO.Directory]::Exists($userData)) { continue }
        foreach ($profileFolder in [System.IO.Directory]::GetDirectories($userData)) {
            $leaf = [System.IO.Path]::GetFileName($profileFolder)
            if ($leaf -ne 'Default' -and $leaf -notlike 'Profile *') { continue }
            foreach ($cacheName in 'Cache', 'Code Cache', 'GPUCache') {
                $cache = Join-Path $profileFolder $cacheName
                if ([System.IO.Directory]::Exists($cache)) {
                    Clear-OldFiles -Folder $cache -Cutoff $everything -Stats $stats
                }
            }
        }
    }

    $firefoxProfiles = Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles'
    if ([System.IO.Directory]::Exists($firefoxProfiles)) {
        foreach ($profileFolder in [System.IO.Directory]::GetDirectories($firefoxProfiles)) {
            $cache = Join-Path $profileFolder 'cache2'
            if ([System.IO.Directory]::Exists($cache)) {
                Clear-OldFiles -Folder $cache -Cutoff $everything -Stats $stats
            }
        }
    }

    Write-StepResult -Step 'Browser caches (Chrome, Edge, Firefox)' -Stats $stats
}

function Get-OneDriveFolder {
    # Returns every folder on this computer that OneDrive keeps in sync for this person.
    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($name in 'OneDrive', 'OneDriveCommercial', 'OneDriveConsumer') {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { $candidates.Add($value) }
    }

    $accountsKey = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
    if (Test-Path -LiteralPath $accountsKey) {
        foreach ($account in @(Get-ChildItem -LiteralPath $accountsKey -ErrorAction SilentlyContinue)) {
            # The person's own OneDrive folder.
            $userFolder = (Get-ItemProperty -LiteralPath $account.PSPath -ErrorAction SilentlyContinue).UserFolder
            if ($userFolder) { $candidates.Add($userFolder) }

            # SharePoint and Teams libraries that are synced to this computer.
            $tenantsKey = Join-Path $account.PSPath 'Tenants'
            if (Test-Path -LiteralPath $tenantsKey) {
                foreach ($tenant in @(Get-ChildItem -LiteralPath $tenantsKey -ErrorAction SilentlyContinue)) {
                    foreach ($valueName in $tenant.GetValueNames()) {
                        if ($valueName) { $candidates.Add($valueName) }
                    }
                }
            }
        }
    }

    # Keep real folders only, drop duplicates, and drop folders that sit inside another one.
    $unique = @{}
    foreach ($candidate in $candidates) {
        $clean = $candidate.Trim().TrimEnd('\')
        if ($clean.Length -lt 4) { continue }                      # never a whole drive
        if (-not [System.IO.Directory]::Exists($clean)) { continue }
        $unique[$clean.ToLowerInvariant()] = $clean
    }
    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($folder in @($unique.Values | Sort-Object Length)) {
        $inside = $false
        foreach ($parent in $kept) {
            if ($folder.StartsWith($parent + '\', [System.StringComparison]::OrdinalIgnoreCase)) { $inside = $true; break }
        }
        if (-not $inside) { $kept.Add($folder) }
    }
    return @($kept)
}

function Invoke-OneDriveCleanup {
    Write-Log ("OneDrive step: looking for files not used for {0} days." -f $OneDriveDays)

    $folders = @(Get-OneDriveFolder)
    if ($folders.Count -eq 0) {
        Write-Log 'OneDrive is not set up for this person. Skipped.'
        return
    }

    $mySession = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $oneDriveRunning = @(Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $mySession }).Count -gt 0
    if (-not $oneDriveRunning) {
        Write-Log 'OneDrive is not running for this person. Files are still marked, but the space is only freed once OneDrive is running.' 'WARN'
    }

    $attribExe = Join-Path $env:windir 'System32\attrib.exe'
    $cutoff    = (Get-Date).AddDays(-$OneDriveDays)
    $deadline  = (Get-Date).AddMinutes($MaxOneDriveMinutes)

    $freedCount = 0; [long]$freedBytes = 0
    $failed = 0; $recent = 0; $alreadyOnline = 0; $alwaysKeep = 0; $unreadableFolders = 0
    $outOfTime = $false
    $failReasons = @{}; $folderReasons = @{}

    foreach ($root in $folders) {
        if ($outOfTime) { break }

        # Walk the folder tree one folder at a time so a single unreadable folder does not stop the rest.
        $pending = New-Object System.Collections.Stack
        $pending.Push((New-Object System.IO.DirectoryInfo($root)))

        while ($pending.Count -gt 0 -and -not $outOfTime) {
            $folder = $pending.Pop()
            try {
                foreach ($entry in $folder.EnumerateFileSystemInfos()) {
                    if ((Get-Date) -gt $deadline) { $outOfTime = $true; break }

                    $attributes = [int]$entry.Attributes

                    if ($attributes -band $ATTR_DIRECTORY) {
                        # Do not follow shortcuts-to-folders (junctions and symbolic links). They can
                        # point outside OneDrive. Normal OneDrive folders are followed.
                        if (($attributes -band $ATTR_REPARSE) -and $entry.LinkType) { continue }
                        $pending.Push($entry)
                        continue
                    }

                    # Hidden and system files are left alone. attrib refuses to change hidden files anyway.
                    if ($attributes -band ($ATTR_SYSTEM -bor $ATTR_HIDDEN)) { continue }
                    if ($entry.Length -eq 0) { continue }
                    if (($attributes -band $ATTR_RECALL_DATA) -or ($attributes -band $ATTR_OFFLINE)) { $alreadyOnline++; continue }
                    if ($attributes -band $ATTR_PINNED) { $alwaysKeep++; continue }

                    # "Last used" = the newest of last opened, last changed, and created.
                    $lastUsed = $entry.LastAccessTime
                    if ($entry.LastWriteTime -gt $lastUsed) { $lastUsed = $entry.LastWriteTime }
                    if ($entry.CreationTime  -gt $lastUsed) { $lastUsed = $entry.CreationTime }
                    if ($lastUsed -ge $cutoff) { $recent++; continue }

                    # Same as "Free up space" in File Explorer. attrib prints text only when something goes wrong.
                    $output = & $attribExe '+U' '-P' $entry.FullName
                    if ($LASTEXITCODE -ne 0 -or $output) {
                        $failed++
                        # attrib answers "<reason> - <path>". Keep the reason only, never the file name.
                        $reason    = 'other'
                        $firstLine = [string](@($output)[0])
                        $dashAt    = $firstLine.IndexOf(' - ')
                        if ($dashAt -gt 0) { $reason = $firstLine.Substring(0, $dashAt).Trim() }
                        $failReasons[$reason] = 1 + [int]$failReasons[$reason]
                    }
                    else {
                        $freedCount++
                        $freedBytes += $entry.Length
                    }
                }
            }
            catch {
                $unreadableFolders++
                # Keep the kind of error only. The full message can contain a folder name.
                $problem = $_.Exception
                while ($problem.InnerException) { $problem = $problem.InnerException }
                $kind = $problem.GetType().Name
                $folderReasons[$kind] = 1 + [int]$folderReasons[$kind]
            }
        }
    }

    Write-Log ("OneDrive folders checked: {0}" -f $folders.Count)
    Write-Log ("OneDrive: {0} files set to online-only, about {1} to be freed." -f $freedCount, (Format-Size $freedBytes))
    Write-Log ("OneDrive: left alone: {0} used in the last {1} days, {2} already online-only, {3} marked 'Always keep on this device'." -f $recent, $OneDriveDays, $alreadyOnline, $alwaysKeep)
    if ($failed -gt 0) {
        $why = @($failReasons.Keys | Sort-Object | ForEach-Object { '{0} ({1})' -f $_, $failReasons[$_] }) -join ', '
        Write-Log ("OneDrive: {0} files could not be changed. Reason given by Windows: {1}" -f $failed, $why) 'WARN'
    }
    if ($unreadableFolders -gt 0) {
        $why = @($folderReasons.Keys | Sort-Object | ForEach-Object { '{0} ({1})' -f $_, $folderReasons[$_] }) -join ', '
        Write-Log ("OneDrive: {0} folders could not be read. Kind of error: {1}" -f $unreadableFolders, $why) 'WARN'
    }
    if ($outOfTime)               { Write-Log ("OneDrive: the {0}-minute time limit was reached. The remaining files are handled on the next run." -f $MaxOneDriveMinutes) 'WARN' }
}

function Get-OldRecycleBinItem {
    # Windows stores every Recycle Bin item as two files in <drive>:\$Recycle.Bin\<account ID>\ :
    #   $I...  a small record that holds the original size and the date the item was deleted
    #   $R...  the deleted file or folder itself
    param([datetime]$CutoffUtc)

    $sid   = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    # A plain ArrayList on purpose. Windows PowerShell 5.1 fails with "Argument types do not
    # match" when a List[object] that holds custom objects is wrapped in @().
    $items = New-Object System.Collections.ArrayList

    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -ne [System.IO.DriveType]::Fixed -or -not $drive.IsReady) { continue }
        $binFolder = Join-Path $drive.RootDirectory.FullName ('$Recycle.Bin\' + $sid)
        if (-not [System.IO.Directory]::Exists($binFolder)) { continue }

        try { $records = [System.IO.Directory]::GetFiles($binFolder, '$I*') } catch { continue }

        foreach ($record in $records) {
            try {
                $stream = [System.IO.File]::Open($record, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    $buffer = New-Object byte[] 24
                    $read   = $stream.Read($buffer, 0, 24)
                }
                finally { $stream.Dispose() }
                if ($read -lt 24) { continue }

                $version = [System.BitConverter]::ToInt64($buffer, 0)
                if ($version -ne 1 -and $version -ne 2) { continue }          # unknown layout: leave it alone

                $size       = [System.BitConverter]::ToInt64($buffer, 8)
                $deletedUtc = [datetime]::FromFileTimeUtc([System.BitConverter]::ToInt64($buffer, 16))

                if ($deletedUtc -lt $CutoffUtc) {
                    $fileName = [System.IO.Path]::GetFileName($record)
                    [void]$items.Add([pscustomobject]@{
                        RecordPath  = $record
                        ContentPath = Join-Path $binFolder ('$R' + $fileName.Substring(2))
                        Size        = [math]::Max([long]0, $size)
                    })
                }
            }
            catch { }
        }
    }
    return $items.ToArray()
}

function Remove-TreeSafely {
    # Deletes a file or a folder with everything in it. If it meets a shortcut-to-a-folder
    # (junction or symbolic link), it removes only the shortcut and never what it points to.
    param([string]$Path)

    $item       = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $attributes = [int]$item.Attributes
    $isLink     = (($attributes -band $ATTR_REPARSE) -ne 0) -and [bool]$item.LinkType

    # Windows refuses to delete read-only items, so clear that marker first.
    if ($attributes -band 1) {
        $item.Attributes = [System.IO.FileAttributes]($attributes -band (-bnot 1))
    }

    if (-not $item.PSIsContainer) {
        [System.IO.File]::Delete($Path)
        return
    }

    if ($isLink) {
        [System.IO.Directory]::Delete($Path, $false)      # removes the shortcut only
        return
    }

    foreach ($child in [System.IO.Directory]::GetFileSystemEntries($Path)) {
        Remove-TreeSafely -Path $child
    }
    [System.IO.Directory]::Delete($Path, $false)
}

function Show-YesNoPrompt {
    # Shows a small window with two buttons. Returns 'Yes', 'No', or 'Timeout'.
    param([string]$Title, [string]$Message, [string]$YesText, [string]$NoText, [int]$TimeoutSeconds)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $state = @{ Remaining = $TimeoutSeconds; TimedOut = $false }

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = $Title
    $form.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.TopMost         = $true
    $form.ShowInTaskbar   = $true
    $form.Font            = New-Object System.Drawing.Font('Segoe UI', 10)
    $form.ClientSize      = New-Object System.Drawing.Size(480, 262)

    $text = New-Object System.Windows.Forms.Label
    $text.Location = New-Object System.Drawing.Point(20, 18)
    $text.Size     = New-Object System.Drawing.Size(440, 150)
    $text.Text     = $Message
    $form.Controls.Add($text)

    $countdown = New-Object System.Windows.Forms.Label
    $countdown.Location  = New-Object System.Drawing.Point(20, 174)
    $countdown.Size      = New-Object System.Drawing.Size(440, 22)
    $countdown.ForeColor = [System.Drawing.Color]::DimGray
    $countdown.Text      = ("This message closes in {0} seconds. If it closes, nothing is deleted." -f $state.Remaining)
    $form.Controls.Add($countdown)

    $yesButton = New-Object System.Windows.Forms.Button
    $yesButton.Text         = $YesText
    $yesButton.Size         = New-Object System.Drawing.Size(160, 34)
    $yesButton.Location     = New-Object System.Drawing.Point(130, 212)
    $yesButton.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $form.Controls.Add($yesButton)

    $noButton = New-Object System.Windows.Forms.Button
    $noButton.Text         = $NoText
    $noButton.Size         = New-Object System.Drawing.Size(160, 34)
    $noButton.Location     = New-Object System.Drawing.Point(300, 212)
    $noButton.DialogResult = [System.Windows.Forms.DialogResult]::No
    $form.Controls.Add($noButton)

    # Pressing Enter or Esc means "no", so a stray key press never deletes anything.
    $form.AcceptButton = $noButton
    $form.CancelButton = $noButton

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick({
        $state.Remaining = $state.Remaining - 1
        if ($state.Remaining -le 0) {
            $state.TimedOut = $true
            $timer.Stop()
            $form.Close()
        }
        else {
            $countdown.Text = ("This message closes in {0} seconds. If it closes, nothing is deleted." -f $state.Remaining)
        }
    })
    $form.Add_Shown({ $form.Activate(); $noButton.Focus() | Out-Null; $timer.Start() })

    try {
        $answer = $form.ShowDialog()
    }
    finally {
        $timer.Stop()
        $timer.Dispose()
        $form.Dispose()
    }

    if ($state.TimedOut) { return 'Timeout' }
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) { return 'Yes' }
    return 'No'
}

function Invoke-RecycleBinCleanup {
    Write-Log ("Recycle Bin step: looking for items deleted more than {0} days ago." -f $RecycleBinDays)

    $oldItems = @(Get-OldRecycleBinItem -CutoffUtc ((Get-Date).ToUniversalTime().AddDays(-$RecycleBinDays)))
    if ($oldItems.Count -eq 0) {
        Write-Log ("Recycle Bin: nothing older than {0} days. The person was not asked." -f $RecycleBinDays)
        return
    }

    [long]$totalBytes = 0
    foreach ($oldItem in $oldItems) { $totalBytes += $oldItem.Size }
    Write-Log ("Recycle Bin: {0} items older than {1} days, about {2}. Asking the person." -f $oldItems.Count, $RecycleBinDays, (Format-Size $totalBytes))

    $message = ("Your Recycle Bin has {0} item(s) that were deleted more than {1} days ago. They use about {2}.`r`n`r`n" +
                "Do you want to remove them for good to free up disk space?`r`n`r`n" +
                "Items you deleted in the last {1} days are not touched.") -f $oldItems.Count, $RecycleBinDays, (Format-Size $totalBytes)

    $answer = Show-YesNoPrompt -Title 'Free up disk space' -Message $message `
                -YesText 'Delete old items' -NoText 'Keep them' -TimeoutSeconds $PromptTimeoutSeconds

    if ($answer -eq 'Timeout') {
        Write-Log ("Recycle Bin: no answer within {0} seconds. Skipped, nothing deleted." -f $PromptTimeoutSeconds)
        return
    }
    if ($answer -ne 'Yes') {
        Write-Log 'Recycle Bin: the person chose to keep the items. Skipped, nothing deleted.'
        return
    }

    $removed = 0; [long]$removedBytes = 0; $notRemoved = 0; $notRemovedReasons = @{}
    foreach ($oldItem in $oldItems) {
        try {
            if (Test-Path -LiteralPath $oldItem.ContentPath) {
                Remove-TreeSafely -Path $oldItem.ContentPath
            }
            # Remove the small record last, so an item that could not be deleted still shows in the Recycle Bin.
            [System.IO.File]::Delete($oldItem.RecordPath)
            $removed++
            $removedBytes += $oldItem.Size
        }
        catch {
            $notRemoved++
            # Keep the kind of error only. The full message can contain a file name.
            $problem = $_.Exception
            while ($problem.InnerException) { $problem = $problem.InnerException }
            $kind = $problem.GetType().Name
            $notRemovedReasons[$kind] = 1 + [int]$notRemovedReasons[$kind]
        }
    }

    # Tell Windows to redraw the Recycle Bin icon (full or empty).
    try {
        Add-Type -Namespace DiskCleanup -Name Shell -MemberDefinition '[DllImport("shell32.dll")] public static extern void SHUpdateRecycleBinIcon();'
        [DiskCleanup.Shell]::SHUpdateRecycleBinIcon()
    }
    catch { }

    Write-Log ("Recycle Bin: the person said yes. {0} items removed, about {1} freed." -f $removed, (Format-Size $removedBytes))
    if ($notRemoved -gt 0) {
        $why = @($notRemovedReasons.Keys | Sort-Object | ForEach-Object { '{0} ({1})' -f $_, $notRemovedReasons[$_] }) -join ', '
        Write-Log ("Recycle Bin: {0} items could not be removed and were left in place. Kind of error: {1}" -f $notRemoved, $why) 'WARN'
    }
}

# ----------------------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------------------
try {
    $logFolder = Split-Path -Parent $ResultPath
    if (-not (Test-Path -LiteralPath $logFolder)) {
        New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($ResultPath, '')            # start a fresh log for this run

    Write-Log ("Cleanup started for {0}\{1}." -f $env:USERDOMAIN, $env:USERNAME)

    try { Invoke-TempCleanup }
    catch {
        $script:HadError = $true
        Write-Log ("The temp folder step failed: {0}" -f $_.Exception.Message) 'ERROR'
    }

    if ($CleanBrowserCaches -eq 'Yes') {
        try { Invoke-BrowserCacheCleanup }
        catch {
            $script:HadError = $true
            Write-Log ("The browser cache step failed: {0}" -f $_.Exception.Message) 'ERROR'
        }
    }

    try { Invoke-OneDriveCleanup }
    catch {
        $script:HadError = $true
        Write-Log ("The OneDrive step failed: {0}" -f $_.Exception.Message) 'ERROR'
    }

    try { Invoke-RecycleBinCleanup }
    catch {
        $script:HadError = $true
        Write-Log ("The Recycle Bin step failed: {0}" -f $_.Exception.Message) 'ERROR'
    }
}
catch {
    $script:HadError = $true
    Write-Log ("Cleanup failed: {0}" -f $_.Exception.Message) 'ERROR'
}
finally {
    $status = 'ok'
    if ($script:HadError) { $status = 'error' }
    Write-Log ('DONE {0} status={1}' -f $RunId, $status)
}
