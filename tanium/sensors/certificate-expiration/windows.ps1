# Tanium sensor: Certificate Expiration (Windows)
#
# Sensor settings
#   Script type : PowerShell
#   Parameters  : none
#   Result type : Text, split into columns, delimiter |
#   Columns     : Subject | Issuer | Expiration Date | Days Left | Thumbprint | Store or Path
#                 (Days Left = Integer, Expiration Date = Date/Time (RFC822), others = Text)
#
# Reads the LocalMachine stores that hold the machine's own certificates.
# Trust stores (Root, AuthRoot, CA, Disallowed) are skipped on purpose: they hold
# hundreds of Microsoft-managed certificates, some of them expired by design.
# Also skipped: MS-Organization-P2P-Access certificates. Windows issues these with a
# one-day lifetime and renews them automatically, so they would always show as expiring.
# Read-only: every store is opened with ReadOnly and OpenExistingOnly.

$stores     = 'My', 'WebHosting', 'Remote Desktop', 'SMS', 'WindowsServerUpdateServices'
$skipIssuer = 'CN=MS-Organization-P2P-Access*'

$flags       = [Security.Cryptography.X509Certificates.OpenFlags]'ReadOnly, OpenExistingOnly'
$notFound    = -2147024894   # 0x80070002, store does not exist on this machine
$now         = [DateTime]::UtcNow
$rows        = New-Object 'System.Collections.Generic.List[object]'
$errors      = New-Object 'System.Collections.Generic.List[string]'

function Clean([string]$text) {
    if ($text) { $text.Replace('|', '/').Trim() } else { '' }
}

# Some certificates (domain controller Kerberos certificates, for example) have an empty
# Subject and carry the name only in the Subject Alternative Name.
function Get-SubjectText($cert) {
    $subject = Clean $cert.Subject
    if ($subject) { return $subject }
    $dns = Clean (Get-FirstDnsName $cert)
    if ($dns) { "SAN: $dns" } else { '(no subject)' }
}

# First DNS name in the Subject Alternative Name, read from the raw extension bytes.
# Other entry types (such as a domain controller's DS Object GUID) are skipped, and
# nothing depends on the localized text Windows uses to display the extension.
function Get-FirstDnsName($cert) {
    $ext = $cert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' } | Select-Object -First 1
    if (-not $ext) { return '' }
    try {
        $b = $ext.RawData
        $i = 2
        if ($b[1] -band 0x80) { $i += $b[1] -band 0x7F }
        while ($i -lt $b.Length) {
            $tag = $b[$i]
            $len = [int]$b[$i + 1]
            $i += 2
            if ($len -band 0x80) {
                $n = $len -band 0x7F
                $len = 0
                for ($k = 0; $k -lt $n; $k++) { $len = $len * 256 + $b[$i + $k] }
                $i += $n
            }
            if ($tag -eq 0x82) { return [Text.Encoding]::ASCII.GetString($b, $i, $len) }
            $i += $len
        }
    } catch { }
    ''
}

try {
    foreach ($name in $stores) {
        $store = New-Object Security.Cryptography.X509Certificates.X509Store($name, 'LocalMachine')
        try {
            $store.Open($flags)
        } catch {
            $e = $_.Exception
            while ($e.InnerException) { $e = $e.InnerException }
            if ($e.HResult -ne $notFound) { $errors.Add("Error: Cannot open store $name|||||") }
            continue
        }

        try {
            foreach ($c in $store.Certificates) {
                if ($c.Issuer -like $skipIssuer) { continue }
                $end  = $c.NotAfter.ToUniversalTime()
                $days = [int][Math]::Floor(($end - $now).TotalDays)
                $line = '{0}|{1}|{2:yyyy-MM-dd HH:mm:ss}|{3}|{4}|LocalMachine\{5}' -f
                        (Get-SubjectText $c), (Clean $c.Issuer), $end, $days, $c.Thumbprint.ToUpper(), $name
                $rows.Add([pscustomobject]@{ Days = $days; Line = $line })
            }
        } finally {
            $store.Close()
        }
    }
} catch {
    Write-Output 'Error: Unexpected failure|||||'
    exit
}

$rows | Sort-Object Days | ForEach-Object { $_.Line }
$errors | Write-Output

if ($rows.Count -eq 0 -and $errors.Count -eq 0) { Write-Output 'None|||||' }
