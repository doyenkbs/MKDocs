---
tags:
  - Pangolin
  - Networking
  - Reverse Proxy
---

# Pangolin

Pangolin is a self-hosted reverse proxy and tunneling platform. It lets you publish internal
services on public hostnames without opening inbound ports on the network where those services
live, and it puts authentication in front of them.

This page covers installing Pangolin on a VPS, connecting a network to it, installing clients,
and upgrading. Configuration reference lives on the
[Pangolin configuration](pangolin-configuration.md) page.

All domains, IP addresses, and credentials on this page are examples. Replace them with your own.

---

## How the pieces fit together

A self-hosted Pangolin server is four components:

| Component | What it does |
|---|---|
| **Pangolin** | The control plane. Dashboard, database, API, authentication, and policy. |
| **Gerbil** | The WireGuard server. Terminates tunnels from sites and clients. |
| **Traefik** | The reverse proxy. Handles TLS certificates and routes public traffic. |
| **Badger** | A Traefik plugin. Asks Pangolin whether a given request is authorized. |

Two more components run away from the server:

- A **site** connector runs on the network where your services live. It dials out to Gerbil and
  builds the tunnel, so that network needs no inbound firewall rules.
- A **client** runs on a user device (laptop, phone) and gives that device a private path to
  resources.

