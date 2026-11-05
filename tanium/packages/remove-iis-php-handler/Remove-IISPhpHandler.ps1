<#
.SYNOPSIS
    Removes IIS handler mappings and FastCGI applications that point to a PHP install folder.
    Built for a Tanium package.

.DESCRIPTION
    Usage: Remove-IISPhpHandler.ps1 "<PHP folder>" "<Mode: Report|Remove>"
    Default folder: C:\Program Files (x86)\PHP\v7.1
    Default mode:   Report

    Report: lists every matching handler mapping (server level and <location> sections in
            applicationHost.config) and every matching FastCGI application. Changes nothing.
    Remove: backs up the IIS configuration with appcmd, removes the handler mappings first,
            then the FastCGI applications, then re-reads the config to confirm they are gone.

    After Remove, any IIS site that relied on these entries can no longer run PHP from this folder.
    Run Remove only after the site owner has approved.

    Rollback: %windir%\system32\inetsrv\appcmd.exe restore backup "<backup name from the log>"

.NOTES
    Exit codes:
      0  Report completed, nothing to remove, or removal succeeded
      1  Failed (backup failed, appcmd error, or entries still present after removal)
      2  Blocked: path failed validation
    Log: C:\Windows\Temp\Remove-IISPhpHandler.log (also written to stdout)
#>

param(
    [string]$PhpDir,
    [string]$Mode
)

