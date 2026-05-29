# AD Admin OU — Automated Local Admin Removal via Tanium

## Overview

This solution automatically removes domain accounts from the local Administrators group on all managed endpoints. It consists of two PowerShell scripts and two Tanium packages working together:

| Component | Role |
|---|---|
| `Get-AdminOU.ps1` | Runs on the DC — queries AD, writes `InAdminOU.txt`, uploads it to Tanium, patches Package 2 |
| `Remove-AdminOUUsers.ps1` | Runs on each endpoint via Tanium — reads `InAdminOU.txt` and removes listed accounts from local Administrators |
| **Package 1** | Calls `Get-AdminOU.ps1` on the DC (scheduled or on-demand) |
| **Package 2** | Delivers `InAdminOU.txt` + `Remove-AdminOUUsers.ps1` to endpoints and executes the removal |

---

## Prerequisites

### On the Domain Controller

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

### Tanium

- API service account with permissions to upload files and PATCH packages
- Package 2 (`LabTest - Remove Admin`) already created in the Tanium console before running `Get-AdminOU.ps1` for the first time — note its numeric Package ID

---

## Step 1 — Create the Tanium API Credential File

This is a **one-time setup** step run interactively on the machine that will execute `Get-AdminOU.ps1`. The password is encrypted with DPAPI and is machine- and user-bound — no plaintext is stored.

```powershell
$c = Get-Credential -UserName 'your-tanium-api-user' -Message 'Enter Tanium API password'
$c.Password | ConvertFrom-SecureString |
    Out-File 'C:\path\to\scripts\tanium_api_cred.bin'
```

Verify it was created:

```powershell
Test-Path 'C:\path\to\scripts\tanium_api_cred.bin'
# Returns: True
```

!!! warning
    The `.bin` file must be created by the same Windows user account that will run `Get-AdminOU.ps1`. DPAPI encryption is tied to the user and machine — copying the file to another machine or running as a different user will fail to decrypt.

---

## Step 2 — Configure Get-AdminOU.ps1

Edit the config block at the top of the script to match your environment:

```powershell
$TaniumUrl    = 'https://tanium.yourdomain.com'   # Your Tanium URL
$TaniumUser   = 'api-service-account'             # Tanium API username
$Package2Id   = 148603                            # Numeric ID of Package 2
$Package2Name = 'LabTest - Remove Admin'          # Display name of Package 2

$AdminOUs = @(
    'OU=KBSUsers,DC=yourdomain,DC=local'
    # Add more OUs as needed:
    # 'OU=ServiceAccounts,OU=KBSUsers,DC=yourdomain,DC=local',
    # 'OU=PrivilegedUsers,DC=yourdomain,DC=local'
)
```

### SSL bypass (lab environments)

If your Tanium server uses a self-signed or internal CA certificate, set this flag at the top of the script:

```powershell
$BypassSslErrors = $true   # Set $false in production with a trusted cert
```

---

## Step 3 — Get-AdminOU.ps1 (Full Script)

Save this as `Get-AdminOU.ps1` in the same directory as `tanium_api_cred.bin`.

