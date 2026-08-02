# **<span style="color:#009688;">AD Admin OU — Automated Local Admin Removal via Tanium**

## <span style="color:#009688;">Overview

This solution automatically removes domain accounts from the local Administrators group on all managed endpoints. It consists of two PowerShell scripts and two Tanium packages working together:

| Component | Role |
|---|---|
| `Get-AdminOU.ps1` | Runs on the DC — queries AD, writes `InAdminOU.txt`, uploads it to Tanium, patches Package 2 |
| `Remove-AdminOUUsers.ps1` | Runs on each endpoint via Tanium — reads `InAdminOU.txt` and removes listed accounts from local Administrators |
| **Package 1** | Calls `Get-AdminOU.ps1` on the DC (scheduled or on-demand) |
| **Package 2** | Delivers `InAdminOU.txt` + `Remove-AdminOUUsers.ps1` to endpoints and executes the removal |

---

## <span style="color:#009688;">Prerequisites

### **On the Domain Controller**

- PowerShell 5.1+
- RSAT ActiveDirectory module

Install RSAT if missing:

```powershell
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

Or via DISM (Server OS):

```powershell
Install-WindowsFeature -Name RSAT-AD-PowerShell
```

### **Tanium**

- API service account with permissions to upload files and PATCH packages
- Package 2 (`LabTest - Remove Admin`) already created in the Tanium console before running `Get-AdminOU.ps1` for the first time — note its numeric Package ID

---

## <span style="color:#009688;">Step 1 — Create the Encrypted Token Files

This is a **one-time setup** step run interactively on the runner server. The Tanium API token is encrypted with a portable AES-256 key — unlike DPAPI, this is not bound to a specific user or machine, so the Tanium client service can decrypt it regardless of which account it runs as.

Two files are produced and must live in the same directory as `Get-AdminOU.ps1`:

| File | Purpose |
|---|---|
| `data_restore.txt` | 32-byte AES key — used to encrypt and decrypt the token |
| `data.txt` | AES-encrypted Tanium API token |

### **Generate the key and encrypt the token**

```powershell
# Step 1: Generate a 32-byte AES key and save it
$Key = New-Object Byte[] 32
[Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($Key)
$Key | Out-File data_restore.txt

# Step 2: Enter the Tanium API token securely (no plaintext on screen)
$SecureToken = Read-Host "Enter Tanium API Token" -AsSecureString

# Step 3: Encrypt the token with the key and save it
$SecureToken | ConvertFrom-SecureString -Key $Key | Out-File data.txt
```

!!! info
    `Out-File` writes each byte as a text line. The script reads them back with an explicit `[byte[]]` cast via `ForEach-Object { [byte]$_ }` to ensure the key is exactly 32 bytes when passed to `ConvertTo-SecureString`. Do not use `Set-Content -Encoding Byte` or `WriteAllBytes` for the key — the script expects the `Out-File` text format.

Verify both files were created:

```powershell
Test-Path data_restore.txt   # Returns: True
Test-Path data.txt           # Returns: True
```

!!! tip
    To get your Tanium API token, go to **Tanium Console → Administration → API Tokens → New API Token**. Copy the token value immediately — it is only shown once.

!!! warning
    Keep `data_restore.txt` and `data.txt` together — the token cannot be decrypted without the key. Back up both files securely. Anyone with both files can decrypt the token, so restrict filesystem access to this directory accordingly.

---

## <span style="color:#009688;">Step 2 — Configure Get-AdminOU.ps1

Edit the config block at the top of the script to match your environment:

```powershell
# On-premise Tanium server — format: https://<tanium-server-hostname-or-ip>
$TaniumUrl    = 'https://tanium.yourdomain.local'   # Replace with your Tanium server hostname or IP
$Package2Id   = 698130                              # Numeric ID of Package 2
$Package2Name = 'Local Admin Removal - TEST'        # Display name of Package 2

$AdminOUs = @(
    'OU=Users,DC=company,DC=local'
    # Add more OUs as needed:
    # 'OU=ServiceAccounts,OU=Users,DC=company,DC=local',
    # 'OU=PrivilegedUsers,DC=company,DC=local'
    # 'OU=ServiceAccounts,OU=Accounts,DC=yourdomain,DC=local'
)

# SSL toggle — set $true for self-signed or internal CA certificates (on-premise default)
# Set $false when a trusted public certificate is in place
$BypassSslErrors = $true
if ($BypassSslErrors) {
    [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}
```

### **Tanium URL format (on-premise)**

On-premise Tanium is reached directly by hostname or IP — not via a cloud subdomain:

| Environment | Example URL |
|---|---|
| Hostname | `https://tanium.yourdomain.local` |
| IP address | `https://192.168.1.50` |
| Cloud (Tanium-as-a-Service) | `https://company-api.cloud.tanium.com` |

### **SSL toggle**

The `$BypassSslErrors` flag controls whether the script validates the Tanium server certificate:

| Value | When to use |
|---|---|
| `$true` | On-premise with self-signed or internal CA certificate (most common) |
| `$false` | Certificate issued by a trusted public CA |

### **Token files**

Ensure `data.txt` and `data_restore.txt` are in the same directory as the script before running. The script resolves them via `$PSScriptRoot` — no hardcoded paths needed.

---

## <span style="color:#009688;">Step 3 — Get-AdminOU.ps1 (Full Script)

Save this as `Get-AdminOU.ps1` in the same directory as `data.txt` and `data_restore.txt`.

```powershell
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Queries Active Directory for user accounts in defined Admin OUs, writes the
    results to UsersInOU.txt, then uploads that file to an on-premise Tanium server
    and patches a target package so all managed endpoints receive the updated list.
 
.DESCRIPTION
    Phase 1 - Queries each OU defined in $AdminOUs via Get-ADUser and writes a
              single-column UTF-8 file (SamAccountName) with no BOM.
    Phase 2 - Decrypts the Tanium API token stored in data.txt using the AES key
              in data_restore.txt and validates it against the Tanium REST API.
    Phase 3 - Uploads UsersInOU.txt to Tanium via the streaming upload endpoint.
    Phase 4 - PATCHes the target package (Package 2) to attach the new file,
              leaving the package command and all other settings untouched.
 
.PARAMETER
    None — all configuration is in the config block below.
 
.NOTES
    Prerequisites:
      - PowerShell 5.1+
      - RSAT ActiveDirectory module (Install-WindowsFeature RSAT-AD-PowerShell)
      - Tanium client with access to the Tanium server defined in $TaniumUrl
      - data_restore.txt and data.txt generated once via:
            $Key = New-Object Byte[] 32
            [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($Key)
            $Key | Out-File data_restore.txt
            $SecureToken = Read-Host "Enter Tanium API Token" -AsSecureString
            $SecureToken | ConvertFrom-SecureString -Key $Key | Out-File data.txt
 
    All three files (Get-AdminOU.ps1, data_restore.txt, data.txt) must live
    in the same directory. UsersInOU.txt and Get-AdminOU.log are written there too.
 
    SSL: set $BypassSslErrors = $true for self-signed or internal CA certificates.
         Set $false when a trusted public certificate is in place.
 
.EXAMPLE
    # Run directly
    .\Get-AdminOU.ps1
 
    # Called by Tanium Package 1 (on-premise runner server)
    cmd.exe /d /c %SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe
        -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile
        -File "F:\path\to\scripts\Get-AdminOU.ps1"
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Config
$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    Write-Warning "Script path unavailable - falling back to working directory. Save the script before running."
    (Get-Location).Path
}

$outputFile   = Join-Path $ScriptDir 'UsersInOU.txt'
$logFile      = Join-Path $ScriptDir 'Get-AdminOU.log'

#Token files
$keyFile      = Join-Path $ScriptDir 'data_restore.txt'
$tokenFile    = Join-Path $ScriptDir 'data.txt'

# On-premise Tanium server — format: https://<tanium-server-hostname-or-ip>
$TaniumUrl    = 'https://tanium.yourdomain.local'
$Package2Id   = 858174
$Package2Name = 'Local Admin Removal - TEST'

# SSL toggle — set $true if Tanium uses a self-signed or internal CA certificate
# Set $false when a trusted public certificate is in place
$BypassSslErrors = $true
if ($BypassSslErrors) {
    [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}

$AdminOUs = @(
        'OU=Users,DC=company,DC=local'
    # Add OUs here once they exist in AD:
    # 'OU=ServiceAccounts,OU=Users,DC=company,DC=local',
    # 'OU=PrivilegedUsers,DC=company,DC=local'
)

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Host $line
}

# Phase 1: Query AD and write UsersInOU.txt
try {
    Write-Log "== Phase 1: AD Query =="

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($ou in $AdminOUs) {
        Write-Log "Querying: $ou"
        try {
            $users = Get-ADUser -SearchBase $ou -Filter * -SearchScope Subtree `
                -Properties SamAccountName, DisplayName, EmailAddress, DistinguishedName, Enabled, PasswordLastSet, LastLogonDate

            foreach ($u in $users) {
                $results.Add($u)
            }

            Write-Log "Found $($users.Count) accounts"
        }
        catch {
            Write-Log "WARNING: Could not query $ou: $_" -Level 'WARN'
        }
    }

    if ($results.Count -eq 0) {
        Write-Log "No accounts found - aborting to avoid pushing empty file" -Level 'ERROR'
        exit 1
    }

    $header = 'SamAccountName'
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($header)

    foreach ($r in $results) {
        $lines.Add($r.SamAccountName)
    }

    $enc = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($outputFile, $lines, $enc)

    Write-Log "Wrote $($results.Count) accounts to $outputFile"
}
catch {
    Write-Log "Phase 1 failed: $_" -Level 'ERROR'
    exit 1
}

