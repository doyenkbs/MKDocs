# Stalwart Mail Server and Bulwark Webmail (Docker Compose)

This page walks through a full install of a self-hosted mail server on a fresh VPS:

- **Stalwart** is the mail server. It handles SMTP, IMAP, JMAP, calendars, contacts, spam filtering, DKIM, and its own Let's Encrypt certificate.
- **Bulwark** is a modern webmail client for Stalwart. It stores no mail. It talks to Stalwart over JMAP.
- **Caddy** is a reverse proxy. It owns ports 80 and 443 and routes each web hostname to the right container.

Everything runs as three containers in one Docker Compose stack.

All names and addresses on this page are examples. Replace them with your own:

| Example value | Replace with |
|---|---|
| `example.com` | Your mail domain |
| `mail.example.com` | Your mail server hostname |
| `webmail.example.com` | Your webmail hostname |
| `203.0.113.10` | Your VPS public IPv4 address |
| `user@example.com` | Your first mailbox |

---

## How it fits together

```
                         Internet
                            |
        +-------------------+--------------------+
        |                                        |
  Mail ports (direct)                     Web ports (Caddy)
  25, 465, 993, 4190                      80, 443
        |                                        |
        v                                        v
   +----------+     http://stalwart:8080    +---------+
   | Stalwart | <-------------------------- |  Caddy  |
   +----------+                             +---------+
        ^                                        |
        |        http://bulwark:3000             |
        |  JMAP  +---------+ <-------------------+
        +--------| Bulwark |
                 +---------+
```

| Hostname | What answers | Used for |
|---|---|---|
| `mail.example.com` | Stalwart (mail ports direct, web through Caddy) | SMTP, IMAP, JMAP, admin console at `/admin`, user self-service at `/account` |
| `webmail.example.com` | Bulwark (through Caddy) | Webmail in the browser |
| `autoconfig`, `autodiscover`, `mta-sts`, `ua-auto-config` | Stalwart (through Caddy) | Automatic mail client setup and MTA-STS policy |

Why a reverse proxy is needed: Stalwart and Bulwark both serve HTTPS, and only one program can listen on port 443. The reverse proxy takes 443 and forwards each hostname to the right container. Because the proxy holds port 443, Stalwart gets its own certificate through the Cloudflare DNS challenge (DNS-01), which needs no open ports.

### Choosing a reverse proxy

Any reverse proxy that can forward HTTPS by hostname works here. **This guide uses Caddy.**

| Option | Notes |
|---|---|
| **Caddy** (used here) | One container, a short config file, and automatic Let's Encrypt certificates. |
| **Traefik** | Configured with Docker labels instead of a config file. A good fit if you already run it. |
| **Nginx** or **Nginx Proxy Manager** | Nginx Proxy Manager adds a web UI for managing hosts and certificates. |
| **Cloudflare Tunnel** | No inbound 80 or 443 needed, but it only carries web traffic, and the Free plan limits each upload to 100 MB (large webmail attachments fail). The `mail` hostname must stay a normal DNS record because the mail ports cannot go through a tunnel. |

The rest of the setup (Stalwart settings, DNS, Bulwark) is the same whichever proxy you pick. Stalwart's documentation has examples for Caddy, Traefik, Nginx, and HAProxy.

> **Mail ports never go through the proxy.** Ports 25, 465, 993, and 4190 are not HTTP, so they are published directly from the Stalwart container.

---

## Prerequisites

- A VPS with a public IPv4 address. Stalwart is light, so 2 vCPU and 4 GB RAM is enough for a personal server.
- A domain whose DNS is hosted in **Cloudflare**. Stalwart uses the Cloudflare API to publish mail records and to get its certificate.
- **Outbound port 25 open** at your VPS provider. Some providers block it by default. Without it, you cannot deliver mail to other servers.
- Access to set **reverse DNS (PTR)** for the VPS IP in your provider's control panel.
- An SSH client on your computer (Windows PowerShell includes `ssh`).

