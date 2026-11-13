<#
.SYNOPSIS
    Remove-StaleUserProfiles.ps1
    Deletes Windows user profiles (C:\Users\<name>) that nobody has signed in to
    for a set number of days. Built to run as a Tanium package (runs as SYSTEM).

.DESCRIPTION
    For every user profile on the computer, the script works out when the profile
    was last signed in to or signed out of, then keeps or deletes it.

    How "last used" is worked out:
      1. Sign-in and sign-out times that Windows stores in the registry under
         HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\<SID>
         (LocalProfileLoadTimeHigh/Low and LocalProfileUnloadTimeHigh/Low).
         The newer of the two is used.
      2. If those values are missing: the "Migrated" date in the same registry
         key. Windows writes it when it carries a profile over during a Windows
         upgrade (for example 23H2 to 25H2). A profile that has that date but no
         sign-in or sign-out time has not been signed in to since the upgrade,
         so the upgrade date is the latest it can have been used.
      3. Only if that is missing too: the LastUseTime that Windows reports for
         the profile (Win32_UserProfile). Antivirus scans and updates change this
         value, so it often shows today. It can only cause a profile to be kept.
    The date on NTUSER.DAT is NOT used. Windows updates and antivirus scans change
    it, so it makes old profiles look recently used.

    A profile is always kept when any of these is true:
      - It is a system profile (SYSTEM, LocalService, NetworkService).
      - It is a built-in account (Administrator, Guest, and so on).
      - Someone is signed in to it right now (or a service is running as it).
      - It belongs to the last person who signed in to the computer.
      - Its folder name is on the "users to keep" list.
      - It is a local account and was not named in "users to delete".
      - Its folder is not directly inside the Windows profiles folder (C:\Users).
      - The script cannot tell when it was last used.
      - It was used more recently than the number of days given.

    The script refuses to run on servers and domain controllers.

.PARAMETER (positional, passed by Tanium as "$1" "$2" "$3" "$4")
    $1  Mode             Audit  = list what would be deleted, change nothing (default)
                         Delete = delete the profiles
    $2  Days not used    Whole number, 30 or more. Default 90.
    $3  Users to delete  Required, there is no default. Either:
                           a comma-separated list of profile folder names, for
                           example jsmith,adoe (the name after C:\Users\), no
                           wildcards, or
                           ALL = every profile that passes the checks.
                         If it is left empty the script stops and changes nothing.
    $4  Users to keep    Optional. NONE (default), or a comma-separated list of
                         profile folder names that must never be deleted.
                         Wildcards are allowed, for example svc*,adm*
                         This list always wins: a name here is kept even if it is
                         also in "users to delete" or matches ALL.

.NOTES
    Exit codes:
      0  Finished. Nothing failed.
      1  At least one profile could not be fully deleted.
      2  A parameter was wrong. Nothing was changed.
      3  The computer is a server or domain controller. Nothing was changed.
      4  Unexpected error. See the log.

    Log (kept after the Tanium action folder is cleaned up):
      C:\ProgramData\RemoveStaleUserProfiles\Remove-StaleUserProfiles.log
    The same lines are written to the Tanium action log.

    Works with Windows PowerShell 5.1.
#>

$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.1.0'
$MinimumDays   = 30      # Lowest value accepted for "days not used". Guards against typos such as 0 or 9.
$LogFolder     = Join-Path $env:ProgramData 'RemoveStaleUserProfiles'
$LogFile       = Join-Path $LogFolder 'Remove-StaleUserProfiles.log'
$RawArgs       = @($args)

# Folder names that are never touched, whatever else is true.
$NeverTouchNames = @('Public', 'Default', 'Default User', 'All Users', 'Administrator')

# ----------------------------------------------------------------------------
# Logging: every line goes to the Tanium action log (standard output) and to a
# log file that stays on the computer.
# ----------------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    try {
        if (-not (Test-Path -LiteralPath $LogFolder)) {
            New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
        }
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    } catch {
        # A logging problem must never stop the work.
    }
}

function Start-LogFile {
    # Keep the log from growing forever: once it passes 1 MB, keep one old copy.
    try {
        if (Test-Path -LiteralPath $LogFile) {
            if ((Get-Item -LiteralPath $LogFile).Length -gt 1MB) {
                Move-Item -LiteralPath $LogFile -Destination ($LogFile + '.old') -Force
            }
        }
    } catch { }
}

