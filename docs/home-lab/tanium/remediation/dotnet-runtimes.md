---
tags:
  - Tanium
  - Tanium Comply
  - Vulnerability Remediation
  - .NET
---

# .NET Runtimes

Tanium Comply reports .NET under several product names, and each one is fixed a different way. One CVE can show up as `.NET Framework`, `.NET Desktop Runtime 8.0`, `ASP.NET Core Hosting Bundle 8.0`, `.NET SDK 10.0`, and `SDK from Visual Studio` on the same day. Patching the shared .NET runtime clears some of these and not others, and removing a runtime is safe on one machine and breaks an app on the next.

This page sorts each finding into one action: patch, remove, update, move to a newer .NET, or hand to the app owner.

---

## Support dates

| .NET | Support ends | What it means |
|---|---|---|
| .NET Framework 4.6.2 to 4.8.1 | Follows the Windows version | Part of Windows. Fixed by the monthly Windows update for .NET Framework |
| .NET 10 (LTS) | November 2028 | Supported. Keep it patched |
| .NET 9 (STS) | **November 10, 2026** | No fixes after this date |
| .NET 8 (LTS) | **November 10, 2026** | No fixes after this date |
| .NET 6 | November 12, 2024 | Out of support. Some vendors (for example HeroDevs) sell paid updates |
| .NET Core 3.1 | December 13, 2022 | Out of support. Scanners often stop reporting it |
| PowerShell 7.4 | November 10, 2026 | Carries its own .NET 8. PowerShell 7.6 LTS runs on .NET 10 and is supported to November 14, 2028 |

