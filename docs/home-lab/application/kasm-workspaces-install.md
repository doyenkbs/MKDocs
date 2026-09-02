---
tags:
  - Kasm Workspaces
---

# Kasm Workspaces: Install, Workspaces, and Servers

Kasm Workspaces gives you browser-based access to containerized desktops and applications. This page covers a single-server install on Ubuntu, adding Workspaces from the registry, and adding a fixed Windows server over RDP.

For single sign-on against Authentik, see [Kasm Workspaces: Authentik OIDC Integration](kasm-authentik-oidc.md) after the install is working.

Example values used throughout:

| Component | Address |
| --- | --- |
| Kasm server (Ubuntu 24.04) | 10.0.0.10 |
| Windows Server 2025 target | 10.0.0.20 |
| Public hostname | kasm.example.com |

## System requirements

Kasm publishes a sizing guide, but for a lab the practical floor is 4 cores, 8 GB RAM, and 50 GB disk. Each concurrent container session adds to that. Fixed servers like a Windows VM run their own resources separately.

Only two ports need to be reachable from users:

| Source | Destination | Port | Purpose |
| --- | --- | --- | --- |
| End user | Kasm Workspaces | 443 | Web application |
| End user | Kasm RDP Gateway | 3389 | RDP thick client access |

Everything else runs on internal Docker networks.

## Installation

Download and run the installer:

```bash
cd /tmp \
&& curl --fail-early \
    -fO https://kasm-static-content.s3.amazonaws.com/kasm_release_1.19.0-latest.tar.gz \
    -fO https://kasm-static-content.s3.amazonaws.com/kasm_release_1.19.0-latest.tar.gz.sha256sum \
&& sha256sum --check *.sha256sum \
&& tar -xf kasm_release_1.19.0-latest.tar.gz \
&& sudo bash kasm_release/install.sh
```

The installer generates random passwords for `admin@kasm.local` and `user@kasm.local` and prints them at the end. Save them immediately.

To set the password yourself instead:

```bash
sudo bash kasm_release/install.sh --admin-password 'YourPassword'
```

### Rolling vs static images

Starting in 1.19.0, the default install uses rolling images that update on their own to deliver security fixes. For pinned versions with manual update control, pass `-f`:

```bash
sudo bash kasm_release/install.sh -f
```

For a lab, rolling is fine. For anything where you need reproducible behavior, use static.

### Useful install flags

| Flag | Purpose |
| --- | --- |
| `-L, --proxy-port` | Run the web app on a port other than 443 |
| `-P, --admin-password` | Set the admin password instead of generating one |
| `-U, --user-password` | Set the default user password |
| `-e, --accept-eula` | Skip the EULA prompt |
| `-J, --swap-size` | Create swap in MB if none exists |
| `-f, --use-static-images` | Pin image versions instead of rolling |
| `--ssl-public-cert` / `--ssl-private-key` | Supply your own certificate at install time |

If the install fails it leaves a log named `kasm_install_<timestamp>.log` in the directory you ran it from. On success that file is removed.

### Post-install checks

```bash
sudo docker ps --format '{{.Names}}\t{{.Status}}'
```

You want eight containers, all healthy:

```
kasm_proxy
kasm_db
kasm_api
kasm_manager
kasm_agent
kasm_guac
kasm_rdp_gateway
kasm_rdp_https_gateway
```

Log in at `https://<server>` with `admin@kasm.local`.

### Change these two settings first

**API Token Refresh Leeway.** Settings > Global > Authentication. The default is 259200 seconds (3 days). This is the grace period during which an expired component token can still be exchanged for a new one. If the deployment sits powered off longer than the token lifespan plus this leeway, the connection proxies cannot recover on their own. For a lab that gets shut down for weeks at a time, raise this to 7776000 (90 days) or 31536000 (a year). Leave the lifespan at 259200.

**Logging volume.** Settings > Global > Logging. Retention is measured in row counts, not days. Defaults are 300,000 debug rows and 400,000 total. A fresh deployment writes roughly 190 rows a minute at debug level, mostly from `kasm_manager`. Turn on **Minimize Local Logging** and drop the retention counts to something like 20,000 and 50,000.

## Adding Workspaces from the registry

Workspaces are the container images users launch. Kasm hosts a registry of prebuilt ones.

1. Go to **Workspaces > Registry**
2. Browse or search for what you want (Chrome, Firefox, VS Code, Kali, Ubuntu Desktop, and so on)
3. Click **Install** on the image
4. Wait for the pull to finish, which can take several minutes for desktop images

After install, the Workspace appears under **Workspaces > Workspaces**. It will not be visible to users until you assign it to a group.

To assign it:

1. **Access Management > Groups**
2. Open the group (for a lab, `All Users` is the simplest)
3. Under **Workspaces**, add the one you installed

Images are large. A full desktop image can run several GB, so watch disk before installing a handful of them:

```bash
df -h
sudo docker images | grep kasmweb
```

## Adding a fixed server (Windows Server 2025)

