---
tags:
  - Tanium
  - Sensors
  - PowerShell
  - .NET
---

# .NET App Dependencies (Sensor)

This page shows how to create the **.NET App Dependencies** sensor in the Tanium Console, and how to use it to find out which apps use each .NET runtime before you remove or upgrade it.

**What it returns:** one row per app and per .NET framework the app asks for: the framework, the version the app asks for, the rule the app uses to pick a version, the installed version it would actually load, where that copy of .NET comes from, the app's architecture, and where the app was found (IIS site, Windows service, app, or developer tool). Machines with no .NET apps return a single `None found` row.

It covers .NET Core 3.1 and .NET 5 and later (including ASP.NET Core and the Windows Desktop runtime). It does not cover .NET Framework 4.x, which is part of Windows and is fixed by Windows updates.

!!! warning "Test status"
    Run through Tanium on Windows 11 and Windows Server lab endpoints: machines without .NET apps, desktop apps that carry their own .NET, a product that ships a private .NET runtime (SQL Server Management Studio 21), an ASP.NET Core site in IIS outside `C:\inetpub`, two Windows services (one started from its own `.exe`, one through `dotnet.exe`), and an app pinned to a version that is not installed. See [Test results](#test-results).

---

## How the sensor works

Every .NET app (Core 3.1, 5 and later) ships a small file next to its program called `<app>.runtimeconfig.json`. It says which .NET framework the app needs, which version, and how strict the app is about that version. The sensor finds those files, reads them, and works out which installed copy of .NET the app would really load.

1. **Lists the installed .NET runtimes.** It reads the install folder from `HKLM\SOFTWARE\dotnet\Setup\InstalledVersions\<x64 or x86>\InstallLocation` (usually `C:\Program Files\dotnet`) and lists every version under its `shared` folder. Version folders left behind by an uninstall (no `.dll` files inside) are ignored.
2. **Finds the apps.** It looks for `*.runtimeconfig.json` in this order, so the most important places are covered even if time runs out:
    1. IIS site and application folders, from `C:\Windows\System32\inetsrv\config\applicationHost.config`
    2. The folder of every Windows service program, from `HKLM\SYSTEM\CurrentControlSet\Services\<service>\ImagePath`. For a service started as `dotnet.exe <app>.dll`, it uses the folder of the `.dll`
    3. `C:\Program Files`, `C:\Program Files (x86)`, `C:\ProgramData` (except `C:\ProgramData\Microsoft`), and `C:\inetpub`, 5 folder levels deep
    4. Each user profile's `AppData\Local\Programs` and `.dotnet\tools`
    5. Other fixed drives such as `D:\`, 4 folder levels deep
3. **Works out which .NET each app loads.** It applies the same rules .NET uses at startup (see [Roll forward](#roll-forward-in-plain-words)). If no installed shared runtime fits, it looks in the app's own product folder for a private copy of .NET (a folder with `host\fxr` and `shared` inside). Some products ship one and point their own programs at it.
4. **Labels each app** by where it was found: `IIS`, `Service`, `DevTool`, or `App`.

It skips folders that only add noise or time: `C:\Windows`, `C:\Program Files\WindowsApps` (except Store apps that run as a service), the .NET install folder itself, Visual Studio install folders (the Visual Studio Installer updates those), Windows Defender, WinSxS, `node_modules`, `.git`, `Package Cache`, and test runner files named `testhost*`.

The script stops itself after 40 seconds and adds a `Scan incomplete` row naming the folders it did not finish. It also stops scanning any one folder tree after 15,000 folders, so a single huge folder (an agent queue or cache) cannot use the whole time. On a lab laptop with more than 85,000 folders under `C:\Program Files (x86)` the full scan took about 7 seconds.

### Roll forward in plain words

An app does not always need the exact version it was built with. Its **roll forward** setting decides how far .NET may go from the version it asks for:

| Roll Forward | Meaning | Example: app asks for 8.0.0 |
|---|---|---|
| `Minor` (the default) | Same major version, newest patch of the closest minor version | Loads 8.0.33. Will not load 10.0 if 8 is missing |
| `Major` | Same as Minor, but may move to the next major version if its own is missing | Loads 8.0.33, or 10.0 if no 8 is installed |
| `LatestMinor` | Newest version of the same major version | Loads the newest 8.x |
| `LatestMajor` | Newest version installed, any major version | Loads 10.0 if installed |
| `LatestPatch` | Newest patch of the exact minor version | Loads 8.0.x only |
| `Disable` | Exactly the version asked for | Loads 8.0.0 only. Almost never installed, so the app fails |

This is why removing .NET 8 breaks some apps and not others: an app set to `Minor` stops starting, while an app set to `Major` moves to .NET 10 on its own.

---

## Use cases

**Before removing a .NET runtime.** Ask the sensor on the endpoints first. If no row resolves to that version, nothing found on the machine loads it and it can go. If rows do, the App Path, Context, and Category columns tell you which app and who owns it.

**.NET 8 and .NET 9 end of support (November 10, 2026).** Apps set to `Major` or `LatestMajor` move to .NET 10 by themselves once it is installed. Apps set to `Minor` stay on 8 or 9 and need a new build from the vendor or developer.

**Finding .NET that patching never reaches.** Rows with Deployment `SelfContained` or `PrivateRuntime` are apps carrying their own copy of .NET. Updating the shared runtime does not change them, and vulnerability scanners often do not report them. Only an update of that product fixes them.

**Finding apps that are already broken.** `None installed` means the app asks for a .NET version that is not on the machine, shared or private. It fails to start today, or that part of it is never used.

**Fleet view.** One question across all Windows machines lists every IIS site, service, and app running on each .NET major version.

---

## Before you start

- You need a role that can create sensors in the content set you plan to use.
- If a sensor with the same name already exists, edit it instead of creating a second one.
- Copy the script with the copy button on its code block so nothing is changed.

---

## Create the sensor

### Step 1: Open a new sensor

1. Sign in to the Tanium Console.
2. Open the main menu, then go to **Administration > Content > Sensors**.
3. Click **Create Sensor**.

### Step 2: Details section

| Field | Value |
|---|---|
| Name | `.NET App Dependencies` |
| Description | Lists .NET (Core 3.1, 5 and later) apps and the runtime each one actually loads. For every runtimeconfig.json found in IIS site folders, Windows service folders, Program Files, ProgramData, user Programs folders and other fixed drives, returns the framework and version the app asks for, its roll-forward setting, the installed version .NET would pick, whether that comes from the shared install, a private copy in the product folder, or a copy bundled with the app, the app architecture, and the IIS site or service it belongs to. Stops itself after 40 seconds and adds a Scan incomplete row. Returns None found when no .NET apps are found. .NET Framework 4.x is not covered. Read-only. |
| Content Set | Your own custom content set, restricted to your endpoint team |

### Step 3: Settings section

| Field | Value |
|---|---|
| Category | Miscellaneous (or any category you use for custom sensors) |
| Result Type | Text |
| Max Sensor Age | `24` and set the unit dropdown to **Hours** (lower it while you test a change) |
| Max String Age | Leave **Enable** unchecked |
| Max Strings | Leave **Enable** unchecked |
| Ignore case in result values | Checked |
| Hide this sensor from sensor lists and parse results | Unchecked |
| Split into multiple columns | Checked |

### Step 4: Column settings

1. Set **Delimiter** to `|`.
2. Add these 9 columns in this order.

| Index | Column Name | Value Type | Ignore case | Hidden |
|---|---|---|---|---|
| 0 | Framework | Text | Checked | Unchecked |
| 1 | Requested | Text | Checked | Unchecked |
| 2 | Roll Forward | Text | Checked | Unchecked |
| 3 | Resolves To | Text | Checked | Unchecked |
| 4 | Deployment | Text | Checked | Unchecked |
| 5 | Arch | Text | Checked | Unchecked |
| 6 | Category | Text | Checked | Unchecked |
| 7 | Context | Text | Checked | Unchecked |
| 8 | App Path | Text | Checked | Unchecked |

**Requested** and **Resolves To** are Text, not Version, because they can hold `None installed`, `8.0.21 (private)`, or `10.0.14 (bundled)`.

### Step 5: Parameters section

None. Leave this section empty.

### Step 6: Scripts section

| Platform | Enable | Query Type | Script |
|---|---|---|---|
| Windows | Checked | PowerShell | Windows script below |
| Linux | Checked | UnixShell | Stub below |
| Mac | Checked | UnixShell | Stub below |
| Solaris | Checked | UnixShell | Stub below |
| AIX | Checked | UnixShell | Stub below |

Set **Timeout** to `60` seconds, above the script's own 40-second limit.

=== "Windows (PowerShell)"

    ```powershell
    --8<-- "tanium/sensors/dotnet-app-dependencies/windows.ps1"
    ```

=== "Linux, Mac, Solaris, AIX (UnixShell)"

    ```sh
    #!/bin/sh
    echo "Not Applicable||||||||"
    ```

The tunable values are at the top of the Windows script: the 40-second time budget, the folder depths, and the 15,000-folder cap per folder tree.

### Step 7: Save

Scroll to the bottom of the page and click **Save**.

### Step 8: Test

1. Go to **Interact**.
2. Ask:

    ```text
    Get Computer Name and .NET App Dependencies from all machines with Computer Name contains "<test machine>"
    ```

3. Check that you see 9 columns, and either one row per app or a single `None found` row.

---

## Ask the question

If you gave the sensor a different name (for example with a `Lab - ` prefix), use that name in every question below.

All Windows machines:

```text
Get Computer Name and .NET App Dependencies from all machines with Is Windows equals True
```

Everything that loads .NET 8 (change `8.` to the major version you want to remove):

```text
Get Computer Name and .NET App Dependencies from all machines with .NET App Dependencies:Resolves To starts with "8."
```

Apps that carry their own copy of .NET:

```text
Get Computer Name and .NET App Dependencies from all machines with .NET App Dependencies:Deployment equals "SelfContained"
Get Computer Name and .NET App Dependencies from all machines with .NET App Dependencies:Deployment equals "PrivateRuntime"
```

Apps that cannot find the .NET they need:

```text
Get Computer Name and .NET App Dependencies from all machines with .NET App Dependencies:Resolves To equals "None installed"
```

IIS sites on .NET:

```text
Get Computer Name and .NET App Dependencies from all machines with .NET App Dependencies:Category equals "IIS"
```

To save the results, click **Export** above the results grid and choose **CSV**. Keep **Computer Name** in the question so the export has a machine column. The [.NET Remediation Plan](../tools/dotnet-remediation-plan.md) tool reads that export.

---

## Reading the results

| Column | What it tells you |
|---|---|
| Framework | `Microsoft.NETCore.App` (base runtime), `Microsoft.AspNetCore.App` (web apps), or `Microsoft.WindowsDesktop.App` (Windows Forms and WPF apps). An app can ask for more than one, so it can have more than one row |
| Requested | The version written in the app's runtimeconfig.json, usually `x.0.0` |
| Roll Forward | How strict the app is about the version. See [Roll forward in plain words](#roll-forward-in-plain-words). `n/a` for apps that bundle .NET |
| Resolves To | The installed version .NET would load for this app. `(private)` means a copy inside the product folder, `(bundled)` a copy inside the app itself. `None installed` means nothing fits |
| Deployment | `FrameworkDependent` (uses the shared .NET install), `PrivateRuntime` (uses a copy inside the product folder), or `SelfContained` (the app carries its own .NET) |
| Arch | Architecture of the app's program file. `x64 (dotnet.exe)` means the app has no `.exe` of its own and is started through `dotnet.exe` |
| Category | `IIS`, `Service`, `DevTool` (Visual Studio Code, JetBrains, NuGet, .NET tools), or `App` |
| Context | The IIS site (`IIS: <site>/<app>`) or service name (`Service: <name>`), and for private copies the folder of that copy (`Runtime: <path>`) |
| App Path | The runtimeconfig.json file. Developer tools are shortened to one row per product folder |

Example rows (values are illustrative):

```text
Microsoft.AspNetCore.App|8.0.0|Minor|8.0.33|FrameworkDependent|x64|IIS|IIS: www.example.com|D:\Sites\Example\Example.Web.runtimeconfig.json
Microsoft.NETCore.App|8.0.0|Minor|8.0.33|FrameworkDependent|x64|Service|Service: ExampleSvc|C:\Program Files\Example\ExampleSvc.runtimeconfig.json
Microsoft.NETCore.App|8.0.0|Major|8.0.21 (private)|PrivateRuntime|x64|DevTool|Runtime: C:\Program Files\Microsoft SQL Server Management Studio 21\Release\dotnet\net8.0\runtime|C:\Program Files\Microsoft SQL Server Management Studio 21\Release\Common7\ServiceHub\Controller
Microsoft.NETCore.App|10.0.14|n/a|10.0.14 (bundled)|SelfContained|x64|App||C:\Program Files\ExampleApp\ExampleApp.runtimeconfig.json
Microsoft.NETCore.App|8.0.0|Disable|None installed|FrameworkDependent|x64 (dotnet.exe)|Service|Service: ExampleWorker|C:\Apps\ExampleWorker\ExampleWorker.runtimeconfig.json
None found||||||||
```

### What to do with a row

| What you see | Meaning | Next step |
|---|---|---|
| No row resolves to the version you want to remove | Nothing found on the machine loads it | Remove that runtime. On servers, confirm with the owner first (see [Limits](#limits)) |
| `FrameworkDependent`, Roll Forward `Major` or `LatestMajor` | The app moves to a newer major version by itself | Install the newer .NET first, then remove the old one. Test on one machine |
| `FrameworkDependent`, Roll Forward `Minor` | The app stays on its major version | Keep that version patched. Moving off it needs a new build of the app from the vendor or developer |
| `SelfContained` or `PrivateRuntime` | The product carries its own .NET | Update the product. Updating the shared runtime does not change it |
| `None installed` | The app cannot start, or that part of it is never used | Ask the app owner whether it is still in use before installing anything for it |

The full decision guide is in [.NET Runtimes](../remediation/dotnet-runtimes.md).

---

## Troubleshooting

| Result | Meaning | What to do |
|---|---|---|
| `Scan incomplete` row | Time ran out, or one folder tree hit the 15,000-folder cap. The row names the folders that were not finished | Rows above it are still valid. If one folder is always named (an agent queue, a cache), add its folder name to `$skipNames` in the script |
| `TSE-Error: Sensor evaluation timed out` | The sensor **Timeout** is below 60 seconds | Edit the sensor and recheck Step 6 |
| `TSE-Error: No Sensor Definition for this Platform` | The Linux, Mac, Solaris, or AIX script tab was left empty | Edit the sensor and add the stub script to those tabs (Step 6) |
| All values in one column | The column split was not saved | Edit the sensor and recheck Step 4 |
| `Unreadable runtimeconfig` | The file could not be read as JSON | Seen on old copies that products leave behind after an update. If the App Path is a live app, check the file with the vendor |
| `Unparsed version` | The app asks for a four-part version such as `8.0.0.0` | Read the Roll Forward column. `Major` or `LatestMajor` means the app takes the newest .NET installed |
| `None installed` for an app you know works | The product uses a private copy of .NET in a layout the sensor does not recognize | Look for the private copy with [Find File by Name](find-file-by-name.md), for example `Find File by Name[hostfxr.dll,C:\Program Files\<Product>,]` |

---

## Limits

- **.NET Framework 4.x is not covered.** It is part of Windows. Windows updates fix it.
- **Only the folders listed in [How the sensor works](#how-the-sensor-works) are searched.** An app started by a scheduled task or from another folder on `C:\` (for example `C:\Tools`) is not found. Check those with [Scheduled Tasks - By Command](scheduled-tasks-by-command.md) and [Running Processes - Paths - Hashes](running-processes-paths-hashes.md) (look for `\dotnet\dotnet.exe` in the Path column).
- **Installed runtimes that nothing uses get no row.** The sensor lists apps, not runtimes. A runtime that appears in your vulnerability findings but in no **Resolves To** value is the one nothing uses.
- **Old version folders show up as apps.** Some products keep old copies after updating. Dell TechHub, for example, keeps `C:\Program Files\Dell\DTP\<Component>Deps\<version>` folders that often show `None installed`. The copies in use are in the `<Component>SubAgent` folders.
- **Tools inside NuGet package folders show up as apps.** A site folder that contains `packages\<package>\tools\` (for example the Entity Framework `ef6` tool) gives a row that is not a real app.
- **Context shows the first match.** A folder used by two IIS sites shows only one of them.

---

## Test results

| Case | Expected | Result |
|---|---|---|
| Windows PowerShell 5.1 parser | No errors | Pass |
| Domain controller and clients without .NET apps | `None found` | Pass |
| Laptop with desktop apps that bundle .NET 8 and .NET 10 | `SelfContained`, `(bundled)` | Pass |
| First version on a laptop with more than 85,000 folders under one agent folder | Finish inside the time limit | Failed (`Scan incomplete` after 12,000 folders). Fixed with the folder depth, the 15,000-folder cap, and skipping Visual Studio folders. Full scan now about 7 seconds |
| First version on Visual Studio Build Tools | Useful rows only | Failed (16 rows of test runner noise). Fixed by skipping Visual Studio folders and `testhost*` files |
| SQL Server Management Studio 21, no shared .NET installed | `8.0.21 (private)`, `PrivateRuntime` | First version showed `None installed`. Fixed with the private-runtime check. Pass |
| Product with a private copy that lacks one framework | That framework still `None installed` | Pass |
| ASP.NET Core site in IIS at `C:\Sites` (outside `C:\inetpub`) | Category `IIS`, Context `IIS: <site>` | Pass |
| Service started from its own `.exe` | Category `Service`, Arch `x64` | Pass |
| Service started as `dotnet.exe <app>.dll` | Category `Service`, Arch `x64 (dotnet.exe)` | Pass |
| ASP.NET Core app asking for 8.0.0, Roll Forward `Minor`, 8.0.33 installed | Two rows (`AspNetCore.App` and `NETCore.App`), both `8.0.33` | Pass |
| Same app changed to Roll Forward `Disable` | `None installed` on that app only | Pass |
| Through Tanium as SYSTEM | Same rows as a local run | Pass |

---

## Related

- [.NET Runtimes](../remediation/dotnet-runtimes.md): what to do with each kind of .NET finding
- [.NET Remediation Plan](../tools/dotnet-remediation-plan.md): turns a findings export and this sensor's export into a plan per endpoint
- [Scheduled Tasks - By Command](scheduled-tasks-by-command.md) and [Running Processes - Paths - Hashes](running-processes-paths-hashes.md): find .NET apps started from folders this sensor does not search
- [Pseudonymize Exports](../tools/pseudonymize-exports.md): share the exports without real machine names
