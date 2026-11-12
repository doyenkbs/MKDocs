---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Endpoint Management
  - Vulnerability Remediation
---

# Update Store Apps (Package)

A parameterized Tanium package that asks the Microsoft Store to check for app updates on Windows endpoints, then checks whether the apps you list reached the version you need.

Use it when a vulnerability scan reports a Store app (Paint, Calculator, Photos, and similar) below a fixed version, and the endpoints are not updating the app on their own.

!!! warning "Read this before you use it"
    **It cannot select the apps to update.** The package starts one Store update scan for the full machine. Thus, each Store app that has an update gets the update, not only the apps in the list. The list decides what the script checks and reports.

    **It cannot install a version that the Store does not offer yet.** If the Store has not released the fixed version, each endpoint reports `BELOW MINIMUM`. A longer wait does not change this. Check first: see [Is the version available yet?](#is-the-version-available-yet)

    **It cannot update system apps.** Some apps that show up in the Store app list, such as Windows Security, are updated through Windows Update instead. See [System apps](#system-apps-are-not-updated-by-the-store).

!!! note "Test status"
    Run through Tanium as SYSTEM on Windows 11 endpoints. The Store scan trigger, the wait loop, the version check, URL decoding, and exit codes `0` and `1` were confirmed in real action logs. **A successful update has not been seen yet**: in every test so far, the Store had no newer version to install. Exit codes `2` through `6` have not been tested. See [Test results](#test-results).

---

## How it works

1. Reads the installed version of each listed app, for every user on the machine.
2. If each app with a minimum version already meets it, the script stops. It does not start a scan.
3. Otherwise, it triggers a Microsoft Store update scan through the Windows MDM WMI bridge (class `MDM_EnterpriseModernAppManagement_AppManagement01`, method `UpdateScanMethod`). This only works as SYSTEM. An administrator account is not enough.
4. It checks the app versions every 30 seconds, until every app reaches its target or the wait time runs out.
5. It writes one summary line per app and exits with a code that shows the result.

The scan call does not return right away. In testing it took between 1.5 and 3 minutes before the wait started. That time is not part of **Wait Minutes**.

Apps that are not installed on the endpoint are skipped. A Store update scan does not install new apps.

---

## Parameters

| Parameter | Passed as | Required | What to enter |
|---|---|---|---|
| Apps | `$1` | Yes | One or more entries, separated by commas. Each entry is `Name` or `Name=MinimumVersion`. Example: `Microsoft.Paint=11.2605.91.0,Microsoft.WindowsCalculator` |
| Wait Minutes | `$2` | No | How long to wait for updates after the scan, from `1` to `30`. Blank means `10`. |

Tanium replaces `$1` and `$2` in the command line with the values you enter, in the order the parameters are defined in the package.

### Entry forms

| Entry | What the script does | Use it for |
|---|---|---|
| `Microsoft.Paint=11.2605.91.0` | Passes only when the app reaches at least that version. Stops waiting as soon as it does. | Vulnerability remediation. This is the form to use when a scan names a fixed version. |
| `Microsoft.Paint` | Reports the version before and after. Stops waiting as soon as the version goes up at all. | Testing whether Store updates work on an endpoint. |

!!! warning "Report-only entries always exit 0"
    An entry with no minimum version exits `0` even when nothing was updated. Read the summary line (`Updated` or `No change`) instead of the exit code. Do not use the report-only form to confirm a vulnerability fix: going from one old build to a newer old build also counts as `Updated`.

Other rules:

- Use the package **Name**, not the display name and not the full package name. `Microsoft.Paint` is correct. `Paint` (the display name) and `Microsoft.Paint_11.2605.81.0_x64__8wekyb3d8bbwe` (the full name) are both rejected.
- Wildcards are rejected.
- Names are not case sensitive. If the same app is listed twice, the first entry is used and the second is logged as a duplicate.
- Spaces around the commas and the `=` are ignored.

### Finding the package name and version

**In Tanium**, ask a question with the **Installed Store Apps** sensor. Example for Paint:

```
Get Installed Store Apps contains Paint from all machines with Installed Store Apps contains Paint
```

The **Name** column is what goes into the **Apps** parameter. The **Version** column shows what is installed today.

Reading the results:

- One endpoint can return several versions of the same app. That usually means an older version is still registered for another user profile. See [Exit code 6](#exit-code-6-older-version-left-for-another-user).
- Similar names can be different apps. For example, `Microsoft.Paint` is Paint, and `Microsoft.MSPaint` is Paint 3D, a separate app. Check that the name matches the app in your scan finding.

**On a reference machine**, open PowerShell as Administrator and run:

```powershell
Get-AppxPackage -AllUsers -Name *Paint* | Select-Object Name, Version, SignatureKind
```

Check the `SignatureKind` column before you deploy:

| SignatureKind | Can this package update it? |
|---|---|
| `Store` | Yes, when the Store is offering a newer version. |
| `System` | No. The Store does not update it. See [System apps](#system-apps-are-not-updated-by-the-store). |

### Choosing Wait Minutes

- The script stops early when every app reaches its target, so a long wait does not cost time on endpoints that update quickly.
- The Store keeps downloading and installing in the background after the script exits. An endpoint that reports `BELOW MINIMUM` with a short wait may finish a few minutes later. To check it again, deploy the package again with the same values. When the app already meets the minimum, the script skips the scan and only reports.
- `10` to `15` is a reasonable start for a small app. The maximum is `30`, which keeps the whole run inside the 40-minute command timeout below.

---

## Is the version available yet?

Check this before deploying to many endpoints. If the Store is not offering the fixed version, the package cannot succeed anywhere, and every endpoint uses up its full wait time.

1. On a Windows 11 test machine, sign in as a normal user.
2. Open **Microsoft Store**.
3. Click **Library** in the bottom-left corner.
4. Click **Get updates**.
5. Look for the app in the list, and check which version it installs.

Other signs that the version is not out yet:

- Almost every endpoint is on the same build of the app, and none is newer. That pattern usually means Store updates are working and the next build has not been released.
- The vendor's security advisory lists a different fixed build than the scanner, or none at all. A scanner definition can name the fixed build before the Store offers it.

While you wait for the release, either record an exception for the finding, or remove the app where it is not needed with the [Remove Store Apps](remove-store-apps.md) package.

---

## System apps are not updated by the Store

Some apps show up in the Store app list but are serviced through Windows Update. The Store scan has nothing to install for them. The script waits the full time and ends with `BELOW MINIMUM`.

The main example is **Windows Security** (`Microsoft.SecHealthUI`). Microsoft ships its updates as KB5007651 through Windows Update, WSUS, and the Microsoft Update Catalog, for Windows 11 only. Microsoft's KB article also links standalone installers. To update it, use your patching tool, or deploy the standalone installer as a package.

Check `SignatureKind` as shown in [Finding the package name and version](#finding-the-package-name-and-version). If it says `System`, do not use this package for that app.

---

## Exit codes

| Exit code | Meaning |
|---|---|
| `0` | Every app with a minimum version meets it, or nothing needed an update. For report-only entries, `0` does not mean anything was updated. Read the summary line. |
| `1` | At least one app is still below its minimum version after the wait. The update was not offered, did not finish in time, or the app is a system app. |
| `2` | A parameter was not valid: no apps, a wildcard, a full package name, a version that is not a number like `11.2605.91.0`, or a Wait Minutes value outside 1 to 30. |
| `3` | The Store update scan could not be triggered. Either the WMI call failed, or the Microsoft Store Install Service (`InstallService`) is disabled. |
| `4` | The Microsoft Store is blocked by policy (`RemoveWindowsStore = 1` or `DisableStoreApps = 1`). Nothing was done. |
| `5` | The script is not running as SYSTEM. Nothing was done. |
| `6` | The app reached the minimum version, but an older version is still registered for at least one user. A vulnerability scan can still flag the endpoint. |

In Action History, exit codes other than `0` can show as **Failed**. For codes `2`, `4`, and `5`, that is the script working as intended: it stopped before doing anything.

---

## Requirements

- Windows 11 endpoints with Windows PowerShell 5.1. Windows 10 has not been tested.
- The action must run as SYSTEM, which is the Tanium default.
- The Microsoft Store must be allowed. The endpoint must reach the Microsoft Store download servers as SYSTEM, not only as the signed-in user.
- WMI must be working on the endpoint. The scan is triggered through WMI.
- A Tanium account with permission to create packages in a content set and deploy actions to the target computers.

---

## Create the package

Menu labels can differ slightly between Tanium versions.

1. Save the script at the bottom of this page as `Update-StoreApps.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package**.
4. Fill in the fields:
    - **Package Display Name:** `Update Store Apps` (add your team's prefix if you use one).
    - **Description:** `Triggers a Microsoft Store update scan as SYSTEM and checks that the listed Store apps reached a minimum version. Updates every Store app that has an update available, not only the listed ones. $1 = Name or Name=MinimumVersion, comma separated. $2 = wait minutes, 1 to 30.`
    - **Content Set:** the content set your team uses for custom content.
    - **Command:**
      ```
      cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Update-StoreApps.ps1 "$1" "$2"
      ```
    - **Command Timeout:** `40` minutes. The longest run is up to 3 minutes for the scan, plus up to 30 minutes of waiting, plus the final check. The timeout must be longer than that, or Tanium stops the script before it writes its summary.
    - **Download Timeout:** `10` minutes.
    - **Ignore Action Lock:** leave it cleared.
    - **Launch this package command in a process group:** select it. The script can restart itself as 64-bit PowerShell. If the command times out, the process group makes sure that Tanium also stops that second process.
5. Under **Files**, click **Add**, choose **Local File**, and upload `Update-StoreApps.ps1`.
6. Expand **Parameters**. Under **Parameter Inputs**, add a **Text Input** parameter. It shows in the list as `$1`.
    - **Label:** `Apps`
    - **Provide Help Text:** select it and enter `Name or Name=MinimumVersion, separated by commas, for example Microsoft.Paint=11.2605.91.0`
7. Add a second **Text Input** parameter. It shows in the list as `$2`.
    - **Label:** `Wait Minutes`
    - **Default Value:** `10`
    - **Provide Help Text:** select it and enter `Minutes to wait for updates after the scan, 1 to 30`
8. In the **Preview** panel on the right, confirm you see **Apps**, then **Wait Minutes**.
9. Click **Save**.

---

## Deploy the package

1. In **Interact**, ask a question that returns only the computers that have the app. Example for Paint:
    ```
    Get Computer Name and Installed Store Apps contains Microsoft.Paint from all machines with Installed Store Apps contains Microsoft.Paint
    ```
2. Select the computers in the results grid. For the first run, pick two or three test endpoints. If some endpoints show more than one version of the app, include one of them.
3. Click **Deploy Action**.
4. In **Deployment Package**, search for and select `Update Store Apps`.
5. In **Apps**, enter the app and its fixed version, for example `Microsoft.Paint=11.2605.91.0`.
6. In **Wait Minutes**, enter `15`.
7. Under the schedule, leave it as a one-time action for the first run.
8. Click **Show preview to continue**, review the targets, then click **Deploy Action**.

Read the action logs from the test endpoints before you deploy to a larger group. For large groups, use the action's **Distribute over** option to spread the start times, because every endpoint downloads from the Store at the same time otherwise.

---

## View the results

### One endpoint

1. Open the action from **Administration** > **Actions** > **Action History**.
2. Select an endpoint.
3. Open its action log. The script output appears between the `Command Line` line and the `Completed` line. The last lines are a summary with one line per app.

The fixed version was not offered by the Store:

```
2026-10-26 16:19:30 [INFO] Apps to verify (1):
2026-10-26 16:19:30 [INFO]   - Microsoft.Paint (minimum 11.2605.91.0)
2026-10-26 16:19:31 [INFO] Before: Microsoft.Paint installed version(s): 11.2605.81.0
2026-10-26 16:20:55 [INFO] Store update scan triggered. ReturnValue: 0
2026-10-26 16:20:55 [INFO] Waiting up to 30 minute(s) for: Microsoft.Paint
2026-10-26 16:51:18 [WARN] Wait ended. No version change seen for: Microsoft.Paint
2026-10-26 16:51:19 [INFO] Summary:
2026-10-26 16:51:19 [INFO]   Microsoft.Paint: BELOW MINIMUM: 11.2605.81.0 (needs 11.2605.91.0)
2026-10-26 16:51:19 [ERROR] 1 app(s) still below the minimum version.
```

`ReturnValue: 0` means the scan was accepted. The Store simply had nothing newer to install.

Report-only entry, no update arrived:

```
2026-10-26 16:00:15 [INFO]   - Microsoft.Paint (no minimum, report only)
2026-10-26 16:00:16 [INFO] Before: Microsoft.Paint installed version(s): 11.2605.71.0
2026-10-26 16:02:16 [INFO] Store update scan triggered. ReturnValue: 0
2026-10-26 16:02:16 [INFO] Waiting up to 10 minute(s) for: Microsoft.Paint
2026-10-26 16:12:39 [WARN] Wait ended. No version change seen for: Microsoft.Paint
2026-10-26 16:12:40 [INFO] Summary:
2026-10-26 16:12:40 [INFO]   Microsoft.Paint: No change: 11.2605.71.0 (no update found, or it did not finish within 10 minute(s))
2026-10-26 16:12:40 [INFO] Completed.
```

This run exited `0`, even though nothing changed. That is the report-only behavior described in [Entry forms](#entry-forms).

### Many endpoints

Ask a question with the built-in **Tanium Action Log** sensor, using the action ID from the top of the log:

```
Get Tanium Action Log[12345] from all machines
```

### Confirm the fix

After the action finishes, ask the same Installed Store Apps question again:

```
Get Installed Store Apps contains Microsoft.Paint from all machines with Installed Store Apps contains Microsoft.Paint
```

Every row should show the fixed version or higher. Any row that still shows an older version is either an endpoint that did not update, or an older version left for another user.

---

## Troubleshooting

All of these checks are Tanium questions, so they work without direct access to the endpoint.

### Every endpoint reports BELOW MINIMUM or No change

Start with [Is the version available yet?](#is-the-version-available-yet). If the Store is not offering the version, nothing on the endpoints needs fixing.

If the app is a system app, see [System apps](#system-apps-are-not-updated-by-the-store).

### Only some endpoints do not update

Compare a stuck endpoint with one that updated. Replace `<name>` with the computer name.

| What it checks | Question | Blocks updates when |
|---|---|---|
| Store automatic updates | `Get Registry Value Data[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\WindowsStore,AutoDownload] from all machines with Computer Name equals <name>` | The value is `2`. The script also logs a `WARN` line for this. |
| Store removed by policy | `Get Registry Value Data[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\WindowsStore,RemoveWindowsStore] from all machines with Computer Name equals <name>` | The value is `1`. The script exits `4`. |
| Windows Update internet locations | `Get Registry Value Data[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate,DoNotConnectToWindowsUpdateInternetLocations] from all machines with Computer Name equals <name>` | The value is `1`. This can also cut off Store downloads. |
| MDM Store auto-update setting | `Get Registry Value Data[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\current\device\ApplicationManagement,AllowAppStoreAutoUpdate] from all machines with Computer Name equals <name>` | The value is `0`. |
| Delivery Optimization mode | `Get Registry Value Data[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization,DODownloadMode] from all machines with Computer Name equals <name>` | The value is `100` (Bypass). Other values, including `0`, do not block Store downloads. |

Notes on reading these results:

- `Key/Value not found` means the policy is not set, which is the normal state.
- The same value can show up on two rows, one marked `32-bit` and one marked `64-bit`. Tanium reads both registry views. It is one setting.

If none of these are set, the most probable cause is network access. The endpoint can reach the Store as the signed-in user, but not as SYSTEM. For example, a proxy is set only for users.

### Exit code 3 with a WMI error

The scan is triggered through WMI, so a broken WMI repository stops it. Ask any Registry Value Data question against the same endpoint. A result like `TSE-Error: SWbemServicesEx: Not found` points at WMI. Repair WMI on that endpoint, then run the package again.

### Exit code 6: older version left for another user

Store apps are registered separately for each user profile. The new version can be installed while a user who has not signed in recently still has the old version registered. The old version's folder stays under `C:\Program Files\WindowsApps\`, and a vulnerability scan that reads those folders can still flag the endpoint.

Whether the old registration clears when that user signs in again has not been confirmed. To check on one endpoint:

1. Note which users have profiles on the endpoint.
2. After those users sign in, deploy the package again with the same values. Because the app already meets the minimum, the script skips the scan and only reports.
3. Exit `0` means that the sign-in cleared it. Exit `6` again means that you must remove the old version separately.

---

## Things to know

- **Every Store app with an update gets updated.** Plan for that when you deploy to many endpoints at once.
- **Parameters arrive URL-encoded.** Tanium passes `Microsoft.Paint=11.2605.91.0` to the script as `Microsoft%2ePaint%3d11%2e2605%2e91%2e0`. The script decodes the values before reading them.
- **It runs as 64-bit.** The AppX commands do not work reliably from 32-bit PowerShell. If the Tanium client starts 32-bit PowerShell, the script restarts itself as 64-bit.
- **Results are checked, not assumed.** The summary comes from reading the installed versions again at the end, not from the scan's return value.
- **The scan time adds to the run time.** A 30-minute wait can run 33 minutes or more in total. Keep the command timeout at 40 minutes.

---

## Test results

Each case ran as a Tanium action, as SYSTEM, on Windows 11 endpoints.

| Case | Expected | Result |
|---|---|---|
| URL-encoded `.` and `=` in Apps | Decoded to `Microsoft.Paint=11.2605.91.0` | Pass |
| Store scan trigger as SYSTEM | `ReturnValue: 0` | Pass. The call took about 1.5 to 3 minutes on each endpoint. |
| Report-only entry, endpoint one build behind, 10-minute wait | Version reported before and after | Scan accepted. No update arrived within 10 minutes. Exit `0` with `No change`. Why this endpoint did not update has not been found yet. |
| Minimum version not yet released through the Store, 10 endpoints, 30-minute wait | Exit `1` | Pass. Every endpoint waited the full 30 minutes and reported `BELOW MINIMUM`. Total run time about 32 minutes. |
| System app (`Microsoft.SecHealthUI`) with a minimum version | Exit `1` | Pass. Waited the full 30 minutes and reported `BELOW MINIMUM`, because the Store does not update this app. |
| App updates and reaches the minimum | Exit `0`, `OK` | **Not tested yet.** No newer version was available during testing. |
| Older version left for another user | Exit `6` | **Not tested yet** |
| Invalid parameters | Exit `2` | **Not tested yet** |
| Store blocked by policy, or InstallService disabled | Exit `4` or `3` | **Not tested yet** |
| Not running as SYSTEM | Exit `5` | **Not tested yet** |

---

## Script

```powershell
--8<-- "tanium/packages/update-store-apps/Update-StoreApps.ps1"
```