A fixed server is an existing machine Kasm connects to over RDP, rather than a container it spins up. This is how you give users access to a real Windows VM.

### On the Windows side

Enable RDP if it is not already on. Windows Server ships with it disabled:

```powershell
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

Verify from the Kasm host:

```bash
nc -zv 10.0.0.20 3389
```

Keep **Max Simultaneous Sessions** at 2 or lower unless you have RDS CALs. Windows Server allows two administrative RDP sessions without the Remote Desktop Services role licensed.

### Create the server record

**Infrastructure > Servers > + Add**

| Field | Value |
| --- | --- |
| Friendly Name | kasm-client.example.local |
| Deployment Zone | default |
| Connection Type | RDP |
| IP/Hostname | 10.0.0.20 |
| Connection Port | 3389 |
| Connection Credential Type | Prompt User |
| Max Simultaneous Sessions | 2 |

Leave **Kasm Desktop Service Installed** off for now. Turning it on before the service is actually installed produces registration errors in the API log.

### Install the Kasm Desktop Service

The Desktop Service is optional. It adds file upload and download, file mapping, screenshots, and resource monitoring. Standard RDP connections work without it.

Installers and full instructions: <https://docs.kasm.com/docs/guide/windows/windows_service/index.html>

Supported on Windows 10, Windows 11, and Windows Server 2019, 2022, and 2025 (x86_64). Use the latest installer version compatible with your Kasm release, listed in the table on that page.

1. Generate a token under **Infrastructure > Servers > Server Enrollment Tokens**
2. Download the installer on the target Windows machine
3. Run it and supply the Kasm hostname or IP, the port (443 by default), and the enrollment token

Point the agent at the Kasm server directly (`10.0.0.10`) rather than a public hostname. It is a machine-to-machine connection on the local network and gains nothing from traversing a reverse proxy or CDN.

The installer opens the Windows firewall for inbound TCP 4902, which the API server and connection proxies use to reach the service. The service talks outbound to the API server on 443.

Once installed, go back to the server record and turn on **Kasm Desktop Service Installed**.

Verify the service is running:

```powershell
Get-Service | Where-Object {$_.Name -like "*kasm*"}
```

### Create the Workspace

**Workspaces > Workspaces > + Add Workspace**

1. Select **Server** as the Workspace Type
2. Give it a friendly name and description
3. Set it to Enabled
4. Select the server record you created from the **Server** dropdown

Assign it to a group, then launch it from the user dashboard.

## Troubleshooting

### Clearing the log table

The `logs` table in Postgres backs the Diagnostics UI. It fills fast at debug level.

Get the database credentials if you need them:

```bash
sudo docker exec kasm_db env | grep -i postgres
```

See what is being logged:

```bash
sudo docker exec kasm_db psql -U kasmapp -d kasm -c \
  "SELECT data->>'application' AS app, levelname, count(*) FROM logs GROUP BY 1,2 ORDER BY 3 DESC LIMIT 15;"
```

Errors only:

```bash
sudo docker exec kasm_db psql -U kasmapp -d kasm -c \
  "SELECT ingest_date, data->>'application' AS app, left(data->>'message',120) FROM logs WHERE levelname='ERROR' ORDER BY ingest_date DESC LIMIT 20;"
```

Note the schema: `application` and `message` live inside a `jsonb` column called `data`, not as top-level columns. Run `\d logs` to see the real structure.

Delete everything:

```bash
sudo docker exec kasm_db psql -U kasmapp -d kasm -c "TRUNCATE TABLE logs;"
```

Or delete by age, using standard timestamp syntax:

```bash
sudo docker exec kasm_db psql -U kasmapp -d kasm -c \
  "DELETE FROM logs WHERE ingest_date < '2026-08-01 00:00:00';"
sudo docker exec kasm_db psql -U kasmapp -d kasm -c "VACUUM ANALYZE logs;"
```

`TRUNCATE` frees space directly and needs no vacuum. Checking the row count a minute later and seeing a few hundred rows is normal, those are new entries written since the delete.

Truncating is a symptom fix. Change the logging settings described earlier if the table keeps filling.

### Resetting a forgotten admin password

There is no CLI password reset. Kasm stores credentials across two columns, `pw_hash` and a `NOT NULL` bytea column called `crypt_password`, so editing the database directly is unreliable and can lock the account entirely.

**Option 1: use another admin account.** List the users and see what else exists:

```bash
sudo docker exec kasm_db psql -U kasmapp -d kasm -c \
  "SELECT username, locked, disabled FROM users;"
```

If any account you know the password for has admin rights, log in with it and reset `admin@kasm.local` from **Access Management > Users**.

**Option 2: re-run the installer with an explicit password.** This goes through Kasm's own credential path, so both password columns get written correctly:

```bash
sudo bash kasm_release/install.sh --role all --no-db-init --admin-password 'NewPassword' --accept-eula
```

`--no-db-init` skips database initialization and preserves your existing users, workspaces, and server records. Take a backup first.

Confirm your data survived by counting users. A fresh install creates two, so anything more means the database is intact:

```bash
sudo docker exec kasm_db psql -U kasmapp -d kasm -c "SELECT count(*) FROM users;"
```

Note that this may also reset `user@kasm.local` and will rewrite the component config files.

### Database backup and restore

```bash
sudo /opt/kasm/current/bin/utils/db_backup \
  --path /opt/kasm/current \
  --backup-file /home/user/kasm_backup_$(date +%F).tar
