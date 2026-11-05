---
tags:
  - Tanium
  - Tools
  - Comply
  - .NET
---

# .NET Remediation Plan (Tool)

This page covers a browser tool that turns two Tanium exports into a remediation plan for .NET vulnerabilities, one row per endpoint and product:

- the **vulnerability findings** from Tanium Comply (what is vulnerable), and
- the **[.NET App Dependencies](../sensors/dotnet-app-dependencies.md) sensor** results from Interact (what uses it).

For each row the tool says what to do (patch, remove, update, move to .NET 10, or hand to the app owner), why, which apps on that endpoint use the runtime, and who does the work. It follows the rules on the [.NET Runtimes](../remediation/dotnet-runtimes.md) page.

**[Open the .NET Remediation Plan tool](dotnet-plan-tool.html)**

!!! note "Your data stays on your computer"
    The tool reads the CSV files in your browser. Nothing is uploaded or saved anywhere, and reloading the page clears it. The page needs internet access once to load its CSV reader and fonts.

---

## Use cases

**Monthly .NET findings.** Instead of deciding endpoint by endpoint, load both exports and work the plan from the top: known exploited findings first, then quick removals.

**Before the .NET 8 and .NET 9 end of support (November 10, 2026).** The plan separates apps that move to .NET 10 by themselves from apps that need a new build from the vendor.

**After a remediation round.** Ask the sensor again, export both files again, and load them. Fixed rows disappear, and endpoints that were offline the first time get real decisions.

**Finding .NET the scan does not report.** The tool lists copies of .NET that products carry in their own folders, and out-of-support runtimes missing from the findings.

---

## Before you start

You need two CSV files.

### Vulnerability findings (Comply)

Export the findings for the .NET CVEs from Tanium Comply as CSV.
<!-- TODO: add the exact Comply menu path for this export -->

The tool needs these columns. Extra columns are ignored.

| Column | Used for |
|---|---|
| `Check ID` | The CVE |
| `Endpoint` | Matching the findings to the sensor results |
| `Detected Products` | Sorting the finding into .NET Framework, a .NET runtime, an SDK, or another product |
| `Operating System Generation` | Windows 10, Windows 11 and server rules |
| `CISA KEV` | Priority 1 |
| `CVSS Base Score (v3)` | Priority 2 to 4 |
| `EPSS Score` | Shown in the row details |

### Sensor results (Interact)

1. In **Interact**, ask:

    ```text
    Get Computer Name and .NET App Dependencies from all machines with Is Windows equals True
    ```

2. When the results have come in, click **Export** above the results grid and choose **CSV**.

**Computer Name** must be in the question so the export has a machine column. If your sensor has a different name (for example with a `Lab - ` prefix), that is fine: the tool finds the columns by their ending (`:Framework`, `:Resolves To`, and so on).

### Optional: hide machine names

If you share the files or the plan, run both exports through [Pseudonymize Exports](pseudonymize-exports.md) first, **with one shared map file**, so the same machine has the same pseudonym in both files. Otherwise the tool cannot match findings to sensor results.

---

## Use the tool

1. [Open the tool](dotnet-plan-tool.html).
2. Drag both CSV files onto **Drop one or both CSV exports here**, or click **Choose CSV files** and select them. The tool tells the two files apart by their columns. Load just one file to replace only that one.
3. Check the two boxes under the drop area: each one shows the file name, the number of rows, and the number of endpoints. Compare the endpoint counts with what the Tanium Console showed.
4. Read the summary from the top down:

| Section | What it shows |
|---|---|
| Summary numbers | Endpoints with findings, plan rows, rows with a known exploited (KEV) finding, endpoints still missing sensor data |
| Red or green box | How many endpoints with runtime findings have a sensor result. Red means some decisions are missing |
| Runtime decisions backed by the sensor | One line per action, with the endpoints and the apps that drove it |
| Every endpoint and component | The full plan. Filter by priority, action, or sensor result, or search for an endpoint, app, or product. Click a row to see why, the apps found, and the finding numbers |
| Not in the vulnerability scan | .NET copies inside product folders, and out-of-support runtimes missing from the findings |
| Run the sensor on these endpoints | Endpoints with runtime findings and no sensor result |