```powershell
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    1. Queries AD for all user accounts in admin OUs
    2. Writes InAdminOU.txt to the same directory
    3. Authenticates to Tanium via API
    4. Uploads InAdminOU.txt via streaming upload
    5. PATCHes Package 2 so all endpoints get the fresh file

.NOTES
    Credential pre-seeded as DPAPI SecureString (machine-bound, no plaintext).
    To generate once (run interactively on this machine):
        $c = Get-Credential
        $c.Password | ConvertFrom-SecureString |
            Out-File 'C:\path\to\scripts\tanium_api_cred.bin'
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Lab SSL bypass - set $true if Tanium certificate is self-signed or from an internal CA.
# Set $false (or remove) once a trusted certificate is in place.
$BypassSslErrors = $true
if ($BypassSslErrors) {
    [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}

# --- Config ---------------------------------------------------------------
$ScriptDir   = if ($PSScriptRoot) {
                   $PSScriptRoot
               } elseif ($MyInvocation.MyCommand.Path) {
                   Split-Path -Parent $MyInvocation.MyCommand.Path
               } else {
                   Write-Warning "Script path unavailable - falling back to working directory. Save the script before running."
                   (Get-Location).Path
               }
$OutputFile  = Join-Path $ScriptDir 'InAdminOU.txt'
$LogFile     = Join-Path $ScriptDir 'Get-AdminOU.log'
$CredFile    = Join-Path $ScriptDir 'tanium_api_cred.bin'

$TaniumUrl    = 'https://tanium.yourdomain.com'
$TaniumUser   = 'api-service-account'
$Package2Id   = 148603
$Package2Name = 'LabTest - Remove Admin'

$AdminOUs = @(
    'OU=KBSUsers,DC=yourdomain,DC=local'
    # 'OU=ServiceAccounts,OU=KBSUsers,DC=yourdomain,DC=local',
    # 'OU=PrivilegedUsers,DC=yourdomain,DC=local'
)

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

# --- PHASE 1: Query AD and write InAdminOU.txt ----------------------------
try {
    Write-Log "=== Phase 1: AD Query ==="

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($ou in $AdminOUs) {
        Write-Log "Querying: $ou"
        try {
            $users = Get-ADUser -SearchBase $ou -Filter * -SearchScope Subtree `
                -Properties SamAccountName, DisplayName, EmailAddress, `
                            DistinguishedName, Enabled, PasswordLastSet, LastLogonDate

            foreach ($u in $users) { $results.Add($u) }
            Write-Log "  Found $($users.Count) accounts"
        }
        catch {
            Write-Log "WARNING: Could not query '$ou': $_" -Level 'WARN'
        }
    }

    if ($results.Count -eq 0) {
        Write-Log "No accounts found - aborting to avoid pushing empty file" -Level 'ERROR'
        exit 1
    }

    $header = 'SamAccountName'
    $lines  = [System.Collections.Generic.List[string]]::new()
    $lines.Add($header)

    foreach ($r in $results) {
        $lines.Add($r.SamAccountName)
    }

    $enc = [System.Text.UTF8Encoding]::new($false)   # UTF-8 no BOM
    [System.IO.File]::WriteAllLines($OutputFile, $lines, $enc)
    Write-Log "Wrote $($results.Count) accounts to $OutputFile"
}
catch {
    Write-Log "Phase 1 failed: $_" -Level 'ERROR'
    exit 1
}

# --- PHASE 2: Authenticate to Tanium --------------------------------------
try {
    Write-Log "=== Phase 2: Tanium Authentication ==="

    $secPwd   = Get-Content $CredFile | ConvertTo-SecureString
    $bstr     = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPwd)
    $plainPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    $loginResp = Invoke-RestMethod `
        -Uri         "$TaniumUrl/api/v2/session/login" `
        -Method      POST `
        -Body        (@{ username = $TaniumUser; password = $plainPwd; domain = '' } | ConvertTo-Json -Compress) `
        -ContentType 'application/json'

    $plainPwd = $null
    $session  = $loginResp.data.session
    $headers  = @{ session = $session }
    Write-Log "Authenticated - session acquired"
}
catch {
    Write-Log "Phase 2 failed: $_" -Level 'ERROR'
    exit 1
}

# --- PHASE 3: Upload InAdminOU.txt ----------------------------------------
try {
    Write-Log "=== Phase 3: Upload InAdminOU.txt ==="

    $fileBytes  = [System.IO.File]::ReadAllBytes($OutputFile)

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
    try { Invoke-RestMethod -Uri "$TaniumUrl/api/v2/session/logout" -Method POST -Headers $headers -Body "{}" -ContentType "application/json" | Out-Null } catch {}
    exit 1
}

# --- PHASE 4: PATCH Package 2 ---------------------------------------------
try {
    Write-Log "=== Phase 4: Patch Package 2 (id $Package2Id) ==="

    $pkgResp = Invoke-RestMethod `
        -Uri     "$TaniumUrl/api/v2/packages/$Package2Id" `
        -Method  GET `
        -Headers $headers

    $keptFiles = @(
        $pkgResp.data.files |
            Where-Object { $_.name -and $_.name -ne 'InAdminOU.txt' } |
            ForEach-Object { @{ id = $_.id; name = $_.name } }
    )

    $updatedFiles = $keptFiles + @{ hash = $newHash; name = 'InAdminOU.txt' }

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
    try { Invoke-RestMethod -Uri "$TaniumUrl/api/v2/session/logout" -Method POST -Headers $headers -Body "{}" -ContentType "application/json" | Out-Null } catch {}
    exit 1
}

# --- Done -----------------------------------------------------------------
try { Invoke-RestMethod -Uri "$TaniumUrl/api/v2/session/logout" -Method POST -Headers $headers -Body "{}" -ContentType "application/json" | Out-Null } catch {}
Write-Log "Session logged out"
Write-Log "=== All phases complete ==="
exit 0
```

### Expected output

```
[INFO] === Phase 1: AD Query ===
[INFO] Querying: OU=KBSUsers,DC=yourdomain,DC=local
[INFO]   Found 19 accounts
[INFO] Wrote 19 accounts to C:\...\InAdminOU.txt
[INFO] === Phase 2: Tanium Authentication ===
[INFO] Authenticated - session acquired
[INFO] === Phase 3: Upload InAdminOU.txt ===
[INFO] Uploaded 2212 bytes - hash: 12c8eb0f...
[INFO] === Phase 4: Patch Package 2 (id 148603) ===
[INFO] Package 2 patched - modified: 2026-05-28T18:57:52Z
[INFO] Session logged out
[INFO] === All phases complete ===
```

---

## Step 4 — Create Tanium Package 1 (AD Query Package)

This package runs `Get-AdminOU.ps1` on the designated runner server — this does not have to be the Domain Controller, just any domain-joined server with RSAT installed and the Tanium client running.

### Directory layout on the runner server

All three files live at a fixed path on the runner server. `F:\` represents the volume on that server. Nothing is uploaded to Tanium — the package is a trigger only:

```
F:\path\to\scripts\
    ├── Get-AdminOU.ps1       ← pre-existing on the server, referenced by the command
    ├── tanium_api_cred.bin   ← pre-seeded once manually (DPAPI encrypted)
    └── InAdminOU.txt         ← written by the script on each run