# Phase 2: Authenticate to Tanium (API token only)
try {
    Write-Log "== Phase 2: Tanium Authentication (API Token) =="

    # Read key - Out-File writes each byte as a text line; cast explicitly back to [byte[]]
    $key    = [byte[]](Get-Content $keyFile | ForEach-Object { [byte]$_ })
    $secure = Get-Content $tokenFile | ConvertTo-SecureString -Key $key
    $key    = $null   # zero out key from memory

    $bstr  = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    $headers = @{ session = $token }

    # Validate token against Tanium before proceeding
    $null = Invoke-RestMethod `
        -Uri     "$TaniumUrl/api/v2/session/current" `
        -Method  GET `
        -Headers $headers

    $token = $null   # zero out immediately after validation
    Write-Log "Authenticated using API token"
}
catch {
    Write-Log "Phase 2 failed: $_" -Level 'ERROR'
    exit 1
}

# Phase 3: Upload UsersInOU.txt
try {
    Write-Log "== Phase 3: Upload UsersInOU.txt =="

    $fileBytes = [System.IO.File]::ReadAllBytes($outputFile)

    $uploadResp = Invoke-RestMethod `
        -Uri         "$TaniumUrl/api/v2/upload_file_stream" `
        -Method      POST `
        -Headers     $headers `
        -Body        $fileBytes `
        -ContentType 'application/octet-stream'

    $newHash = $uploadResp.data.hash
    Write-Log "Uploaded $($fileBytes.Length) bytes - hash: $newHash"
}
catch {
    Write-Log "Phase 3 failed: $_" -Level 'ERROR'
    exit 1
}

