---
tags:
  - Tanium
  - PowerShell
  - Packages
  - Endpoint Management
---

# Remove Stale User Profiles (Package)

This Tanium package deletes Windows user profiles that nobody has signed in to for a set number of days. A user profile is the folder `C:\Users\<name>` and its entry in the registry.

Old profiles stay on a computer when a person leaves, or when the computer goes to a new person and is not reimaged. Vulnerability scanners report the old software that is in these profiles. When you delete the profile, you remove those files.

The package has an **Audit** mode. Audit mode lists the profiles that the package would delete. It changes nothing.

The package does not restart the endpoint.

!!! warning "Test status"
    The package was run through Tanium on one Windows 11 endpoint. Audit mode and Delete mode completed with exit code `0`. Delete mode removed one domain profile and one local profile that was named in **Users to delete**.

    **These cases were not tested:** a delete that stops before it completes (for example, a locked file), the **Users to keep** list, an empty **Users to delete** value, a very large profile, and Microsoft Entra ID accounts. Deploy to one endpoint first and read the action log.

!!! warning "You cannot restore a deleted profile"
    The package deletes all the files in the profile. Files that are only on that computer are gone. Examples are files on the Desktop or in Documents that are not synced, Outlook data files, and browser data.

    Before you use Delete mode, make sure that the person does not use the computer. Make sure that your organization does not have to keep the data.

## What the package does

1. Makes sure that the endpoint is a workstation. On a server or a domain controller, the package stops. It uses exit code 3.
2. Finds each user profile on the endpoint.
3. Finds the date when each profile was last used.
4. Decides to keep or delete each profile. The action log shows the reason for each decision.
5. In Delete mode, checks each profile again immediately before the delete. If a person signed in after the first check, the package keeps the profile.
6. Deletes the profile through Windows. Windows removes the folder and the registry entry together.
7. Makes sure that the folder and the registry entry are gone.
8. Writes the free space before and after to the action log.

## How the package finds the last-used date

The package uses the first date that it finds, in this order:

| Order | Source | Notes |
|---|---|---|
| 1 | Sign-in time and sign-out time | Windows stores these times in the registry for each profile. The package uses the newer of the two. |
| 2 | Windows upgrade date | The package uses this date only when the profile has no sign-in time and no sign-out time. |
| 3 | Last-use time from Windows | The package uses this date only when the first two are missing. This date can only cause the package to keep a profile. |

**Sign-in time and sign-out time.** The values are in this registry key:

```text
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\<SID>
```

The value names are `LocalProfileLoadTimeHigh`, `LocalProfileLoadTimeLow`, `LocalProfileUnloadTimeHigh`, and `LocalProfileUnloadTimeLow`. The Windows policy **Delete user profiles older than a specified number of days on system restart** uses the same values.

**Windows upgrade date.** The same registry key can have a value with the name `Migrated`. A profile that has this value, but no sign-in time, was not used after that date. Thus, that date is the latest date that the profile was used.

!!! note
    Microsoft does not document the `Migrated` value. On the test endpoint, two profiles had no sign-in time. The two profiles had the same `Migrated` date, less than one second apart. This agrees with a Windows upgrade that moved the two profiles in one step.

**Last-use time from Windows.** Antivirus scans and updates change this date. An old profile can show the date of today. The package logs this source as `Windows last-use time (less exact)`.

The package does not use the date of the file `NTUSER.DAT`. Windows updates and antivirus scans change that date also.

## Profiles that the package always keeps

The package keeps a profile when one of these is true:

- The profile is a system profile, such as SYSTEM, LocalService, or NetworkService.
- The account is a built-in account, such as Administrator or Guest.
- A person is signed in to the profile, or a service uses the account.
- The profile is for the last person who signed in to the endpoint.
- The folder name is in the **Users to keep** list.
- The account is a local account, and its folder name is not in **Users to delete**.
- The folder is not directly in the profiles folder (`C:\Users`).
- The package cannot find a last-used date.
- The profile was used more recently than **Days not used**.

## Requirements

- Windows 10 or Windows 11 workstations
- Windows PowerShell 5.1
- The Tanium Client

## Create the package

1. In the Tanium Console, go to **Administration > Content > Packages**.
2. Click **Create Package**.
3. Fill in the fields with the values in the table below.
4. In the **Files** section, add the script file.
5. In the **Parameters** section, add the four parameters in the second table below. Add them in the order `$1` to `$4`.
6. For `$3`, do not enter a default value.
7. Click **Save**.

| Field | Value |
|---|---|
| Package Name | `Remove Stale User Profiles` |
| Display Name | `Remove Stale User Profiles` |
| Description | `Deletes Windows user profiles (C:\Users\name) that nobody has signed in to for a set number of days. You must name the users to delete, or type ALL. You can also list users that must never be deleted. Audit mode lists what would be deleted and changes nothing. Keeps profiles in use, the last signed-in user, built-in and system accounts. Workstations only.` |
| Content Set | Your custom content set. Use a content set that only administrators can deploy. |
| Command | `cmd.exe /d /c powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File Remove-StaleUserProfiles.ps1 "$1" "$2" "$3" "$4"` |
| Command Timeout | 60 minutes |
| Download Timeout | 10 minutes |
| Ignore Action Lock | Clear (not selected) |
| Launch this package command in a process group | Selected |
| Files | `Remove-StaleUserProfiles.ps1` |