---

## Step 1: Install the operating system

In your VPS provider's control panel, install **Debian 13 (trixie)** with no application or control panel. Do not pick an image with Plesk or cPanel; those take ports 25, 80, and 443.

A reinstalled server has a new SSH host key. If you connected to this IP or hostname before, SSH refuses to connect and shows `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`.

Try removing the old entries first. In PowerShell on your computer:

```powershell
ssh-keygen -R 203.0.113.10
ssh-keygen -R mail.example.com
```

If the warning still appears, remove the entry by hand:

1. Read the warning. It names the exact file and line, for example `Offending ECDSA key in C:\\Users\\<you>/.ssh/known_hosts:5`.
2. List every known hosts file in your SSH folder:

    ```powershell
    Get-ChildItem $env:USERPROFILE\.ssh\known_hosts*
    ```

3. Open the file the warning named (it can be `known_hosts` or another file in that list) in Notepad:

    ```powershell
    notepad $env:USERPROFILE\.ssh\known_hosts
    ```

4. Delete the lines that start with the server's IP or hostname (or the line number from the warning), save, and connect again.

> **Note:** `ssh-keygen -R` saves a backup of the original file as `known_hosts.old` in the same folder.

---

## Step 2: Provider firewall

In your provider's firewall, allow these inbound ports and block everything else:

| Port | Protocol | Purpose |
|---|---|---|
| 22 | TCP | SSH (limit to your own IP if you can) |
| 25 | TCP | Inbound mail from other servers |
| 80 | TCP | Caddy certificate requests and HTTP redirect |
| 443 | TCP and UDP | HTTPS and HTTP/3 through Caddy |
| 465 | TCP | Mail submission from clients (implicit TLS) |
| 993 | TCP | IMAP (implicit TLS) |
| 4190 | TCP | ManageSieve (optional, only for desktop filter editors) |

Do **not** open 3000 or 8080. The setup screens are reached through an SSH tunnel.

> **Note:** Docker publishes ports by writing its own iptables rules, which bypass `ufw` on the host. The provider firewall is your real perimeter.

---

## Step 3: Reverse DNS

In your provider's control panel, set the reverse DNS (PTR) record for the VPS IPv4 address to `mail.example.com`.

Check it from any machine:

```bash
dig -x 203.0.113.10 +short
```

Expected output: `mail.example.com.`

---

## Step 4: Cloudflare DNS records

Go to **Cloudflare dashboard › example.com › DNS › Records** and add two records. Set both to **DNS only** (grey cloud):

| Type | Name | Content | Proxy status |
|---|---|---|---|
| A | `mail` | `203.0.113.10` | DNS only |
| A | `webmail` | `203.0.113.10` | DNS only |

Do **not** create MX, SPF, DKIM, DMARC, SRV, or the `autoconfig`, `autodiscover`, `mta-sts`, or `ua-auto-config` records by hand. Stalwart creates all of them in Step 9. Records you create by hand can conflict with the ones Stalwart tries to write.

Do not add an AAAA record for `mail` unless you also set an IPv6 PTR record.

---

## Step 5: Cloudflare API token for Stalwart

Stalwart needs an API token that can edit DNS for your domain only.

1. In Cloudflare, click your profile icon (top right) › **My Profile** › **API Tokens**.
2. Click **Create Token**.
3. Next to the **Edit zone DNS** template, click **Use template**.
4. Set **Token name** to something you will recognize, for example `stalwart-example-dns`.
5. Under **Zone Resources**, set: `Include` › `Specific zone` › `example.com`.
6. Click **Continue to summary**, then **Create Token**.
7. Copy the token value from the final screen and store it in a password manager. Cloudflare shows it only once.

> **Warning:** Use an **API Token**, not the **Global API Key** listed under "API Keys" on the same page. The Global API Key controls your entire Cloudflare account, and Stalwart rejects it with the error `6111 Invalid format for Authorization header`.