# Phase 4: Update Package 2
try {
    Write-Log "== Phase 4: Patch Package 2 (id $Package2Id) =="

    $pkgResp = Invoke-RestMethod `
        -Uri     "$TaniumUrl/api/v2/packages/$Package2Id" `
        -Method  GET `
        -Headers $headers

    $keptFiles = @(
        $pkgResp.data.files |
            Where-Object { $_.name -and $_.name -ne 'UsersInOU.txt' } |
            ForEach-Object { @{ id = $_.id; name = $_.name; size = $_.size; hash = $_.hash } }
    )

    $updatedFiles = $keptFiles + @{ hash = $newHash; name = 'UsersInOU.txt'; size = $fileBytes.Length }

    $patchBody = @{
        files = $updatedFiles
    } | ConvertTo-Json -Depth 5 -Compress

    $patchResp = Invoke-RestMethod `
        -Uri         "$TaniumUrl/api/v2/packages/$Package2Id" `
        -Method      PATCH `
        -Headers     $headers `
        -Body        $patchBody `
        -ContentType 'application/json'

    Write-Log "Package 2 patched - modified: $($patchResp.data.modification_time)"
}
catch {
    Write-Log "Phase 4 failed: $_" -Level 'ERROR'
    exit 1
}

# Done
Write-Log "== All phases complete =="
exit 0
```

### **Expected output**

```
[INFO] === Phase 1: AD Query ===
[INFO] Querying: OU=Users,DC=company,DC=local
[INFO]   Found 19 accounts
[INFO] Wrote 19 accounts to F:\...\InAdminOU.txt
[INFO] === Phase 2: Tanium Authentication ===
[INFO] Authenticated - token accepted
[INFO] === Phase 3: Upload InAdminOU.txt ===
[INFO] Uploaded 2212 bytes - hash: 12c8eb0f...
[INFO] === Phase 4: Patch Package 2 (id 148603) ===
[INFO] Package 2 patched - modified: 2026-05-28T18:57:52Z
[INFO] Session logged out
[INFO] === All phases complete ===
```

---

## <span style="color:#009688;">Step 4 — Create Tanium Package 1 (AD Query Package)

This package runs `Get-AdminOU.ps1` on the designated runner server — this does not have to be the Domain Controller, just any domain-joined server with RSAT installed and the Tanium client running.

### **Directory layout on the runner server**

All three files live at a fixed path on the runner server. `F:\` represents the volume on that server. Nothing is uploaded to Tanium — the package is a trigger only:

```
F:\path\to\scripts\
    ├── Get-AdminOU.ps1       ← pre-existing on the server, referenced by the command
    ├── data_restore.txt      ← AES key, generated once in Step 1
    ├── data.txt              ← AES-encrypted Tanium API token, generated once in Step 1
    └── InAdminOU.txt         ← written by the script on each run