### Parameters

| Key | Type | Label | Values | Default |
|---|---|---|---|---|
| `$1` | Drop Down List | Mode | Audit, Delete | Audit |
| `$2` | Numeric | Days not used | 30 or more | 90 |
| `$3` | Text Input | Users to delete | Folder names, or `ALL` | None. The operator must enter a value. |
| `$4` | Text Input | Users to keep | Folder names, or `NONE` | NONE |

Enter this help text for each parameter:

| Key | Help text |
|---|---|
| `$1` | `Audit lists what would be deleted and changes nothing. Delete removes the profiles.` |
| `$2` | `A profile is only deleted if nobody has signed in to it for this many days. 30 or more.` |
| `$3` | `Required. Folder names from C:\Users, separated by commas, for example jdoe,asmith. Type ALL for every profile that passes the checks.` |
| `$4` | `Only needed when Users to delete is ALL. Folder names from C:\Users that must never be deleted, separated by commas. Wildcards work, for example svc*,adm*. Otherwise leave NONE.` |

### Rules for the parameters

- **Days not used** must be 30 or more. A lower value stops the package. Nothing is changed.
- **Users to delete** is necessary. An empty value stops the package. Nothing is changed.
- A name is the folder name in `C:\Users`. For `C:\Users\jdoe`, the name is `jdoe`. The folder name can be different from the account name, for example `jdoe.EXAMPLE`.
- **Users to delete** does not accept wildcards (`*` and `?`).
- `ALL` selects each profile that passes the checks. A local account is not included in `ALL`. To delete the profile of a local account, enter its folder name.
- **Users to keep** accepts wildcards, for example `svc*`.
- A name in **Users to keep** is always kept. This is true when the name is also in **Users to delete**.
- When you enter names in **Users to delete**, the package can delete only those profiles. Leave **Users to keep** as `NONE`.
- Uppercase and lowercase letters are the same. `all` and `ALL` give the same result.

## Deploy the package

Deploy the package two times. Use Audit mode first. Then use Delete mode.

### Run 1: Audit

1. In the Tanium Console, go to **Interact**.
2. In the question bar, type this question. Replace `ENDPOINT-01` with the name of your endpoint.

    ```text
    Get Computer Name from all machines with Computer Name equals ENDPOINT-01
    ```

