<#
.SYNOPSIS
    Puts real endpoint names back into a CSV that uses pseudonyms from Pseudonymize-Exports.ps1.

.DESCRIPTION
    Reads the private map file and replaces each pseudonym (for example SRV-EP001) with the
    real endpoint name. By default only the endpoint column is restored. Use -AllColumns to
    also restore pseudonyms that appear inside other columns, such as notes or plan text.

    Masked user profile names (<user>) cannot be restored: that masking is one-way.

.PARAMETER Path
    The pseudonymized CSV to restore, for example a remediation plan built from the shared files.

.PARAMETER MapPath
    The private map file written by Pseudonymize-Exports.ps1.

.PARAMETER OutPath
    Where to write the result. Default: <name>-RealNames.csv next to the input.

.PARAMETER KeyColumns
    Column names that hold the endpoint name. The first one found is used.

.PARAMETER AllColumns
    Also replace pseudonyms found inside every other column.

.EXAMPLE
    .\Restore-RealNames.ps1 -Path "$env:USERPROFILE\Downloads\Remediation-Plan.csv" -MapPath "$env:USERPROFILE\Downloads\Pseudonym-Map.csv"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$MapPath,
    [string]$OutPath,
    [string[]]$KeyColumns = @('Endpoint', 'Computer Name', 'Hostname', 'Host Name'),
    [switch]$AllColumns
)

$ErrorActionPreference = 'Stop'

foreach ($f in @($Path, $MapPath)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "File not found: $f" }
}
$src = (Resolve-Path -LiteralPath $Path).Path
if (-not $OutPath) {
    $OutPath = Join-Path (Split-Path -Parent $src) ('{0}-RealNames.csv' -f [IO.Path]::GetFileNameWithoutExtension($src))
}

$back = @{}   # pseudonym -> real name
foreach ($m in Import-Csv -LiteralPath $MapPath -Encoding UTF8) {
    if (-not $back.ContainsKey($m.Pseudonym)) { $back[$m.Pseudonym] = $m.Endpoint }
}
if ($back.Count -eq 0) { throw "The map file has no entries: $MapPath" }

$rows = @(Import-Csv -LiteralPath $src -Encoding UTF8)
if ($rows.Count -eq 0) { throw "No rows in $src" }
$cols = $rows[0].PSObject.Properties.Name
$key  = $KeyColumns | Where-Object { $cols -contains $_ } | Select-Object -First 1
if (-not $key -and -not $AllColumns) {
    throw "None of these columns found: $($KeyColumns -join ', '). Use -AllColumns or -KeyColumns. Columns: $($cols -join ', ')"
}

$pseudoRegex = $null
if ($AllColumns) {
    $alts = $back.Keys | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape($_) }
    $pseudoRegex = New-Object regex ('(?<![\w-])(' + ($alts -join '|') + ')(?![\w-])')
}
$replacePseudo = { param($m) $back[$m.Groups[1].Value] }

$restored = 0; $unknown = @{}
foreach ($r in $rows) {
    if ($key) {
        $v = "$($r.$key)".Trim()
        if ($back.ContainsKey($v))  { $r.$key = $back[$v]; $restored++ }
        elseif ($v -match '-EP\d+$') { $unknown[$v] = $true }
    }
    if ($AllColumns) {
        foreach ($c in $cols) {
            if ($c -eq $key) { continue }
            $v = $r.$c
            if ($v -is [string] -and $v) {
                $r.$c = $pseudoRegex.Replace($v, [System.Text.RegularExpressions.MatchEvaluator]$replacePseudo)
            }
        }
    }
}

$rows | Export-Csv -LiteralPath $OutPath -NoTypeInformation -Encoding UTF8
Write-Host "Restored $restored endpoint values. Output: $OutPath"
if ($unknown.Count) {
    Write-Warning "$($unknown.Count) pseudonyms are not in the map (was it made with a different map file?): $(($unknown.Keys | Select-Object -First 10) -join ', ')"
}