# ----------------------------------------------------------------------------
# Parameters
# ----------------------------------------------------------------------------
function Get-PackageParameter {
    # Tanium can pass parameter values percent-encoded (for example %2C for a comma).
    # Decoding a value that is not encoded leaves it unchanged.
    param([int]$Index, [string]$Default)
    if ($RawArgs.Count -gt $Index -and $null -ne $RawArgs[$Index]) {
        $value = [string]$RawArgs[$Index]
        try { $value = [System.Uri]::UnescapeDataString($value) } catch { }
        $value = $value.Trim().Trim('"').Trim("'").Trim()
        if ($value -ne '') { return $value }
    }
    return $Default
}

function ConvertTo-NameList {
    # Turns "jsmith, C:\Users\adoe ;bob" into jsmith, adoe, bob
    param([string]$Text)
    $names = @()
    foreach ($part in ($Text -split '[,;]')) {
        $name = $part.Trim().Trim('"').Trim("'").Trim().TrimEnd('\').TrimEnd('/')
        if ($name -eq '') { continue }
        $cut = [Math]::Max($name.LastIndexOf('\'), $name.LastIndexOf('/'))
        if ($cut -ge 0) { $name = $name.Substring($cut + 1) }
        if ($name -ne '') { $names += $name }
    }
    return , $names
}

# ----------------------------------------------------------------------------
# Working out when a profile was last used
# ----------------------------------------------------------------------------
function Convert-RegFileTime {
    # Windows stores each time as two registry numbers (high and low half).
    # Returns a UTC date, or $null when the value is missing or makes no sense.
    param($High, $Low)
    if ($null -eq $High -or $null -eq $Low) { return $null }
    try {
        $h = ([int64]$High) -band 4294967295
        $l = ([int64]$Low) -band 4294967295
        $fileTime = ($h -shl 32) -bor $l
        if ($fileTime -le 0) { return $null }
        $date = [DateTime]::FromFileTimeUtc($fileTime)
        if ($date.Year -lt 2000) { return $null }
        return $date
    } catch {
        return $null
    }
}

function Convert-RegBinaryFileTime {
    # The "Migrated" value is one 8-byte date. Returns a UTC date, or $null.
    param($Bytes)
    if ($null -eq $Bytes) { return $null }
    try {
        $raw = [byte[]]$Bytes
        if ($raw.Length -lt 8) { return $null }
        $fileTime = [BitConverter]::ToInt64($raw, 0)
        if ($fileTime -le 0) { return $null }
        $date = [DateTime]::FromFileTimeUtc($fileTime)
        if ($date.Year -lt 2000) { return $null }
        return $date
    } catch {
        return $null
    }
}

function Get-ProfileLastUsed {
    # Returns @{ Utc = <date or $null>; Source = <text> }
    param($LoadUtc, $UnloadUtc, $MigratedUtc, $WmiLastUseUtc)
    $best = $null
    foreach ($candidate in @($LoadUtc, $UnloadUtc)) {
        if ($null -ne $candidate -and ($null -eq $best -or $candidate -gt $best)) { $best = $candidate }
    }
    if ($null -ne $best) {
        return @{ Utc = $best; Source = 'sign-in/sign-out time stored by Windows' }
    }
    if ($null -ne $MigratedUtc) {
        return @{ Utc = $MigratedUtc; Source = 'date of the last Windows upgrade, not signed in to since' }
    }
    if ($null -ne $WmiLastUseUtc) {
        return @{ Utc = $WmiLastUseUtc; Source = 'Windows last-use time (less exact)' }
    }
    return @{ Utc = $null; Source = 'unknown' }
}

# ----------------------------------------------------------------------------
# The keep-or-delete decision for one profile. No side effects.
# ----------------------------------------------------------------------------
function Get-ProfileDecision {
    param(
        [string]$Name,
        [string]$Sid,
        [string]$Path,
        [bool]$Loaded,
        [bool]$IsLocalAccount,
        [bool]$IsLastSignedIn,
        $LastUsedUtc,
        [datetime]$NowUtc,
        [int]$InactiveDays,
        [string[]]$DeleteList,
        [string[]]$KeepList,
        [string]$ProfilesDir,
        [string[]]$NeverTouch
    )

    $keep = { param($why) return @{ Action = 'Keep'; Reason = $why } }

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Name)) {
        return (& $keep 'Windows has no folder recorded for it')
    }
    if ($Sid -notlike 'S-1-5-21-*' -and $Sid -notlike 'S-1-12-1-*') {
        return (& $keep 'not a normal user account')
    }
    if ($Sid -like 'S-1-5-21-*') {
        [int64]$lastPart = 0
        if ([int64]::TryParse(($Sid -split '-')[-1], [ref]$lastPart) -and $lastPart -lt 1000) {
            return (& $keep 'built-in account')
        }
    }
    if ($NeverTouch -contains $Name) {
        return (& $keep 'protected folder name')
    }

    $named = $false
    if ($DeleteList.Count -gt 0) {
        if ($DeleteList -notcontains $Name) {
            return (& $keep 'not on the list of users to delete')
        }
        $named = $true
    }

    if ($Loaded) {
        return (& $keep 'in use right now')
    }
    if ($IsLastSignedIn) {
        return (& $keep 'belongs to the last person who signed in to this computer')
    }
    foreach ($pattern in $KeepList) {
        if ($Name -like $pattern) {
            return (& $keep ("on the list of users to keep ({0})" -f $pattern))
        }
    }
    if ($IsLocalAccount -and -not $named) {
        return (& $keep 'local account (only deleted when named in the list of users to delete)')
    }

    # The folder must sit directly inside the profiles folder, for example C:\Users\jsmith
    $cleanPath = $Path.TrimEnd('\')
    $cut = $cleanPath.LastIndexOf('\')
    $parent = ''
    if ($cut -gt 0) { $parent = $cleanPath.Substring(0, $cut) }
    if ($parent -eq '' -or ($parent -ne $ProfilesDir.TrimEnd('\'))) {
        return (& $keep ("folder is not directly inside {0}" -f $ProfilesDir))
    }

    if ($null -eq $LastUsedUtc) {
        return (& $keep 'cannot tell when it was last used')
    }
    $idleDays = [int][Math]::Floor(($NowUtc - $LastUsedUtc).TotalDays)
    if ($idleDays -lt 0) {
        return (& $keep 'last-used date is in the future (check the computer clock)')
    }
    if ($idleDays -lt $InactiveDays) {
        return (& $keep ("used {0} day(s) ago, limit is {1}" -f $idleDays, $InactiveDays))
    }
    return @{ Action = 'Delete'; Reason = ("not used for {0} day(s), limit is {1}" -f $idleDays, $InactiveDays) }
}

# ----------------------------------------------------------------------------
# Windows lookups (registry is always read in the 64-bit view)
# ----------------------------------------------------------------------------
function Open-LocalMachineKey {
    param([string]$SubKey)
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    return $base.OpenSubKey($SubKey)
}

function Get-LocalSidPrefix {
    # Every local account on a computer shares the same start of its SID.
    $sids = @()
    try {
        $sids = @(Get-CimInstance -ClassName Win32_UserAccount -Filter 'LocalAccount = True' | ForEach-Object { $_.SID })
    } catch { }
    if ($sids.Count -eq 0) {
        try { $sids = @(Get-LocalUser | ForEach-Object { $_.SID.Value }) } catch { }
    }
    foreach ($sid in $sids) {
        if ($sid -like 'S-1-5-21-*') {
            return $sid.Substring(0, $sid.LastIndexOf('-'))
        }
    }
    throw 'Could not read the list of local accounts, so local accounts cannot be told apart from others.'
}

function Get-FreeSpaceGB {
    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID = '{0}'" -f $env:SystemDrive)
        return [Math]::Round($disk.FreeSpace / 1GB, 2)
    } catch {
        return $null
    }
}

# ----------------------------------------------------------------------------
# Deleting one profile
# ----------------------------------------------------------------------------
function Remove-OneProfile {
    # Returns @{ Ok = $true/$false; Note = <text> }
    param([string]$Sid, [string]$Path, [string]$ProfilesDir)

    # Look again right before deleting, in case someone signed in since the check.
    $fresh = Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID = '{0}'" -f $Sid)
    if ($null -eq $fresh) {
        return @{ Ok = $false; Note = 'Windows no longer lists this profile' }
    }
    if ($fresh.Loaded) {
        return @{ Ok = $false; Note = 'someone signed in to it after the check, left alone' }
    }

    $deleteError = $null
    try {
        # The Windows-supported way: removes the folder and the registry entry together.
        Remove-CimInstance -InputObject $fresh -ErrorAction Stop
    } catch {
        $deleteError = $_.Exception.Message
    }

    $regKey = Open-LocalMachineKey ("SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\{0}" -f $Sid)
    $regGone = ($null -eq $regKey)
    if (-not $regGone) { $regKey.Close() }
    $folderGone = -not (Test-Path -LiteralPath $Path)

    if ($regGone -and -not $folderGone) {
        # Windows removed the profile entry but left files behind. Clear the leftover folder.
        $cleanPath = $Path.TrimEnd('\')
        $parent = $cleanPath.Substring(0, $cleanPath.LastIndexOf('\'))
        if ($parent -eq $ProfilesDir.TrimEnd('\')) {
            try {
                $rd = Start-Process -FilePath $env:ComSpec -ArgumentList ('/d /c rd /s /q "{0}"' -f $cleanPath) -Wait -PassThru -WindowStyle Hidden
            } catch { }
            $folderGone = -not (Test-Path -LiteralPath $Path)
        }
    }

    if ($regGone -and $folderGone) {
        return @{ Ok = $true; Note = 'folder and registry entry are gone' }
    }

    $detail = @()
    if (-not $regGone)    { $detail += 'registry entry is still there' }
    if (-not $folderGone) { $detail += 'folder (or part of it) is still there' }
    if ($deleteError)     { $detail += ("Windows said: {0}" -f $deleteError) }
    return @{ Ok = $false; Note = ($detail -join '; ') }
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
function Invoke-Main {
    Start-LogFile

    $mode       = Get-PackageParameter -Index 0 -Default 'Audit'
    $daysText   = Get-PackageParameter -Index 1 -Default '90'
    $deleteText = Get-PackageParameter -Index 2 -Default ''
    $keepText   = Get-PackageParameter -Index 3 -Default 'NONE'

    Write-Log ("===== Remove-StaleUserProfiles {0} started on {1} =====" -f $ScriptVersion, $env:COMPUTERNAME)
    Write-Log ("Settings: mode={0}; days not used={1}; users to delete={2}; users to keep={3}" -f $mode, $daysText, $deleteText, $keepText)

    # --- Check the settings ---
    if ($mode -notin @('Audit', 'Delete')) {
        Write-Log ("Mode must be Audit or Delete. Got: {0}. Nothing was changed." -f $mode) 'ERROR'
        return 2
    }
    $inactiveDays = 0
    if (-not [int]::TryParse($daysText, [ref]$inactiveDays)) {
        Write-Log ("Days not used must be a whole number. Got: {0}. Nothing was changed." -f $daysText) 'ERROR'
        return 2
    }
    if ($inactiveDays -lt $MinimumDays) {
        Write-Log ("Days not used must be {0} or more. Got: {1}. Nothing was changed." -f $MinimumDays, $inactiveDays) 'ERROR'
        return 2
    }

    if ($deleteText -eq '') {
        Write-Log 'Users to delete is required. Give profile folder names (for example jsmith,adoe) or ALL. Nothing was changed.' 'ERROR'
        return 2
    }
    $deleteList = @()
    if ($deleteText -ne 'ALL') {
        $deleteList = ConvertTo-NameList $deleteText
        if ($deleteList.Count -eq 0) {
            Write-Log 'Users to delete must be ALL or a list of profile folder names. Nothing was changed.' 'ERROR'
            return 2
        }
        foreach ($name in $deleteList) {
            if ($name -match '[\*\?]') {
                Write-Log ("Wildcards are not allowed in the list of users to delete. Got: {0}. Nothing was changed." -f $name) 'ERROR'
                return 2
            }
        }
    }

    $keepList = @()
    if ($keepText -ne 'NONE') { $keepList = ConvertTo-NameList $keepText }

    # --- Workstations only ---
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($os.ProductType -ne 1) {
        Write-Log ("This computer is a server or domain controller ({0}). The package is for workstations only. Nothing was changed." -f $os.Caption) 'ERROR'
        return 3
    }

    # --- Collect facts ---
    $profileListKey = Open-LocalMachineKey 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    if ($null -eq $profileListKey) { throw 'Could not open the ProfileList registry key.' }
    $profilesDir = [string]$profileListKey.GetValue('ProfilesDirectory')
    if ([string]::IsNullOrWhiteSpace($profilesDir)) { $profilesDir = Join-Path $env:SystemDrive 'Users' }
    $profilesDir = $profilesDir.TrimEnd('\')

    $lastSignedInSids = @()
    $logonUiKey = Open-LocalMachineKey 'SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI'
    if ($null -ne $logonUiKey) {
        foreach ($valueName in @('LastLoggedOnUserSID', 'SelectedUserSID')) {
            $value = [string]$logonUiKey.GetValue($valueName)
            if ($value) { $lastSignedInSids += $value }
        }
        $logonUiKey.Close()
    }

    $localSidPrefix = Get-LocalSidPrefix
    $nowUtc = (Get-Date).ToUniversalTime()
    $freeBefore = Get-FreeSpaceGB

    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter 'Special = False')
    Write-Log ("Profiles folder: {0}. User profiles found: {1}." -f $profilesDir, $profiles.Count)

    $countKept = 0; $countWould = 0; $countDeleted = 0; $countFailed = 0
    $foundNames = @()

    foreach ($p in $profiles) {
        $sid  = [string]$p.SID
        $path = [string]$p.LocalPath
        $name = ''
        if ($path) {
            $trimmed = $path.TrimEnd('\')
            $name = $trimmed.Substring($trimmed.LastIndexOf('\') + 1)
        }
        $foundNames += $name

        # Sign-in / sign-out times from the registry
        $loadUtc = $null; $unloadUtc = $null; $migratedUtc = $null
        $sidKey = $profileListKey.OpenSubKey($sid)
        if ($null -ne $sidKey) {
            $loadUtc   = Convert-RegFileTime $sidKey.GetValue('LocalProfileLoadTimeHigh')   $sidKey.GetValue('LocalProfileLoadTimeLow')
            $unloadUtc = Convert-RegFileTime $sidKey.GetValue('LocalProfileUnloadTimeHigh') $sidKey.GetValue('LocalProfileUnloadTimeLow')
            $migratedUtc = Convert-RegBinaryFileTime $sidKey.GetValue('Migrated')
            $sidKey.Close()
        }
        $wmiUtc = $null
        if ($null -ne $p.LastUseTime) { $wmiUtc = ([datetime]$p.LastUseTime).ToUniversalTime() }
        $lastUsed = Get-ProfileLastUsed -LoadUtc $loadUtc -UnloadUtc $unloadUtc -MigratedUtc $migratedUtc -WmiLastUseUtc $wmiUtc

        $decision = Get-ProfileDecision -Name $name -Sid $sid -Path $path -Loaded ([bool]$p.Loaded) `
            -IsLocalAccount ($sid -like ($localSidPrefix + '-*')) `
            -IsLastSignedIn ($lastSignedInSids -contains $sid) `
            -LastUsedUtc $lastUsed.Utc -NowUtc $nowUtc -InactiveDays $inactiveDays `
            -DeleteList $deleteList -KeepList $keepList -ProfilesDir $profilesDir -NeverTouch $NeverTouchNames

        $lastUsedText = 'unknown'
        if ($null -ne $lastUsed.Utc) {
            $lastUsedText = '{0} ({1})' -f $lastUsed.Utc.ToLocalTime().ToString('yyyy-MM-dd'), $lastUsed.Source
        }
        $about = '{0} | folder: {1} | last used: {2}' -f $name, $path, $lastUsedText

        if ($decision.Action -eq 'Keep') {
            $countKept++
            Write-Log ("KEEP          {0} | why: {1}" -f $about, $decision.Reason)
            continue
        }

        if ($mode -eq 'Audit') {
            $countWould++
            Write-Log ("WOULD DELETE  {0} | why: {1}" -f $about, $decision.Reason)
            continue
        }

        Write-Log ("DELETING      {0} | why: {1}" -f $about, $decision.Reason)
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Remove-OneProfile -Sid $sid -Path $path -ProfilesDir $profilesDir
        $timer.Stop()
        if ($result.Ok) {
            $countDeleted++
            Write-Log ("DELETED       {0} | {1} | took {2} second(s)" -f $name, $result.Note, [int]$timer.Elapsed.TotalSeconds)
        } else {
            $countFailed++
            Write-Log ("FAILED        {0} | {1}" -f $name, $result.Note) 'ERROR'
        }
    }
    $profileListKey.Close()

    # Tell the operator about names that were asked for but are not on this computer.
    foreach ($wanted in $deleteList) {
        if ($foundNames -notcontains $wanted) {
            Write-Log ("NOT FOUND     {0} | no user profile with this folder name on this computer" -f $wanted) 'WARN'
        }
    }

    $freeAfter = Get-FreeSpaceGB
    if ($mode -eq 'Audit') {
        Write-Log ("Summary (Audit, nothing changed): would delete={0}; keep={1}; free space={2} GB" -f $countWould, $countKept, $freeAfter)
    } else {
        Write-Log ("Summary (Delete): deleted={0}; failed={1}; kept={2}; free space before={3} GB; after={4} GB" -f $countDeleted, $countFailed, $countKept, $freeBefore, $freeAfter)
    }

    if ($countFailed -gt 0) { return 1 }
    return 0
}

$exitCode = 4
try {
    # Take the last value only, so a stray output line can never replace the exit code.
    $exitCode = [int](@(Invoke-Main)[-1])
} catch {
    Write-Log ("Unexpected error: {0}" -f $_.Exception.Message) 'ERROR'
    $exitCode = 4
}
Write-Log ("===== Finished with exit code {0} =====" -f $exitCode)
exit $exitCode
