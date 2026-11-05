<#
.SYNOPSIS
    Removes a legacy PHP install folder from a Windows endpoint. Built for a Tanium package.

.DESCRIPTION
    Usage: Remove-PHPInstall.ps1 "<PHP folder>" "<Force: Yes|No>"
    Default folder: C:\Program Files (x86)\PHP\v7.1
    Default Force:  No

    Safety checks, in order. Any failure stops the script before anything is changed:
      1. Folder must sit directly under C:\Program Files (x86)\PHP or C:\Program Files\PHP
         and must contain php.exe.
      2. IIS applicationHost.config must not reference the folder (FastCGI app or handler mapping).
         Force does NOT override this check.
      3. No running process may be executing from the folder.
         Force = Yes kills those processes, waits, and re-checks. If they come back
         (restarted by a service or IIS), the script stops.

    Removal:
      - Runs the MSI uninstall if a matching uninstall entry exists.
      - Deletes the folder.
      - Removes any leftover uninstall entry so inventory stops reporting it.
      - Removes the folder from the machine PATH.

.NOTES
    Exit codes:
      0  Removed, or folder was not present
      1  Failed
      2  Blocked: in use, referenced by IIS, processes restarted after kill, or path failed validation
    Log: C:\Windows\Temp\Remove-PHPInstall.log (also written to stdout)
#>

param(
    [string]$PhpDir,
    [string]$Force
)

$ErrorActionPreference = 'Stop'
$DefaultDir = 'C:\Program Files (x86)\PHP\v7.1'
$LogFile    = Join-Path $env:windir 'Temp\Remove-PHPInstall.log'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 's'), $Level, $Message
    Write-Output $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Get-PhpProcesses {
    param([string]$Dir)
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith("$Dir\", [StringComparison]::OrdinalIgnoreCase)
    })
}

