# Tanium sensor: Java Last Run (Prefetch)
# Returns one row per Java launcher Prefetch file: Executable|Last Run|Days Ago
# Windows creates one .pf file per executable path and updates it each time that executable runs.

$pfDir = Join-Path $env:SystemRoot 'Prefetch'
$reg   = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'
$mode  = (Get-ItemProperty -Path $reg -Name EnablePrefetcher -ErrorAction SilentlyContinue).EnablePrefetcher

if ($mode -eq 0) { 'Prefetch disabled|N/A|N/A'; exit 0 }
if (-not (Test-Path -LiteralPath $pfDir)) { 'Prefetch folder missing|N/A|N/A'; exit 0 }

$hits = Get-ChildItem -LiteralPath $pfDir -Filter '*.pf' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(JAVA|JAVAW|JAVAWS|JP2LAUNCHER)\.EXE-[0-9A-F]{8}\.pf$' }

if (-not $hits) { 'No Java runs recorded|N/A|N/A'; exit 0 }

$now = Get-Date
foreach ($h in $hits) {
    '{0}|{1}|{2}' -f $h.Name,
        $h.LastWriteTime.ToString('yyyy-MM-dd HH:mm'),
        [int][Math]::Floor(($now - $h.LastWriteTime).TotalDays)
}