```

### Package settings

In the Tanium console, go to **Content → Packages → New Package**:

| Field | Value |
|---|---|
| Package Name | `AD - Query Admin OU Users` |
| Command | `cmd.exe /d /c %SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File "F:\path\to\scripts\Get-AdminOU.ps1"` |
| Command Timeout | `90 minutes` |
| Files | *(none — all files are pre-existing on the runner server)* |

Replace `F:\path\to\scripts\` with the actual path on your runner server.

Because `$PSScriptRoot` in the script resolves to `F:\path\to\scripts\`, both `tanium_api_cred.bin` and `InAdminOU.txt` are automatically found in the same directory — no hardcoded paths needed inside the script.

!!! warning
    `tanium_api_cred.bin` is DPAPI-encrypted and bound to the Windows user account and machine it was created on. The Tanium client service on the runner server must execute as the same user account that ran the credential generation command in Step 1 — otherwise decryption fails and Phase 2 returns `Forbidden`.

!!! note
    Target Package 1 only at the designated runner server using a Tanium targeting filter on computer name or subnet — not at all endpoints.

---

## Step 5 — Create Tanium Package 2 (Enforcement Package)

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

### Audit mode

To run in audit mode (no changes, just logs what would be removed), change the trailing `0` to `1` in the command:

```
... -File Remove-AdminOUUsers.ps1 1
```

---

## Step 6 — Remove-AdminOUUsers.ps1 (Full Script)

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
$LogFile   = Join-Path $env:ProgramData 'Tanium\Remove-AdminOUUsers.log'

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

## Step 7 — Run the Full Flow

### Manual run (testing)

Run `Get-AdminOU.ps1` from PowerShell on the DC:

```powershell
C:\path\to\scripts\Get-AdminOU.ps1
```

Then deploy Package 2 from the Tanium console to your target endpoints.

### Automated (scheduled)

Create a Windows Scheduled Task on the DC to call `Get-AdminOU.ps1` on your desired cadence (e.g. daily at 02:00), then trigger Package 2 deployment via a Tanium Scheduled Action targeting all managed Windows endpoints.

---

## Log Locations

| Log | Location |
|---|---|
| AD query + upload | Same directory as `Get-AdminOU.ps1` → `Get-AdminOU.log` |
| Endpoint removal | `C:\ProgramData\Tanium\Remove-AdminOUUsers.log` on each endpoint |

### Sample endpoint log

```
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Starting - InAdminOU.txt: C:\...\InAdminOU.txt
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Parsed 19 accounts from InAdminOU.txt
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Current local Administrators (3 members): Administrator, jsmith, bjones
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Removed DOYENKABA\jsmith from local Administrators
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Removed DOYENKABA\bjones from local Administrators
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] --- Summary ---
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Removed   : 2 - jsmith, bjones
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Not found : 17 - ...
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Skipped   : 0 -
[2026-05-28 18:57:52] [INFO] [ENDPOINT01] [Mode=0] Enforcement complete
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Cannot bind argument to parameter 'Path' because it is null` | Script run from unsaved ISE buffer | Save the `.ps1` file to disk before running |
| `ScriptRequiresMissingModules: ActiveDirectory` | RSAT not installed | Run `Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0` |
| `Could not establish trust relationship for SSL/TLS` | Connecting to IP instead of hostname, or untrusted cert | Use the FQDN (`https://tanium.yourdomain.com`) and set `$BypassSslErrors = $true` for lab |
| `{"text":"Forbidden"}` on login | Wrong username or password, or account lacks API permissions | Re-create `.bin` file; verify user has API role in Tanium console |
| `File Name` blank entry appears in package | File uploaded without a `name` field in a previous run | Manually delete the blank entry in Tanium; fixed in current script version |
| `InAdminOU.txt not found` on endpoint | Package 2 deployed before `Get-AdminOU.ps1` ran | Run Package 1 first, confirm upload success, then deploy Package 2 |
| `Removal would leave 0 local Administrators` | All local admins are in the OU list | Review `InAdminOU.txt` — ensure at least one permanent admin is excluded |