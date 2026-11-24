---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Microsoft Edge
  - AppX
  - Patch Management
---

# Edge MSI Standardization (Package)

This Tanium package makes the Microsoft Edge Enterprise MSI the owner of Edge on an endpoint. It also lets Edge update itself again.

Windows includes a copy of Edge from the Microsoft Store. This copy is an AppX package named `Microsoft.MicrosoftEdge.Stable`. On some endpoints, this copy is the only Edge, or policy values stop Edge from installing and updating. Then the browser stays on an old version, and vulnerability scanners report it.

The package does these things:

- It clears the Edge update policy values that stop Edge from installing or updating.
- It installs the Enterprise MSI where MSI Edge is missing.
- It removes older Edge AppX registrations that a user profile holds.

The package has no parameters. The package files are the settings: the script and the Enterprise MSI.

The package does not restart the endpoint.

!!! note "Test status"
    The package was deployed through Tanium to a Windows 11 lab endpoint. It was also deployed to two Windows 11 endpoints where policy values stopped Edge from installing and updating. These items were tested:

    - The package cleared six and seven blocking policy values. The Group Policy check ran and found no Group Policy that sets them.
    - The package installed the MSI where MSI Edge was missing. The install exit code was `0`.
    - The package kept the older registration that no user profile held, and ended with `RESULT|Success`.
    - A second deployment to a correct endpoint ended with `RESULT|Success` and `PoliciesCleared=0`.
    - After the deployment, the endpoints showed no blocking policy values, and MSI Edge and `msedge.exe` were on the same version.

    **These items were not tested:**

    - The removal of a registration that a user profile holds, through the removal for all users and the removal for each user profile.
    - The registration of a newer, staged registration for all users, or at the next sign-in, before that removal.
    - The force uninstall and the second MSI install after a failed install.
    - The unlock of a registration that is marked non-removable.
    - The warning line for a Group Policy that sets the values.

    Deploy to one endpoint first and read the action log.

!!! warning "Group Policy can set the values again"
    If a Group Policy sets the policy values, they come back at the next policy refresh. The action log names the Group Policy. Change that Group Policy, or Edge stops updating again.

## What the package does