```

### **Package settings**

In the Tanium console, go to **Content → Packages → New Package**:

| Field | Value |
|---|---|
| Package Name | `AD - Query Admin OU Users` |
| Command | `cmd.exe /d /c %SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File "F:\path\to\scripts\Get-AdminOU.ps1"` |
| Command Timeout | `90 minutes` |
| Files | *(none — all files are pre-existing on the runner server)* |

Replace `F:\path\to\scripts\` with the actual path on your runner server.

Because `$PSScriptRoot` in the script resolves to `F:\path\to\scripts\`, both `data.txt` and `data_restore.txt` are automatically found in the same directory alongside `InAdminOU.txt` — no hardcoded paths needed inside the script.

!!! warning
    `data_restore.txt` and `data.txt` must both be present in the same directory as `Get-AdminOU.ps1` before the package runs. If either file is missing, Phase 2 will fail. Restrict filesystem permissions on this directory — anyone with both files can decrypt the token.

!!! note
    Target Package 1 only at the designated runner server using a Tanium targeting filter on computer name or subnet — not at all endpoints.

---

## <span style="color:#009688;">Step 5 — Create Tanium Package 2 (Enforcement Package)

This package delivers `InAdminOU.txt` to endpoints and runs the removal.

In the Tanium console, go to **Content → Packages → New Package**:

| Field | Value |
|---|---|
| Package Name | `LabTest - Remove Admin` |
| Command | `/d /c %SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Remove-AdminOUUsers.ps1 0` |
| Command Timeout | `1 minute` |
| Download Timeout | `10 minutes` |
| Files | Upload `Remove-AdminOUUsers.ps1` — `InAdminOU.txt` is injected automatically by `Get-AdminOU.ps1` |

Note the **Package ID** (visible in the URL when editing the package) and set `$Package2Id` in `Get-AdminOU.ps1` accordingly.

### **Audit mode**

To run in audit mode (no changes, just logs what would be removed), change the trailing `0` to `1` in the command:

```
... -File Remove-AdminOUUsers.ps1 1
```

---

## <span style="color:#009688;">Step 6 — Remove-AdminOUUsers.ps1 (Full Script)

This script is delivered by Tanium to each endpoint alongside `InAdminOU.txt`.

```powershell
<#
.SYNOPSIS
    Reads InAdminOU.txt (delivered by Tanium alongside this script),
    removes each listed account from the local Administrators group.

