---
tags:
  - Pangolin
  - Networking
  - Reverse Proxy
---

# Pangolin configuration

Reference for the files the Pangolin installer creates, and the changes you are most likely to make
to them after the install is working.

You do not need any of this to get a working server. Come here when you want to change email
settings, publish a raw TCP or UDP port, switch to wildcard certificates, or understand what a file
is for before you edit it.

For installing the server in the first place, connecting a network to it, or upgrading it, see
the [Pangolin](pangolin.md) page.

All domains, IP addresses, and credentials on this page are examples. Replace them with your own.

---

## What the installer created

Everything lives under the install directory, `/opt/pangolin` by convention:

```
/opt/pangolin/
├── docker-compose.yml                  # the three services and their versions
├── config/
│   ├── config.yml                      # Pangolin server config: domains, email, flags
│   ├── db/                             # SQLite database (default backend)
│   ├── letsencrypt/                    # issued TLS certificates
│   └── traefik/
│       ├── traefik_config.yml          # Traefik static config, incl. the Badger plugin version
│       └── dynamic_config.yml          # Traefik dynamic config
```

Three of these matter most:

- **`docker-compose.yml`** pins the image version of each container. You edit this to upgrade.
- **`config/config.yml`** holds the server configuration: domains, email, and feature flags.
- **`config/traefik/traefik_config.yml`** pins the Badger plugin version and defines Traefik's
  entry points. You edit this when a Pangolin release requires a newer Badger.

## The server config file

`/opt/pangolin/config/config.yml` is written by the installer from your answers, and you edit it
by hand afterward. The sections below are the ones you are most likely to touch.

```yaml
gerbil:
    start_port: 51820                              # first UDP port for site tunnels
    base_endpoint: "pangolin.example.com"          # what sites and clients dial

app:
    dashboard_url: "https://pangolin.example.com"
    log_level: "info"                              # debug, info, warn, error
    telemetry:
        anonymous_usage: true                      # set false to opt out

domains:
    domain1:
        base_domain: "example.com"
        prefer_wildcard_cert: true                 # one wildcard cert instead of one per resource

server:
    secret: "REPLACE_WITH_A_LONG_RANDOM_STRING"    # signs sessions and tokens
    cors:
        origins: ["https://pangolin.example.com"]
        methods: ["GET", "POST", "PUT", "DELETE", "PATCH"]
        allowed_headers: ["X-CSRF-Token", "Content-Type"]
        credentials: false
    maxmind_db_path: "./config/GeoLite2-Country.mmdb"   # required for geo-blocking

email:
    smtp_host: "mail.example.com"
    smtp_port: 587
    smtp_user: "notifications@example.com"
    smtp_pass: "REPLACE_WITH_SMTP_PASSWORD"
    no_reply: "notifications@example.com"

flags:
    require_email_verification: true
    disable_signup_without_invite: true
    disable_user_create_org: false
    allow_raw_resources: true                      # required for TCP/UDP resources
```

Notes on individual keys:

- **`server.secret`** signs sessions and tokens. Treat it like a private key. If it is ever
  exposed, generate a new one with `openssl rand -base64 48`, replace the value, and restart the
  stack. Everyone will need to log in again.
- **`smtp_pass`** is stored in plain text in this file. Use an application password or a dedicated
  sending account rather than your main mailbox password, and keep the file at mode 600.
- **`flags.disable_signup_without_invite: true`** stops anyone who reaches the dashboard from
  creating an account. Leave this on for an internet-facing server.
- **`flags.allow_raw_resources: true`** is what enables TCP and UDP resources. Without it, only
  HTTP and HTTPS resources can be created.
- **`server.maxmind_db_path`** must point at a GeoLite2 database file for geo-blocking to work.
  The file is not shipped with Pangolin; you download it from MaxMind separately.

This file is read at startup. After editing it:

```bash
cd /opt/pangolin
sudo docker compose up -d
sudo docker compose logs --since 2m pangolin | grep -iE "error|config"
```

Check the permissions, since the file contains both the signing secret and the SMTP password:

```bash
sudo chmod 600 /opt/pangolin/config/config.yml
ls -l /opt/pangolin/config/config.yml
```