You will test the token on the VPS in Step 6.

---

## Step 6: Prepare the server and install Docker

SSH into the VPS as root:

```powershell
ssh root@mail.example.com
```

Update the system and set the hostname:

```bash
apt update && apt -y full-upgrade
hostnamectl set-hostname mail.example.com
apt -y install ca-certificates curl dnsutils netcat-openbsd
```

Make sure nothing on the host already uses the mail or web ports:

```bash
ss -tlnp | grep -E ':(25|80|443|465|993|4190)\b'
```

The command should print nothing. If `exim4` or `postfix` appears, remove it:

```bash
apt -y purge exim4* postfix && apt -y autoremove
```

Install Docker from Docker's official repository:

```bash
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
apt update
apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
docker compose version
```

Confirm outbound port 25 is open:

```bash
nc -vz -w5 gmail-smtp-in.l.google.com 25
```

Expected output ends with `succeeded`. If it times out, ask your provider to unblock outbound port 25 before going further.

Test the Cloudflare token from Step 5. The first line waits for you to paste the token; what you paste is not shown on screen:

```bash
read -rs CF_TOKEN; echo
curl -s -H "Authorization: Bearer $CF_TOKEN" https://api.cloudflare.com/client/v4/user/tokens/verify | grep -o '"status":"[a-z]*"'
unset CF_TOKEN
```

Expected output: `"status":"active"`

---

## Step 7: Create the stack files

Create the project folder and a file holding a temporary setup password for Stalwart:

```bash
mkdir -p /opt/mail && cd /opt/mail
echo "STALWART_RECOVERY_ADMIN=admin:$(openssl rand -hex 16)" > stalwart.env
chmod 600 stalwart.env
```

Create `/opt/mail/docker-compose.yml`:

```bash
cat > /opt/mail/docker-compose.yml <<'EOF'
services:
  stalwart:
    image: stalwartlabs/stalwart:v0.16
    container_name: stalwart
    restart: unless-stopped
    env_file: stalwart.env
    environment:
      - TZ=America/New_York
      - STALWART_PUBLIC_URL=https://mail.example.com
    ports:
      - "25:25"
      - "465:465"
      - "993:993"
      - "4190:4190"
      - "127.0.0.1:8080:8080"
    volumes:
      - stalwart-etc:/etc/stalwart
      - stalwart-data:/var/lib/stalwart

  bulwark:
    image: ghcr.io/bulwarkmail/webmail:latest
    container_name: bulwark
    restart: unless-stopped
    environment:
      - TZ=America/New_York
      - HOSTNAME=0.0.0.0
      - PORT=3000
    volumes:
      - bulwark-settings:/app/data/settings
      - bulwark-admin:/app/data/admin
      - bulwark-admin-state:/app/data/admin-state
      - bulwark-telemetry:/app/data/telemetry
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://127.0.0.1:3000/api/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    depends_on:
      - stalwart

  caddy:
    image: caddy:2
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    depends_on:
      - stalwart
      - bulwark

volumes:
  stalwart-etc:
  stalwart-data:
  bulwark-settings:
  bulwark-admin:
  bulwark-admin-state:
  bulwark-telemetry:
  caddy-data:
  caddy-config:
EOF
```

What each choice does:

| Setting | Why |
|---|---|
| `stalwartlabs/stalwart:v0.16` | Current image name, pinned to one minor version so an update cannot jump to a version with breaking changes. |
| Volumes at `/etc/stalwart` and `/var/lib/stalwart` | The only two paths the image writes to. A volume mounted anywhere else is ignored and data is lost when the container is recreated. |
| No port 587 | Stalwart has no listener on 587 by default. Clients use 465. |
| `127.0.0.1:8080` | Stalwart's setup screen, reachable only from the server itself (through an SSH tunnel). Removed in Step 15. |
| No `ports:` on Bulwark | Bulwark is only reached through Caddy on the internal Docker network, so it publishes nothing on the host. |
| `STALWART_PUBLIC_URL` | Tells Stalwart its public address, since Caddy handles HTTPS in front of it. |

