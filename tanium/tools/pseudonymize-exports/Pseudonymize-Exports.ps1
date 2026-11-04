<#
.SYNOPSIS
    Replaces endpoint names in CSV exports with stable pseudonyms before the files are shared.

.DESCRIPTION
    Each endpoint name becomes <first N characters>-EP###, numbered per prefix
    (for example SRV-EP001, SRV-EP002, WKS-EP001). One map file is shared by every run,
    so the same machine gets the same pseudonym in every export, today and in later runs.
    That lets the shared files still be joined to each other on the endpoint column.

    The script also:
      - Replaces endpoint names of 4 or more characters that appear inside other columns
        (paths, UNC shares, notes), including their domain suffix.
      - Masks user profile names in every column (C:\Users\<user>, /home/<user>, /Users/<user>).

    The original files are never changed. Output is written next to each input as
    <name>-Pseudonymized.csv. Keep the map file private: it is the only way back to real names.

.PARAMETER Path
    One or more CSV files to pseudonymize.

.PARAMETER MapPath
    The shared map file. Created on the first run and reused after that.
    Default: Pseudonym-Map.csv in the folder of the first input file.

.PARAMETER PrefixLength
    How many characters of the real name to keep. Default 3. Use 0 to keep none.

.PARAMETER KeyColumns
    Column names that hold the endpoint name. The first one found in each file is used.

.EXAMPLE
    .\Pseudonymize-Exports.ps1 -Path "$env:USERPROFILE\Downloads\Findings.csv", "$env:USERPROFILE\Downloads\Processes.csv"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Path,
    [string]$MapPath,
    [ValidateRange(0, 10)][int]$PrefixLength = 3,
    [string[]]$KeyColumns = @('Endpoint', 'Computer Name', 'Hostname', 'Host Name')
)

$ErrorActionPreference = 'Stop'

foreach ($p in $Path) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "File not found: $p" }
}
if (-not $MapPath) { $MapPath = Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $Path[0])) 'Pseudonym-Map.csv' }

# Map key: the short name in lower case (host.example.com and HOST are the same machine).
# IP addresses are kept whole.
function Get-NameKey([string]$name) {
    $n = $name.Trim()
    if ($n -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { $n = $n.Split('.')[0] }
    return $n.ToLowerInvariant()
}

$map   = @{}   # name key -> pseudonym
$count = @{}   # prefix   -> highest number used

if (Test-Path -LiteralPath $MapPath) {
    foreach ($m in Import-Csv -LiteralPath $MapPath -Encoding UTF8) {
        $key = Get-NameKey $m.Endpoint
        if (-not $map.ContainsKey($key)) { $map[$key] = $m.Pseudonym }
        if ($m.Pseudonym -match '^(.*)-EP(\d+)$') {
            if ([int]$Matches[2] -gt [int]$count[$Matches[1]]) { $count[$Matches[1]] = [int]$Matches[2] }
        }
    }
    Write-Host "Loaded $($map.Count) existing pseudonyms from $MapPath"
}

$profilePatterns = @(
    @{ Find = '(?i)([A-Z]:\\Users\\)[^\\\r\n"]+'; Replace = '$1<user>' },
    @{ Find = '(/home/)[^/\r\n"\s]+';            Replace = '$1<user>' },
    @{ Find = '(/Users/)[^/\r\n"\s]+';           Replace = '$1<user>' }
)

foreach ($p in $Path) {
    $src  = (Resolve-Path -LiteralPath $p).Path
    $rows = @(Import-Csv -LiteralPath $src -Encoding UTF8)
    if ($rows.Count -eq 0) { Write-Warning "Skipped $src : no rows"; continue }

    $cols = $rows[0].PSObject.Properties.Name
    $key  = $KeyColumns | Where-Object { $cols -contains $_ } | Select-Object -First 1
    if (-not $key) {
        Write-Warning "Skipped $src : none of these columns found: $($KeyColumns -join ', '). Columns: $($cols -join ', ')"
        continue
    }

    # Pass 1: give every endpoint in this file a pseudonym
    foreach ($r in $rows) {
        $name = "$($r.$key)".Trim()
        if (-not $name) { continue }
        $k = Get-NameKey $name
        if (-not $map.ContainsKey($k)) {
            $prefix = $name.Substring(0, [Math]::Min($PrefixLength, $name.Length)).ToUpperInvariant()
            $count[$prefix] = 1 + [int]$count[$prefix]
            $map[$k] = '{0}-EP{1:D3}' -f $prefix, $count[$prefix]
        }
    }

    # One regex for every known name, longest first, matched as a whole word.
    # Names shorter than 4 characters are skipped here so common words are not replaced.
    $names = $map.Keys | Where-Object { $_.Length -ge 4 } | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape($_) }
    $nameRegex = $null
    if ($names) {
        $nameRegex = New-Object regex ('(?<![\w-])(' + ($names -join '|') + ')(?:\.[\w-]+)*(?![\w-])', 'IgnoreCase')
    }
    $replaceName = { param($m) $map[(Get-NameKey $m.Groups[1].Value)] }

    # Pass 2: replace names everywhere and mask user profiles
    foreach ($r in $rows) {
        $name = "$($r.$key)".Trim()
        if ($name) { $r.$key = $map[(Get-NameKey $name)] }

        foreach ($c in $cols) {
            if ($c -eq $key) { continue }
            $v = $r.$c
            if (-not ($v -is [string]) -or -not $v) { continue }
            foreach ($pp in $profilePatterns) { $v = $v -replace $pp.Find, $pp.Replace }
            if ($nameRegex) { $v = $nameRegex.Replace($v, [System.Text.RegularExpressions.MatchEvaluator]$replaceName) }
            $r.$c = $v
        }
    }

    $out = Join-Path (Split-Path -Parent $src) ('{0}-Pseudonymized.csv' -f [IO.Path]::GetFileNameWithoutExtension($src))
    $rows | Export-Csv -LiteralPath $out -NoTypeInformation -Encoding UTF8
    Write-Host "$src -> $out ($($rows.Count) rows, endpoint column '$key')"
}

$map.GetEnumerator() |
    Sort-Object Value |
    Select-Object @{ n = 'Endpoint'; e = { $_.Name } }, @{ n = 'Pseudonym'; e = { $_.Value } } |
    Export-Csv -LiteralPath $MapPath -NoTypeInformation -Encoding UTF8

Write-Host "$($map.Count) endpoints in the map. Keep this file private: $MapPath"