## Reading the Compose file

The structure below is what the installer generates. Comments call out the parts that matter.

```yaml
name: pangolin
services:
  pangolin:
    image: docker.io/fosrl/pangolin:1.22.2      # version pin; ee- prefix on Enterprise
    container_name: pangolin
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 2g                             # raise if the container is OOM-killed
    volumes:
      - ./config:/app/config                     # all persistent state lives here
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api/v1/"]
      interval: "10s"
      timeout: "10s"
      retries: 15

  gerbil:
    image: docker.io/fosrl/gerbil:1.5.2
    container_name: gerbil
    restart: unless-stopped
    depends_on:
      pangolin:
        condition: service_healthy               # gerbil waits for the control plane
    command:
      - --reachableAt=http://gerbil:3004
      - --generateAndSaveKeyTo=/var/config/key
      - --remoteConfig=http://pangolin:3001/api/v1/
    volumes:
      - ./config/:/var/config
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    ports:
      - 51820:51820/udp                          # site tunnels
      - 21820:21820/udp                          # client tunnels
      - 443:443                                  # Traefik's HTTPS, published here
      - 443:443/udp                              # HTTP/3 (QUIC), optional
      - 80:80                                    # Traefik's HTTP, published here

  traefik:
    image: docker.io/traefik:v3.7
    container_name: traefik
    restart: unless-stopped
    network_mode: service:gerbil                 # ports appear on the gerbil service
    depends_on:
      pangolin:
        condition: service_healthy
    command:
      - --configFile=/etc/traefik/traefik_config.yml
    environment:
      CLOUDFLARE_DNS_API_TOKEN: "REPLACE_WITH_TOKEN"   # only for DNS-01 wildcard certs
    volumes:
      - ./config/traefik:/etc/traefik:ro         # Traefik configuration
      - ./config/letsencrypt:/letsencrypt        # issued certificates
      - ./config/traefik/logs:/var/log/traefik   # access and application logs

networks:
  default:
    driver: bridge
    name: pangolin
    enable_ipv6: true
```