Create `/opt/mail/Caddyfile`:

```bash
cat > /opt/mail/Caddyfile <<'EOF'
mail.example.com, autoconfig.example.com, autodiscover.example.com, mta-sts.example.com, ua-auto-config.example.com {
    reverse_proxy stalwart:8080
}

webmail.example.com {
    reverse_proxy bulwark:3000
}
EOF
```

The first block sends the mail hostname and the four client-setup hostnames to Stalwart. The second sends webmail to Bulwark. Bulwark's first-run setup page becomes reachable once Caddy starts, but it cannot be used without a one-time token that is only printed in the container log (Step 14).

Validate the compose file:

```bash
cd /opt/mail
docker compose config --quiet && echo OK
```

Expected output: `OK`

> **Warning:** Always use `--quiet`. Without it, `docker compose config` prints the setup password from `stalwart.env` on screen.

---

## Step 8: Start Stalwart and run its setup wizard

Start Stalwart and Bulwark (not Caddy yet):

```bash
cd /opt/mail
docker compose up -d stalwart bulwark
docker compose ps
```

Both containers should show `Up`.

Get the temporary admin password. This prints the password on screen:

```bash
cat /opt/mail/stalwart.env
```

The password is the part after `admin:`.

On your own computer, open a **new** PowerShell window and create an SSH tunnel to Stalwart's setup port. Leave this window open until Step 15:

```powershell
ssh -N -L 18080:127.0.0.1:8080 root@mail.example.com
```

After you enter your password, the window looks frozen. That is normal; `-N` keeps the tunnel open without starting a shell.

In your browser, go to:

```
http://127.0.0.1:18080/admin
```

Sign in with username `admin` and the password from `stalwart.env`. The setup wizard opens. Fill it in:

| Wizard screen | What to set |
|---|---|
| **Server identity** | Server hostname: `mail.example.com`. Default email domain: `example.com`. Leave **Automatically obtain TLS certificate** and **Generate email signing keys** checked. |
| **Storage** | Keep RocksDB and "Use data store" for every store. Check that the RocksDB **Path** starts with `/var/lib/stalwart`; any other path is outside the data volume. |
| **Account directory** | Use the Internal Directory. |
| **Logging** | Log destination: **Console**. A log file inside a container is lost on restart. |
| **DNS management** | Choose **Cloudflare** and paste the API token from Step 5 into the secret field. |

The final screen shows a permanent admin account (`admin@example.com`) and a generated password. **Save both now.** They are shown only once.

Restart Stalwart so the new configuration takes effect:

```bash
cd /opt/mail
docker compose restart stalwart
```

---

## Step 9: Confirm DNS records and the certificate

Watch the log for DNS and certificate activity:

```bash
cd /opt/mail
docker compose logs -f --since 5m stalwart | grep -Ei 'dns|acme|certificate|task'
```

A successful run looks like this, in order:

1. Many `DNS record created` lines (MX, SPF, DKIM, DMARC, SRV, CNAME records).
2. `ACME order started` with type `dns-01`.
3. `ACME order completed`, listing a validity window of about 90 days.

Press `Ctrl+C` when you see `ACME order completed`.

### If the DNS task failed

If the log shows `Task failed during processing ... DnsManagement`, fix the cause first. The most common one is `6111 Invalid format for Authorization header`, which means the wrong Cloudflare credential was pasted.

1. Go to `http://127.0.0.1:18080/admin` and sign in as `admin@example.com`.
2. Switch to **Settings** using the icons at the bottom of the left sidebar.
3. Go to **Network › DNS › DNS Providers** › open the Cloudflare entry.
4. Clear the **Secret** field, paste the API token from Step 5, and click **Save**.