.PARAMETER Mode
    0 = Enforce  - actually removes accounts
    1 = Audit    - reports what would be removed, no changes made
#>

[CmdletBinding()]
param(
    [int]$Mode = 0
)

$ErrorActionPreference = 'Stop'

$WorkDir   = if ($PSScriptRoot) {
               $PSScriptRoot
           } elseif ($MyInvocation.MyCommand.Path) {
               Split-Path -Parent $MyInvocation.MyCommand.Path
           } else {
               (Get-Location).Path
           }
$InputFile = Join-Path $WorkDir 'InAdminOU.txt'
$LogFile   = Join-Path $env:'C:\Temp\Remove-AdminOUUsers.log'

$null = New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force -ErrorAction SilentlyContinue

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $ts   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts] [$Level] [$env:COMPUTERNAME] [Mode=$Mode] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

try {
    Write-Log "Starting - InAdminOU.txt: $InputFile"

    if (-not (Test-Path $InputFile)) {
        Write-Log "InAdminOU.txt not found at $InputFile" -Level 'ERROR'
        exit 1
    }

    # Supports single-column (SamAccountName only) and multi-column pipe-delimited formats
    $lines          = Get-Content $InputFile -Encoding UTF8
    $header         = $lines[0] -split '\|'
    $isSingleColumn = ($header.Count -eq 1)

    $records = foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($isSingleColumn) {
            [PSCustomObject]@{ SamAccountName = $line.Trim() }
        } else {
            $fields = $line -split '\|'
            $obj = [ordered]@{}
            for ($i = 0; $i -lt $header.Count; $i++) {
                $obj[$header[$i]] = if ($i -lt $fields.Count) { $fields[$i] } else { '' }
            }
            [PSCustomObject]$obj
        }
    }

    Write-Log "Parsed $($records.Count) accounts from InAdminOU.txt"

    $localAdminGroup = [ADSI]"WinNT://./Administrators,group"
    $currentMembers  = @(
        $localAdminGroup.psbase.Invoke("Members") | ForEach-Object {
            $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)
        }
    )

    Write-Log "Current local Administrators ($($currentMembers.Count) members): $($currentMembers -join ', ')"

    # Safety: abort if removal would leave 0 admins; warn if only 1 would remain
    $adminCount    = $currentMembers.Count
    $toRemoveCount = ($records | Where-Object {
        $sam = $_.SamAccountName
        $currentMembers | Where-Object { $_ -eq $sam -or $_ -match "\\$sam$" }
    }).Count

    if (($adminCount - $toRemoveCount) -lt 1) {
        Write-Log "Removal would leave 0 local Administrators - aborting for safety" -Level 'ERROR'
        exit 1
    }
    if (($adminCount - $toRemoveCount) -lt 2) {
        Write-Log "WARNING: Only 1 Administrator will remain after removal" -Level 'WARN'
    }

    $removed  = [System.Collections.Generic.List[string]]::new()
    $notFound = [System.Collections.Generic.List[string]]::new()
    $skipped  = [System.Collections.Generic.List[string]]::new()

    foreach ($r in $records) {
        $sam   = $r.SamAccountName
        $match = $currentMembers | Where-Object { $_ -eq $sam -or $_ -match "\\$sam$" }

        if (-not $match) {
            $notFound.Add($sam)
            continue
        }

        if ($sam -match '^Administrator$') {
            Write-Log "Skipping built-in Administrator account" -Level 'WARN'
            $skipped.Add($sam)
            continue
        }

        if ($Mode -eq 1) {
            Write-Log "[AUDIT] Would remove: $sam"
            $removed.Add($sam)
        }
        else {
            try {
                $localAdminGroup.Remove("WinNT://$sam")
                Write-Log "Removed $sam from local Administrators"
                $removed.Add($sam)
            }
            catch {
                try {
                    $domain = (Get-WmiObject Win32_ComputerSystem).Domain.Split('.')[0]
                    $localAdminGroup.Remove("WinNT://$domain/$sam")
                    Write-Log "Removed $domain\$sam from local Administrators"
                    $removed.Add($sam)
                }
                catch {
                    Write-Log "Failed to remove ${sam}: $_" -Level 'WARN'
                }
            }
        }
    }

    Write-Log "--- Summary ---"
    Write-Log "Removed   : $($removed.Count) - $($removed -join ', ')"
    Write-Log "Not found : $($notFound.Count) - $($notFound -join ', ')"
    Write-Log "Skipped   : $($skipped.Count) - $($skipped -join ', ')"

    if ($Mode -eq 1) { Write-Log "Audit complete - no changes made" }
    else             { Write-Log "Enforcement complete" }

    exit 0
}
catch {
    Write-Log "Fatal: $_" -Level 'ERROR'
    exit 1
}
```

---

## <span style="color:#009688;">Step 7 — Run the Full Flow

### **Manual run (testing)**

Run `Get-AdminOU.ps1` from PowerShell on the DC:

```powershell
C:\path\to\scripts\Get-AdminOU.ps1
```

Then deploy Package 2 from the Tanium console to your target endpoints.

### **Automated (scheduled)**

Create a Windows Scheduled Task on the DC to call `Get-AdminOU.ps1` on your desired cadence (e.g. daily at 02:00), then trigger Package 2 deployment via a Tanium Scheduled Action targeting all managed Windows endpoints.

---

## <span style="color:#009688;">Log Locations

| Log | Location |
|---|---|
| AD query + upload | Same directory as `Get-AdminOU.ps1` → `Get-AdminOU.log` |
| Endpoint removal | `C:\Temp\Remove-AdminOUUsers.log` on each endpoint |

### **Sample endpoint log**

```
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Starting - InAdminOU.txt: C:\...\InAdminOU.txt
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Parsed 19 accounts from InAdminOU.txt
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Current local Administrators (3 members): Administrator, jsmith, bjones
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Removed COMPANY\jsmith from local Administrators
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Removed COMPANY\bjones from local Administrators
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] --- Summary ---
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Removed   : 2 - jsmith, bjones
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Not found : 17 - ...
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Skipped   : 0 -
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Enforcement complete
```

---

## <span style="color:#009688;">Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Cannot bind argument to parameter 'Path' because it is null` | Script run from unsaved ISE buffer | Save the `.ps1` file to disk before running |
| `ScriptRequiresMissingModules: ActiveDirectory` | RSAT not installed | Run `Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0` |
| `Could not establish trust relationship for SSL/TLS` | Tanium uses a self-signed or internal CA cert | Set `$BypassSslErrors = $true` in the config block; use the server FQDN rather than IP where possible |
| `{"text":"Forbidden"}` on login | Invalid or expired API token | Regenerate the token in Tanium console and re-run Step 1 setup commands |
| `Cannot find path 'data.txt'` | Token files missing from script directory | Run the Step 1 setup commands on the runner server |
| `File Name` blank entry appears in package | File uploaded without a `name` field in a previous run | Manually delete the blank entry in Tanium; fixed in current script version |
| `InAdminOU.txt not found` on endpoint | Package 2 deployed before `Get-AdminOU.ps1` ran | Run Package 1 first, confirm upload success, then deploy Package 2 |
| `Removal would leave 0 local Administrators` | All local admins are in the OU list | Review `InAdminOU.txt` — ensure at least one permanent admin is excluded |