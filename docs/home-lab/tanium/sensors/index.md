---
tags:
  - Tanium
  - PowerShell
  - Sensors
---

# Tanium Sensor Repository

Custom Tanium sensors, with the script source and the console settings needed to recreate each one.

A sensor answers a question in Interact. It runs on every targeted endpoint each time the question is asked, so it has to return in seconds. Anything slower belongs in a [package](../packages/index.md).

| Sensor | What it answers | Platform | Updated |
|---|---|---|---|
| [Certificate Expiration](certificate-expiration.md) | Which machine certificates expire soon, or have already expired? | Windows, Linux, macOS | 2026-09-24 |
| [Find File by Name](find-file-by-name.md) | Does this file exist in these folders, and when was it last modified? | Windows | 2026-09-18 |
| [Java - Runtime Inventory and Dependencies](java-runtime-inventory.md) | Which Java runtimes are installed, and what uses each one? | Windows, Linux | 2026-09-25 |

## Conventions used here

- **Naming:** short and plain, since the name becomes part of every question typed in Interact. Avoid brackets, quotes, and `|`, which Interact uses for parameters and column splitting.
- **Parameters** are read through placeholders such as `||FileName||`. The parameter **Key** in the console must match the placeholder exactly, including capitalization.
- **Parameters arrive URL-encoded.** Tanium passes `*.pst` to the script as `%2a%2epst`. Every script that takes a parameter decodes it before use.
- **Multi-column results** use `|` as the delimiter, with the columns defined in the sensor settings.
- **Time budget.** Each script stops itself before the sensor timeout and returns a status line instead of being killed mid-run. Set the sensor timeout above that internal limit.
- **One sensor, one script per platform.** Windows, Linux, and Mac scripts live in the same sensor instead of separate sensors per OS.
- **Status results are never blank:** `None` when nothing matches, `Not Applicable` when the feature doesn't exist on that endpoint, and `Error: <reason>` on failure, using a fixed set of reasons so results can be filtered. Find File by Name predates this convention and still uses `NOT FOUND` style strings.
- **Read-only.** Sensors never change anything on the endpoint.

## Before creating a sensor

1. Replace the `||Parameter||` placeholders with real values in a test copy, then run it locally to confirm it works and to measure the run time.
2. Compare that run time against the sensor timeout. A sensor is re-run on every question, so anything close to the limit will hurt at scale.
3. Check the **Max Sensor Age**. Results are reused for that long before the script runs again.