A failed task does not run again on its own, so create a new one:

1. Switch to **Management** and go to **Tasks › Scheduled** › create (**+**).
2. **Task type:** open the list and scroll to the bottom. Choose **Perform DNS management for a domain**.
3. **Record Types:** click **Select options...** and select every type.
4. **Renew Certificate on Success:** turn on.
5. **Domain:** `example.com`.
6. **Status:** leave as *Pending task awaiting execution*.
7. **Due:** today, with the time set to now.
8. Click **Create**, then watch the log again.

### Verify the certificate

```bash
openssl s_client -connect mail.example.com:993 -servername mail.example.com </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

The `issuer=` line should name Let's Encrypt.

---

## Step 10: Review the DNS records Stalwart created

Go to **Cloudflare dashboard › example.com › DNS › Records** and check these items.

**Delete the CAA records.** Stalwart publishes two CAA records at the root of the domain:

```
example.com  CAA  0 issue "letsencrypt.org; accounturi=https://acme-v02.api.letsencrypt.org/acme/acct/..."
example.com  CAA  0 iodef "mailto:postmaster@example.com"
```

The `accounturi` value allows only Stalwart's own Let's Encrypt account to issue certificates for the whole domain. Caddy uses a different account, so its certificate requests fail. So can certificates for any other site on the domain. Delete both CAA records, then confirm:

```bash
dig +short CAA example.com @1.1.1.1
```

Expected output: nothing.

**Check proxy status.** The CNAME records `autoconfig`, `autodiscover`, `mta-sts`, and `ua-auto-config` must be **DNS only** (grey cloud). If any show an orange cloud, click **Edit** and switch them to DNS only.

**Remove the POP3 SRV record if you do not use POP3.** Stalwart publishes `_pop3s._tcp.example.com`, but port 995 is not published in this setup. Delete that SRV record so mail apps do not try POP3.

**Consider relaxing DMARC at first.** Stalwart publishes `_dmarc.example.com` with `p=reject`. That tells receiving servers to reject any message that fails checks. On a new server, a common approach is to start with monitoring only, then tighten after a week or two of clean reports. To do that, edit the `_dmarc` TXT record to:

```
v=DMARC1; p=none; rua=mailto:postmaster@example.com
```

---

## Step 11: Prepare Stalwart for the reverse proxy

Do this **before** starting Caddy.

Stalwart bans any IP that requests exploit-style paths such as `/info.php` or `/.env`. Internet scanners send those requests within minutes of a new site going live. Behind Caddy, every request reaches Stalwart from Caddy's container IP, so without these settings Stalwart bans Caddy itself and every web request returns `502`.

Find the Docker network's subnet:

```bash
docker network inspect mail_default --format '{{(index .IPAM.Config 0).Subnet}}'
```

Example output: `172.18.0.0/16`. Use your own output below.

In `http://127.0.0.1:18080/admin`, switch to **Settings** and change these three pages. Click **Save** on each page before leaving it.

1. **Network › HTTP › General**
    - Turn on **Obtain remote IP from Forwarded header**. Stalwart then sees and bans the real client IP instead of Caddy's.
2. **Network › HTTP › Security**
    - Turn on **Permissive CORS policy**. Bulwark runs in the browser on `webmail.example.com` and calls JMAP on `mail.example.com`, which needs CORS.
3. **Security › Allowed IPs**
    - Add the Docker subnet from the command above (for example `172.18.0.0/16`) so Caddy and the tunnel can never be banned.

Trusting the forwarded header is safe here only because port 8080 is never exposed to the internet. Only Caddy and the local `127.0.0.1` binding can reach it.

---

## Step 12: Start Caddy

```bash
cd /opt/mail
docker compose up -d caddy
docker compose logs -f caddy
```

Wait for `certificate obtained successfully` for `mail.example.com`, the four autoconfig hostnames, and `webmail.example.com`, then press `Ctrl+C`.

