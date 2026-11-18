<#
.SYNOPSIS
    RunCommand.ps1
    Break-glass package: checks one operator-supplied PowerShell command and,
    in Run mode, runs it.
    Built to run as a Tanium package (runs as SYSTEM). For Windows.

.DESCRIPTION
    1. Reads Mode and the command, and URL-decodes the command.
    2. Runs the safety checks. They stop the command when it deletes a
       protected Windows path, runs a high-damage disk, boot, registry, or
       shadow-copy operation, stops or removes CrowdStrike, Tanium, or CyberArk,
       or uses an encoded command or Invoke-Expression.
    3. Audit mode stops here and reports what Run mode would do.
       Run mode runs the command in Windows PowerShell 5.1.

    SECURITY MODEL: the real control is the content set and RBAC that limit
    who can deploy this package. The checks prevent accidents. They are not a
    security boundary, and a trusted operator who wants to get around them can.
    Do not widen deploy rights because the checks exist.

.PARAMETER (positional, passed by Tanium as "$1" "$2")
    $1  Mode     Audit = run the checks and report, run nothing (default)
                 Run   = run the checks, then run the command if they pass
    $2  Command  The PowerShell command to run. Required.

.NOTES
    Tanium command line:
      cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File RunCommand.ps1 "$1" "$2"

    Exit codes:
      0  Finished. Run: the command ran and returned 0. Audit: always 0
         (read the BLOCKED or WOULD RUN line).
      1  The command ran and failed: it returned a non-zero exit code or
         stopped with an error. The log line gives the command's own code.
         Some programs (robocopy) use non-zero codes for success.
      2  A parameter was wrong (Mode, empty command, the value was split, or the
         command is not valid PowerShell). Nothing ran.
      3  Stopped by a check: protected Windows path, or a high-damage disk,
         boot, registry, or shadow-copy operation. Nothing ran.
      4  Unexpected error in the script. Nothing ran.
      5  Stopped by a check: protected security agent. Nothing ran.
      6  Stopped by a check: encoded command or Invoke-Expression. Nothing ran.
      The first check that trips decides the code, except that a high-damage
      operation (3) wins over a protected path found earlier.

    Log:
      The Tanium action log shows the important lines and the first 60 lines
      of the command's output, because the console shows about 100 lines.
      Every line, with up to 5000 output lines, goes to
      C:\Windows\Temp\RunCommand.log. Change the two numbers below the header.
      The command is logged as typed. A password or token in it is logged too.
      Output that a program writes to its error stream is not captured. It
      goes straight to the action log and is not counted or cut.

    Works with Windows PowerShell 5.1.
#>

$ErrorActionPreference = 'Stop'

$ScriptVersion = '2.0.0'
$ScriptName    = 'RunCommand'
$LogFile       = Join-Path $env:windir ("Temp\{0}.log" -f $ScriptName)
$RawArgs       = @($args)

# How many lines of the command's output to show in the Tanium action log, and
# to keep in the log file. Keep the first number well under 100.
$MaxActionLogOutputLines = 60
$MaxFileOutputLines      = 5000

# If the Tanium Client started the 32-bit PowerShell on 64-bit Windows, start again in the
# 64-bit one. The raw (still URL-encoded) values are passed on, so they are decoded only once.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:windir 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $powershell64) {
        # Windows PowerShell 5.1 drops an empty value when it starts a program, which would
        # move the values after it one place to the left. '""' keeps the empty place.
        $passOn = @($RawArgs | ForEach-Object { if ([string]::IsNullOrEmpty([string]$_)) { '""' } else { [string]$_ } })
        & $powershell64 -ExecutionPolicy Bypass -NoProfile -NonInteractive -File $PSCommandPath @passOn
        exit $LASTEXITCODE
    }
}

