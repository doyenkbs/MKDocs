---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Endpoint Management
---

# Remove Store Apps (Package)

A parameterized Tanium package that removes Microsoft Store (AppX) apps from Windows endpoints, for every user on the machine and for new users who sign in later.

The operator types how many apps are in the list as a confirmation. The script refuses wildcards and refuses apps that Windows itself depends on, such as the Store, App Installer (winget), and Windows Security.

Use this package to remove built-in consumer apps (news, weather, games, and similar) from managed devices.

!!! warning "Test status"
    Tested on Windows 11 Pro 24H2 with Windows PowerShell 5.1, run through `cmd.exe` with URL-encoded parameters the same way a Tanium package runs it. The parameter checks, protected-app checks, confirmation, and 64-bit restart were all tested. **The removal itself has not been tested yet**, because the test session was not elevated and the script stops before removing anything when it is not running as SYSTEM or an administrator. Test it on one endpoint through Tanium before deploying widely. See [Test results](#test-results).

---

## Why there is a confirmation parameter

The package runs as SYSTEM and removes apps for every user on the machine. A mistyped list removes the wrong apps from every profile at once.

The **Confirm Count** parameter must equal the number of apps in the list. For `Microsoft.BingNews,Microsoft.BingWeather`, the operator types `2`. Retyping every package name would be tedious, but the count still makes the operator look at the list before deploying. If the count does not match, nothing is removed.

Wildcards are rejected, so the count always matches the number of apps that can actually be touched.

---

## Parameters

| Parameter | Passed as | Required | What to enter |
|---|---|---|---|
| Apps | `$1` | Yes | One or more package names, separated by commas. Example: `Microsoft.BingNews,Microsoft.BingWeather` |
| Option | `$2` | No | `None` (or blank), or `DisableReinstall`. See [Stopping apps from coming back](#stopping-apps-from-coming-back). |
| Confirm Count | `$3` | Yes | The number of apps in the list. Example: `2` |

- Use the package **Name**, not the display name and not the full package name. `Microsoft.BingNews` is correct. `Microsoft Start` (the display name) and `Microsoft.BingNews_4.55.62231.0_x64__8wekyb3d8bbwe` (the full name) are both rejected.
- Names are not case sensitive, and duplicates are counted once. `Microsoft.BingNews,microsoft.bingnews` counts as `1`.
- Spaces around the commas are ignored.

Tanium replaces `$1`, `$2`, and `$3` in the command line with the values you enter, in the order the parameters are defined in the package.

### Finding the package name

On a reference machine with the same Windows version as your endpoints, open PowerShell as Administrator and run:

```powershell
Get-AppxPackage -AllUsers | Where-Object { -not $_.IsFramework -and $_.SignatureKind -eq 'Store' } | Sort-Object Name | Select-Object Name, Version
```

The `Name` column is what goes into the **Apps** parameter. Examples seen on a Windows 11 24H2 build:

| Name | App |
|---|---|
| `Microsoft.BingNews` | News |
| `Microsoft.BingWeather` | Weather |
| `Microsoft.GetHelp` | Get Help |
| `Microsoft.MicrosoftSolitaireCollection` | Solitaire Collection |
| `Microsoft.ZuneMusic` | Media Player |
| `Microsoft.WindowsFeedbackHub` | Feedback Hub |
| `Clipchamp.Clipchamp` | Clipchamp |

Package names change between Windows releases, so check your own build instead of copying this list.

---

## What it refuses to remove

The script stops with exit code `4`, and removes nothing, if any app in the list is one of these. Removing them breaks the Store, winget, Windows Security, the Start menu, sign-in, or other apps that depend on them.

| Package name | What it is |
|---|---|
| `Microsoft.WindowsStore`, `Microsoft.StorePurchaseApp`, `Microsoft.Services.Store.Engagement` | Microsoft Store |
| `Microsoft.DesktopAppInstaller`, `Microsoft.Winget.Source` | App Installer and winget |
| `Microsoft.SecHealthUI` | Windows Security |
| `Microsoft.Windows.ShellExperienceHost`, `Microsoft.Windows.StartMenuExperienceHost`, `Microsoft.Windows.Search` | Taskbar, Start menu, and search |
| `Microsoft.Windows.CloudExperienceHost`, `Microsoft.AAD.BrokerPlugin`, `Microsoft.AccountsControl`, `Microsoft.LockApp` | Sign-in, work accounts, and the lock screen |
| `windows.immersivecontrolpanel` | Settings |
| `Microsoft.Win32WebViewHost` | Web content host used by other apps |
| `Microsoft.VCLibs*`, `Microsoft.NET.Native*`, `Microsoft.UI.Xaml*` | Runtime libraries other apps need |
| `Microsoft.WindowsAppRuntime*`, `MicrosoftCorporationII.WinAppRuntime*`, `Microsoft.WidgetsPlatformRuntime` | Windows App SDK and widget runtimes |
| `MicrosoftWindows.Client.*` | Core Windows client components |

Apps that Windows marks as framework, system, or non-removable are also skipped and reported as `FAILED (system package, not removable)`.

---

## What the script does

For each app in the list:

1. Removes it for every user profile on the machine.
2. Removes the provisioned copy, so the app is not installed for new users who sign in later.
3. Checks again and reports `Removed`, `Not present`, or `FAILED` for that app.

Then, if Option is `DisableReinstall`, it applies the settings described below.

---

## Stopping apps from coming back

Removing the provisioned copy (step 2 above) is what keeps an app from being installed for new users. That is the main fix, and it happens on every run.

The `DisableReinstall` option adds two settings that stop Windows from installing "suggested" apps on its own:

| Setting | Where | Notes |
|---|---|---|
| `DisableWindowsConsumerFeatures = 1` | `HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent` | Windows honors this policy on Enterprise and Education editions. |
| `SilentInstalledAppsEnabled = 0` | `HKEY_USERS\<user SID>\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | Per-user setting. Applied to every user who is signed in when the action runs. Users who are not signed in are not covered. |

What `DisableReinstall` does **not** do:

- **It does not block installing an app on purpose.** Users and administrators can still install the app from the Microsoft Store, with winget, or with a Tanium package.
- **It does not turn off Store app updates.** Apps such as Calculator, Photos, and App Installer keep updating normally.
- **It does not survive a feature update.** An in-place upgrade to a new Windows version can bring the built-in apps back. Run this package again after each feature update, or schedule it to repeat with the same app list.

### Undoing DisableReinstall

To turn the settings back off, run this on the endpoint as Administrator, or as a Tanium package command:

```powershell
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -ErrorAction SilentlyContinue
Get-ChildItem 'Registry::HKEY_USERS' | Where-Object { $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$' } | ForEach-Object {
    Remove-ItemProperty -Path "Registry::HKEY_USERS\$($_.PSChildName)\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name 'SilentInstalledAppsEnabled' -ErrorAction SilentlyContinue
}
```

### Installing a removed app again later

- **One user:** install it from the Microsoft Store or with winget, the same as any other app.
- **Every user on a machine:** the app's package file (`.appxbundle` or `.msixbundle`) is needed. Removing the provisioned copy can also remove the staged files from the machine, so plan on getting the package file from another source. With the file in hand, run `Add-AppxProvisionedPackage -Online -PackagePath <path to bundle> -SkipLicense` as Administrator.

---

## Exit codes

| Exit code | Meaning |
|---|---|
| `0` | Every app in the list was removed, or was not installed to begin with. |
| `1` | At least one app could not be removed, was a system package, or a `DisableReinstall` setting could not be written. The summary at the end of the log shows which. |
| `2` | A parameter was blank or not valid: no apps, a wildcard, a full package name, or an Option other than `None`, blank, or `DisableReinstall`. |
| `3` | Confirm Count did not match the number of apps. Nothing was removed. |
| `4` | A protected app was in the list. Nothing was removed. |
| `5` | The script is not running as SYSTEM or an administrator. Nothing was removed. |

In Action History, exit codes other than `0` can show as **Failed**. For codes `2` through `5`, that is the script working as intended: it stopped before removing anything.

---

## Requirements

- Windows 10 or Windows 11 endpoints with Windows PowerShell 5.1.
- The action must run as SYSTEM, which is the Tanium default. Without administrator rights, Windows does not show other users' apps, and the script stops with exit code `5` instead of reporting them as not installed.
- A Tanium account with permission to create packages in a content set and deploy actions to the target computers.

---

## Create the package

Menu labels can differ slightly between Tanium versions.

1. Save the script at the bottom of this page as `Remove-StoreApps.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package**.
4. Fill in the fields:
    - **Package Display Name:** `Remove Store Apps` (add your team's prefix if you use one).
    - **Content Set:** the content set your team uses for custom content.
    - **Command:**
      ```
      cmd.exe /d /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Remove-StoreApps.ps1 "$1" "$2" "$3"
      ```
    - **Command Timeout:** `15` minutes. Removing an app for many user profiles, and reading the provisioned app list, can each take a minute or more on a slow disk.
5. Under **Files**, click **Add**, choose **Local File**, and upload `Remove-StoreApps.ps1`.
6. Expand **Parameters**. Under **Parameter Inputs**, add a **Text Input** parameter. It shows in the list as `$1`.
    - **Label:** `Apps`
    - **Provide Help Text:** select it and enter `Package names separated by commas, for example Microsoft.BingNews,Microsoft.BingWeather`
7. Add a **Drop-Down List** parameter. It shows in the list as `$2`.
    - **Label:** `Option`
    - **Provide Help Text:** select it and enter `Leave blank to only remove the apps. DisableReinstall also stops Windows from installing suggested apps.`
    - **Values:** add two entries, in this order: `None`, then `DisableReinstall`. The script treats `None` the same as blank.
8. Add a third **Text Input** parameter. It shows in the list as `$3`.
    - **Label:** `Confirm Count`
    - **Provide Help Text:** select it and enter `Number of apps in the list above, for example 2`
9. In the **Preview** panel on the right, confirm you see **Apps**, then **Option**, then **Confirm Count**.
10. Click **Save**.

---

## Deploy the package

1. In **Interact**, ask a question that returns the computers you want to change. Example:
    ```
    Get Computer Name from all machines with ( Is Windows equals True and Computer Name starts with "nyc-" )
    ```
2. Select the computers in the results grid.
3. Click **Deploy Action**.
4. In **Deployment Package**, search for and select `Remove Store Apps`.
5. In **Apps**, enter the package names, for example `Microsoft.BingNews,Microsoft.BingWeather`.
6. In **Option**, pick `None`, or `DisableReinstall`.
7. In **Confirm Count**, enter the number of apps, for example `2`.
8. Under the schedule, leave it as a one-time action for the first run.
9. Click **Show preview to continue**, review the targets, then click **Deploy Action**.

Start with one test endpoint and read its action log before deploying to a larger group.

---

## View the results

### One endpoint

1. Open the action from **Administration** > **Actions** > **Action History**.
2. Select an endpoint.
3. Open its action log. The script output appears between the `Command Line` line and the `Completed` line. The last lines are a summary with one line per app.

Confirm Count did not match:

```
2026-10-08 11:20:06 [INFO] Apps requested for removal (2):
2026-10-08 11:20:06 [INFO]   - Microsoft.BingNews
2026-10-08 11:20:06 [INFO]   - Microsoft.BingWeather
2026-10-08 11:20:06 [ERROR] Confirm Count '1' does not match the number of apps requested (2). Nothing removed.
```

Protected app in the list:

```
2026-10-08 11:20:05 [ERROR] Protected app(s) requested: Microsoft.WindowsStore. Removing these breaks Windows components. Nothing removed.
```

Full package name instead of the Name:

```
2026-10-08 11:20:03 [ERROR] Invalid app name(s): Microsoft.BingNews_4.55.62231.0_x64__8wekyb3d8bbwe. Use the package Name only (letters, numbers, periods, hyphens). No wildcards or PackageFullName.
```

### Many endpoints

Ask a question with the built-in **Tanium Action Log** sensor, using the action ID from the top of the log:

```
Get Tanium Action Log[12345] from all machines
```

---

## Things to know

- **Parameters arrive URL-encoded.** Tanium passes the comma between app names as `%2C`. The script decodes the values before splitting the list. Without that step, the whole list would be treated as one app name that matches nothing.
- **It runs as 64-bit.** The AppX commands do not work reliably from 32-bit PowerShell. If the Tanium client starts 32-bit PowerShell, the script restarts itself as 64-bit.
- **Results are checked, not assumed.** After each removal the script looks for the app again, so `Removed` in the summary means the app is actually gone.
- **A signed-in user with the app open** may still show the app as present right after removal, which reports as `FAILED`. Run the action again after the user signs out.
- **Feature updates can bring apps back.** See [Stopping apps from coming back](#stopping-apps-from-coming-back).

---

## Test results

Each case ran through `cmd.exe` with URL-encoded parameters, as a standard user. Every case below stops before the removal step, so nothing was removed from the test machine.

| Case | Expected | Result |
|---|---|---|
| Blank app list | Exit 2 | Pass |
| Wildcard name `Microsoft.*` | Exit 2 | Pass |
| Full package name instead of Name | Exit 2 | Pass |
| Typo in Option (`DisableReinstal`) | Exit 2 | Pass |
| Option `None` or `none` | Treated as blank | Pass |
| `Microsoft.WindowsStore` | Exit 4 | Pass |
| VCLibs inside a list with a normal app | Exit 4 | Pass |
| WinAppRuntime, Winget.Source, WidgetsPlatformRuntime | Exit 4 | Pass |
| Confirm Count wrong, not a number, or blank | Exit 3 | Pass |
| Valid list of two apps, not elevated | Exit 5, list parsed as two apps | Pass |
| Same name three times in different case, count `1` | Accepted as one app | Pass |
| `DisableReinstall`, not elevated | Exit 5, no registry change | Pass |
| Run from 32-bit PowerShell with all three values | Restarts as 64-bit, values passed through | Pass |
| Run from 32-bit PowerShell with blank Option and Count | Restarts as 64-bit, exit 3 | Pass |
| Removal for all users, provisioned removal, `DisableReinstall` writes | Removed and verified | **Not tested yet** |

---

## Script

```powershell
--8<-- "tanium/packages/remove-store-apps/Remove-StoreApps.ps1"
```