$ErrorActionPreference = 'Stop'
$DefaultDir = 'C:\Program Files (x86)\PHP\v7.1'
$LogFile    = Join-Path $env:windir 'Temp\Remove-IISPhpHandler.log'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 's'), $Level, $Message
    Write-Output $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Test-UnderFolder {
    param([string]$Value, [string]$Folder)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $expanded = [Environment]::ExpandEnvironmentVariables($Value)
    return $expanded.StartsWith("$Folder\", [StringComparison]::OrdinalIgnoreCase)
}

function Get-PhpIisEntries {
    param([string]$ConfigPath, [string]$Folder)

    [xml]$cfg = Get-Content -LiteralPath $ConfigPath -Raw

    # Handler mappings: server level plus any <location> sections in applicationHost.config
    $scopes = @([pscustomobject]@{ Location = ''; Node = $cfg.configuration.'system.webServer' })
    foreach ($loc in @($cfg.configuration.location)) {
        if ($loc) { $scopes += [pscustomobject]@{ Location = [string]$loc.path; Node = $loc.'system.webServer' } }
    }

    $handlers = @()
    foreach ($s in $scopes) {
        if (-not $s.Node -or -not $s.Node.handlers) { continue }
        foreach ($h in @($s.Node.handlers.add)) {
            if (-not $h) { continue }
            if (Test-UnderFolder -Value ([string]$h.scriptProcessor) -Folder $Folder) {
                $handlers += [pscustomobject]@{
                    Location        = $s.Location
                    Name            = [string]$h.name
                    Path            = [string]$h.path
                    ScriptProcessor = [string]$h.scriptProcessor
                }
            }
        }
    }

    # FastCGI applications (server level only; this section cannot be set per site)
    $fastCgi = @()
    $fNode = $cfg.configuration.'system.webServer'.fastCgi
    if ($fNode) {
        foreach ($a in @($fNode.application)) {
            if (-not $a) { continue }
            if (Test-UnderFolder -Value ([string]$a.fullPath) -Folder $Folder) {
                $fastCgi += [pscustomobject]@{
                    FullPath  = [string]$a.fullPath
                    Arguments = [string]$a.arguments
                }
            }
        }
    }

    [pscustomobject]@{ Handlers = $handlers; FastCgi = $fastCgi }
}

function Invoke-AppCmd {
    param([string]$AppCmd, [string[]]$Arguments)
    $out = & $AppCmd @Arguments 2>&1
    $text = ($out | ForEach-Object { "$_" }) -join ' '
    Write-Log "appcmd $($Arguments -join ' ') => exit $LASTEXITCODE | $text"
    if ($LASTEXITCODE -ne 0) { throw "appcmd failed with exit code $LASTEXITCODE" }
}

try {
    # Tanium passes parameters URL-encoded (a space arrives as %20), so decode them first.
    $PhpDir = [System.Uri]::UnescapeDataString([string]$PhpDir)
    $Mode   = [System.Uri]::UnescapeDataString([string]$Mode)
    if ([string]::IsNullOrWhiteSpace($PhpDir)) { $PhpDir = $DefaultDir }
    $PhpDir   = $PhpDir.Trim().Trim('"').TrimEnd('\')
    $removeOn = ([string]$Mode).Trim() -ieq 'Remove'
    Write-Log "Start. PHP folder: $PhpDir | Mode: $(if ($removeOn) { 'Remove' } else { 'Report' })"

    # --- Path validation ----------------------------------------------------
    $allowedRoots = @("$env:SystemDrive\Program Files (x86)\PHP", "$env:SystemDrive\Program Files\PHP")
    if ($allowedRoots -notcontains (Split-Path -Path $PhpDir -Parent)) {
        Write-Log "Blocked: folder must be directly under one of: $($allowedRoots -join ', ')" 'ERROR'
        exit 2
    }

    # Use Sysnative when running as a 32-bit process so System32 is not redirected to SysWOW64.
    $sysDir  = if (Test-Path "$env:windir\Sysnative") { "$env:windir\Sysnative" } else { "$env:windir\System32" }
    $appCmd  = Join-Path $sysDir 'inetsrv\appcmd.exe'
    $appHost = Join-Path $sysDir 'inetsrv\config\applicationHost.config'

    if (-not (Test-Path -LiteralPath $appHost) -or -not (Test-Path -LiteralPath $appCmd)) {
        Write-Log 'IIS not installed. Nothing to do.'
        exit 0
    }

    # --- Find entries -------------------------------------------------------
    $found = Get-PhpIisEntries -ConfigPath $appHost -Folder $PhpDir
    foreach ($h in $found.Handlers) {
        $scope = if ($h.Location) { "location '$($h.Location)'" } else { 'server level' }
        Write-Log "Handler: '$($h.Name)' path=$($h.Path) [$scope] -> $($h.ScriptProcessor)"
    }
    foreach ($f in $found.FastCgi) {
        Write-Log "FastCGI application: $($f.FullPath) arguments='$($f.Arguments)'"
    }
    Write-Log "Found $($found.Handlers.Count) handler mapping(s) and $($found.FastCgi.Count) FastCGI application(s)."

    if ($found.Handlers.Count -eq 0 -and $found.FastCgi.Count -eq 0) {
        Write-Log 'Nothing references this folder. Done. Exit 0.'
        exit 0
    }

    if (-not $removeOn) {
        Write-Log 'Report mode. No changes made. Rerun with Mode = Remove to delete these entries. Exit 0.'
        exit 0
    }

    # --- Backup IIS config --------------------------------------------------
    $backupName = 'PHP-Cleanup-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    Invoke-AppCmd -AppCmd $appCmd -Arguments @('add', 'backup', $backupName)
    Write-Log "IIS config backed up as '$backupName'. Rollback: appcmd restore backup `"$backupName`""

    # --- Remove handler mappings first, then FastCGI applications -----------
    foreach ($h in $found.Handlers) {
        $a = @('set', 'config')
        if ($h.Location) { $a += $h.Location }
        $a += @('-section:system.webServer/handlers', "/-[name='$($h.Name)']", '/commit:apphost')
        Invoke-AppCmd -AppCmd $appCmd -Arguments $a
    }

    foreach ($f in $found.FastCgi) {
        $key = if ($f.Arguments) { "[fullPath='$($f.FullPath)',arguments='$($f.Arguments)']" } else { "[fullPath='$($f.FullPath)']" }
        Invoke-AppCmd -AppCmd $appCmd -Arguments @('set', 'config', '-section:system.webServer/fastCgi', "/-$key", '/commit:apphost')
    }

    # --- Verify -------------------------------------------------------------
    $after = Get-PhpIisEntries -ConfigPath $appHost -Folder $PhpDir
    if ($after.Handlers.Count -gt 0 -or $after.FastCgi.Count -gt 0) {
        Write-Log "Still present after removal: $($after.Handlers.Count) handler(s), $($after.FastCgi.Count) FastCGI app(s)." 'ERROR'
        exit 1
    }

    Write-Log "All IIS references to $PhpDir removed. Backup: '$backupName'. Exit 0."
    exit 0
}
catch {
    Write-Log "Failed: $($_.Exception.Message)" 'ERROR'
    exit 1
}
