# Tanium sensor: Defender - Computer Status (Windows)
#
# Sensor settings
#   Script type : PowerShell
#   Parameters  : none
#   Result type : Text, split into columns, delimiter |
#   Columns     : Running Mode | Service Enabled | AV Enabled | Real-Time Protection |
#                 Tamper Protected | Platform Version | Signature Version |
#                 Signature Last Updated | Signature Age (Days)
#                 (Platform Version and Signature Version = Version,
#                  Signature Age (Days) = Integer, others = Text)
#
# Status values in the Running Mode column when Defender can't be read:
#   Not Applicable             The WinDefend service does not exist (Defender removed or never installed)
#   Error: Service not running WinDefend exists but is stopped, so Get-MpComputerStatus can't answer
#   Error: Status unavailable  WinDefend is running but Get-MpComputerStatus failed
# Read-only: nothing on the endpoint is changed.

# Run as 64-bit so the Defender module and WMI provider load from System32.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess -and $PSCommandPath) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

$d = '|'

function Write-StatusRow([string]$status) {
    Write-Output ((@($status) + @('N/A') * 8) -join $d)
}

$svc = Get-Service -Name 'WinDefend' -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-StatusRow 'Not Applicable'
    exit 0
}
if ($svc.Status -ne 'Running') {
    Write-StatusRow 'Error: Service not running'
    exit 0
}

try {
    $s = Get-MpComputerStatus -ErrorAction Stop
}
catch {
    Write-StatusRow 'Error: Status unavailable'
    exit 0
}

$sigDate = $null
if ($s.AntivirusSignatureLastUpdated) {
    $sigDate = $s.AntivirusSignatureLastUpdated.ToString('yyyy-MM-dd HH:mm')
}

$raw = @(
    $s.AMRunningMode
    $s.AMServiceEnabled
    $s.AntivirusEnabled
    $s.RealTimeProtectionEnabled
    $s.IsTamperProtected
    $s.AMProductVersion
    $s.AntivirusSignatureVersion
    $sigDate
    $s.AntivirusSignatureAge
)

# Never return a blank column
$fields = foreach ($v in $raw) {
    if ($null -eq $v -or "$v" -eq '') { 'Unknown' } else { ("$v" -replace '[\r\n|]', ' ').Trim() }
}

Write-Output ($fields -join $d)
