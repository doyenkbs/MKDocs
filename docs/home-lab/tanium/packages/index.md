---
tags:
  - Tanium
  - PowerShell
  - Packages
---

# Tanium Package Repository

Custom Tanium packages, with the PowerShell source and the console settings needed to recreate each one.

A package runs a script on targeted endpoints as an action. Output goes to the action log on each endpoint, not to Interact. Use a package when the work changes something on the endpoint, or when it takes longer than a sensor is allowed to run.

| Package | What it does | Platform | Updated |
|---|---|---|---|
| [Edge MSI Standardization](edge-msi-standardization.md) | Makes the Enterprise MSI the only managed copy of Edge, removes the stale Store (AppX) registration even when locked, and clears stale registry entries. | Windows | 2026-09-18 |
| [Find File by Name](find-file-by-name.md) | Searches drives or folders for a file name or wildcard. Returns every matching path and its last modified date. | Windows | 2026-09-18 |
| [Local Admin Removal](local-admin-removal.md) | Removes domain accounts in the AD admin OU from the local Administrators group on managed endpoints. Two scripts, two packages. | Windows | 2026-08-10 |
| [Set Time Zone](set-time-zone.md) | Sets endpoints to a common U.S. time zone picked from a drop-down. Separate packages for Windows and for Linux and macOS. | Windows, Linux, macOS | 2026-09-23 |

## Conventions used here

- **Naming:** `<prefix> - <what it does>`, for example `BF - Find File by Name`. Keep the prefix consistent so custom content sorts together and stays separate from Tanium's default content.
- **Command line:** every package calls PowerShell through `cmd.exe` so parameters are passed the same way each time:
  ```
  cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File <script>.ps1 -Param1 "$1" -Param2 "$2"
  ```
- **Parameters arrive URL-encoded.** Tanium passes `*.pst` to the script as `%2a%2epst`. Every script that takes a parameter decodes it before use.
- **Command timeout** is set higher than the script's own internal limit, so the script can report its own status before Tanium stops it.
- **Validate input.** A blank or wildcard-only parameter should be rejected by the script, not acted on.

## Before deploying

1. Test the script locally on one machine, running as Administrator.
2. Deploy to a single endpoint through Tanium and read the action log. Running as SYSTEM from the client's download folder is not the same as running it yourself.
3. For large target groups, use the action's **Distribute over** option to spread the start times.