Sources: [.NET 8 and .NET 9 end of support](https://devblogs.microsoft.com/dotnet/dotnet-8-9-end-of-support/), [PowerShell support lifecycle](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle).

---

## Find the scope

You need two exports: what is vulnerable (Comply) and what uses it (the sensor).

1. **Comply findings.** Export the vulnerability findings for the .NET CVEs from Tanium Comply as CSV. The export must have these columns: `Check ID`, `Endpoint`, `Operating System Generation`, `CISA KEV`, `CVSS Base Score (v3)`, `EPSS Score`, `Detected Products`.
   <!-- TODO: add the exact Comply menu path for this export -->
2. **Sensor results.** In **Interact**, ask the [.NET App Dependencies](../sensors/dotnet-app-dependencies.md) sensor on the same endpoints, then click **Export** above the results grid and choose **CSV**:

    ```text
    Get Computer Name and .NET App Dependencies from all machines with Is Windows equals True
    ```

3. **Endpoints that did not answer.** Machines that are offline when you ask have no sensor result. Ask again later and export again. Without a sensor result, a runtime finding cannot be decided.
4. **Optional, sharing the data.** To get help from someone outside your team, run both files through [Pseudonymize Exports](../tools/pseudonymize-exports.md) with one shared map file.
5. **Build the plan.** Load both CSV files into the [.NET Remediation Plan](../tools/dotnet-remediation-plan.md) tool. It applies the rules below to every endpoint.

---

## Decide

Work through each endpoint and each product in its findings.

### .NET Framework

| What you find | Action |
|---|---|
| Supported Windows version | Install the latest .NET Framework cumulative update with Tanium Patch |
| Windows 10 | Windows 10 support ended October 14, 2025. Without Extended Security Updates (ESU) there is no fix. Upgrade to Windows 11 |
| Windows 11 23H2 (build 22631) | Pro and Home ended November 2025. Enterprise and Education get their last update November 10, 2026. Move the device to 25H2 |

### .NET runtimes (Desktop Runtime, .NET Runtime, ASP.NET Core, Hosting Bundle)

Ask the sensor on the endpoint first, then match the result:

| Sensor result for that major version | Action |
|---|---|
| No row resolves to it | Remove that runtime. Nothing found on the machine loads it. On servers, confirm with the owner first: the sensor does not see apps started by scheduled tasks or from folders it does not search |
| Rows resolve to .NET 10 | Update to the latest .NET 10 patch |
| Rows resolve to .NET 8 or 9, every app set to `Major` or `LatestMajor` | Install .NET 10, then remove .NET 8 or 9. Those apps move to .NET 10 by themselves. Test on one machine first |
| Rows resolve to .NET 8 or 9, any app set to `Minor` | The vendor or developer needs to ship a .NET 10 build. Until then, install the final .NET 8 or 9 patch and record a risk exception in Comply |
| Rows resolve to .NET 6 or older | Out of support. The app owner upgrades or retires the app |
| No sensor result for the endpoint | Ask the sensor again when the machine is online. Do not remove anything yet |

!!! tip "Stopgap for an app stuck on .NET 8"
    Setting `"rollForward": "Major"` in the app's `runtimeconfig.json` makes it start on .NET 10. It often works for ASP.NET Core apps and services, but the vendor may not support it, and the next app update overwrites the file. Test it in a lab, never straight in production.

### SDK and Visual Studio

| What you find | Action |
|---|---|
| `SDK x.0 from Visual Studio` or `Visual Studio 20xx` | Update Visual Studio with the Visual Studio Installer, or remove Visual Studio if the machine is not used for development |
| `.NET SDK x.0` on a developer or build machine | Update the SDK to the latest patch |
| `.NET SDK x.0` on any other machine | Remove the SDK. If the sensor shows apps loading the .NET version that came with it, install the matching **Desktop Runtime** first, so those apps keep working after the SDK is gone |

### Products that carry their own .NET

Rows with Deployment `SelfContained` or `PrivateRuntime` are not fixed by any .NET update. Update the product itself:

| Product | Action |
|---|---|
| PowerShell 7.4 (`C:\Program Files\PowerShell\7`) | Upgrade to PowerShell 7.6 LTS |
| Store apps (`C:\Program Files\WindowsApps`) | Let the Microsoft Store or the vendor's package update them |
| WSL Settings (`C:\Program Files\WSL`) | Run `wsl --update` |
| SQL Server Management Studio 21 | Update SSMS |
| Anything else | Update the product to a release built on a supported .NET |

---

## Order of work

1. **Known exploited first.** Findings marked `CISA KEV`, highest CVSS and EPSS first.
2. **Removals next.** A runtime nothing uses is the fastest fix and cannot come back with the next CVE.
3. **.NET 8 and 9 before November 10, 2026.** Start the vendor conversations now; a new build takes longer than a patch.
4. **Everything else** by CVSS.

---

## What the scan does not see

The vulnerability scan reads installed products. Some .NET copies are not installed products:

- **Copies inside a product folder** (`SelfContained`, `PrivateRuntime`). They keep the version the vendor shipped until the product is updated.
- **Out-of-support runtimes.** Once a version stops getting fixes, scanners often stop reporting new CVEs for it. A live IIS site on .NET Core 3.1 can have no finding at all.

Ask the sensor for these directly:

```text
Get Computer Name and .NET App Dependencies from all machines with .NET App Dependencies:Deployment equals "SelfContained"
Get Computer Name and .NET App Dependencies from all machines with .NET App Dependencies:Resolves To starts with "3."
Get Computer Name and .NET App Dependencies from all machines with .NET App Dependencies:Resolves To starts with "6."
```

The [.NET Remediation Plan](../tools/dotnet-remediation-plan.md) tool lists them in its **Not in the vulnerability scan** section.

!!! warning "Old version folders are not proof of use"
    Some products keep old copies after updating, and the sensor reports those too. Before removing a runtime because "only old copies use it", check that no live copy of the same product uses it. On one laptop, old Dell TechHub folders pointed at .NET 6, but so did Dell SupportAssist Agent, a running service. Removing .NET 6 there first would have broken it. Update the product, then remove the runtime.

---

## Verify

1. Ask the [.NET App Dependencies](../sensors/dotnet-app-dependencies.md) sensor again. No row resolves to the runtime you removed, and no app shows `None installed` that did not before.
2. In Comply, run a new vulnerability scan on the endpoints.
3. Open the CVE again. The endpoints are no longer listed under **View Endpoints**.

If a finding stays after the shared runtime was removed, the scanner may be reading a product's own copy of .NET. Check the sensor for `PrivateRuntime` or `SelfContained` rows of the same version on that endpoint.

---

## Related

- [.NET App Dependencies](../sensors/dotnet-app-dependencies.md)
- [.NET Remediation Plan](../tools/dotnet-remediation-plan.md)
- [Pseudonymize Exports](../tools/pseudonymize-exports.md)