Test:

```bash
curl -sI https://mail.example.com/admin | head -1
```

Expected output: `HTTP/2 302` or `HTTP/2 200`.

From now on, the Stalwart admin console is at `https://mail.example.com/admin`.

---

## Step 13: Remove the temporary admin account

The recovery admin from `stalwart.env` is a backdoor login. Remove it once the permanent admin works over HTTPS:

```bash
cd /opt/mail
: > stalwart.env
docker compose up -d stalwart
```

---

## Step 14: Set up Bulwark

Confirm Bulwark can reach Stalwart's JMAP endpoint through Caddy:

```bash
cd /opt/mail
docker compose exec bulwark wget -S --spider https://mail.example.com/.well-known/jmap 2>&1 | grep "HTTP/"
```

Expected output: a redirect (`307`) followed by `200 OK`.

Bulwark's setup wizard needs a one-time token printed in its log. The token expires after 1 hour, so restart Bulwark to get a fresh one. This prints the token on screen:

```bash
docker compose restart bulwark
sleep 10
docker compose logs --since 1m bulwark | grep -iE 'token|setup'
```

Go to `https://webmail.example.com` and fill in the wizard:

| Wizard screen | What to set |
|---|---|
| **Welcome** | Paste the setup token (64 hex characters). |
| **Server** | JMAP server URL: `https://mail.example.com`. Click **Test**. Keep **Enable Stalwart-specific features** checked. |
| **Auth** | Leave **Enable OAuth2 / OpenID Connect** unchecked. Basic authentication is always available. |
| **Security** | Keep the generated session secret. Check **Sync user settings across devices** so preferences follow the user between browsers. The anonymous usage stats option is your choice; it does not change how webmail works. |
| **Logging** | Keep the defaults. |
| **Branding** | Optional: organization name, favicon, login logos, website URL. |
| **Review** | Confirm the server URL, then finish. Set the Bulwark admin password and save it. |

The Bulwark admin password is only for Bulwark's own settings (branding, plugins, policies) at `https://webmail.example.com/admin`. It is not a mailbox login.

---

## Step 15: Close the setup port

Stalwart's admin console now works at `https://mail.example.com/admin`, so the local setup port is no longer needed. Remove it:

```bash
cd /opt/mail
sed -i '/127.0.0.1:8080:8080/d' docker-compose.yml
docker compose config --quiet && echo OK
docker compose up -d
ss -tlnp | grep -E ':8080\b'
```

The last command should print nothing. Close the SSH tunnel window; it is no longer needed. Caddy still reaches Stalwart over the internal Docker network.

---

## Step 16: Create a mailbox and test

1. Go to `https://mail.example.com/admin` and sign in as `admin@example.com`.
2. Go to **Management › Directory › Accounts** › create a new account:
    - Name: the part before the `@`, for example `user`
    - Domain: `example.com`
    - A strong password