```

Both `--path` and `--backup-file` are required. Add `--exclude-logs` to skip log data, which is most of the size on a busy deployment.

Verify the archive before you rely on it:

```bash
tar -tf /home/user/kasm_backup_*.tar | head
```

Restore with `db_restore`, which takes the same `--path` and `--backup-file` arguments plus `--accept-warning`, since it overwrites the current database.

Move backups off `/tmp`, which most Ubuntu builds clear on reboot.

### Full teardown

If you need to start over from nothing:

```bash
# Stop and remove the stack
sudo systemctl stop kasm
sudo systemctl disable kasm
sudo docker stop $(sudo docker ps -aq)
sudo docker rm $(sudo docker ps -aq)

# Volumes and networks
sudo docker volume ls
sudo docker volume rm kasm_db_<version>
sudo docker network rm kasm_default_network
sudo docker network rm kasm_sidecar_network

# Images and files
sudo docker rmi $(sudo docker images -q "kasmweb/*")
sudo rm -rf /opt/kasm
sudo rm -f /etc/systemd/system/kasm.service
sudo systemctl daemon-reload
```

Leave the `kasm` user and group. The installer reuses them.

Confirm nothing is left:

```bash
sudo docker ps -a
sudo docker volume ls
sudo docker network ls
sudo docker images
ls /opt
```

`/opt` should show only `containerd`, with no kasmweb images remaining.

The sidecar network uses a custom plugin driver rather than `bridge`. If it refuses to remove, check the plugin state first:

```bash
sudo docker plugin ls
```

**Uninstall the Desktop Service on every endpoint before or after the teardown.** Agent registration lives in a config file on the endpoint, not in Kasm's database, so an agent survives a full server wipe and keeps heartbeating at the new deployment with a dead token.

The Windows agent is an NSIS installer, not an MSI, so `Uninstall-Package` will not work. Find the uninstall string:

```powershell
Get-ItemProperty HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
  Where-Object {$_.DisplayName -like "*Kasm*"} |
  Select-Object DisplayName, UninstallString, QuietUninstallString

Start-Process "C:\Program Files\Kasm\uninstall.exe" -ArgumentList "/S" -Wait
```

Do not delete `C:\Program Files\Kasm` manually first. The uninstaller lives inside it, and removing it leaves a registry entry pointing at a file that no longer exists. If that happens, clean up by hand:

```powershell
sc.exe delete Kasm
Get-NetFirewallRule -DisplayName "*Kasm*" | Remove-NetFirewallRule
Remove-Item "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Kasm KasmAgent" -Recurse
```

The directory often stays locked until a reboot.

## Quick reference

```bash
# Service control
sudo /opt/kasm/bin/stop
sudo /opt/kasm/bin/start
sudo /opt/kasm/bin/restart

# Health
sudo docker ps --format '{{.Names}}\t{{.Status}}'

# Logs
sudo docker logs -f --tail 100 kasm_guac
sudo docker logs --tail 100 kasm_api

# Database
sudo docker exec kasm_db env | grep -i postgres
sudo docker exec kasm_db psql -U kasmapp -d kasm -c "\dt"
```

---

## *References*

- [*Kasm Workspaces Documentation*](https://kasmweb.com/docs/latest/index.html): Documentation root for the current release
- [*Single Server Installation*](https://kasmweb.com/docs/latest/install/single_server_install.html): The install path used on this page, including installer flags
- [*System Requirements*](https://kasmweb.com/docs/latest/install/system_requirements.html): Supported operating systems, hardware minimums, and port requirements
- [*Sizing and Operations*](https://kasmweb.com/docs/latest/how_to/sizing_operations.html): Capacity planning for concurrent sessions
- [*Workspace Registry*](https://kasmweb.com/docs/latest/guide/workspace_registry.html): Adding and managing registries to pull Workspaces from
- [*Workspaces*](https://kasmweb.com/docs/latest/guide/workspaces.html): Workspace settings, images, and launch behavior
- [*Servers*](https://kasmweb.com/docs/latest/guide/compute/servers.html): Fixed server configuration, including RDP targets like the Windows VM
- [*Fixed Infrastructure*](https://kasmweb.com/docs/latest/how_to/fixed_infrastructure.html): Connecting Kasm to existing machines rather than containers
- [*Single Server Upgrade*](https://kasmweb.com/docs/latest/upgrade/single_server_upgrade.html): Upgrade procedure for a single-server deployment
- [*Uninstall*](https://kasmweb.com/docs/latest/install/uninstall.html): Removing Kasm and its agents cleanly