try {
    # Tanium passes parameters URL-encoded (a space arrives as %20), so decode them first.
    $PhpDir = [System.Uri]::UnescapeDataString([string]$PhpDir)
    $Force  = [System.Uri]::UnescapeDataString([string]$Force)
    if ([string]::IsNullOrWhiteSpace($PhpDir)) { $PhpDir = $DefaultDir }
    $PhpDir  = $PhpDir.Trim().Trim('"').TrimEnd('\')
    $forceOn = ([string]$Force).Trim() -match '^(yes|true|1)$'
    Write-Log "Start. Target folder: $PhpDir | Force: $forceOn"

    # --- 1. Path validation -------------------------------------------------
    $allowedRoots = @("$env:SystemDrive\Program Files (x86)\PHP", "$env:SystemDrive\Program Files\PHP")
    $parent = Split-Path -Path $PhpDir -Parent
    if ($allowedRoots -notcontains $parent) {
        Write-Log "Blocked: folder must be directly under one of: $($allowedRoots -join ', ')" 'ERROR'
        exit 2
    }

    if (-not (Test-Path -LiteralPath $PhpDir)) {
        Write-Log 'Folder not present. Nothing to do.'
        exit 0
    }

    $phpExe = Join-Path $PhpDir 'php.exe'
    if (-not (Test-Path -LiteralPath $phpExe)) {
        Write-Log "Blocked: $phpExe not found, folder does not look like a PHP install." 'ERROR'
        exit 2
    }

    $fileVer = (Get-Item -LiteralPath $phpExe).VersionInfo.FileVersion
    $majMin  = (($fileVer -split '\.')[0..1]) -join '.'
    Write-Log "php.exe version: $fileVer"

    # --- 2. IIS reference check (Force does not override) -------------------
    # Use Sysnative when running as a 32-bit process so System32 is not redirected to SysWOW64.
    $sysDir  = if (Test-Path "$env:windir\Sysnative") { "$env:windir\Sysnative" } else { "$env:windir\System32" }
    $appHost = Join-Path $sysDir 'inetsrv\config\applicationHost.config'
    if (Test-Path -LiteralPath $appHost) {
        $cfg = Get-Content -LiteralPath $appHost -Raw
        $envForm = $PhpDir -ireplace [regex]::Escape("$env:SystemDrive\Program Files (x86)"), '%ProgramFiles(x86)%'
        $envForm = $envForm -ireplace [regex]::Escape("$env:SystemDrive\Program Files"), '%ProgramFiles%'
        foreach ($needle in @($PhpDir, $envForm) | Select-Object -Unique) {
            if ($cfg.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                Write-Log "Blocked: IIS applicationHost.config references '$needle'. Remove the FastCGI application and handler mapping first. Force does not override this." 'ERROR'
                exit 2
            }
        }
        Write-Log 'IIS present, no reference to the folder.'
    } else {
        Write-Log 'IIS not installed.'
    }

    # --- 3. In-use check, with optional kill --------------------------------
    $procs = Get-PhpProcesses -Dir $PhpDir
    if ($procs.Count -gt 0) {
        foreach ($p in $procs) { Write-Log "In use: PID $($p.ProcessId) $($p.ExecutablePath)" 'WARN' }

        if (-not $forceOn) {
            Write-Log 'Blocked: processes are running from the folder. Rerun with Force = Yes to kill them.' 'ERROR'
            exit 2
        }

        foreach ($p in $procs) {
            try {
                Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
                Write-Log "Killed PID $($p.ProcessId) $($p.ExecutablePath)"
            } catch {
                Write-Log "Could not kill PID $($p.ProcessId): $($_.Exception.Message)" 'WARN'
            }
        }

        Start-Sleep -Seconds 5
        $procs = Get-PhpProcesses -Dir $PhpDir
        if ($procs.Count -gt 0) {
            foreach ($p in $procs) { Write-Log "Still running after kill: PID $($p.ProcessId) $($p.ExecutablePath)" 'WARN' }
            Write-Log 'Blocked: processes restarted or could not be killed. A service or scheduled job is likely relaunching them.' 'ERROR'
            exit 2
        }
        Write-Log 'All processes from the folder stopped.'
    } else {
        Write-Log 'No running processes from the folder.'
    }

    # --- 4. Find uninstall entries (64-bit view sees both hives) -------------
    $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    $uninstRoots = @(
        'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $entries = @()
    foreach ($root in $uninstRoots) {
        $rk = $hklm.OpenSubKey($root)
        if (-not $rk) { continue }
        foreach ($name in $rk.GetSubKeyNames()) {
            $sk = $rk.OpenSubKey($name)
            if (-not $sk) { continue }
            $dn  = [string]$sk.GetValue('DisplayName')
            $dv  = [string]$sk.GetValue('DisplayVersion')
            $loc = ([string]$sk.GetValue('InstallLocation')).TrimEnd('\')
            $byLoc  = $loc -and ($loc -ieq $PhpDir)
            $byName = ($dn -like 'PHP*') -and ($dv -like "$majMin*")
            if ($byLoc -or $byName) {
                $entries += [pscustomobject]@{
                    Root      = $root
                    Key       = $name
                    Name      = $dn
                    Version   = $dv
                    Uninstall = [string]$sk.GetValue('UninstallString')
                }
            }
            $sk.Close()
        }
        $rk.Close()
    }
    Write-Log "Matching uninstall entries: $($entries.Count)"

    # --- 5. MSI uninstall where available -----------------------------------
    foreach ($e in $entries) {
        Write-Log "Entry: '$($e.Name)' $($e.Version) [$($e.Root)\$($e.Key)]"
        if ($e.Uninstall -match 'msiexec' -and $e.Uninstall -match '\{[0-9A-Fa-f-]{36}\}') {
            $guid = $Matches[0]
            Write-Log "Running msiexec /x $guid /qn /norestart"
            $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
            if ($p.ExitCode -in 0, 1605, 3010) {
                Write-Log "msiexec exit code $($p.ExitCode) (OK)"
            } else {
                Write-Log "msiexec exit code $($p.ExitCode). Continuing with folder removal." 'WARN'
            }
        } else {
            Write-Log 'Not an MSI entry. Folder will be removed directly.'
        }
    }

    # --- 6. Delete folder ---------------------------------------------------
    if (Test-Path -LiteralPath $PhpDir) {
        Write-Log 'Deleting folder.'
        Remove-Item -LiteralPath $PhpDir -Recurse -Force
    }
    if (Test-Path -LiteralPath $PhpDir) {
        Write-Log 'Folder still present after delete.' 'ERROR'
        exit 1
    }
    Write-Log 'Folder removed.'

    # --- 7. Remove leftover uninstall entries -------------------------------
    foreach ($e in $entries) {
        $rk = $hklm.OpenSubKey($e.Root, $true)
        if ($rk -and ($rk.GetSubKeyNames() -contains $e.Key)) {
            $rk.DeleteSubKeyTree($e.Key, $false)
            Write-Log "Removed leftover uninstall key $($e.Root)\$($e.Key)"
        }
        if ($rk) { $rk.Close() }
    }

    # --- 8. Clean machine PATH (keeps REG_EXPAND_SZ and %vars% intact) ------
    $envKey = $hklm.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $true)
    $raw    = [string]$envKey.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $parts  = @($raw -split ';' | Where-Object { $_ -ne '' })
    $keep   = @($parts | Where-Object {
        [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ine $PhpDir
    })
    if ($keep.Count -ne $parts.Count) {
        $envKey.SetValue('Path', ($keep -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
        Write-Log "Removed $($parts.Count - $keep.Count) PATH entr(ies) pointing to the folder."
    } else {
        Write-Log 'No PATH entries to remove.'
    }
    $envKey.Close()
    $hklm.Close()

    Write-Log 'Done. Exit 0.'
    exit 0
}
catch {
    Write-Log "Failed: $($_.Exception.Message)" 'ERROR'
    exit 1
}
