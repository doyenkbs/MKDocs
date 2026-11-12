---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Adobe
  - Node.js
---

# Update Node.js in Adobe Creative Cloud (Package)

Two Tanium packages that swap the old `node.exe` files inside Adobe Creative Cloud for the patched builds from nodejs.org, while keeping the same major version.

Creative Cloud ships its own private copies of Node.js. Vulnerability scanners flag them like any other Node.js install. For example, Tanium Comply flags them for CVE-2026-111497 (a Brotli flaw). Installing or updating Node.js from nodejs.org does not touch these copies, because they sit inside Adobe's own folders. Until Adobe ships an update, the only fix is to replace the file.

| Package | File it replaces | Node.js line | Fixed in |
|---|---|---|---|
| Update Node.js in Adobe CC Libraries | `C:\Program Files\Common Files\Adobe\Creative Cloud Libraries\libs\node.exe` | 22.x | 22.23.4 |
| Update Node.js in Adobe CC Experience | `C:\Program Files\Adobe\Adobe Creative Cloud Experience\libs\node.exe` | 24.x | 24.22.1 |

!!! warning "Test status"
    Tested through Tanium on one Windows computer with Creative Cloud open. Both files were replaced, Creative Cloud kept working, and the old file was gone after a restart. **A Comply scan after the fix has not been checked yet.** See [Test results](#test-results).

!!! note "Adobe doesn't support this"
    This changes files inside Adobe's install folders. If a user opens a ticket with Adobe, Adobe may ask them to repair Creative Cloud first. A Creative Cloud update or repair puts Adobe's own `node.exe` back, which can bring the old version back too.

---

## What the script does

First it checks that the swap is safe. If any check fails, it stops and changes nothing:

1. **Is the Adobe file there?** If not, there's nothing to do.
2. **Is the `node.exe` in the package correct?** It must be the same major version (22 or 24), at or above the fixed version, and the 64-bit (x64) build.
3. **Does the installed `node.exe` need it?** It must be the same major version and older than the fixed version. The script does not touch a newer file. The script never replaces a different major version, because Adobe add-ons work only with the Node.js version that they were built for.
4. **Is the installed `node.exe` 64-bit?** The package has only the x64 build. Thus, the script skips ARM computers.

If everything is fine, it:

1. Renames the old `node.exe` to `node-<old version>-<date and time>.replaced`. Windows allows this even while Creative Cloud is using the file, so the user is not interrupted.
2. Copies the new `node.exe` in and checks that it matches the package file exactly.
3. Deletes the old file. If Creative Cloud is still using it, Windows deletes it at the next restart.

If the copy fails, the script renames the old file back so Creative Cloud keeps working. It only closes Adobe's `node.exe` if the rename fails, and only the copy running from that exact folder.

Every step is written to the Tanium action log. No backup is kept. Repairing or reinstalling Creative Cloud restores Adobe's own file.

!!! info "The scan clears before the old code stops"
    The file on disk changes right away, so Tanium and Comply show the new version straight away. A Creative Cloud process that was already running keeps using the old code until Creative Cloud restarts, the user signs out, or the computer restarts. The action log says so when this happens.

---

## Exit codes

The exit code tells you how the action ended. You'll find it at the end of the action log.

| Exit code | Meaning |
|---|---|
| `0` | The file was replaced, was already patched, or Creative Cloud isn't installed. |
| `1` | The swap failed. The original was put back. Look for `[ERROR]` in the action log. |
| `2` | Skipped. The installed `node.exe` is a different major version or isn't 64-bit. Nothing was changed. |
| `3` | The `node.exe` in the package is missing, the wrong version, or not 64-bit. Nothing was changed. |
| `5` | The script didn't run as SYSTEM or an administrator. Nothing was changed. |

---

## Get node.exe

Each package needs its own `node.exe` from nodejs.org, the plain Windows x64 file.

1. Download the file for each package. Use the version from the table above or a newer one in the same line:
    - `https://nodejs.org/dist/v22.23.4/win-x64/node.exe`
    - `https://nodejs.org/dist/v24.22.1/win-x64/node.exe`
2. Save each file in a different folder, because both files have the name `node.exe`.
3. Check each file before you upload it. In PowerShell, in the folder with the file:
    ```powershell
    (Get-Item .\node.exe).VersionInfo.FileVersion
    (Get-FileHash .\node.exe -Algorithm SHA256).Hash
    (Get-AuthenticodeSignature .\node.exe).SignerCertificate.Subject
    ```
4. Compare the hash with the `win-x64/node.exe` line in `SHASUMS256.txt` for that version, for example `https://nodejs.org/dist/v22.23.4/SHASUMS256.txt`. The signer should be `CN=OpenJS Foundation`.

---

## Create the packages

1. Save the two [scripts](#scripts) at the bottom of this page as `Update-AdobeCCLibrariesNode.ps1` and `Update-AdobeCCXNode.ps1`.
2. In the Tanium Console, go to **Administration** > **Content** > **Packages**.
3. Click **Create Package** and fill in the fields below. Repeat for the second package.

=== "CC Libraries (Node.js 22)"

    | Field | Value |
    |---|---|
    | Package Name | `<prefix> - Update Node.js in Adobe CC Libraries (Windows)` |
    | Display Name | `<prefix> - Update Node.js in Adobe CC Libraries (Windows)` |
    | Description | `Replaces node.exe in C:\Program Files\Common Files\Adobe\Creative Cloud Libraries\libs with Node.js 22.23.4 x64. Only replaces Node 22.x older than 22.23.4. Exit 0 updated or nothing to do, 1 failed and restored, 2 skipped, 3 bad package file, 5 not admin.` |
    | Content Set | The content set your team uses for custom content |
    | Command | `cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Update-AdobeCCLibrariesNode.ps1` |
    | Command Timeout | `10` minutes |
    | Download Timeout | `30` minutes. `node.exe` is about 85 MB |
    | Ignore Action Lock | Unchecked |
    | Launch this package command in a process group | Checked |
    | Files | Click **Add File**, choose **Local File**, upload `Update-AdobeCCLibrariesNode.ps1`. Repeat for the Node.js 22 `node.exe`. The name must stay exactly `node.exe` |
    | Parameters | None |

=== "CC Experience (Node.js 24)"

    | Field | Value |
    |---|---|
    | Package Name | `<prefix> - Update Node.js in Adobe CC Experience (Windows)` |
    | Display Name | `<prefix> - Update Node.js in Adobe CC Experience (Windows)` |
    | Description | `Replaces node.exe in C:\Program Files\Adobe\Adobe Creative Cloud Experience\libs with Node.js 24.22.1 or newer x64. Only replaces Node 24.x older than 24.22.1. Exit 0 updated or nothing to do, 1 failed and restored, 2 skipped, 3 bad package file, 5 not admin.` |
    | Content Set | The content set your team uses for custom content |
    | Command | `cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Update-AdobeCCXNode.ps1` |
    | Command Timeout | `10` minutes |
    | Download Timeout | `30` minutes. `node.exe` is about 90 MB |
    | Ignore Action Lock | Unchecked |
    | Launch this package command in a process group | Checked |
    | Files | Click **Add File**, choose **Local File**, upload `Update-AdobeCCXNode.ps1`. Repeat for the Node.js 24 `node.exe`. The name must stay exactly `node.exe` |
    | Parameters | None |

4. Click **Save**.

!!! tip "Changed the script later?"
    Tanium keeps its own copy of each uploaded file. After you edit a script, edit the package and upload the file again, or endpoints keep running the old copy.

---

## Deploy

1. In **Interact**, see which computers have the old files:
    ```text
    Get Computer Name and File Version[C:\Program Files\Common Files\Adobe\Creative Cloud Libraries\libs\node.exe] and File Version[C:\Program Files\Adobe\Adobe Creative Cloud Experience\libs\node.exe] from all machines with Installed Applications:Name contains "Adobe Creative Cloud"
    ```
2. Select the computers, click **Deploy Action**, and choose one of the two packages. Deploy the other package the same way.
3. Click **Show preview to continue**, then **Deploy Action**.
4. To see what happened, go to **Administration** > **Actions** > **Action History**, open the action, select a computer, and read the action log.

Both packages are safe to run on every computer with Creative Cloud. Computers that are already patched, or that don't have the file, end with exit code `0` and nothing changed. Because a Creative Cloud update or repair can bring the old file back, set the action to run again every day under **Schedule Deployment** on the deploy page.

### Example output

Creative Cloud Experience, with Creative Cloud open:

```text
[INFO] Component: Adobe Creative Cloud Experience
[INFO] Target: C:\Program Files\Adobe\Adobe Creative Cloud Experience\libs\node.exe
[INFO] Package node.exe: version 24.22.2, x64
[INFO] Package node.exe signature: Valid, signed by: CN=OpenJS Foundation, O=OpenJS Foundation, L=San Francisco, S=California, C=US
[INFO] Installed node.exe: version 24.19.0, x64
[INFO] Renamed the old node.exe to node-24.19.0-20261106022604.replaced
[INFO] Copied in node.exe 24.22.2 and confirmed the file hash.
[INFO] The old node.exe is still in use by a running Adobe process. It will be deleted at the next restart.
[INFO] 1 node.exe process(es) from this folder are still running the old code (PID 1884). They switch to the new file when Creative Cloud restarts, the user signs out, or the machine restarts.
[INFO] Done. Adobe Creative Cloud Experience node.exe updated from 24.19.0 to 24.22.2.
```

Creative Cloud Libraries, where nothing was using the old file:

```text
[INFO] Component: Adobe Creative Cloud Libraries
[INFO] Target: C:\Program Files\Common Files\Adobe\Creative Cloud Libraries\libs\node.exe
[INFO] Package node.exe: version 22.23.4, x64
[INFO] Installed node.exe: version 22.23.2, x64
[INFO] Renamed the old node.exe to node-22.23.2-20261106023244.replaced
[INFO] Copied in node.exe 22.23.4 and confirmed the file hash.
[INFO] Deleted the old node.exe.
[INFO] Done. Adobe Creative Cloud Libraries node.exe updated from 22.23.2 to 22.23.4.
```

---

## Things to know

- **A `.replaced` file in the folder is normal** until the next restart. Scanners look for files named `node.exe`, so they don't count it. The next run of the package also deletes it if nothing is using it.
- **Adobe may move to a new Node.js major version.** When that happens the script skips the computer with exit code `2`. Check whether Adobe's new version is already patched before you build a new package.
- **When Adobe ships a fixed version, stop the schedule.** Then Adobe's own updates take over.

---

## Test results

| What was tested | Expected | Result |
|---|---|---|
| Scripts checked for syntax errors | No errors | Pass |
| CC Experience, Creative Cloud open | File replaced, old file set to delete at restart, exit 0 | Pass |
| CC Libraries, nothing using the file | File replaced, old file deleted right away, exit 0 | Pass |
| Restart after the CC Experience run | `.replaced` file gone | Pass |
| File Version sensor right after the action | Shows the new version | Pass |
| Creative Cloud after the swap | Keeps working | Pass |
| Comply scan after the fix | CVE no longer lists the Node.js tests | **Not tested yet** |
| Run again on a patched computer | Exit 0, nothing changed | **Not tested yet** |

---

## Scripts

=== "Update-AdobeCCLibrariesNode.ps1"

    ```powershell
    --8<-- "tanium/packages/update-adobe-cc-node/Update-AdobeCCLibrariesNode.ps1"
    ```

=== "Update-AdobeCCXNode.ps1"

    ```powershell
    --8<-- "tanium/packages/update-adobe-cc-node/Update-AdobeCCXNode.ps1"
    ```