3. Go to `https://webmail.example.com` and sign in as `user@example.com`.
4. Send a message to yourself, then to an outside address (Gmail, Outlook.com) and reply back.
5. Send a message to the address shown at [mail-tester.com](https://www.mail-tester.com) and check the score.

---

## Mail app settings

Most apps (Thunderbird, Apple Mail, Outlook) configure themselves from the autoconfig records when you enter the email address and password. If an app asks for manual settings:

| | Server | Port | Security |
|---|---|---|---|
| Incoming (IMAP) | `mail.example.com` | 993 | SSL/TLS |
| Outgoing (SMTP) | `mail.example.com` | 465 | SSL/TLS |
| Username | Full email address, for example `user@example.com` | | |

Choose **IMAP**, not POP3, so every device sees the same mailbox. If an app offers port 587 with STARTTLS, change it to 465 with SSL/TLS.

Calendars and contacts use CalDAV and CardDAV on `mail.example.com`. Thunderbird, iOS, and macOS support them natively. On Android, use DAVx5.

If two-factor authentication is turned on for a mailbox, mail apps need an app password, created at `https://mail.example.com/account`.

---

## Maintenance

### Updates

```bash
cd /opt/mail
docker compose pull
docker compose up -d
```

Read the Stalwart and Bulwark release notes before updating. Once the setup is stable, pin Bulwark to a release tag instead of `latest` so updates happen only when you choose.

### Editing the Caddyfile

After any change to `/opt/mail/Caddyfile`, restart the container instead of running `caddy reload`:

```bash
cd /opt/mail
docker compose restart caddy
```

The Caddyfile is mounted into the container as a single file. `sed -i` and many editors save by writing a new file, and the running container keeps seeing the old one, so `caddy reload` reloads the old version. A restart mounts the current file.

### Backups

All mail, accounts, settings, and DKIM keys live in the `mail_stalwart-data` volume. Stop Stalwart briefly for a consistent copy:

```bash
cd /opt/mail
docker compose stop stalwart
tar -czf /root/stalwart-data-$(date +%F).tar.gz -C /var/lib/docker/volumes/mail_stalwart-data/_data .
docker compose start stalwart
```

Copy the archive off the server. If the DKIM keys are lost, outgoing signatures break until the DNS records are republished. Test a restore at least once.

Bulwark's volumes hold only webmail preferences and branding. Losing them does not lose mail.

### Check for returning CAA records

Stalwart may publish a CAA record again during later DNS management runs. If Caddy starts failing certificate renewals, check:

```bash
dig +short CAA example.com @1.1.1.1
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `services.<name>.ports must be a array` | A `ports:` key was left with no entries under it. | Remove the empty `ports:` line under that service, or restore the entry. |
| `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` when connecting over SSH | The server was reinstalled and has a new host key. | Remove the old entry (Step 1). |
| Stalwart log: `6111 Invalid format for Authorization header` | The Cloudflare Global API Key was used instead of an API Token. | Replace the secret (Step 9), then create a new DNS management task. |
| Stalwart log repeats `No TLS certificates available` | The DNS management task failed, so the certificate request never started. | Fix the DNS error and create a new DNS management task (Step 9). |
| `https://mail.example.com` returns `502` and the Stalwart log shows `Blocked IP address ... remoteIp = 172.18.x.x` | Stalwart auto-banned Caddy's container IP after scanner traffic. | Do Step 11, delete the entry under **Settings › Security › Blocked IPs**, then `docker compose restart stalwart`. |
| Caddy fails to get a certificate | A CAA record restricts issuance to Stalwart's account, or a record is proxied (orange cloud). | Delete the CAA records and set the records to DNS only (Step 10). |
| Browser says a site "sent an invalid response" | Caddy has no certificate for that hostname, often because it never loaded an edited Caddyfile. | `docker compose restart caddy` (see Editing the Caddyfile). |
| Bulwark wizard rejects the setup token | The token expired (1 hour). | Restart Bulwark and read the new token from the log (Step 14). |
| Webmail login page loads but sign-in fails | CORS is off in Stalwart. | Turn on **Permissive CORS policy** (Step 11). |
| Outbound mail stays queued and the log shows timeouts on port 25 | The VPS provider blocks outbound port 25. | Ask the provider to unblock it. |

---

## References

- [Stalwart: Docker installation](https://stalw.art/docs/install/platform/docker/)
- [Stalwart: Reverse proxy with Caddy](https://stalw.art/docs/server/reverse-proxy/caddy/)
- [Stalwart: Auto-banning](https://stalw.art/docs/server/auto-ban/)
- [Stalwart: TLS certificates](https://stalw.art/docs/domains/tls-certificates/)
- [Stalwart: Tasks](https://stalw.art/docs/management/tasks-actions/tasks/)
- [Bulwark Webmail on GitHub](https://github.com/bulwarkmail/webmail)