Pangolin, Gerbil, and Traefik run as Docker containers from a single Compose file. Badger is not
a container; it is a plugin Traefik downloads at startup, and its version is pinned in the Traefik
config file. Both files are walked through on the configuration page, under
[Reading the Compose file](pangolin-configuration.md#reading-the-compose-file) and
[What the installer created](pangolin-configuration.md#what-the-installer-created).

---

## Prerequisites

- A Linux server with root access and a public IP address. Ubuntu 22.04 or Debian 12 are good
  choices. 2 vCPU and 4 GB RAM is comfortable for a small deployment.
- Docker Engine and the Docker Compose plugin installed.
- A domain name you control.
- An email address for Let's Encrypt certificates.

### Install Docker

If Docker is not already installed:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo docker --version
sudo docker compose version
```

Both commands must print a version. If `docker compose version` fails, you have the standalone
`docker-compose` binary instead of the plugin, and every `docker compose` command on this page
needs to be written as `docker-compose`.

### DNS records

Create these records at your DNS provider before installing. Replace `203.0.113.10` with your
server's public IP address.

| Type | Name | Value |
|---|---|---|
| A | `pangolin.example.com` | `203.0.113.10` |
| A | `example.com` | `203.0.113.10` |
| A | `*.example.com` | `203.0.113.10` |

The wildcard record is what lets you publish `app1.example.com`, `app2.example.com`, and so on
without adding a record for each one.

A wildcard DNS record is not the same thing as a wildcard certificate. By default Traefik still
requests one certificate per hostname. To issue a single `*.example.com` certificate instead, see
[Wildcard certificates with a DNS-01 challenge](pangolin-configuration.md#wildcard-certificates-with-a-dns-01-challenge).

Confirm the records resolve before continuing:

```bash
dig +short pangolin.example.com
dig +short test.example.com
```

Both should return your server's IP. DNS changes can take several minutes to propagate. Do not
start the installer until they do, because Let's Encrypt will fail to issue a certificate.

### Firewall ports

Open these on the server and, if your provider has one, in the provider's external firewall:

| Port | Protocol | Purpose |
|---|---|---|
| 80 | TCP | HTTP, and Let's Encrypt certificate validation |
| 443 | TCP | HTTPS |
| 443 | UDP | HTTP/3 (QUIC), optional |
| 51820 | UDP | WireGuard tunnels from sites |
| 21820 | UDP | WireGuard tunnels from clients |

With UFW:

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp
sudo ufw allow 51820/udp
sudo ufw allow 21820/udp
sudo ufw reload
sudo ufw status numbered
```

If your VPS provider has its own firewall layer (Contabo, Hetzner, AWS security groups, and
others), open the same ports there. A rule set correctly in UFW will still be blocked upstream if
the provider firewall does not match.

---

## Installation

The installer writes every file into the directory you run it from, so create the installation
directory first and run it from there. `/opt/pangolin` is the convention used throughout this page.

### 1. Create the install directory

```bash
sudo mkdir -p /opt/pangolin
cd /opt/pangolin
```

### 2. Download the installer

```bash
curl -fsSL https://static.pangolin.net/get-installer.sh | bash
ls -l /opt/pangolin
```

You should now see an `installer` binary in the directory. It supports both AMD64 (x86_64) and
ARM64.

### 3. Run the installer

```bash
sudo ./installer
```

The installer asks a series of questions:

- **Edition.** Community Edition or Enterprise Edition. Enterprise requires a license key and
  pulls a different image tag (`ee-` prefixed).
- **Base domain.** Your root domain with no subdomain, for example `example.com`.
- **Dashboard domain.** Press Enter to accept `pangolin.example.com`, or type a different
  hostname.
- **Let's Encrypt email.** Used for certificate notices and for the admin login.
- **Tunneling.** Whether to install Gerbil. Answer yes unless you only want a plain reverse proxy
  with no tunnels.
- **SMTP.** Optional. Answer no for the initial install; email can be configured later in
  `config/config.yml`. See [The server config file](pangolin-configuration.md#the-server-config-file) for the
  `email` block.
- **Start containers.** Answer yes.

Pulling the images and starting the containers takes two to three minutes.

### 4. Confirm the containers are running

```bash
cd /opt/pangolin
sudo docker compose ps
sudo docker ps --format "{{.Names}}\t{{.Image}}\t{{.Status}}"
```

You should see `pangolin`, `gerbil`, and `traefik`, all up.

The installer has also written the config files that drive them, all under `/opt/pangolin`. You do
not need to touch them to finish the install. For what each one is, see
[What the installer created](pangolin-configuration.md#what-the-installer-created).

### 5. Get the setup token

The first admin account is created with a one-time token that Pangolin prints to its log on first
start:

```bash
sudo docker compose logs pangolin | grep -i "setup token"
```

If that returns nothing, read the whole log and look near the top:

```bash
sudo docker compose logs pangolin | head -60
```

### 6. Create the admin account

In a browser, go to:

```
https://pangolin.example.com/auth/initial-setup
```

Then:

1. Paste the setup token.
2. Enter the admin email address.
3. Set a strong password. This account has full access to the server.
4. Submit.

The first certificate can take a few minutes to issue. A browser warning on the first attempt is
normal; wait a minute and reload before troubleshooting.

### 7. Create the first organization

After logging in, enter an organization name and description and select **Create Organization**.
Sites, resources, and users all live inside an organization.

The server is now running, but it has nothing to reach yet. The next step is connecting a network
to it.

---

## Installing a site connector

A site connects a remote network to Pangolin. It runs on a machine inside that network, dials out
to the server, and needs no inbound firewall rules on the remote side.

The connector used here is **Newt**, the standalone site connector. It is a single binary with no
dependencies, and it is what the dashboard hands you when you choose the Linux install method.

### 1. Create the site in the dashboard

1. Open the Pangolin dashboard.
2. Go to **Sites** and select **Add Site**.
3. Give it a name and create it.
4. Copy the **site ID**, **secret**, and **endpoint** shown on the next screen. The secret is shown
   once.

### 2. Use the commands the dashboard generates

Pangolin builds the install and run commands for you, already filled in with that site's ID,
secret, and endpoint. Use these rather than typing anything by hand, since the credentials are long
and a typo produces a connector that simply never connects.

On the site's page, under **Install Site**, choose:

- **Operating System.** Linux, macOS, Docker, Kubernetes, Advantech, Podman, NixOS, or Windows.
- **Method.** The options change with the operating system. Linux offers **Run** (a foreground
  command) and **Systemd Service** (a complete unit file with the credentials already in it).
  Docker offers **Docker Compose** and **Docker Run**.
- **Configuration.** Toggles that change the generated command, all changeable later:
  - **Accept Client Connections** lets user devices and clients reach resources on this site.
  - **Allow Pangolin SSH** allows SSH access to resources on this site. This one appears on the
    Linux method, not on Docker.

The commands appear underneath, each with a copy button.

To find them again after the site exists, go to **Sites**, select the site, and open the
**Credentials** tab. The header on that page also shows the connector type, its version, and
whether the site is currently online.

### 3. Install Newt

On the machine inside the network you want to connect:

```bash
curl -fsSL https://static.pangolin.net/get-newt.sh | bash
which newt
newt --version
```

The script detects your CPU architecture, pulls the latest release, and puts the binary on your
`PATH`. Note the path `which newt` returns; the service unit below needs it.

### 4. Test the connection in the foreground

```bash
sudo newt \
  --id EXAMPLE_SITE_ID \
  --secret EXAMPLE_SITE_SECRET \
  --endpoint https://pangolin.example.com
```

Confirm in the dashboard that the site shows **Online**, then stop it with `Ctrl+C`.

This foreground run is for testing only. Newt is an ordinary foreground process, so it dies the
moment you close the terminal or your SSH session drops, and the site goes down with it and stays
down until you log back in and start it again. That is why the next step exists.

### 5. Convert it to a systemd service

The dashboard's **Systemd Service** method generates a unit with the credentials written directly
into the `ExecStart` line. The version below does the same job but keeps the credentials in a
separate environment file, so the unit itself holds no secrets.

Create the environment file:

```bash
sudo install -d -m 0755 /etc/newt
sudo nano /etc/newt/newt.env
```

Contents:

```bash
NEWT_ID=EXAMPLE_SITE_ID
NEWT_SECRET=EXAMPLE_SITE_SECRET
PANGOLIN_ENDPOINT=https://pangolin.example.com
```

Save with `Ctrl+O`, `Enter`, then exit with `Ctrl+X`. Restrict the file, since it holds the site
secret:

```bash
sudo chmod 600 /etc/newt/newt.env
ls -l /etc/newt/newt.env
```

Create the unit:

```bash
sudo nano /etc/systemd/system/newt.service
```

Paste:

```ini
[Unit]
Description=Newt
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
Group=root
EnvironmentFile=/etc/newt/newt.env
ExecStart=/usr/local/bin/newt
Restart=always
RestartSec=2
UMask=0077
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

Newt reads `NEWT_ID`, `NEWT_SECRET`, and `PANGOLIN_ENDPOINT` from the environment on its own, so
`ExecStart` does not repeat them as flags.

Confirm the binary is where `ExecStart` says it is before enabling. systemd needs an absolute path
and the service will fail to start if it is wrong:

```bash
which newt
ls -l /usr/local/bin/newt
```

If the binary is somewhere else, either move it to `/usr/local/bin/newt` or edit `ExecStart` to
match.

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now newt
sudo systemctl status newt
```

`enable --now` does two things at once: `enable` makes it start on boot, `--now` starts it
immediately.

Newt logs to the journal rather than to a file:

```bash
sudo journalctl -u newt -f
sudo journalctl -u newt --since "10 minutes ago"
```

Confirm the site shows **Online** in the dashboard, then close your SSH session and check the
dashboard again. It should still be online. That is the whole point of the service.

What each of the less obvious directives buys you:

- **`EnvironmentFile`** keeps the site secret out of the unit file. Unit files under
  `/etc/systemd/system/` are world-readable by default; the env file at mode 600 is not.
- **`Restart=always`** with **`RestartSec=2`** brings the connector back after a crash or a network
  drop, which is exactly the behavior you lose when running it by hand.
- **`Wants`** and **`After=network-online.target`** stop it starting before the network is up on
  boot, which otherwise produces a failed first connection attempt.
- **`NoNewPrivileges=true`** stops the process gaining additional privileges after it starts.

After editing either file:

```bash
sudo systemctl daemon-reload
sudo systemctl restart newt
```

`daemon-reload` is only needed when the unit file itself changed. If you only edited
`/etc/newt/newt.env`, the `restart` alone is enough.

### Running Newt in Docker instead

If the site machine already runs Docker, the **Docker** method in the dashboard generates a Compose
service instead of a unit file:

```yaml
services:
  newt:
    image: fosrl/newt
    container_name: newt
    restart: unless-stopped
    environment:
      - PANGOLIN_ENDPOINT=https://pangolin.example.com
      - NEWT_ID=EXAMPLE_SITE_ID
      - NEWT_SECRET=EXAMPLE_SITE_SECRET
```

Start it with `docker compose up -d`. The `restart: unless-stopped` policy does the same job the
systemd unit does on a bare-metal install: Docker brings the container back after a crash or a
reboot.

Use one or the other, not both. Two connectors running against the same site ID fight over the
tunnel.

### Keeping Newt current

The connector and the server are versioned separately. A connector well behind the server logs
configuration version warnings, misses features the server has gained, and may be missing
reconnection fixes. Update it after any significant server upgrade.

Check the running version in the dashboard, under **Sites**, then the site, where the header shows
**Connection Type** and **Version**. Compare it against the latest release at
<https://github.com/fosrl/newt/releases>.

There are no database migrations in the connector, so you go straight to the current version rather
than stepping through minors:

```bash
sudo systemctl stop newt
curl -fsSL https://static.pangolin.net/get-newt.sh | bash
newt --version
sudo systemctl start newt
sudo systemctl status newt
sudo journalctl -u newt --since "2 minutes ago"
```

The install script overwrites the binary in place, so the unit file and the environment file are
left alone. Confirm the version in the dashboard header afterward.

If the script installs to a different path than the one in `ExecStart`, the service will fail to
start after the update. Check with `which newt` and fix the unit if needed.

### Where to run the connector

The connector is a single point of failure for every resource behind that site. If it shares a
machine with something else you reboot or rebuild regularly, every resource on that site goes down
with it.

Give it a small dedicated VM or container that does nothing else, or add a second site for the
resources that cannot tolerate an outage.

---

## Installing a client

A client gives a user device a private path to resources. Unlike a site, it authenticates as a
user rather than with a fixed ID and secret.

### Windows

1. Download the `.msi` installer from <https://pangolin.net/downloads/windows>.
2. Run the installer.
3. Launch Pangolin from the Start menu.
4. Click the Pangolin icon in the system tray and select **Log in**.
5. Enter your self-hosted server URL, `https://pangolin.example.com`, and sign in.

### macOS

1. Download the `.dmg` from <https://pangolin.net/downloads/mac>.
2. Open the `.dmg` and drag **Pangolin.app** into **Applications**.
3. Launch Pangolin from Applications.
4. When prompted to install a network extension, select **Open System Settings**.
5. Go to **System Settings > General > Login Items & Extensions > By Category > Network
   Extensions** and make sure **Pangolin.app** is toggled on.
6. Select **Allow** when Pangolin asks to add a VPN configuration.
7. Click the Pangolin icon in the menu bar, select **Log in**, and enter
   `https://pangolin.example.com`.

### iOS and iPadOS

1. Install **Pangolin Client** from the App Store.
2. Open the app.
3. Allow Pangolin to add VPN configurations when prompted. You may need Face ID, Touch ID, or your
   passcode.
4. Log in against `https://pangolin.example.com`.
5. Tap **Connect**.

### Android

1. Install **Pangolin** from Google Play.
2. Open the app and log in against `https://pangolin.example.com`.
3. Tap **Connect**. Allow the VPN connection when Android prompts on first use.

### Linux and macOS command line

```bash
curl -fsSL https://static.pangolin.net/get-cli.sh | bash
pangolin login
pangolin up
```

`pangolin login` prompts for your server URL and credentials. `pangolin up` brings the tunnel up.

The CLI runs on Windows too, but VPN functionality is not supported there. Use the Windows GUI
client for the tunnel and the CLI for SSH if you want both.

### Machine clients

A machine client connects a server or service rather than a person, so it uses an ID and secret
instead of a login. Create it in the dashboard under **Clients**, then install it as a service:

```bash
sudo pangolin service install client \
  --id EXAMPLE_CLIENT_ID \
  --secret EXAMPLE_CLIENT_SECRET \
  --endpoint https://pangolin.example.com

sudo pangolin service status client
sudo pangolin service logs client
```

In Docker:

```yaml
services:
  pangolin-cli:
    image: fosrl/pangolin-cli:latest
    container_name: pangolin-cli
    restart: unless-stopped
    network_mode: host
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      - PANGOLIN_ENDPOINT=https://pangolin.example.com
      - CLIENT_ID=EXAMPLE_CLIENT_ID
      - CLIENT_SECRET=EXAMPLE_CLIENT_SECRET
```

All three of those Docker settings are required, not optional:

- `network_mode: host` puts the WireGuard interface on the host network stack.
- `cap_add: NET_ADMIN` lets the container manage network interfaces.
- `devices: /dev/net/tun` gives the container the TUN device it needs to create the interface.

### Running a client inside an LXC container on Proxmox

The client creates a native TUN interface, which an unprivileged LXC container cannot do by
default:

1. Select the container in the Proxmox web interface.
2. Open the **Resources** tab.
3. Select **Add**, then **Device Passthrough**.
4. In **Device Path**, enter `dev/net/tun`, then select **Add**.
5. Stop and start the container. A reboot from inside does not apply the change.

---

## Configuration and customization

The installer writes a working configuration, so there is nothing you have to change to use the
server. The settings you are most likely to want later are documented separately, on the
[Pangolin configuration](pangolin-configuration.md) page.

??? info "What is on that page"

    - [The files the installer created](pangolin-configuration.md#what-the-installer-created) and what each one is for
    - [The server config file](pangolin-configuration.md#the-server-config-file): domains, SMTP, feature flags, and the signing secret
    - [Reading the Compose file](pangolin-configuration.md#reading-the-compose-file), including why Traefik publishes its ports on Gerbil
    - [Adding a custom entry point](pangolin-configuration.md#adding-a-custom-entry-point) for a raw TCP or UDP port such as SMTP
    - [Wildcard certificates with a DNS-01 challenge](pangolin-configuration.md#wildcard-certificates-with-a-dns-01-challenge)
    - [Traefik logs and log growth](pangolin-configuration.md#traefik-logs-and-log-growth), and capping Docker's own log files

---

## Upgrading

Pangolin runs database migrations automatically on startup when it detects a version change. It
records the last version it migrated, then runs every unrun script in order. A failed migration
blocks startup entirely.

Downgrading after a migration is often impossible, because the schema has already changed. Back up
before every upgrade.

### Rules to follow

1. **Back up first**, every time.
2. **Step through minor versions.** Go 1.17 to 1.18 to 1.19, not 1.17 straight to 1.22. If
   something breaks you then have one migration to diagnose instead of five.
3. **Read the release notes** for every version you pass through, not just the target. Breaking
   changes live in the versions you skip over.
4. **Gerbil is not upgraded by the migration.** You increment it yourself.
5. **Badger is a Traefik plugin, not a container.** Its version lives in `traefik_config.yml`
   (see [What the installer created](pangolin-configuration.md#what-the-installer-created)). Pangolin tries to update
   it automatically when the Traefik config is in the default location, but it fails silently if it
   cannot. Set it yourself and verify.

### 1. Back up

```bash
cd /opt/pangolin
sudo docker compose down
sudo tar -czf /root/pangolin-backup-$(date +%F-%H%M).tar.gz -C /opt/pangolin config docker-compose.yml
ls -lh /root/pangolin-backup-*.tar.gz
sudo docker compose up -d
```

That archive holds the database, the certificates, and both config files. It is a complete
rollback. For what each of those files is, see
[What the installer created](pangolin-configuration.md#what-the-installer-created).

If you moved the DNS provider token into a `.env` file as described under
[Wildcard certificates with a DNS-01 challenge](pangolin-configuration.md#wildcard-certificates-with-a-dns-01-challenge),
add `.env` to the `tar` command as well, or the restored stack will start without it.

On SQLite, Pangolin also copies the database file before each migration unless the
`DISABLE_BACKUP_ON_MIGRATION` environment variable is set to `true`. Do not rely on that alone.

### 2. Find the available versions

Check the release pages for the current version of each component:

- Pangolin: <https://github.com/fosrl/pangolin/releases>
- Gerbil: <https://github.com/fosrl/gerbil/releases>
- Badger: <https://github.com/fosrl/badger/releases>
- Traefik: <https://github.com/traefik/traefik/releases>

To list the image tags that actually exist, including the last patch release of each minor
version, query Docker Hub directly. Community Edition:

```bash
curl -s "https://hub.docker.com/v2/repositories/fosrl/pangolin/tags?page_size=100" \
  | grep -o '"name":"[0-9][^"]*"'
```

Enterprise Edition tags carry an `ee-` prefix:

```bash
curl -s "https://hub.docker.com/v2/repositories/fosrl/pangolin/tags?page_size=100&name=ee-1.2" \
  | grep -o '"name":"ee-[^"]*"'
```

Ignore anything ending in `-rc.0`, `-amd64`, or `-arm64`. Use the plain version tag and let Docker
pick the architecture.

### 3. Upgrade one minor version at a time

For each hop, change the version, confirm the change landed, pull, and start:

```bash
cd /opt/pangolin
sudo sed -i -E 's|fosrl/pangolin:[0-9.]+|fosrl/pangolin:1.18.4|' docker-compose.yml
grep -n "fosrl/pangolin:" docker-compose.yml
sudo docker compose pull
sudo docker compose up -d
sudo docker compose logs -f pangolin
```

On Enterprise Edition, the pattern includes the prefix:

```bash
sudo sed -i -E 's|fosrl/pangolin:ee-[0-9.]+|fosrl/pangolin:ee-1.18.4|' docker-compose.yml
```

The `grep` prints the line back so you can see the change before pulling anything. If it still
shows the old version, the pattern did not match and you stop there rather than pulling.

Watch the log until migrations finish and the server reports it is listening. `Ctrl+C` stops
following the log; it does not stop the container. Then confirm the migration was clean:

```bash
sudo docker compose logs --tail=50 pangolin | grep -iE "migration|error|fail"
```

A healthy run looks like this:

```
Starting migrations from version 1.21.0
Migrations to run: 1.22.0
Running migration 1.22.0
1.22.0 migration complete
Successfully completed migration 1.22.0
All migrations completed successfully
```

Load the dashboard and confirm your sites show as connected before moving to the next version.

### 4. Upgrade Gerbil, Traefik, and Badger

Do these on the last hop. Change all four pins:

```bash
cd /opt/pangolin
sudo sed -i -E 's|fosrl/gerbil:[0-9.]+|fosrl/gerbil:1.5.2|' docker-compose.yml
sudo sed -i -E 's|traefik:v3\.6|traefik:v3.7|' docker-compose.yml
grep -n -A2 badger config/traefik/traefik_config.yml
```

Look at that last output before changing it. If it shows a single `version:` line under the badger
plugin:

```yaml
experimental:
  plugins:
    badger:
      moduleName: github.com/fosrl/badger
      version: v1.7.0
```

Then set it:

```bash
sudo sed -i -E 's|version: v1\.[0-9.]+|version: v1.7.0|' config/traefik/traefik_config.yml
```

Verify everything, then apply:

```bash
grep -n "image:" docker-compose.yml
grep -n -A2 badger config/traefik/traefik_config.yml
sudo docker compose pull
sudo docker compose up -d
sudo docker compose logs -f
```

Because Traefik shares Gerbil's network namespace (see
[Reading the Compose file](pangolin-configuration.md#reading-the-compose-file)), this step drops every published port
for a minute, not just the tunnels. Do it in a maintenance window if the server is serving anything that
matters.

### 5. Verify

```bash
sudo docker ps --format "{{.Names}}\t{{.Image}}\t{{.Status}}"
sudo docker compose logs --since 5m traefik | grep -iE "error|entrypoint"
sudo docker compose logs --since 5m pangolin | grep -iE "error|outdated"
```

Then in the dashboard: sites connected, one real resource loading end to end, and on Enterprise
Edition, the license still showing as valid.

### Rolling back

```bash
cd /opt/pangolin
sudo docker compose down
sudo rm -rf config docker-compose.yml
sudo tar -xzf /root/pangolin-backup-YYYY-MM-DD-HHMM.tar.gz -C /opt/pangolin
sudo docker compose up -d
```

Replace the filename with your actual backup. This restores the previous version's database,
certificates, and configuration together, which is the only combination guaranteed to work.

---

## Troubleshooting

### Certificate not issuing

Check that port 80 is reachable from the internet, since Let's Encrypt validates over HTTP:

```bash
sudo docker compose logs traefik | grep -i "acme\|certificate"
curl -I http://pangolin.example.com
```

The most common causes are a DNS record that has not propagated yet and a provider-level firewall
that still blocks port 80.

If you use a DNS-01 challenge for wildcard certificates, port 80 is not involved. Check the DNS
provider token instead: its permissions, and whether Traefik actually received it. See
[Wildcard certificates with a DNS-01 challenge](pangolin-configuration.md#wildcard-certificates-with-a-dns-01-challenge).

### A site shows as disconnected

On the site machine:

```bash
sudo systemctl status newt
sudo journalctl -u newt --since "10 minutes ago"
```

On the server:

```bash
cd /opt/pangolin
sudo docker compose logs --since 10m pangolin | grep -i "websocket\|site"
```

A healthy connection logs `WebSocket connection fully established and ready`. If the connector
cannot reach the server at all, confirm that UDP 51820 is open from the site's network.

### A router has no entry point

```
ERR EntryPoint doesn't exist entryPointName=tcp-25
```

The resource in Pangolin is pointing at an entry point that is not declared in
`config/traefik/traefik_config.yml`. Either add the entry point and publish the matching port on
the Gerbil service, or delete the resource in the dashboard. See
[Adding a custom entry point](pangolin-configuration.md#adding-a-custom-entry-point).

Note that logs are historical. `docker compose logs --tail=50` on an idle container shows you what
it said at startup, not its current state. Use `--since` to check whether a problem is still
happening:

```bash
sudo docker compose logs --since 5m traefik | grep -i error
```

Where those logs are stored, and how to stop them filling the disk, is covered under
[Traefik logs and log growth](pangolin-configuration.md#traefik-logs-and-log-growth).

### Pangolin container restarting or killed

Check whether it hit its memory limit:

```bash
sudo docker inspect pangolin --format '{{.State.OOMKilled}}'
free -h
```

If that returns `true`, raise the `deploy.resources.limits.memory` value in `docker-compose.yml`
(see [Reading the Compose file](pangolin-configuration.md#reading-the-compose-file)) and run `docker compose up -d`. An out-of-memory kill in the middle of a database migration is the
worst time for this to happen, so raise the limit before a large upgrade rather than after.

### Migration failed and the container will not start

```bash
sudo docker compose logs pangolin | grep -iE "migration|error"
```

A failed migration blocks startup by design. Restore the backup taken before the upgrade rather
than trying to patch the database by hand.

---

## Reference

- Pangolin documentation: <https://docs.pangolin.net>
- Pangolin releases: <https://github.com/fosrl/pangolin/releases>
- Gerbil releases: <https://github.com/fosrl/gerbil/releases>
- Badger releases: <https://github.com/fosrl/badger/releases>
- Traefik releases: <https://github.com/traefik/traefik/releases>