# ----------------------------------------------------------------------------
# Logging: each line goes to the Tanium action log (Write-Host) and to the log
# file. -FileOnly keeps a detail line out of the action log.
# ----------------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO', [switch]$FileOnly)
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if (-not $FileOnly) { Write-Host $line }
    try {
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

function Get-PackageParameter {
    # Tanium passes parameter values percent-encoded (for example %2C for a comma).
    param([int]$Index, [string]$Default)
    if ($RawArgs.Count -gt $Index -and $null -ne $RawArgs[$Index]) {
        $value = [string]$RawArgs[$Index]
        try { $value = [System.Uri]::UnescapeDataString($value) } catch { }
        $value = $value.Trim().Trim('"').Trim("'").Trim()
        if ($value -ne '') { return $value }
    }
    return $Default
}

function Complete-Run {
    # Writes the summary and the last line, then stops the script with the exit code.
    param([int]$Code, [string]$Summary)
    if ($Summary) { Write-Log $Summary }
    Write-Log ("===== Finished with exit code {0} =====" -f $Code)
    exit $Code
}

$script:BlockCode = 0
$script:BlockText = $null
function Set-Block {
    # Records the first reason to stop. Later reasons are ignored.
    param([int]$Code, [string]$Text)
    if (-not $script:BlockCode) { $script:BlockCode = $Code; $script:BlockText = $Text }
}
function Stop-IfBlocked {
    # Call only as a statement at script level.
    if (-not $script:BlockCode) { return }
    if ($script:BlockCode -eq 2) {
        Write-Log ('{0,-14}{1} Nothing ran.' -f 'WRONG INPUT', $script:BlockText) 'ERROR'
        Complete-Run 2 ('Summary ({0}): wrong input, nothing ran' -f $Mode)
    }
    Write-Log ('{0,-14}{1}' -f 'BLOCKED', $script:BlockText) 'WARN'
    if ($Mode -eq 'Audit') { Complete-Run 0 'Summary (Audit, nothing changed): would run=0; blocked=1' }
    Complete-Run $script:BlockCode 'Summary (Run): blocked=1; nothing ran'
}
trap {
    # Any unexpected error inside the checks: stop, run nothing, say why.
    Write-Log ('Unexpected error in the safety checks, so nothing ran: {0}' -f $_.Exception.Message) 'ERROR'
    Complete-Run 4 'Summary: unexpected error, nothing ran'
}

# ----------------------------------------------------------------------------
# Parameters
# ----------------------------------------------------------------------------
Start-LogFile
$Mode = Get-PackageParameter -Index 0 -Default 'Audit'
# The command is decoded only. Quotes and spaces at its ends are part of the command.
$RawCommand = ''
if ($RawArgs.Count -ge 2 -and $null -ne $RawArgs[1]) { $RawCommand = [string]$RawArgs[1] }
$DecodedCommand = $RawCommand
try { $DecodedCommand = [System.Uri]::UnescapeDataString($RawCommand) } catch { }

Write-Log ("===== {0} {1} started on {2} =====" -f $ScriptName, $ScriptVersion, $env:COMPUTERNAME)
# The command is logged as typed, so a secret in it is logged too.
Write-Log ("Settings: mode={0}; command={1}" -f $Mode, $DecodedCommand)

switch -Regex ($Mode) {
    '^(?i)audit$' { $Mode = 'Audit' }
    '^(?i)run$'   { $Mode = 'Run' }
    default {
        Write-Log ('{0,-14}Mode must be Audit or Run. Got: {1}. Nothing ran.' -f 'WRONG INPUT', $Mode) 'ERROR'
        Complete-Run 2 'Summary: wrong input, nothing ran'
    }
}
if ($RawArgs.Count -gt 2) {
    Write-Log ('{0,-14}the script received {1} values instead of 2. The command was split before it reached the script, so the quoting or URL-encoding broke. Nothing ran.' -f 'WRONG INPUT', $RawArgs.Count) 'ERROR'
    Complete-Run 2 ('Summary ({0}): wrong input, nothing ran' -f $Mode)
}
if ([string]::IsNullOrWhiteSpace($DecodedCommand)) {
    Write-Log ('{0,-14}the command is empty. Nothing ran.' -f 'WRONG INPUT') 'ERROR'
    Complete-Run 2 ('Summary ({0}): wrong input, nothing ran' -f $Mode)
}

# ----- helpers --------------------------------------------------------
$script:Bases = @((Get-Location).ProviderPath)   # folders a relative path could be resolved against
$script:CdDynamic = $false                       # a Set-Location target this script cannot read
$script:NeedWholeScan = $false                   # a delete this script cannot bind to one path

function Expand-EnvText {
    # expands %var%, $env:var, ${env:var} and $pwd. An undefined $env: variable becomes
    # empty text, the same as PowerShell does at run time ("$env:Nope\*" really is "\*").
    param([string]$Text)
    if (-not $Text) { return '' }
    $t = [System.Environment]::ExpandEnvironmentVariables($Text)
    $t = [regex]::Replace($t, '(?i)\$\{env:([^}]+)\}|\$env:([a-z_][a-z0-9_]*)', {
        param($m)
        $name = $m.Groups[2].Value
        if ($m.Groups[1].Success) { $name = $m.Groups[1].Value }
        $v = [System.Environment]::GetEnvironmentVariable($name)
        if ($null -ne $v) { $v } else { '' }
    })
    $t = [regex]::Replace($t, '(?i)\$pwd\b', { param($m) (Get-Location).ProviderPath })
    return $t
}

function Join-Segments {
    # collapses . and .. and doubled separators, trims trailing dots and spaces the way
    # Windows does, and expands 8.3 short names (PROGRA~1) when the folder exists
    param([string]$Drive, [string]$Rest, [bool]$IsFileSystem)
    $out = New-Object System.Collections.ArrayList
    foreach ($s in ($Rest -split '\\')) {
        if ($s -eq '' -or $s -eq '.') { continue }
        if ($s -eq '..') { if ($out.Count -gt 0) { $out.RemoveAt($out.Count - 1) }; continue }
        $seg = $s.TrimEnd('.', ' ')
        if ($seg -eq '') { continue }
        if ($IsFileSystem -and $seg -match '~\d' -and $seg -notmatch '[*?\[]') {
            try {
                $parent = $Drive + '\' + (($out.ToArray()) -join '\')
                if (-not $parent.EndsWith('\')) { $parent += '\' }
                $found = @([System.IO.Directory]::GetFileSystemEntries($parent, $seg))
                if ($found.Count -ge 1) { $seg = [System.IO.Path]::GetFileName($found[0]) }
            } catch { }
        }
        [void]$out.Add($seg)
    }
    return ($Drive + '\' + (($out.ToArray()) -join '\'))
}

function ConvertTo-CheckPath {
    # Turns a path as typed into the normalized absolute form(s) the lists are matched against,
    # for example 'C:\Windows\System32', 'HKLM:\SOFTWARE\X' or '\\host\share\x'.
    # A relative path gives one result per folder in $script:Bases.
    param([string]$Text, [switch]$RegistryContext)
    $t = (Expand-EnvText $Text).Trim().Trim('"', "'").Trim()
    if (-not $t) { return @() }
    $t = $t -replace '/', '\'
    $t = $t -replace '(?i)^(Microsoft\.PowerShell\.Core\\)?FileSystem::', ''

    # registry: HKLM:\x, HKLM:x, Registry::HKEY_LOCAL_MACHINE\x, and for reg.exe HKLM\x or \\host\HKLM\x
    $hiveRx = '(?i)^(?<prov>(?:Microsoft\.PowerShell\.Core\\)?Registry::)?(?:\\\\[^\\]+\\)?(?<hive>HKLM|HKEY_LOCAL_MACHINE|HKCU|HKEY_CURRENT_USER|HKCR|HKEY_CLASSES_ROOT|HKU|HKEY_USERS|HKCC|HKEY_CURRENT_CONFIG)(?<sep>:\\?|\\|$)(?<rest>.*)$'
    if ($t -match $hiveRx) {
        $isReg = $RegistryContext -or $Matches['prov'] -or $Matches['sep'].StartsWith(':')
        if ($isReg) {
            $rest = $Matches['rest']
            switch -Regex ($Matches['hive']) {
                '(?i)^(HKLM|HKEY_LOCAL_MACHINE)$'  { return @(Join-Segments 'HKLM:' $rest $false) }
                '(?i)^(HKCR|HKEY_CLASSES_ROOT)$'   { return @(Join-Segments 'HKLM:' ('SOFTWARE\Classes\' + $rest) $false) }
                '(?i)^(HKU|HKEY_USERS)$'           { return @(Join-Segments 'HKU:' $rest $false) }
                '(?i)^(HKCU|HKEY_CURRENT_USER)$'   { return @(Join-Segments 'HKCU:' $rest $false) }
                default                            { return @(Join-Segments 'HKCC:' $rest $false) }
            }
        }
    }

    # \\?\C:\x and \\.\C:\x and \\?\UNC\host\share
    $t = $t -replace '(?i)^\\\\[?.]\\UNC\\', '\\'
    $t = $t -replace '^\\\\[?.]\\', ''

    # the local admin shares are just the local drive
    $me = [regex]::Escape([string]$env:COMPUTERNAME)
    $local = "(?:localhost|127\.0\.0\.1|\.|$me)"
    if ($t -match "(?i)^\\\\$local\\([a-z])\`$(\\.*)?`$") { $t = $Matches[1] + ':' + [string]$Matches[2] }
    elseif ($t -match "(?i)^\\\\$local\\admin\`$(\\.*)?`$") { $t = [string]$env:windir + [string]$Matches[1] }

    # UNC
    if ($t -match '^\\\\([^\\]+)\\([^\\]+)(.*)$') {
        return @(Join-Segments ('\\' + $Matches[1] + '\' + $Matches[2]) $Matches[3] $false)
    }
    # drive letter (C:\x, and C:x which is treated as C:\x)
    if ($t -match '^([A-Za-z]):(.*)$') {
        return @(Join-Segments ($Matches[1].ToUpper() + ':') $Matches[2] $true)
    }
    # another PowerShell drive (Env:, Cert:, Function:, Variable:) is not checked
    if ($t -match '^[A-Za-z][\w.]*:') { return @() }

    # relative, or rooted without a drive (\Windows): resolve against every known folder
    $results = New-Object System.Collections.ArrayList
    foreach ($b in $script:Bases) {
        if (-not $b) { continue }
        $full = $null
        if ($t.StartsWith('\')) {
            if ($b -match '^([A-Za-z]:|HK[A-Z]+:)') { $full = $Matches[1] + $t }
            elseif ($b -match '^(\\\\[^\\]+\\[^\\]+)') { $full = $Matches[1] + $t }
        }
        else { $full = $b.TrimEnd('\') + '\' + $t }
        if ($full) {
            foreach ($n in (ConvertTo-CheckPath -Text $full -RegistryContext:$false)) {
                if ($results -notcontains $n) { [void]$results.Add($n) }
            }
        }
    }
    return @($results.ToArray())
}

# ----- protected locations --------------------------------------------
# Class: fs (any drive letter) or a registry hive. Mode:
#   Allow   - cleanup folders that may be deleted even though they sit under a protected folder
#   Subtree - the folder and everything in it
#   Exact   - the folder itself (and "folder\*"), but not single items inside it
# A path is also protected when it is a PARENT of a protected folder (C:\ProgramData holds
# C:\ProgramData\Microsoft\Windows), and when a wildcard in it could match one (C:\Win*).
$script:Roots = New-Object System.Collections.ArrayList
function Add-Root {
    param([string]$Class, [string]$Path, [string]$Mode, [string]$Kind)
    [void]$script:Roots.Add([pscustomobject]@{
        Class = $Class; Segs = @($Path -split '\\' | Where-Object { $_ }); Mode = $Mode; Kind = $Kind
    })
}
foreach ($p in 'Windows\Temp', 'Windows\SoftwareDistribution\Download', 'Windows\ccmcache', 'Windows\Logs') { Add-Root 'fs' $p 'Allow' '' }
foreach ($p in 'Windows', 'Boot', 'Recovery', 'System Volume Information', 'Program Files\WindowsApps',
               'Program Files (x86)\WindowsApps', 'ProgramData\Microsoft\Windows', '$Recycle.Bin') { Add-Root 'fs' $p 'Subtree' 'os' }
# 'Users' is new in v2 (C:\Users and C:\Users\* only). Remove it if you do not want it.
foreach ($p in 'Program Files', 'Program Files (x86)', 'Users') { Add-Root 'fs' $p 'Exact' 'os' }

# security agent folders and registry keys. Add your real install folders if they differ.
$AgentFolderNames = 'CrowdStrike', 'Tanium', 'CyberArk'
foreach ($parent in 'Program Files', 'Program Files (x86)', 'ProgramData') {
    foreach ($v in $AgentFolderNames) { Add-Root 'fs' "$parent\$v" 'Subtree' 'agent' }
}
foreach ($p in 'SYSTEM', 'SAM', 'SECURITY') { Add-Root 'HKLM' $p 'Subtree' 'os' }
foreach ($p in 'SOFTWARE', 'SOFTWARE\Microsoft', 'SOFTWARE\Microsoft\Windows', 'SOFTWARE\Microsoft\Windows\CurrentVersion',
               'SOFTWARE\Microsoft\Windows NT', 'SOFTWARE\Microsoft\Windows NT\CurrentVersion', 'SOFTWARE\Classes',
               'SOFTWARE\Policies', 'SOFTWARE\WOW6432Node') { Add-Root 'HKLM' $p 'Exact' 'os' }
foreach ($v in $AgentFolderNames) {
    Add-Root 'HKLM' "SOFTWARE\$v" 'Subtree' 'agent'
    Add-Root 'HKLM' "SOFTWARE\WOW6432Node\$v" 'Subtree' 'agent'
}
Add-Root 'HKU' '' 'Exact' 'os'
# When Tanium runs this, the script sits in <Tanium Client>\Downloads\Action_<id>. Protect the
# client folder wherever it is installed, but let the operator clean this action's own folder.
if ($PSScriptRoot -match '^[A-Za-z]:\\(.+)\\Downloads\\Action_\d+$') {
    Add-Root 'fs' $Matches[1] 'Subtree' 'agent'
    Add-Root 'fs' $PSScriptRoot.Substring(3) 'Allow' ''
}

function Test-Seg {
    # does one typed path segment (maybe with wildcards) match one protected segment
    param([string]$Typed, [string]$Root)
    if ($Typed -match '[*?\[]') {
        try { return ($Root -like $Typed) } catch { return ($Typed -eq $Root) }
    }
    return ($Typed -eq $Root)
}

function Get-ProtectionKind {
    # returns $null, 'os' or 'agent' for one normalized path
    param([string]$NormPath)
    $class = $null; $rest = ''
    if ($NormPath -match '^(\\\\[^\\]+\\[^\\]+)') {
        # admin shares on other hosts stay blocked as a whole, as in v1
        if ($Matches[1] -match '(?i)\\([a-z]|admin)\$$') { return 'os' }
        return $null
    }
    elseif ($NormPath -match '^[A-Za-z]:(.*)$') { $class = 'fs'; $rest = $Matches[1] }
    elseif ($NormPath -match '^(HK[A-Z]+):(.*)$') { $class = $Matches[1].ToUpper(); $rest = $Matches[2] }
    else { return $null }
    $segs = @($rest -split '\\' | Where-Object { $_ })

    foreach ($r in $script:Roots) {
        if ($r.Mode -ne 'Allow' -or $r.Class -ne $class -or $segs.Count -lt $r.Segs.Count) { continue }
        $same = $true
        for ($i = 0; $i -lt $r.Segs.Count; $i++) { if ($segs[$i] -ne $r.Segs[$i]) { $same = $false; break } }
        if ($same) { return $null }                                   # allow wins
    }
    $kind = $null
    foreach ($r in $script:Roots) {
        if ($r.Mode -eq 'Allow' -or $r.Class -ne $class) { continue }
        $n = [Math]::Min($segs.Count, $r.Segs.Count)
        $overlap = $true
        for ($i = 0; $i -lt $n; $i++) { if (-not (Test-Seg $segs[$i] $r.Segs[$i])) { $overlap = $false; break } }
        if (-not $overlap) { continue }
        $hit = $false
        if ($segs.Count -le $r.Segs.Count) { $hit = $true }           # the root itself, or a parent of it
        elseif ($r.Mode -eq 'Subtree') { $hit = $true }               # something inside it
        elseif ($segs.Count -eq ($r.Segs.Count + 1) -and ($segs[$segs.Count - 1] -eq '*' -or $segs[$segs.Count - 1] -eq '*.*')) { $hit = $true }
        if ($hit) {
            if ($r.Kind -eq 'os') { return 'os' }
            $kind = 'agent'
        }
    }
    return $kind
}

function Test-Protected {
    # returns $null, or an object with Kind ('os' / 'agent') and the normalized Path that matched
    param([string]$Token, [switch]$RegistryContext)
    foreach ($n in (ConvertTo-CheckPath -Text $Token -RegistryContext:$RegistryContext)) {
        $k = Get-ProtectionKind $n
        if ($k) { return [pscustomobject]@{ Kind = $k; Path = $n } }
    }
    return $null
}

function Set-PathBlock {
    param($Hit, [string]$Typed, [string]$How = 'deletes')
    $shown = "'$($Hit.Path)'"
    if ($Typed -and $Typed.Trim('"', "'") -ne $Hit.Path) { $shown = "'$Typed' (checked as '$($Hit.Path)')" }
    if ($Hit.Kind -eq 'agent') {
        Set-Block 5 "command $How $shown, which belongs to a protected security agent (CrowdStrike, Tanium, or CyberArk)."
    }
    else {
        Set-Block 3 "command $How $shown, a protected OS path."
    }
}

function Test-IsRelative {
    param([string]$Text)
    $t = (Expand-EnvText $Text).Trim().Trim('"', "'") -replace '/', '\'
    return ($t -notmatch '^(\\\\|[A-Za-z][\w.]*:|(Microsoft\.PowerShell\.Core\\)?\w+::)')
}

function Find-ProtectedToken {
    # Conservative fallback for deletes this script cannot bind to one path: test every
    # path-looking token in the text.
    param([string]$Text)
    $rx = '(?i)(?<![\w:\\])(?:[a-z]:[\\/]|%[\w()]+%|\$env:\w+|\$\{env:[^}]+\}|\\\\[^\\\s"'']+\\)[^"''|;&<>\r\n]*'
    foreach ($m in [regex]::Matches($Text, $rx)) {
        $whole = $m.Value.Trim()
        # the whole token, then the token cut at the first space, ")" or ","
        foreach ($cand in @($whole, ($whole -split '\s+')[0], ($whole -split '\)')[0], ($whole -split ',')[0]) | Select-Object -Unique) {
            $hit = Test-Protected $cand
            if ($hit) { return [pscustomobject]@{ Hit = $hit; Typed = $cand } }
        }
    }
    foreach ($m in [regex]::Matches($Text, '(?<![\w:\\.%$])\\[A-Za-z$][^\s"''|;&<>]*')) {   # \Windows
        $hit = Test-Protected $m.Value
        if ($hit) { return [pscustomobject]@{ Hit = $hit; Typed = $m.Value } }
    }
    return $null
}

function Test-KnownVariable {
    param($Node)
    return ($Node -is [System.Management.Automation.Language.VariableExpressionAst] -and
            ($Node.VariablePath.DriveName -eq 'env' -or $Node.VariablePath.UserPath -eq 'pwd'))
}

function Get-Literal {
    # Reads the literal text of one argument. Dynamic is $true when any part of it is only
    # known at run time (a variable, a sub-expression, a method call).
    param($Node)
    $r = [pscustomobject]@{ Dynamic = $false; Values = @() }
    if ($null -eq $Node) { return $r }
    if ($Node -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $r.Values = @([string]$Node.Value); return $r }
    if ($Node -is [System.Management.Automation.Language.ConstantExpressionAst]) { $r.Values = @([string]$Node.Value); return $r }
    if ($Node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        foreach ($n in $Node.NestedExpressions) { if (-not (Test-KnownVariable $n)) { $r.Dynamic = $true; return $r } }
        $r.Values = @(Expand-EnvText $Node.Value); return $r
    }
    if ($Node -is [System.Management.Automation.Language.VariableExpressionAst]) {
        if (-not $Node.Splatted -and (Test-KnownVariable $Node)) { $r.Values = @(Expand-EnvText $Node.Extent.Text); return $r }
        $r.Dynamic = $true; return $r
    }
    if ($Node -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        foreach ($e in $Node.Elements) {
            $x = Get-Literal $e
            if ($x.Dynamic) { $r.Dynamic = $true; return $r }
            $r.Values = @($r.Values) + @($x.Values)
        }
        return $r
    }
    if ($Node -is [System.Management.Automation.Language.ParenExpressionAst]) {
        $pl = $Node.Pipeline
        if ($pl -is [System.Management.Automation.Language.PipelineAst] -and $pl.PipelineElements.Count -eq 1 -and
            $pl.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
            return (Get-Literal $pl.PipelineElements[0].Expression)
        }
    }
    $r.Dynamic = $true; return $r
}

function Get-BoundArgs {
    # Small static parameter binder. Returns a hashtable: parameter name -> list of argument ASTs,
    # '_pos' -> positional arguments in order. A switch is present as a key with an empty list.
    # An unknown or ambiguous parameter name is treated as a switch, so the argument after it is
    # checked as a positional value (the safe direction).
    param($Cmd, [string[]]$ValueParams, [string[]]$SwitchParams, [hashtable]$Aliases)
    $valueAll = @($ValueParams) + @('ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable',
                                   'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable')
    $switchAll = @($SwitchParams) + @('Verbose', 'Debug', 'WhatIf', 'Confirm')
    $aliasAll = @{ ea = 'ErrorAction'; wa = 'WarningAction'; infa = 'InformationAction'; ev = 'ErrorVariable'; wv = 'WarningVariable'
                   iv = 'InformationVariable'; ov = 'OutVariable'; ob = 'OutBuffer'; pv = 'PipelineVariable'; vb = 'Verbose'
                   db = 'Debug'; wi = 'WhatIf'; cf = 'Confirm' }
    if ($Aliases) { foreach ($k in $Aliases.Keys) { $aliasAll[$k] = $Aliases[$k] } }
    $result = @{ _pos = (New-Object System.Collections.ArrayList) }
    $pending = $null
    for ($i = 1; $i -lt $Cmd.CommandElements.Count; $i++) {
        $el = $Cmd.CommandElements[$i]
        if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
            $pending = $null
            $typed = [string]$el.ParameterName
            $name = $typed
            if ($aliasAll.ContainsKey($typed)) { $name = $aliasAll[$typed] }
            else {
                $exact = @(@($valueAll) + @($switchAll) | Where-Object { $_ -eq $typed })
                if ($exact.Count -ge 1) { $name = $exact[0] }
                else {
                    $prefix = @(@($valueAll) + @($switchAll) | Where-Object { $_ -like "$typed*" })
                    if ($prefix.Count -eq 1) { $name = $prefix[0] }
                }
            }
            if (-not $result.ContainsKey($name)) { $result[$name] = (New-Object System.Collections.ArrayList) }
            if ($el.Argument) { [void]$result[$name].Add($el.Argument) }       # -Name:value
            elseif ($valueAll -contains $name) { $pending = $name }
            continue
        }
        if ($pending) { [void]$result[$pending].Add($el); $pending = $null }
        else { [void]$result['_pos'].Add($el) }
    }
    return $result
}

$script:CmdCache = @{}
function Get-CmdInfo {
    # Follows an alias to its real command (rm -> Remove-Item, kill -> Stop-Process).
    # It reads the alias Definition. ResolvedCommand is empty until the module that owns the
    # target cmdlet has been loaded, which it has not in a new Windows PowerShell started by a package.
    param([string]$Name)
    if (-not $Name) { return [pscustomobject]@{ Name = ''; Leaf = ''; Type = 'Unknown' } }
    if ($script:CmdCache.ContainsKey($Name)) { return $script:CmdCache[$Name] }
    $n = $Name.Trim('"', "'"); $type = 'Unknown'
    if ($n -notmatch '[*?\[\]$`]' -and $n.Length -lt 260) {
        for ($hop = 0; $hop -lt 5; $hop++) {
            $c = $null
            try { $c = @(Get-Command -Name $n -ErrorAction SilentlyContinue)[0] } catch { $c = $null }
            if (-not $c) { break }
            if ($c.CommandType -eq 'Alias') { $n = [string]$c.Definition; continue }
            $n = [string]$c.Name; $type = [string]$c.CommandType; break
        }
    }
    $leaf = ($n -replace '^.*[\\/]', '') -replace '(?i)\.(exe|com|cmd|bat)$', ''
    $info = [pscustomobject]@{ Name = $n; Leaf = $leaf; Type = $type }
    $script:CmdCache[$Name] = $info
    return $info
}
function Get-AstCmdInfo {
    param($Cmd)
    $nm = $Cmd.GetCommandName()
    if (-not $nm) { $nm = [string]$Cmd.CommandElements[0].Extent.Text }    # & "$env:windir\System32\cmd.exe"
    return (Get-CmdInfo $nm)
}

function Get-PipelineSource {
    # for a command fed by the pipeline (also inside ForEach-Object { }), returns the first
    # element of that pipeline
    param($Cmd)
    $node = $Cmd
    while ($node) {
        $parent = $node.Parent
        if ($parent -is [System.Management.Automation.Language.PipelineAst] -and $parent.PipelineElements.Count -gt 1 -and
            $parent.PipelineElements[0] -ne $node) {
            return $parent.PipelineElements[0]
        }
        $node = $parent
    }
    return $null
}

# ----- 1. Parse -------------------------------------------------------
$tok = $null; $perr = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($DecodedCommand, [ref]$tok, [ref]$perr)
if ($perr -and $perr.Count -gt 0) {
    Set-Block 2 "input did not parse cleanly as PowerShell ($($perr[0].Message))."
}
Stop-IfBlocked

# Command lines hidden inside the command (cmd /c "...", powershell -Command "...",
# Start-Process -ArgumentList ...) are parsed too, so the checks below see them.
$script:Cmds = New-Object System.Collections.ArrayList    # every command found: Cmd, Info, Nested
$script:AllAsts = New-Object System.Collections.ArrayList
$script:SeenText = @{}
$NestedDeleteVerb = '(?i)(?<![\w\\.:$-])(del|erase|rd|rmdir|rm|ri|Remove-Item)(?![\w\\.:-])'
$Launchers = 'cmd', 'powershell', 'pwsh', 'psexec', 'psexec64', 'wmic', 'schtasks', 'forfiles', 'start'

function Add-Ast {
    param($Tree, [bool]$Nested, [int]$Depth)
    [void]$script:AllAsts.Add($Tree)
    $found = $Tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($c in $found) {
        $info = Get-AstCmdInfo $c
        [void]$script:Cmds.Add([pscustomobject]@{ Cmd = $c; Info = $info; Nested = $Nested })
        # does this command carry another command line in its arguments?
        $carrier = ($info.Name -eq 'Start-Process') -or ($Launchers -contains $info.Leaf)
        if (-not $carrier -and -not $Nested -and $info.Type -in 'Application', 'ExternalScript', 'Unknown') { $carrier = $true }
        if ($carrier -and $c.CommandElements.Count -gt 1) {
            $vals = New-Object System.Collections.ArrayList
            for ($i = 1; $i -lt $c.CommandElements.Count; $i++) {
                $el = $c.CommandElements[$i]
                $strings = @($el.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                                                   $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true))
                if ($el -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                    $el -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { $strings = @($el) }
                if ($strings.Count -eq 0) { [void]$vals.Add([string]$el.Extent.Text); continue }
                foreach ($s in $strings) {
                    $v = [string]$s.Value
                    if ($v -match '\s') {
                        if ($v -match '\$') { $v = '"' + ($v -replace '"', '`"') + '"' } else { $v = "'" + ($v -replace "'", "''") + "'" }
                    }
                    [void]$vals.Add($v)
                }
            }
            $arr = $vals.ToArray()
            for ($i = 0; $i -lt $arr.Count; $i++) { Add-CommandText (($arr[$i..($arr.Count - 1)]) -join ' ') ($Depth + 1) }
        }
    }
    # any quoted string that looks like a command line
    $quoted = $Tree.FindAll({ param($n)
        ($n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
         $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and
        $n.StringConstantType -ne 'BareWord' -and ([string]$n.Value) -match '\S\s+\S' }, $true)
    foreach ($s in $quoted) { Add-CommandText ([string]$s.Value) ($Depth + 1) }
}
function Add-CommandText {
    param([string]$Text, [int]$Depth)
    if (-not $Text -or $Depth -gt 12) { return }       # each unwrap makes the text shorter; 12 is a safety stop
    $key = $Text.Trim()
    if (-not $key -or $script:SeenText.ContainsKey($key)) { return }
    $script:SeenText[$key] = $true
    # "/c rd /s /q C:\x" or "-NoProfile -Command Remove-Item C:\x": also read it without the leading switches
    $bare = $key -replace '^(?:[/-]\S+\s+)+', ''
    if ($bare -ne $key) { Add-CommandText $bare ($Depth + 1) }
    $tk = $null; $er = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseInput($key, [ref]$tk, [ref]$er)
    if ($er -and $er.Count -gt 0) {
        # cmd.exe syntax that PowerShell cannot parse: try the pieces between & && | ||
        $parts = @($key -split '\s*(?:&&|\|\||&|\|)\s*' | Where-Object { $_ })
        if ($parts.Count -gt 1) { foreach ($p in $parts) { Add-CommandText $p ($Depth + 1) } }
        elseif ($key -match $NestedDeleteVerb) { $script:NeedWholeScan = $true }
        return
    }
    Add-Ast $tree $true $Depth
}
$script:SeenText[$DecodedCommand.Trim()] = $true
Add-Ast $ast $false 0

# folders a relative path could mean: the current folder plus every literal Set-Location target
foreach ($rec in $script:Cmds) {
    if ($rec.Info.Name -notin 'Set-Location', 'Push-Location') { continue }
    for ($i = 1; $i -lt $rec.Cmd.CommandElements.Count; $i++) {
        $el = $rec.Cmd.CommandElements[$i]
        if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
            if ($el.Argument) { $el = $el.Argument } else { continue }
        }
        $lit = Get-Literal $el
        if ($lit.Dynamic) { $script:CdDynamic = $true; continue }
        foreach ($v in $lit.Values) {
            if ($v -match '^/[A-Za-z]$' -or $v -eq '-' -or $v -eq '+') { continue }       # cd /d
            foreach ($n in (ConvertTo-CheckPath -Text $v)) { if ($script:Bases -notcontains $n) { $script:Bases += $n } }
        }
    }
}

# ----- 2. Hard blocks (obfuscation / nested eval) --------------------
# -EncodedCommand in any accepted spelling (-e, -ec, -en, -enc ... and /enc), quoted or not
if ($DecodedCommand -match '(?i)\b(powershell|pwsh)(\.exe)?\b[^;|&\r\n]*?(?<![\w-])[-/]e(c|n|nc|nco|ncod|ncode|ncoded|ncodedc[a-z]*)?[\s,"'']+[A-Za-z0-9+/=]{8,}') {
    Set-Block 6 'encoded command (-EncodedCommand) is not allowed.'
}
foreach ($rec in $script:Cmds) {
    if ($rec.Info.Name -eq 'Invoke-Expression') { Set-Block 6 'nested Invoke-Expression is not allowed.' }
}
Stop-IfBlocked

# ----- 3. Delete protection ------------------------------------------
$RemoveItemValue = 'Path', 'LiteralPath', 'Filter', 'Include', 'Exclude', 'Credential', 'Stream'
$RemoveItemSwitch = 'Recurse', 'Force', 'UseTransaction'
$GetChildValue = 'Path', 'LiteralPath', 'Filter', 'Include', 'Exclude', 'Depth', 'Attributes', 'Credential', 'Stream'
$GetChildSwitch = 'Recurse', 'Force', 'Name', 'Directory', 'File', 'Hidden', 'ReadOnly', 'System', 'FollowSymlink', 'UseTransaction'
$PathAliases = @{ PSPath = 'LiteralPath'; LP = 'LiteralPath'; s = 'Recurse'; ad = 'Directory'; af = 'File'; h = 'Hidden'; ar = 'ReadOnly'; as = 'System' }

function Get-SourcePatterns {
    # For "Get-ChildItem <path> | Remove-Item": returns the path patterns the delete can reach,
    # or $null when the source is not a Get-ChildItem / Get-Item / literal list this script can read.
    param($Source)
    if ($Source -is [System.Management.Automation.Language.CommandExpressionAst]) {
        $lit = Get-Literal $Source.Expression
        if ($lit.Dynamic -or @($lit.Values).Count -eq 0) { return $null }
        return @($lit.Values)
    }
    if ($Source -isnot [System.Management.Automation.Language.CommandAst]) { return $null }
    $name = (Get-AstCmdInfo $Source).Name
    if ($name -notin 'Get-ChildItem', 'Get-Item') { return $null }
    $b = Get-BoundArgs $Source $GetChildValue $GetChildSwitch $PathAliases
    $pathAsts = @($b['Path']) + @($b['LiteralPath']) | Where-Object { $_ }
    $pos = @($b['_pos'].ToArray())
    $filterAsts = @($b['Filter']) | Where-Object { $_ }
    if ($pos.Count -ge 1 -and @($pathAsts).Count -eq 0) { $pathAsts = @($pos[0]); if ($pos.Count -ge 2) { $filterAsts = @($filterAsts) + @($pos[1]) } }
    elseif ($pos.Count -ge 1) { $filterAsts = @($filterAsts) + @($pos[0]) }
    $paths = @()
    foreach ($a in $pathAsts) { $lit = Get-Literal $a; if ($lit.Dynamic) { return $null }; $paths += @($lit.Values) }
    if ($paths.Count -eq 0) { $paths = @('.') }
    if ($name -eq 'Get-Item') { return $paths }
    $leaf = '*'
    if (@($filterAsts).Count -ge 1) { $lit = Get-Literal $filterAsts[0]; if (-not $lit.Dynamic -and @($lit.Values).Count -eq 1 -and $lit.Values[0]) { $leaf = $lit.Values[0] } }
    $recurse = $b.ContainsKey('Recurse') -or $b.ContainsKey('Depth')
    $out = @()
    foreach ($p in $paths) {
        $root = $p.TrimEnd('\', '/')
        if ($root -match '^[A-Za-z]:$' -or $root -eq '') { $root = $p.TrimEnd('\', '/') }
        $out += ($root + '\' + $leaf)
        if ($recurse) { $out += ($root + '\*\' + $leaf) }
        if (($p -split '[\\/]')[-1] -match '[*?\[]') { $out += $p }
    }
    return $out
}

# 3a. PowerShell-native deletes - read path args straight from the AST
foreach ($rec in $script:Cmds) {
    if ($rec.Info.Name -ne 'Remove-Item') { continue }
    $c = $rec.Cmd
    $b = Get-BoundArgs $c $RemoveItemValue $RemoveItemSwitch $PathAliases
    $pathAsts = @(@($b['Path']) + @($b['LiteralPath']) + @($b['_pos'].ToArray()) | Where-Object { $_ })
    $dynamic = $false; $pipeVarOnly = $true
    foreach ($a in $pathAsts) {
        $lit = Get-Literal $a
        if ($lit.Dynamic) {
            $dynamic = $true
            $vars = @($a.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true))
            if ($vars.Count -eq 0) { $pipeVarOnly = $false }
            foreach ($v in $vars) { if ($v.VariablePath.UserPath -notin '_', 'PSItem') { $pipeVarOnly = $false } }
            continue
        }
        foreach ($t in $lit.Values) {
            if (-not $t) { continue }
            if ($script:CdDynamic -and (Test-IsRelative $t)) {
                Set-Block 3 "command deletes the relative path '$t' after a Set-Location whose target this script cannot read."
            }
            $hit = Test-Protected $t
            if ($hit) { Set-PathBlock $hit $t }
        }
    }
    if ($dynamic -or $pathAsts.Count -eq 0) {
        $patterns = $null
        if ($pathAsts.Count -eq 0 -or $pipeVarOnly) {
            $src = Get-PipelineSource $c
            if ($src) { $patterns = Get-SourcePatterns $src }
        }
        if ($patterns) {
            foreach ($t in $patterns) {
                if ($script:CdDynamic -and (Test-IsRelative $t)) {
                    Set-Block 3 "command deletes items piped from the relative path '$t' after a Set-Location whose target this script cannot read."
                }
                $hit = Test-Protected $t
                if ($hit) { Set-PathBlock $hit $t 'deletes items piped from' }
            }
        }
        elseif ($rec.Nested) { $script:NeedWholeScan = $true }
        else {
            Set-Block 3 'Remove-Item with no literal path this script can check (path built from a variable, or piped from something other than Get-ChildItem or Get-Item with a literal path).'
        }
    }
}

# 3b. .NET IO deletes - [IO.File]::Delete(...) / [IO.Directory]::Delete(...)
foreach ($tree in $script:AllAsts) {
    $deletes = $tree.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        ([string]$n.Member.Extent.Text).Trim('"', "'") -match '(?i)^Delete$'
    }, $true)
    foreach ($d in $deletes) {
        if ($d.Expression.ToString() -match '(?i)IO\.(File|Directory)') {
            $lit = @()
            foreach ($a in @($d.Arguments)) {
                $x = Get-Literal $a
                if (-not $x.Dynamic) { $lit += @($x.Values | Where-Object { $_ -and $_ -notmatch '^(True|False)$' }) }
            }
            if ($lit.Count -eq 0) { Set-Block 3 '.NET IO delete with no literal path to check.' }
            foreach ($t in $lit) { $hit = Test-Protected $t; if ($hit) { Set-PathBlock $hit $t } }
        }
        else { $script:NeedWholeScan = $true }       # (Get-Item C:\x).Delete()
    }
}

# 3c. deletes this script cannot bind to one path (inside cmd /c, forfiles, an unparsed string):
#     test every path token in the whole command
if ($script:NeedWholeScan) {
    $found = Find-ProtectedToken $DecodedCommand
    if ($found) { Set-PathBlock $found.Hit $found.Typed 'contains a delete and names' }
}

# 3d. registry deletes (reg.exe) and mirror copies (robocopy /MIR deletes in the destination)
foreach ($rec in $script:Cmds) {
    $c = $rec.Cmd
    if ($rec.Info.Leaf -eq 'reg' -and $c.CommandElements.Count -ge 3) {
        $verb = Get-Literal $c.CommandElements[1]
        if (-not $verb.Dynamic -and $verb.Values[0] -eq 'delete') {
            $key = Get-Literal $c.CommandElements[2]
            if ($key.Dynamic) {
                if (-not $rec.Nested) { Set-Block 3 'reg delete with a key name this script cannot read (built from a variable).' }
            }
            else {
                $hit = Test-Protected $key.Values[0] -RegistryContext
                if ($hit) { Set-PathBlock $hit $key.Values[0] }
            }
        }
    }
    if ($rec.Info.Leaf -eq 'robocopy') {
        $plain = @(); $switches = @()
        for ($i = 1; $i -lt $c.CommandElements.Count; $i++) {
            $x = Get-Literal $c.CommandElements[$i]
            if ($x.Dynamic) { $plain += $null; continue }           # keeps its position; checked below
            foreach ($v in $x.Values) { if ($v -match '^/') { $switches += $v } else { $plain += $v } }
        }
        $mirror = @($switches | Where-Object { $_ -match '(?i)^/(MIR|PURGE)$' }).Count -gt 0
        $move = @($switches | Where-Object { $_ -match '(?i)^/(MOVE|MOV)$' }).Count -gt 0
        $targets = @()
        if ($mirror -and $plain.Count -ge 2) { $targets += , @($plain[1], 'mirrors into (and deletes extra files in)') }
        if ($move -and $plain.Count -ge 1) { $targets += , @($plain[0], 'moves files out of') }
        foreach ($t in $targets) {
            if ($null -eq $t[0]) {
                if (-not $rec.Nested) { Set-Block 3 'robocopy /MIR, /PURGE or /MOVE with a folder this script cannot read (built from a variable).' }
                continue
            }
            $hit = Test-Protected $t[0]
            if ($hit) { Set-PathBlock $hit $t[0] $t[1] }
        }
    }
}

# 3e. high-damage system operations - blocked outright
$NativeHardBlocks = @(
    '(?i)\bformat(\.com)?\s+["'']?[a-z]:',
    '(?i)\bvssadmin(\.exe)?\s+delete\s+shadows',
    '(?i)\bwbadmin(\.exe)?\s+delete',
    '(?i)\bbcdedit(\.exe)?\b.*/(delete|deletevalue)',
    '(?i)\bcipher(\.exe)?\s+/w',
    '(?i)\bdiskpart\b',
    '(?i)\breg(\.exe)?["'']?\s+delete\s+["'']?(\\\\[^\\\s]+\\)?(HKLM|HKEY_LOCAL_MACHINE)\\(SYSTEM|SAM|SECURITY)\b',
    '(?i)\bwmic(\.exe)?\b.*\bshadowcopy\b.*\bdelete\b',
    '(?i)Win32_ShadowCopy.*(Remove-|Delete)|(Remove-|Delete).*Win32_ShadowCopy'
)
$hard = $false
foreach ($h in $NativeHardBlocks) { if ($DecodedCommand -match $h) { $hard = $true } }
foreach ($rec in $script:Cmds) {
    if ($rec.Info.Name -in 'Format-Volume', 'Clear-Disk', 'Remove-Partition', 'Initialize-Disk') { $hard = $true }
}
if ($hard -and $script:BlockCode -ne 5) {
    # keep the v1 order: a hard block is reported before a protected path
    $script:BlockCode = 3
    $script:BlockText = 'command matches a high-damage system operation (disk/boot/registry/shadow-copy).'
}
Stop-IfBlocked

# 3f. power off. A powered-off endpoint cannot be started again from Tanium. A restart is allowed.
#     shutdown /s, /sg, /p, /h (and -s ...), Stop-Computer, and Win32Shutdown / wmic ... shutdown.
$powerOff = $DecodedCommand -match '(?i)\bshutdown(\.exe)?["'']?\s+([^;|&\r\n]*\s)?[/-](s|sg|p|h)\b'
if ($DecodedCommand -match '(?i)\.Win32Shutdown\s*\(|\bwmic(\.exe)?\b.*\bcall\s+(shutdown|win32shutdown)\b') { $powerOff = $true }
foreach ($rec in $script:Cmds) { if ($rec.Info.Name -eq 'Stop-Computer') { $powerOff = $true } }
if ($powerOff) {
    Set-Block 3 'command shuts down, powers off, or hibernates the endpoint. Tanium cannot start it again. Use a restart instead (shutdown /r /t 0 or Restart-Computer -Force).'
}
Stop-IfBlocked

# ----- 4. Security-agent protection ----------------------------------
$AgentVendor = '(?i)crowdstrike|falcon|csagent|cstray|csuninstalltool|cyberark|cybr|tanium'

$agentVerbHit = $false
$AgentVerbAst = @('Stop-Service', 'Remove-Service', 'Suspend-Service', 'Restart-Service', 'Stop-Process',
                  'Invoke-WmiMethod', 'Invoke-CimMethod', 'Remove-WmiObject', 'Remove-CimInstance', 'Uninstall-Package')
$ServiceValue = 'Name', 'DisplayName', 'InputObject', 'Include', 'Exclude', 'StartupType', 'Status', 'Description', 'ComputerName', 'Credential'
$ServiceSwitch = 'Force', 'PassThru', 'NoWait'
$ProcessValue = 'Name', 'Id', 'InputObject'
$serviceTargets = @(); $processTargets = @()

function Get-LiteralList {
    param($Bound, [string[]]$Keys)
    $out = @()
    foreach ($k in $Keys) {
        if (-not $Bound.ContainsKey($k)) { continue }
        foreach ($a in @($Bound[$k].ToArray())) { $x = Get-Literal $a; if (-not $x.Dynamic) { $out += @($x.Values | Where-Object { $_ }) } }
    }
    return $out
}

foreach ($rec in $script:Cmds) {
    $name = $rec.Info.Name; $leaf = $rec.Info.Leaf; $c = $rec.Cmd
    if ($name -in $AgentVerbAst) { $agentVerbHit = $true }
    if ($name -eq 'Set-Service') {
        # Set-Service is a "disable" verb unless it clearly only enables or starts the service
        $b = Get-BoundArgs $c $ServiceValue $ServiceSwitch @{ StartMode = 'StartupType'; SM = 'StartupType'; ST = 'StartupType' }
        $want = @(Get-LiteralList $b @('StartupType', 'Status'))
        $given = 0
        foreach ($k in 'StartupType', 'Status') { if ($b.ContainsKey($k)) { $given += $b[$k].Count } }
        $enableOnly = ($given -gt 0 -and $want.Count -eq $given -and
                       @($want | Where-Object { $_ -notmatch '(?i)^(Automatic|AutomaticDelayedStart|Manual|Running)$' }).Count -eq 0)
        if (-not $enableOnly) { $agentVerbHit = $true }
        $serviceTargets += @(Get-LiteralList $b @('Name', 'DisplayName', '_pos'))
    }
    if ($name -in 'Stop-Service', 'Restart-Service', 'Suspend-Service', 'Remove-Service') {
        $b = Get-BoundArgs $c $ServiceValue $ServiceSwitch @{}
        $names = @(Get-LiteralList $b @('Name', 'DisplayName', '_pos'))
        if ($names.Count -eq 0) {
            $src = Get-PipelineSource $c
            if ($src -is [System.Management.Automation.Language.CommandAst] -and (Get-AstCmdInfo $src).Name -eq 'Get-Service') {
                $names = @(Get-LiteralList (Get-BoundArgs $src $ServiceValue $ServiceSwitch @{}) @('Name', 'DisplayName', '_pos'))
            }
        }
        $serviceTargets += $names
    }
    if ($name -eq 'Stop-Process') {
        $b = Get-BoundArgs $c $ProcessValue @('Force', 'PassThru') @{ ProcessName = 'Name'; PID = 'Id' }
        $names = @(Get-LiteralList $b @('Name', 'Id', '_pos'))
        if ($names.Count -eq 0) {
            $src = Get-PipelineSource $c
            if ($src -is [System.Management.Automation.Language.CommandAst] -and (Get-AstCmdInfo $src).Name -eq 'Get-Process') {
                $names = @(Get-LiteralList (Get-BoundArgs $src $ProcessValue @('FileVersionInfo', 'Module', 'IncludeUserName') @{ ProcessName = 'Name'; PID = 'Id' }) @('Name', 'Id', '_pos'))
            }
        }
        $processTargets += $names
    }
    if ($leaf -in 'taskkill', 'tskill') {
        for ($i = 1; $i -lt $c.CommandElements.Count; $i++) {
            $x = Get-Literal $c.CommandElements[$i]
            if (-not $x.Dynamic) { foreach ($v in $x.Values) { if ($v -and $v -notmatch '^[/-]') { $processTargets += $v } } }
        }
    }
    if ($leaf -in 'net', 'net1', 'sc') {
        $words = @()
        for ($i = 1; $i -lt $c.CommandElements.Count; $i++) { $x = Get-Literal $c.CommandElements[$i]; if (-not $x.Dynamic) { $words += @($x.Values) } }
        for ($i = 0; $i -lt $words.Count - 1; $i++) {
            if ($words[$i] -match '(?i)^(stop|pause|delete|config|failure|sdset)$') { $serviceTargets += $words[$i + 1]; break }
        }
    }
}
$NativeAgentVerb = '(?i)\bnet1?(\.exe)?\s+(stop|pause)\b|\bsc(\.exe)?\s+(\\\\\S+\s+)?(stop|delete|pause|sdset|failure)\b|\btaskkill\b|\btskill\b|\bwmic(\.exe)?\b.*\b(call|delete)\b|\bmsiexec(\.exe)?\b.*[/-](x|uninstall)\b|\w*unins\w*\.exe|(?<![\w\\])[/-]uninstall\b|\.(Kill|Terminate|StopService|PauseService|Uninstall|ChangeStartMode|Delete)\s*\(|\b(Stop-Service|Stop-Process|Restart-Service|Suspend-Service|Remove-Service|Uninstall-Package)\b'
if ($DecodedCommand -match $NativeAgentVerb) { $agentVerbHit = $true }
# sc config is a "disable" verb unless it only sets the service back to automatic start
if ($DecodedCommand -match '(?i)\bsc(\.exe)?\s+(\\\\\S+\s+)?config\b' -and $DecodedCommand -notmatch '(?i)\bstart=\s*(auto|delayed-auto)\b') { $agentVerbHit = $true }

if ($agentVerbHit -and ($DecodedCommand -match $AgentVendor)) {
    Set-Block 5 'command targets a protected security agent (CrowdStrike, Tanium, or CyberArk) with a stop/disable/uninstall action.'
}

# The name typed may not contain a vendor word (a wildcard, a PID, a binary such as vf_agent).
# Look up what it really points at on this computer and test that.
if ($agentVerbHit -and -not $script:BlockCode) {
    foreach ($t in @($serviceTargets | Where-Object { $_ } | Select-Object -Unique)) {
        $svc = @()
        try { $svc += @(Get-Service -Name $t -ErrorAction SilentlyContinue) } catch { }
        try { $svc += @(Get-Service -DisplayName $t -ErrorAction SilentlyContinue) } catch { }
        foreach ($s in $svc) {
            $img = ''
            try { $img = [string](Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)" -Name ImagePath -ErrorAction SilentlyContinue).ImagePath } catch { }
            if ("$($s.Name) | $($s.DisplayName) | $img" -match $AgentVendor) {
                Set-Block 5 "command targets the service '$($s.Name)' (typed as '$t'), which belongs to a protected security agent (CrowdStrike, Tanium, or CyberArk)."
            }
        }
    }
    foreach ($t in @($processTargets | Where-Object { $_ } | Select-Object -Unique)) {
        $procs = @()
        try {
            if ($t -match '^\d+$') { $procs += @(Get-Process -Id ([int]$t) -ErrorAction SilentlyContinue) }
            else { $procs += @(Get-Process -Name ($t -replace '(?i)\.exe$', '') -ErrorAction SilentlyContinue) }
        } catch { }
        foreach ($p in $procs) {
            $path = ''; $company = ''
            try { $path = [string]$p.Path } catch { }
            try { $company = [string]$p.Company } catch { }
            if ("$($p.Name) | $path | $company" -match $AgentVendor) {
                Set-Block 5 "command targets the process '$($p.Name)' (typed as '$t'), which belongs to a protected security agent (CrowdStrike, Tanium, or CyberArk)."
            }
        }
    }
    # msiexec /x {GUID}: look the product code up in both registry views
    if ($DecodedCommand -match '(?i)\bmsiexec(\.exe)?\b.*[/-](x|uninstall)\b') {
        foreach ($m in [regex]::Matches($DecodedCommand, '\{[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}')) {
            foreach ($view in 'Registry64', 'Registry32') {
                try {
                    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view)
                    $k = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + $m.Value)
                    if ($k) {
                        $label = "$($k.GetValue('DisplayName')) | $($k.GetValue('Publisher'))"
                        if ($label -match $AgentVendor) {
                            Set-Block 5 "command uninstalls product $($m.Value) ($($k.GetValue('DisplayName'))), which is a protected security agent (CrowdStrike, Tanium, or CyberArk)."
                        }
                    }
                } catch { }
            }
        }
    }
}
Stop-IfBlocked

# ----- 5. Run ---------------------------------------------------------
if ($Mode -eq 'Audit') {
    Write-Log ('{0,-14}the checks passed. Run mode would run the command.' -f 'WOULD RUN')
    Complete-Run 0 'Summary (Audit, nothing changed): would run=1; blocked=0'
}

Write-Log ('{0,-14}the checks passed. Output follows.' -f 'RUNNING')
$exitCode = 0
$script:RunError = $null
$script:OutTotal = 0
$fileLines = New-Object System.Collections.Generic.List[string]
$global:LASTEXITCODE = 0
# >>> EXECUTE-BEGIN  (test tools swap this block out to build a copy that never runs the command)
try {
    $sb = [scriptblock]::Create($DecodedCommand)
    # The output is formatted here (Out-String), so table output is never lost when the
    # script exits. Write-Host output of the command (stream 6) is included. The inner
    # try/catch lets the output printed before an error reach the log as well.
    # Blank lines are dropped so they do not use up the action log lines.
    & { try { & $sb } catch { $script:RunError = $_ } } 6>&1 |
        ForEach-Object { if ($_ -is [System.Management.Automation.InformationRecord]) { [string]$_.MessageData } else { $_ } } |
        Out-String -Stream -Width 250 |
        ForEach-Object {
            $text = ([string]$_).TrimEnd()
            if ($text -ne '') {
                $script:OutTotal++
                if ($script:OutTotal -le $MaxActionLogOutputLines) { Write-Host $text }
                if ($script:OutTotal -le $MaxFileOutputLines) { $fileLines.Add($text) }
            }
        }
    if ($global:LASTEXITCODE) { $exitCode = [int]$global:LASTEXITCODE }
}
catch {
    $script:RunError = $_
}
# <<< EXECUTE-END
try { if ($fileLines.Count -gt 0) { Add-Content -LiteralPath $LogFile -Value $fileLines -Encoding UTF8 } } catch { }

Write-Log ('Output lines: {0}' -f $script:OutTotal) -FileOnly
if ($script:OutTotal -gt $MaxActionLogOutputLines) {
    Write-Log ('{0,-14}the action log shows the first {1} of {2} output lines. The log file {3} has up to {4}.' -f 'TRUNCATED', $MaxActionLogOutputLines, $script:OutTotal, $LogFile, $MaxFileOutputLines) 'WARN'
}
if ($script:RunError) {
    Write-Log ('{0,-14}the command stopped with an error: {1}' -f 'FAILED', $script:RunError) 'ERROR'
    Complete-Run 1 'Summary (Run): ran=1; failed=1'
}
if ($exitCode -ne 0) {
    Write-Log ('{0,-14}the command returned exit code {1}.' -f 'FAILED', $exitCode) 'ERROR'
    Complete-Run 1 ('Summary (Run): ran=1; failed=1; command exit code={0}' -f $exitCode)
}
Write-Log ('{0,-14}the command returned exit code 0.' -f 'RAN')
Complete-Run 0 'Summary (Run): ran=1; failed=0'
