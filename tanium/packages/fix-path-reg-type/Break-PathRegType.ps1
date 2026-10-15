<#
.SYNOPSIS
    LAB ONLY. Reproduces the Tanium Client Core Health errors on a test VM so
    Fix-PathRegType.ps1 can be validated. Never run this on a production machine.

.DESCRIPTION
    Run in an elevated PowerShell session on a lab VM. Take a VM snapshot first.

      .\Break-PathRegType.ps1 -Mode Break        Path becomes REG_SZ, data unchanged (%SystemRoot% kept)
      .\Break-PathRegType.ps1 -Mode BreakNoVars  Path becomes REG_SZ with variables expanded (no %)
      .\Break-PathRegType.ps1 -Mode HideClmTest  Renames Tools\StdUtils\tanium-clm-test.ps1 to .bak
      .\Break-PathRegType.ps1 -Mode Status       Shows the current state, changes nothing
      .\Break-PathRegType.ps1 -Mode Restore      Puts everything back

    The first Break or BreakNoVars saves the untouched Environment key to
    C:\Windows\Temp\Break-PathRegType_original.reg. Later runs do not overwrite it.
#>
param (
    [ValidateSet('Break', 'BreakNoVars', 'HideClmTest', 'Status', 'Restore')]
    [string]$Mode = 'Status'
)

$keyPath  = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$original = 'C:\Windows\Temp\Break-PathRegType_original.reg'
$noExpand = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Output 'Run this from an elevated PowerShell session.'; exit 1 }

function Get-ClmTestPath {
    foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Tanium\Tanium Client', 'HKLM:\SOFTWARE\Tanium\Tanium Client') {
        $dir = (Get-ItemProperty -Path $k -Name Path -ErrorAction SilentlyContinue).Path
        if ($dir) { return Join-Path $dir 'Tools\StdUtils\tanium-clm-test.ps1' }
    }
    return $null
}

function Show-Status {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($keyPath)
    Write-Output ("Path type:    {0}" -f $key.GetValueKind('Path'))
    Write-Output ("First entry:  {0}" -f (($key.GetValue('Path', $null, $noExpand) -split ';')[0]))
    $key.Close()
    $clm = Get-ClmTestPath
    if ($clm) {
        Write-Output ("clm test:     {0} exists: {1}, .bak exists: {2}" -f $clm, (Test-Path -LiteralPath $clm), (Test-Path -LiteralPath "$clm.bak"))
    } else {
        Write-Output 'clm test:     Tanium Client folder not found in the registry'
    }
    Write-Output ("Backup saved: {0}" -f (Test-Path -LiteralPath $original))
}

function Save-Original {
    if (Test-Path -LiteralPath $original) { return }
    & reg.exe export "HKLM\$keyPath" $original /y | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Output 'Backup failed. Nothing changed.'; exit 1 }
    Write-Output "Original Environment key saved to $original"
}

switch ($Mode) {
    'Break' {
        Save-Original
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($keyPath, $true)
        $key.SetValue('Path', $key.GetValue('Path', $null, $noExpand), [Microsoft.Win32.RegistryValueKind]::String)
        $key.Close()
        Write-Output 'Path is now REG_SZ with %SystemRoot% still in it.'
    }
    'BreakNoVars' {
        Save-Original
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($keyPath, $true)
        $key.SetValue('Path', $key.GetValue('Path'), [Microsoft.Win32.RegistryValueKind]::String)
        $key.Close()
        Write-Output 'Path is now REG_SZ with every variable expanded (no % left).'
    }
    'HideClmTest' {
        $clm = Get-ClmTestPath
        if (-not $clm -or -not (Test-Path -LiteralPath $clm)) { Write-Output "Not found: $clm"; exit 1 }
        Rename-Item -LiteralPath $clm -NewName 'tanium-clm-test.ps1.bak'
        Write-Output "Renamed $clm to tanium-clm-test.ps1.bak"
    }
    'Restore' {
        if (Test-Path -LiteralPath $original) {
            & reg.exe import $original 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Remove-Item -LiteralPath $original
                Write-Output 'Environment key restored from the original backup.'
            } else {
                Write-Output "reg import failed. The backup is still at $original"
            }
        }
        $clm = Get-ClmTestPath
        if ($clm -and (Test-Path -LiteralPath "$clm.bak") -and -not (Test-Path -LiteralPath $clm)) {
            Rename-Item -LiteralPath "$clm.bak" -NewName 'tanium-clm-test.ps1'
            Write-Output 'tanium-clm-test.ps1 restored.'
        }
    }
}

Show-Status