5. Click **Download plan (CSV)** to save the rows that match your current filters. The file has empty **Status** and **Notes** columns for tracking.

### Put the real names back

If you pseudonymized the exports, run the downloaded plan through `Restore-RealNames.ps1` from [Pseudonymize Exports](pseudonymize-exports.md#step-5-restore-the-real-names). The plan's machine column is named `Endpoint`, which the script recognizes:

```powershell
cd "$env:USERPROFILE\Downloads"
powershell -ExecutionPolicy Bypass -File .\Restore-RealNames.ps1 -Path ".\NET-Remediation-Plan-<date>.csv" -MapPath ".\Pseudonym-Map.csv" -AllColumns
```

`-AllColumns` also restores names that appear in the **Why** and **Apps** text.

---

## How rows are decided

| Priority | Rule |
|---|---|
| 1 | The finding is on the CISA Known Exploited Vulnerabilities list |
| 2 | CVSS 9.0 or higher |
| 3 | CVSS 7.0 or higher |
| 4 | Everything else |

The action for each row follows the tables on [.NET Runtimes](../remediation/dotnet-runtimes.md#decide). The tool adds these checks:

- **A runtime counts as used** only when the sensor shows an app on that endpoint that loads it from the shared .NET install. Apps with their own copy of .NET do not count.
- **Old version folders do not count as use.** When a folder holds several numbered copies of the same product, only the newest counts. Dell TechHub's `<Component>Deps\<version>` folders never count, because the copies in use are in its `<Component>SubAgent` folders.
- **Tools inside NuGet package folders** (`\packages\<package>\tools\`) do not count.
- **Before suggesting a removal**, it checks for apps with an unreadable version that are set to use the newest .NET installed, and says to check first.
- **On servers**, every removal says to confirm with the owner first.
- **Confidence:** `Certain` means the action follows from the data or vendor documentation. `Likely` means a strong inference that you should check before acting.

---

## Limits

- The tool knows a few products by name (PowerShell 7, WSL, Store apps, Dell, UiPath, Autodesk) and suggests a specific update for them. Other products get a general "update or retire it" action.
- It only knows what the two exports contain. An endpoint that was offline when the sensor question was asked gets "Run the sensor first" for every runtime row.
- It carries the [sensor's limits](../sensors/dotnet-app-dependencies.md#limits): apps started from folders the sensor does not search are not seen, so a server removal still needs the owner's confirmation.
- Product names in `Detected Products` are matched by pattern (`Desktop Runtime 8.0`, `Hosting Bundle 8.0`, `SDK 10.0`, and so on). A product name the tool does not recognize gets a row with the action "Review".
- Support dates are written into the tool. Check them again after November 2026.

---

## Troubleshooting

| Message or result | Meaning | What to do |
|---|---|---|
| `<file> is neither export` | The file has none of the expected columns | Check the column names listed in [Before you start](#before-you-start). For the sensor export, ask the question again with **Computer Name** |
| `The CSV reader did not load` | The page could not reach `cdnjs.cloudflare.com` | Check your internet connection or proxy, then reload the page |
| Every runtime row says "Run the sensor first" | No sensor file is loaded, or the machine names differ between the two files | Load the sensor export. If you pseudonymized, use one shared map file for both exports |
| Fewer endpoints than expected in the sensor box | Machines were offline when the question was asked | Ask again later and export again. Those endpoints are listed under **Run the sensor on these endpoints** |
| The download does nothing | The browser blocked the download | Allow downloads for the site and click **Download plan (CSV)** again |

---

## Related

- [.NET App Dependencies](../sensors/dotnet-app-dependencies.md)
- [.NET Runtimes](../remediation/dotnet-runtimes.md)
- [Pseudonymize Exports](pseudonymize-exports.md)