The `CLOUDFLARE_DNS_API_TOKEN` line is only needed for wildcard certificates. How to create that
token is covered under
[Create the Cloudflare API token](#create-the-cloudflare-api-token). Without wildcard
certificates, remove the line.

Note the `network_mode: service:gerbil` line on the Traefik service. Traefik has no ports of its
own; it uses Gerbil's network namespace, which is why ports 80 and 443 are published on the
**gerbil** service and not on Traefik. Two consequences follow from this:

- Restarting Gerbil takes Traefik down with it. Every published port goes dark for the duration,
  not just the tunnels.
- To publish an extra TCP port (for example a mail port), you add it to the **gerbil** ports list
  and add a matching entry point in `config/traefik/traefik_config.yml`. Adding it to the Traefik
  service does nothing.

## Adding a custom entry point

A router pointed at an entry point that does not exist produces this error in the Traefik log:

```
ERR EntryPoint doesn't exist entryPointName=tcp-25 routerName=2-Example-router@http
ERR No valid entryPoint for this router routerName=2-Example-router@http
```

Entry points are static configuration, so they only exist if they are declared in
`/opt/pangolin/config/traefik/traefik_config.yml`:

```yaml
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
  tcp-25:
    address: ":25"
```

Then publish the port on the Gerbil service in `docker-compose.yml`:

```yaml
    ports:
      - 25:25
```

Static configuration is only read at startup, so apply it with a restart:

```bash
cd /opt/pangolin
sudo docker compose up -d
sudo docker compose logs --since 2m traefik | grep -i "entrypoint"
```

Port 25 is used here only as an example, since SMTP is a common reason to need a raw TCP port. The
same three steps apply to any port: declare the entry point, publish the port on Gerbil, restart.

To remove a port later, reverse the order. Delete the resource in the dashboard first, then remove
the entry point from `traefik_config.yml` and the port from the Gerbil service, then restart. If
you remove the entry point while the resource still exists, Pangolin regenerates a router pointing
at an entry point that is gone, and Traefik logs the error below on every reload.

If instead you want to remove the router, delete the resource in the Pangolin dashboard. Pangolin
generates Traefik's dynamic configuration from your resources, so removing the entry point while
leaving the resource in place brings the error straight back on the next reload.

## Wildcard certificates with a DNS-01 challenge

The default HTTP-01 challenge issues one certificate per hostname. That works, but it means a
certificate request every time you publish a new resource, and it cannot issue a wildcard at all.

A DNS-01 challenge proves domain ownership by writing a TXT record instead of serving a file, so
it can issue a single `*.example.com` certificate that covers every resource. It requires an API
token from your DNS provider.

Turn it on in `config/config.yml`:

```yaml
domains:
    domain1:
        base_domain: "example.com"
        prefer_wildcard_cert: true
```

Then create an API token at your DNS provider and give it to Traefik. The steps below use
Cloudflare. Other providers are covered at the end of this section.

### Create the Cloudflare API token

The token needs two permissions. Traefik first looks up the zone ID for your domain, which needs
**Zone Read**, then writes a temporary TXT record, which needs **DNS Edit**. A token with only DNS
Edit fails the challenge. Cloudflare's **Edit zone DNS** template includes only DNS Edit, so the
Zone Read line has to be added by hand.

1. Sign in at <https://dash.cloudflare.com>.
2. Click the profile icon in the top right, then select **My Profile**.
3. In the left menu, select **API Tokens**.
4. Select **Create Token**.
5. Next to the **Edit zone DNS** template, select **Use template**.
6. At the top, click the pencil icon next to the token name and give it a name that says what it
   is for, for example `traefik-dns01-example.com`.
7. Under **Permissions**, the template has already filled in one row: **Zone**, **DNS**,
   **Edit**. Leave it.
8. Select **+ Add more** to add a second row, and set it to **Zone**, **Zone**, **Read**.
9. Under **Zone Resources**, set the row to **Include**, **Specific zone**, and choose your
   domain, for example `example.com`.
10. Optional, under **Client IP Address Filtering**: select **Is in** and enter your server's
    public IP, for example `203.0.113.10`. The token then only works from that server, so a leaked
    copy is useless anywhere else. Skip this if the server's IP can change.
11. Leave **TTL** empty. A token that expires silently stops certificate renewals, and you only find
    out when a certificate lapses.
12. Select **Continue to summary**, confirm it lists **Zone:Read** and **DNS:Edit** for your
    domain, then select **Create Token**.
13. Copy the token now. Cloudflare shows it only once. If you lose it, delete it and create a new
    one.

When you finished the steps, the permissions summary should read:

| Resource | Permission |
|---|---|
| Zone, `example.com` | Zone: Read |
| Zone, `example.com` | DNS: Edit |

### Verify the token before using it

Test it from the server before putting it anywhere. Replace `REPLACE_WITH_TOKEN` with the real
value and `example.com` with your domain:

```bash
curl -s "https://api.cloudflare.com/client/v4/zones?name=example.com" \
  -H "Authorization: Bearer REPLACE_WITH_TOKEN" | grep -o '"success":[a-z]*'
```

`"success":true` means the token can find your zone, which is the first thing Traefik does on
every certificate request. If you set an IP filter in step 10, run this from the Pangolin server
itself; run anywhere else, it correctly fails.

Cloudflare also has a dedicated token check at `/client/v4/user/tokens/verify`, but it only accepts
user tokens, the kind created under **My Profile**. A token created under **Manage Account >
Account API Tokens** returns `401 Unauthorized` there even when it works perfectly. The zone lookup
above works for both kinds.

Running this puts the token in your shell history. Remove that entry afterward. `history` prints two
numbers per line when piped through `grep -n`; the second one is the history number to delete:

```bash
history | grep "api.cloudflare.com"
history -d 123
history -w
```

Replace `123` with the history number from the first command. `history -w` writes the change to
disk so the token does not come back in your next session.

### Give the token to Traefik

Add it to the Traefik service in `/opt/pangolin/docker-compose.yml`:

```yaml
  traefik:
    environment:
      CLOUDFLARE_DNS_API_TOKEN: "REPLACE_WITH_TOKEN"
```

Traefik also accepts `CF_DNS_API_TOKEN` for the same value. Use one name, not both.

Confirm the certificate resolver in `/opt/pangolin/config/traefik/traefik_config.yml` uses the
Cloudflare DNS challenge:

```bash
grep -n -A6 "certificatesResolvers" /opt/pangolin/config/traefik/traefik_config.yml
```

A correctly configured resolver looks like this:

```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      dnsChallenge:
        provider: cloudflare
      email: admin@example.com
      storage: /letsencrypt/acme.json
```

The line that matters is `provider: cloudflare` under `dnsChallenge`. If the resolver shows
`httpChallenge` instead, the token is never used and you are still on per-hostname certificates.

### Check the token Traefik is actually using

Once the stack is running, you can test the token from inside the Traefik container. These
commands read the variable Traefik sees and never print its value.

Confirm the variable is set and has no stray quotes or spaces:

```bash
docker exec traefik sh -c 'v="$CLOUDFLARE_DNS_API_TOKEN"; [ -z "$v" ] && echo EMPTY || echo "set, length ${#v}"'
docker exec traefik sh -c 'printf %s "$CLOUDFLARE_DNS_API_TOKEN" | tr -d "[:alnum:]_-" | wc -c'
```

The first should print `set` with a length. The second should print `0`; anything higher means the
value in the Compose file or `.env` has quotes or spaces around it.

Confirm Cloudflare accepts it:

```bash
docker exec traefik sh -c 'wget -qO- --header="Authorization: Bearer $CLOUDFLARE_DNS_API_TOKEN" "https://api.cloudflare.com/client/v4/zones?name=example.com" | grep -o "\"success\":[a-z]*"'
```

`"success":true` means the next renewal will be able to authenticate. `401 Unauthorized` means the
token was deleted, rolled, or has expired, and needs replacing before the certificate's renewal
window opens. Traefik starts renewing 30 days before a certificate expires; check the date with
the `openssl` command in the next section.

Type these exactly as shown. `CLOUDFLARE_DNS_API_TOKEN` is the name of the variable, not a
placeholder, so do not paste the token into the command.

### Confirm the wildcard certificate was issued

List the certificates Traefik holds. This parses `acme.json` and prints only the domain fields,
never certificates or keys:

```bash
sudo python3 -c '
import json
d = json.load(open("/opt/pangolin/config/letsencrypt/acme.json"))
for resolver, v in d.items():
    for c in (v.get("Certificates") or []):
        print(resolver, c["domain"].get("main"), c["domain"].get("sans"))
'
```

Use this rather than `grep`. The file spreads each list of names across several lines, so a
single-line `grep` for the wildcard entry finds nothing even when it is there.

On a default install you should see two certificates:

```
letsencrypt pangolin.example.com None
letsencrypt example.com ['*.example.com']
```

Both are expected:

- **`example.com` with `*.example.com`** is the wildcard. Every resource you publish uses it.
- **`pangolin.example.com`** is a separate certificate for the dashboard itself. The installer's
  `config/traefik/dynamic_config.yml` defines three routers for the dashboard hostname. Only the
  first one asks for the wildcard; the API and WebSocket routers ask for their own hostname. When a
  browser connects, Traefik prefers an exact hostname match over a wildcard, so the dashboard is
  served the single-hostname certificate.

That second certificate is harmless. Both renew on their own. If you want to drop it, copy the
`domains:` block from the first router's `tls:` section into the other two, and Traefik stops
requesting it at the next renewal.

To see what a real visitor is served, test a **resource** hostname, not the dashboard. Testing the
dashboard hostname always shows the single-hostname certificate and tells you nothing about the
wildcard:

```bash
echo | openssl s_client -connect app.example.com:443 -servername app.example.com 2>/dev/null \
  | openssl x509 -noout -subject -ext subjectAltName -dates
```

Replace `app.example.com` with one of your published resources. A wildcard shows
`DNS:*.example.com` in the output.

Do not open `/opt/pangolin/config/letsencrypt/acme.json` with `cat` or an editor to check this. It
holds the private keys for every certificate Traefik has issued. The script above extracts only
the domain fields.

### The domain in the dashboard

In the dashboard, under **Domains**, the base domain shows a **Config Managed** badge with a lock
icon. That means Pangolin reads it from the `domains:` block in `config/config.yml`, and it can only
be changed there. There is nothing to set for it in the dashboard. **Add Domain** is for additional
domains beyond the one in the config file.

Apply the change and watch Traefik request the certificate:

```bash
cd /opt/pangolin
sudo docker compose up -d
sudo docker compose logs -f traefik | grep -iE "acme|certificate|cloudflare|error"
```

The first DNS-01 request takes longer than HTTP-01, often a minute or two, because Traefik waits for
the TXT record to propagate before telling Let's Encrypt to check it.

### Other DNS providers

Every provider uses its own variable names, and the resolver's `provider:` value has to match. Look
up yours in the Traefik ACME provider list at
<https://doc.traefik.io/traefik/https/acme/#providers>, which links to the exact variables each one
expects.

### Keep the token out of the Compose file

Putting the token directly in `docker-compose.yml` means it lands in version control if you ever
commit that file, and in any backup you share. Move it to a `.env` file next to the Compose file
instead:

```bash
cd /opt/pangolin
sudo nano .env
```

```bash
CLOUDFLARE_DNS_API_TOKEN=REPLACE_WITH_TOKEN
```

```bash
sudo chmod 600 /opt/pangolin/.env
```

Then reference it in the Compose file without the value:

```yaml
  traefik:
    environment:
      CLOUDFLARE_DNS_API_TOKEN: ${CLOUDFLARE_DNS_API_TOKEN}
```

Docker Compose reads `.env` from the working directory automatically. Add `.env` to `.gitignore`
if the directory is a repository.

Confirm Traefik still receives the value after the change:

```bash
cd /opt/pangolin
sudo docker compose up -d
sudo docker compose config | grep -c CLOUDFLARE_DNS_API_TOKEN
```

That prints a count, not the token. A result of `1` or more means Compose resolved the variable. If
you want to see the value itself, run `sudo docker compose config` without the `grep`, but note
that it prints the token to your terminal in plain text.

### If the token is ever exposed

Delete it at **My Profile > API Tokens**, using the **...** menu next to the token and selecting
**Delete**. Then create a new one with the steps above, put it in `.env`, and restart the stack with
`sudo docker compose up -d`. Existing certificates keep working; only the next renewal needs the new
token.

## Traefik logs and log growth

Two separate logs are involved, and it is easy to confuse them.

**The application log** is configured in `config/traefik/traefik_config.yml`:

```yaml
log:
  level: INFO
  format: common
  maxSize: 100
  maxBackups: 3
  maxAge: 3
```

The `maxSize`, `maxBackups`, and `maxAge` values only take effect when a `filePath` is also set.
Without one, Traefik writes to stdout and those rotation settings do nothing. Check yours:

```bash
grep -n -A6 "^log:" /opt/pangolin/config/traefik/traefik_config.yml
```

**The access log** is a separate `accessLog:` block and is off unless you add it:

```bash
grep -n -A5 -i "accessLog" /opt/pangolin/config/traefik/traefik_config.yml
```

The Compose file mounts `./config/traefik/logs` into the container, but that directory stays empty
until one of these logs is given a `filePath` inside it. A directory reporting 4.0K is empty.

```bash
sudo du -sh /opt/pangolin/config/traefik/logs
```

**Where the growth actually happens.** When containers log to stdout, Docker captures the output
with the `json-file` driver, which has no size limit by default. On a long-running server those
files grow until the disk fills. Check them:

```bash
sudo du -ch /var/lib/docker/containers/*/*-json.log | tail -20
```

Cap it globally in `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
```

Apply it:

```bash
sudo systemctl restart docker
```

The new limit applies only to containers created after the daemon restart. Existing containers
keep their original settings until they are recreated:

```bash
cd /opt/pangolin
sudo docker compose up -d --force-recreate
```

If you do enable access logging to a file, set up logrotate against that path as well, since
Traefik will not rotate it for you without the file-based settings above.
