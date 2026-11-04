---
tags:
  - Tanium
  - PowerShell
  - Tools
  - Comply
---

# Pseudonymize Exports (Scripts)

This page covers two PowerShell scripts that let you share Tanium exports (Comply findings, Interact question results, Asset reports) without sharing real machine names, and then turn the analysis back into a list of real machines you can act on.

| Script | What it does |
|---|---|
| `Pseudonymize-Exports.ps1` | Replaces every endpoint name with a stable pseudonym such as `SRV-EP001`, masks user profile names, and writes a new CSV next to each input. Builds a private map file of real name to pseudonym |
| `Restore-RealNames.ps1` | Uses the private map file to put the real names back into a CSV that came back from the analysis, such as a remediation plan |

Both scripts run on your own workstation against exported CSV files. They never touch an endpoint, and they never change the original export.

!!! warning "Pseudonymized is not anonymized"
    The scripts hide machine names and user profile names. Everything else in the export stays as it is: IP addresses, domain names, serial numbers, application names, install paths. Read the output before you share it (see [Step 3](#step-3-check-the-output-before-you-share-it)).

---

## Use cases

**Getting help with a vulnerability export.** A Comply export of every finding for one product (for example all Java CVEs) can have thousands of rows across a hundred or more machines. You want an AI assistant, a colleague outside the team, or a consultant to turn it into a plan: which installs to remove, which to upgrade, which machines need more than one fix. Pseudonymize it first, share it, and get the plan back with pseudonyms in it.

**Joining several exports in one analysis.** A findings export says what is vulnerable. An Interact export of running processes says what is in use. An Installed Applications export gives the uninstall strings. The analysis only works if the same machine has the same name in every file. Run all the files through the script together (or one after another with the same map file) and the joins still work.

**Coming back weeks later.** The map file is reused on every run, so a machine that was `WKS-EP014` last month is still `WKS-EP014` in this month's export. You can compare before and after a remediation campaign without re-learning which pseudonym is which.

**Attaching data to a vendor support case.** Send the vendor the rows they need to reproduce a detection problem without giving them your naming convention or user names.

**Turning the plan back into targets.** When the plan comes back, `Restore-RealNames.ps1` puts the real names back, so you can build a computer group or paste the names into an action's target list.

---

## How the pseudonyms work

Each endpoint name becomes the first three characters of the real name, in capitals, followed by `-EP` and a number. Numbering is per prefix, so the prefix still tells you something useful about the machine type when your naming convention puts that at the start.

| Real name | Pseudonym |
|---|---|
| `srv-app01.example.com` | `SRV-EP001` |
| `SRV-APP02` | `SRV-EP002` |
| `wks-0142` | `WKS-EP001` |
| `wks-0187` | `WKS-EP002` |
| `10.0.0.25` | `10.-EP001` |

Rules the script follows:

- **The short name is the key.** `srv-app01.example.com`, `SRV-APP01`, and `srv-app01` are treated as the same machine, so an export that uses FQDNs still joins to one that uses short names. IP addresses are kept whole.
- **One map for everything.** The map file (`Pseudonym-Map.csv`) is loaded at the start of every run and saved at the end. New machines get the next free number. Existing machines keep their pseudonym.
- **Names inside other columns are replaced too.** A UNC path such as `\\srv-app01\share` in another column becomes `\\SRV-EP001\share`. Only names of 4 characters or more are replaced inside other columns, so a short name such as `dc1` does not replace parts of ordinary words.
- **User profile names are masked.** `C:\Users\jdoe\...`, `/home/jdoe/...`, and `/Users/jdoe/...` become `C:\Users\<user>\...` and so on, in every column. This one is not reversible.

!!! tip "Check what your first three characters give away"
    If your naming convention starts with a company, site, or customer code, the prefix alone can identify the organization. Run the script with `-PrefixLength 0` to drop the prefix entirely (pseudonyms become `-EP001`, `-EP002`, ...), or `-PrefixLength 1` to keep only the first character.

!!! note "Why one shared map matters"
    If each export is pseudonymized on its own with its own map, both files will contain `SRV-EP004`, but it will be a different machine in each file. Any analysis that joins the files on the endpoint column is then wrong without any error to warn you. Always use the same map file for every export that belongs to the same analysis.

---

## Before you start

- Windows PowerShell 5.1 or PowerShell 7. No modules are needed.
- Exports saved as CSV. The endpoint column must be named `Endpoint`, `Computer Name`, `Hostname`, or `Host Name`. Comply exports use `Endpoint`; Interact exports use `Computer Name`. For anything else, pass the column name with `-KeyColumns`.
- An Interact question must include **Computer Name** in the question for its export to have a machine column at all. If you exported a question without it, ask it again with Computer Name and export again.
- A folder for the work, for example `C:\Users\<user>\Downloads`. The examples below use `$env:USERPROFILE\Downloads`.

---

## The scripts

=== "Pseudonymize-Exports.ps1"

    ```powershell
    --8<-- "tanium/tools/pseudonymize-exports/Pseudonymize-Exports.ps1"
    ```

=== "Restore-RealNames.ps1"

    ```powershell
    --8<-- "tanium/tools/pseudonymize-exports/Restore-RealNames.ps1"
    ```

---

## Step 1: Save the scripts

1. Click the copy button on the first code block above.
2. Open Notepad, paste, and save as `$env:USERPROFILE\Downloads\Pseudonymize-Exports.ps1` (in the Save dialog, set **Save as type** to **All files** and **Encoding** to **UTF-8**).
3. Repeat for `Restore-RealNames.ps1`.

If you downloaded the files instead of pasting them, unblock them once:

```powershell
Unblock-File "$env:USERPROFILE\Downloads\Pseudonymize-Exports.ps1", "$env:USERPROFILE\Downloads\Restore-RealNames.ps1"
```

## Step 2: Pseudonymize the exports

Open PowerShell, then run the script with every export that belongs to the analysis:

```powershell
cd "$env:USERPROFILE\Downloads"
powershell -ExecutionPolicy Bypass -File .\Pseudonymize-Exports.ps1 -Path ".\Vulnerability Findings.csv", ".\Running Processes.csv"
```

The output looks like this:

```text
Loaded 0 existing pseudonyms from C:\Users\<user>\Downloads\Pseudonym-Map.csv
C:\Users\<user>\Downloads\Vulnerability Findings.csv -> C:\Users\<user>\Downloads\Vulnerability Findings-Pseudonymized.csv (2480 rows, endpoint column 'Endpoint')
C:\Users\<user>\Downloads\Running Processes.csv -> C:\Users\<user>\Downloads\Running Processes-Pseudonymized.csv (64 rows, endpoint column 'Computer Name')
58 endpoints in the map. Keep this file private: C:\Users\<user>\Downloads\Pseudonym-Map.csv
```

Check that:

- Every file you passed has a `->` line. A file that was skipped shows a warning with the column names it found.
- The endpoint count matches what you expect from the Tanium console for that export.

To add another export to the same analysis later, run the script again on the new file. It loads `Pseudonym-Map.csv` from the same folder and keeps every existing pseudonym. If the map is somewhere else, pass it with `-MapPath`.

## Step 3: Check the output before you share it

Open each `-Pseudonymized.csv` file and check:

- [ ] The endpoint column contains only pseudonyms.
- [ ] No column still holds real host names (search the file for a few real names you know are in it).
- [ ] No user names remain outside profile paths, for example in a **Run As**, **Owner**, or **Last Logged In User** column. The script only masks user names inside profile paths.
- [ ] IP addresses, domain names, and serial numbers are either absent or acceptable to share.
- [ ] You are sharing the `-Pseudonymized.csv` files only, never `Pseudonym-Map.csv`.

Remove any column you do not need for the analysis before sharing. Fewer columns means less to check.

## Step 4: Share and analyze

Share the `-Pseudonymized.csv` files. Anything that comes back (a remediation plan, a list of machines per action, notes) will use the same pseudonyms.

## Step 5: Restore the real names

Save the file you got back as CSV in the same folder, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-RealNames.ps1 -Path ".\Remediation-Plan.csv" -MapPath ".\Pseudonym-Map.csv"
```

The result is written to `Remediation-Plan-RealNames.csv` next to the input. Add `-AllColumns` if pseudonyms also appear in free-text columns such as notes, so those are restored too.

If the script warns that some pseudonyms are not in the map, the file was made with a different map file. Find the right map, or pseudonymize the exports again with one shared map and redo the analysis.

---

## Keep the map private

`Pseudonym-Map.csv` is the only link between pseudonyms and real machines. Treat it like the original export:

- Keep it on your own workstation or in a location only your team can read.
- Don't attach it to a ticket, email, or chat that also has the pseudonymized files.
- Delete it when the analysis is finished and you no longer need to compare against later exports.

---

## Troubleshooting

| Message or result | Meaning | What to do |
|---|---|---|
| `Skipped <file> : none of these columns found` | The export has no recognized endpoint column | Ask the Interact question again with **Computer Name**, or pass the column name with `-KeyColumns "Device Name"` |
| `File not found` | The path is wrong or relative to a different folder | Run `cd "$env:USERPROFILE\Downloads"` first, or pass full paths |
| `running scripts is disabled on this system` | Execution policy blocks the script | Use `powershell -ExecutionPolicy Bypass -File ...` as shown |
| The same machine has two pseudonyms | The two exports were made with different map files | Delete the pseudonymized files, keep one map, and run all exports again |
| Excel shows garbled characters | Excel opened the UTF-8 file with the wrong encoding | In Excel, use **Data > From Text/CSV** and pick **65001: Unicode (UTF-8)** |
| `pseudonyms are not in the map` when restoring | The file was produced from exports that used another map | Restore with the map that was used when the exports were pseudonymized |

---

## Limits

- Only the endpoint column, names inside other columns, and user profile paths are changed. Review the rest yourself.
- User name masking is one-way. `Restore-RealNames.ps1` cannot bring `<user>` back.
- Endpoint names shorter than 4 characters are only replaced in the endpoint column, not inside other columns.
- Rows are matched on the short name. Two different machines with the same short name in different domains get the same pseudonym.