1. Makes sure that it runs as SYSTEM or as an administrator. If not, it stops with exit code 13.
2. Clears the Edge update policy values that stop Edge from installing or updating. The action log shows the old value of each one. Refer to [The policy values that the package clears](#the-policy-values-that-the-package-clears).
3. Checks if a Group Policy sets the values that it cleared. If one does, the action log shows its name.
4. Sets the Edge update services and scheduled tasks to their normal settings.
5. If MSI Edge is installed, keeps it and installs nothing.
6. If MSI Edge is missing, installs the MSI from the package. If the MSI is not in the package, the package stops with exit code 11.
7. If the install fails, removes the self-updating copy of Edge and installs the MSI again. Only then.
8. Makes sure that MSI Edge is installed. If not, the package stops with exit code 10. It removes nothing.
9. Writes one line to the action log for each Edge AppX registration on the endpoint.
10. Removes each AppX registration that is older than MSI Edge and that a user profile holds.
11. Removes old registry entries that belong to the registrations that it removed.
12. Writes one `RESULT` line to the action log.

The package does not upgrade an MSI Edge that is already installed. Tanium Patch or the Edge update service does that.

## The policy values that the package clears

The values are under `HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate`. The package changes only the values for Edge Stable and for WebView2.

| Value | Why the package clears it |
|---|---|
| `InstallDefault` = `0` | The MSI install fails with error 1722. |
| `UpdateDefault` = `0` | Edge does not update. |
| `Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}` = `0` | The Edge Stable install fails. |
| `Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}` = `0` | Edge Stable does not update. |
| `Install{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}` = `0` | The WebView2 install fails. |
| `Update{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}` = `0` | WebView2 does not update. |
| `AutoUpdateCheckPeriodMinutes` = `0` | Edge never checks for updates. |
| `UpdatesSuppressedDurationMin` of `1440` or more | Updates are held back all day. The package also clears `UpdatesSuppressedStartHour` and `UpdatesSuppressedStartMin`. |

The package keeps a suppression window that is shorter than one day. It writes each value that it keeps to the action log.

## Which AppX registrations the package removes

The installed MSI Edge version is the limit. You do not set a version. To move endpoints to a newer Edge, put a newer MSI in the package.

If the registry and `msedge.exe` show different versions, the package uses the lower version. Then it never removes the registration of the Edge that runs now.

| Registration | What the package does |
|---|---|
| Older than MSI Edge, and a user profile holds it | Removes it. |
| Older than MSI Edge, and no user profile holds it | Keeps it. The action log shows a `Keep` line. |
| The same version as MSI Edge, or newer | Keeps it. |

### Why the package keeps a registration that no user profile holds

In tests, an older registration that no user profile held came back within minutes after each removal. Windows logged each removal as successful. The folder of this registration holds only a manifest and two icons. It does not hold browser files. The browser is the MSI install in `C:\Program Files (x86)\Microsoft\Edge\Application`.

Thus, the package keeps these registrations. A removal that does not last only gives an incorrect `Removed` count.

### A user profile and a staged registration

A newer registration can be staged and not registered to a user. If the package removes an older registration that a user profile holds, that profile can have no Edge registration. Thus, the package does these checks first:

1. It tries to register the newer registration for all users.
2. If that is not possible, it continues only when the newer registration is provisioned. Windows registers a provisioned registration for a user at the next sign-in.
3. If the newer registration is not provisioned, the package changes nothing more. It writes `RESULT|Skipped` and uses exit code 0.

Edge stays usable through all of this. The browser does not need the AppX registration to run.

## What the package always leaves alone

The package never deletes these folders and registry keys:

```text
C:\Program Files (x86)\Microsoft\Edge
C:\ProgramData\Microsoft\EdgeUpdate
HKLM\SOFTWARE\Microsoft\Edge
HKLM\SOFTWARE\WOW6432Node\Microsoft\Edge
HKLM\SOFTWARE\Microsoft\EdgeUpdate
HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate
```

Some Edge cleanup scripts delete them to remove Edge fully. After an MSI install, that deletes the browser that you installed.

The package removes only these registry entries:

| Entry | When |
|---|---|
| `...\Uninstall\Microsoft Edge` | Only when it is not an MSI entry and its `setup.exe` is not on disk. |
| `...\AppxAllUserStore\Applications\<PackageFullName>` | Only for a registration that the package removed. |
| `...\AppxAllUserStore\Deprovisioned\Microsoft.MicrosoftEdge.Stable*` | Always. This marker stops the current Edge registration from being provisioned later. |

## How the package removes a registration

`Remove-AppxPackage` can fail in different ways. Thus, the package tries three ways, in this order. After each one, it checks if the registration is still there. It does not trust the error alone.

1. **Removal for all users.** This works when the registration is in the all-users store.
2. **Removal for each user profile** that holds the registration. A registration that only a user profile holds is not in the all-users store. Then the first way fails with `0x80070002`.
3. **Unlock, then removal for all users.** This is for a registration that is marked non-removable (`0x80073CFA`). The package takes ownership of the registry key of the registration, sets `NonRemovable` to `0`, and tries again.

If the registration is still there after the three ways, the action log shows one `Error` line. The line shows the state of the registration. The package continues with the other registrations and ends with exit code 12.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1
- The Tanium Client
- The Microsoft Edge Enterprise MSI (Stable, x64), in the same package as the script. Download it from [https://www.microsoft.com/edge/business/download](https://www.microsoft.com/edge/business/download).

The script never downloads anything. Tanium copies the package files to the endpoint, and the script installs the MSI from there. The download link is for the person who makes the package.

## Create the package

1. Download the Edge Enterprise MSI (Stable, x64).
2. Rename the file to `MicrosoftEdgeEnterpriseX64.msi`.
3. In the Tanium Console, go to **Administration > Content > Packages**.
4. Click **Create Package**.
5. Fill in the fields with the values in the table below.
6. In the **Files** section, add the script file.
7. In the **Files** section, add the MSI file.
8. Leave the **Parameters** section empty.
9. Click **Save**.

| Field | Value |
|---|---|
| Package Name | `Edge MSI Standardization` |
| Display Name | `Edge MSI Standardization` |
| Description | `Makes the Edge Enterprise MSI the owner of Microsoft Edge. Clears the EdgeUpdate policy values that stop Edge or WebView2 from installing or updating, and logs each old value. Installs the MSI only where MSI Edge is missing. Removes older Edge AppX registrations that a user profile holds, and keeps the ones that no profile holds. Leaves the Edge update service on. If a Group Policy sets the values, the log names it. No parameters. Does not restart the computer. Windows only.` |
| Content Set | Your custom content set. Use a content set that only administrators can deploy. |
| Command | `cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Set-EdgeMsiOnly.ps1` |
| Command Timeout | 30 minutes |
| Download Timeout | 10 minutes |
| Ignore Action Lock | Clear (not selected) |
| Launch this package command in a process group | Selected |
| Files | `Set-EdgeMsiOnly.ps1`, `MicrosoftEdgeEnterpriseX64.msi` |
| Parameters | None |

To use a newer Edge, edit the package, replace the MSI file, and click **Save**. The script stays the same.

The script finds the MSI by its file name. If you use a different file name, change `$MsiName` in the Config section of the script.

## Deploy the package

### Find the endpoints

1. In the Tanium Console, go to **Interact**.
2. In the question bar, type this question:

    ```text
    Get Computer Name and Installed Applications from all machines with Installed Applications contains "Microsoft Edge"
    ```

3. Press Enter.

To see the Edge AppX registrations on the endpoints, ask this question:

```text
Get Computer Name and Installed Store Apps from all machines with Installed Store Apps contains "MicrosoftEdge.Stable"
```

### Deploy to one endpoint first

1. In the Tanium Console, go to **Interact**.
2. In the question bar, type this question. Replace `ENDPOINT-01` with the name of your endpoint.

    ```text
    Get Computer Name from all machines with Computer Name equals ENDPOINT-01
    ```

3. Press Enter.
4. Select the endpoint.
5. Click **Deploy Action**.
6. In the **Deployment Package** field, type `Edge MSI Standardization`. Select the package.
7. Click **Show preview to continue**.
8. Make sure that the list shows the correct endpoint.
9. Click **Deploy Action**.
10. Read the action log. Refer to [Read the results](#read-the-results).
11. Make sure that the last line starts with `RESULT|Success`.

Then deploy the package to more endpoints. The MSI install takes the most time and network. Use **Distribute over** to spread a large deployment.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | The package completed. This includes `RESULT\|Skipped` and an endpoint that was already correct. |
| 10 | MSI Edge is not installed after the install. The package removed nothing. |
| 11 | The MSI is not in the package. The package changed no AppX registration. |
| 12 | MSI Edge is installed, but one or more AppX removals failed. |
| 13 | The package did not run as SYSTEM or as an administrator. Nothing was changed. |

In Action History, an exit code that is not 0 can show as **Failed**.

Exit code 11 comes after the policy step. Thus, the policy values can be cleared on an endpoint that ends with exit code 11.

## Read the results

To read the action log from the Tanium Console:

1. Go to **Interact**.
2. Type this question. Replace `<action ID>` with the ID of your action.

    ```text
    Get Tanium Action Log[<action ID>] from all machines with Computer Name equals ENDPOINT-01
    ```

3. Press Enter.

The action ID is on the action in **Administration > Actions > Action History**.

Each line starts with the time and one of these words:

| Word | Meaning |
|---|---|
| `Fix` | The package changed a policy value, a service, a scheduled task, or a registry entry. |
| `Skip` | MSI Edge is installed. The package installed nothing. |
| `Act` | The package installed the MSI or removed a registration. The line shows the result. |
| `Verify` | The installed MSI Edge version. The package uses it as the limit. |
| `AppX` | One Edge AppX registration: its version, if it is provisioned, if its folder is on disk, and the user profiles that hold it. |
| `Keep` | The package did not remove this registration. The line shows the reason. |
| `Policy` | The Edge update service and its scheduled tasks are set to their normal settings. |
| `Info` | A fact or a decision. The line shows the reason. |
| `Warn` | A step that did not work. The package continued. |
| `Error` | A step that failed. |
| `RESULT` | The outcome. This is always the last line. |

A `Warn` line about the removal for all users is normal. It means that the removal for each user profile did the work.

The package also writes a full log to this file on the endpoint:

```text
C:\ProgramData\_TaniumLogs\Set-EdgeMsiOnly.log
```

The MSI install writes its log to this file:

```text
C:\ProgramData\_TaniumLogs\EdgeMSI_Install.log
```

### Example log: policy values cleared and MSI installed

```text
18:01:00|Fix|Cleared EdgeUpdate policy InstallDefault (was 0).
18:01:00|Fix|Cleared EdgeUpdate policy Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062} (was 0).
18:01:00|Fix|Cleared EdgeUpdate policy Update{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5} (was 0).
18:01:00|Fix|Cleared EdgeUpdate policy AutoUpdateCheckPeriodMinutes (was 0).
18:01:00|Fix|Cleared EdgeUpdate policy UpdatesSuppressedStartHour (was 0).
18:01:00|Fix|Cleared EdgeUpdate policy UpdatesSuppressedStartMin (was 0).
18:01:00|Fix|Cleared EdgeUpdate policy UpdatesSuppressedDurationMin (was 1440).
18:01:00|Info|No Group Policy sets the cleared values (RSoP).
18:01:04|Policy|EdgeUpdate enabled.
18:02:48|Act|MSI install exit code 0.
18:02:49|Verify|MSI Edge 157.0.4341.60. Checking AppX registrations below 157.0.4341.60.
18:02:49|AppX|153.0.4234.48|Provisioned=False|NonRemovable=False|Folder present|Users: none
18:02:49|AppX|157.0.4341.60|Provisioned=True|NonRemovable=False|Folder present|Users: S-1-5-18=Staged
18:02:49|Keep|AppX 153.0.4234.48: no user profile holds it. Windows puts it back when it is removed, so it is left in place.
RESULT|Success|MSI=157.0.4341.60|Removed=0|Kept=1|PoliciesCleared=7
```

### Example log: endpoint with only the Store copy of Edge

```text
18:07:10|Info|No EdgeUpdate policy key.
18:07:10|Policy|EdgeUpdate enabled.
18:07:44|Act|MSI install exit code 0.
18:07:44|Verify|MSI Edge 153.0.4234.48. Checking AppX registrations below 153.0.4234.48.
18:07:44|AppX|152.0.4191.66|Provisioned=False|NonRemovable=False|Folder present|Users: S-1-5-21-1111111111-2222222222-3333333333-1001=Installed
18:07:44|Info|No AppX registration at or above 153.0.4234.48. Removing legacy registrations; MSI Edge 153.0.4234.48 is installed and owns the browser.
18:07:46|Act|Removed AppX 152.0.4191.66.
18:07:46|Fix|Cleared deprovisioned marker Microsoft.MicrosoftEdge.Stable_8wekyb3d8bbwe.
RESULT|Success|MSI=153.0.4234.48|Removed=1|Kept=0|PoliciesCleared=0
```

## Troubleshooting

| Log message | Cause | Action |
|---|---|---|
| `RESULT\|Failed\|MSI missing from package` | The MSI is not in the package, or its file name is different from `$MsiName`. | Edit the package. Add `MicrosoftEdgeEnterpriseX64.msi`. Then deploy again. |
| `Error\|No MSI-registered Edge found. Nothing removed.` | The MSI install failed. The `Act\|MSI install exit code` line shows the Windows Installer code. | Read the action log for `Warn` lines before this line. The full install log is in `C:\ProgramData\_TaniumLogs\EdgeMSI_Install.log` on the endpoint. |
| `Warn\|Group Policy '<name>' sets <value>...` | A Group Policy sets the value that the package cleared. The value comes back at the next policy refresh. | Change the Group Policy. Then deploy the package again. |
| `Error\|AppX ... is still registered after every removal attempt...` | The three ways to remove the registration did not work. The line shows the state of the registration. | Restart the endpoint. Then deploy again. If the line comes back, keep the action log for the case. |
| `RESULT\|Skipped\|Staged ... not provisioned and not registerable...` | A user profile holds an older registration. The newer registration is staged, and the package cannot register it. | Have the user sign out and sign in. Then deploy again. |
| `Keep\|AppX ...` | No user profile holds this registration. | Nothing. Refer to [Why the package keeps a registration that no user profile holds](#why-the-package-keeps-a-registration-that-no-user-profile-holds). |
| Edge does not update after the deployment | A policy value came back, or no new Edge version was released yet. | After the next Edge release, ask `Get Computer Name and File Version[C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe] from all machines with Computer Name equals ENDPOINT-01`. If the version did not change, deploy the package again and read the `Fix` lines. |
| The command timeout occurs | The MSI install took more than 30 minutes. This case was not tested. | Increase the command timeout. Then deploy again. |

## Things to know

- **The package has no Audit mode.** It has no parameters. On an endpoint that is already correct, it changes nothing.
- **You can deploy the package again with no risk.** A second deployment writes `PoliciesCleared=0` and `Removed=0` when there is nothing to do.
- **Scanners can still show the version of a kept registration.** The `Installed Store Apps` sensor lists it too. The registration holds no browser files.
- **Fix the image too.** If the image has only the Store copy of Edge, or has the policy values, each new endpoint has the same problem.
- **The log files stay on the endpoint.** The files in `C:\ProgramData\_TaniumLogs` stay until a person or a cleanup deletes them.

## Script

### Set-EdgeMsiOnly.ps1

```powershell
--8<-- "tanium/packages/edge-msi-standardization/Set-EdgeMsiOnly.ps1"
```

## Related

- [Microsoft Edge for Business download](https://www.microsoft.com/edge/business/download)