3. Press Enter.
4. Select the endpoints.
5. Click **Deploy Action**.
6. In the **Deployment Package** field, type `Remove Stale User Profiles`. Select the package.
7. Set **Mode** to `Audit`.
8. Set **Days not used**. The default is `90`.
9. In **Users to delete**, enter the folder names from your findings, for example `jdoe,asmith`.
10. Leave **Users to keep** as `NONE`.
11. Click **Show preview to continue**.
12. Make sure that the list shows the correct endpoints.
13. Click **Deploy Action**.
14. Read the action log. Refer to [Read the results](#read-the-results).
15. Make sure that each `WOULD DELETE` line shows a profile that you want to delete.

### Run 2: Delete

1. Deploy the package again to the same endpoints.
2. Set **Mode** to `Delete`.
3. Enter the same values for the other parameters.
4. Click **Show preview to continue**.
5. Click **Deploy Action**.
6. Read the action log.
7. Make sure that each profile shows a `DELETED` line.

!!! tip
    Enter folder names in **Users to delete** when you know the names. Use `ALL` only when you want to remove each old profile on the endpoint.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | The package completed. No delete failed. |
| 1 | One or more profiles were not fully deleted. Read the action log. |
| 2 | A parameter was incorrect. Nothing was changed. |
| 3 | The endpoint is a server or a domain controller. Nothing was changed. |
| 4 | An error occurred that the package did not expect. Read the action log. |

In Action History, an exit code that is not 0 can show as **Failed**. For codes 2 and 3, the package stopped before it changed anything.

## Read the results

The action log shows one line for each profile. The line shows the folder, the last-used date, the source of that date, and the reason for the decision.

To read the action log from the Tanium Console:

1. Go to **Interact**.
2. Type this question. Replace `<action ID>` with the ID of your action.

    ```text
    Get Tanium Action Log[<action ID>] from all machines with Computer Name equals ENDPOINT-01
    ```

3. Press Enter.

Each line starts with one of these words:

| Word | Meaning |
|---|---|
| `KEEP` | The package did not change the profile. The line shows the reason. |
| `WOULD DELETE` | Audit mode only. Delete mode would delete this profile. |
| `DELETING` | Delete mode. The delete started. |
| `DELETED` | The folder and the registry entry are gone. |
| `FAILED` | The delete did not complete. The line shows what stayed. |
| `NOT FOUND` | A name in **Users to delete** is not a profile on this endpoint. |

The package also writes the same lines to this file on the endpoint:

```text
C:\ProgramData\RemoveStaleUserProfiles\Remove-StaleUserProfiles.log
```

### Example log: Audit

```text
[INFO] ===== Remove-StaleUserProfiles 1.1.0 started on ENDPOINT-01 =====
[INFO] Settings: mode=Audit; days not used=90; users to delete=ALL; users to keep=NONE
[INFO] Profiles folder: C:\Users. User profiles found: 4.
[INFO] KEEP          jdoe | folder: C:\Users\jdoe | last used: 2026-11-12 (sign-in/sign-out time stored by Windows) | why: in use right now
[INFO] WOULD DELETE  asmith | folder: C:\Users\asmith | last used: 2026-06-03 (sign-in/sign-out time stored by Windows) | why: not used for 162 day(s), limit is 90
[INFO] KEEP          Administrator | folder: C:\Users\Administrator | last used: 2026-10-17 (sign-in/sign-out time stored by Windows) | why: built-in account
[INFO] KEEP          labadmin | folder: C:\Users\labadmin | last used: 2026-07-08 (date of the last Windows upgrade, not signed in to since) | why: local account (only deleted when named in the list of users to delete)
[INFO] Summary (Audit, nothing changed): would delete=1; keep=3; free space=142.04 GB
[INFO] ===== Finished with exit code 0 =====
```

### Example log: Delete

```text
[INFO] ===== Remove-StaleUserProfiles 1.1.0 started on ENDPOINT-01 =====
[INFO] Settings: mode=Delete; days not used=90; users to delete=asmith; users to keep=NONE
[INFO] Profiles folder: C:\Users. User profiles found: 4.
[INFO] KEEP          jdoe | folder: C:\Users\jdoe | last used: 2026-11-12 (sign-in/sign-out time stored by Windows) | why: not on the list of users to delete
[INFO] DELETING      asmith | folder: C:\Users\asmith | last used: 2026-06-03 (sign-in/sign-out time stored by Windows) | why: not used for 162 day(s), limit is 90
[INFO] DELETED       asmith | folder and registry entry are gone | took 31 second(s)
[INFO] KEEP          Administrator | folder: C:\Users\Administrator | last used: 2026-10-17 (sign-in/sign-out time stored by Windows) | why: built-in account
[INFO] KEEP          labadmin | folder: C:\Users\labadmin | last used: 2026-07-08 (date of the last Windows upgrade, not signed in to since) | why: not on the list of users to delete
[INFO] Summary (Delete): deleted=1; failed=0; kept=3; free space before=142.04 GB; after=143.42 GB
[INFO] ===== Finished with exit code 0 =====
```

## Troubleshooting

| Log message | Cause | Action |
|---|---|---|
| `Days not used must be 30 or more` | The value of **Days not used** is lower than 30. | Deploy again with a value of 30 or more. |
| `Users to delete is required` | **Users to delete** was empty. | Deploy again. Enter folder names or `ALL`. |
| `Wildcards are not allowed in the list of users to delete` | A name in **Users to delete** has `*` or `?`. | Deploy again. Enter each folder name in full. |
| `This computer is a server or domain controller` | The package works only on workstations. | No action is necessary. Do not target servers. |
| `NOT FOUND` | No profile on the endpoint has this folder name. | Compare the name with the folder name in `C:\Users`. The folder name can be different from the account name. |
| `why: in use right now` | A person is signed in to the profile, or a service uses the account. | Deploy again after the person signs out, or after the endpoint restarts. |
| `why: belongs to the last person who signed in to this computer` | Windows shows this account as the last sign-in. | The package always keeps this profile. Deploy again after a different person signs in. |
| `Windows last-use time (less exact)` with a recent date | The profile has no sign-in time and no Windows upgrade date. The package cannot find the date when the profile was last used. | The package keeps this profile. Remove the profile by a different method. |
| `FAILED` with `folder (or part of it) is still there` | A file in the profile is in use. This case was not tested. | Restart the endpoint. Then deploy again. |
| The command timeout occurs | The profile is very large, or it has many small files. | Increase the command timeout. Then deploy again. |

## Things to know

- **Parameters arrive URL-encoded.** Tanium passes `jdoe,asmith` to the script as `jdoe%2Casmith`. The script decodes each value before it uses the value.
- **The log file stays on the endpoint.** Tanium removes the action folder after some time. The log file in `C:\ProgramData\RemoveStaleUserProfiles` stays. When the file is larger than 1 MB, the script keeps one old copy and starts a new file.
- **The 30-day minimum is in the script.** The value is `$MinimumDays`, near the top of the script.
- **Each Windows upgrade resets the date for unused profiles.** After an upgrade, a profile that nobody uses shows the upgrade date as its last-used date. The package can delete the profile when that date is older than **Days not used**.

## Script

### Remove-StaleUserProfiles.ps1

```powershell
--8<-- "tanium/packages/remove-stale-user-profiles/Remove-StaleUserProfiles.ps1"
```

## Related

- [Remove Folder](remove-folder.md)
- [Free Up User Disk Space](free-up-user-disk-space.md)
- [Scripts: Retrieve profile age (Microsoft Learn)](https://learn.microsoft.com/en-us/troubleshoot/windows-server/support-tools/scripts-to-retrieve-profile-age)
