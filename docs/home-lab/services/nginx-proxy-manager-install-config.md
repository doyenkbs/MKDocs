---
tags:
  - Nginx Proxy Manager
  - Networking
---

# Installing and Configuring Nginx Proxy Manager

Nginx Proxy Manager is the reverse proxy that every internal hostname in this lab resolves to. Technitium answers `audiobook.example.com` with the proxy's address, and the proxy decides which backend actually serves the request based on the hostname.

This page covers the install, the wildcard certificate, and the per-service configuration. It assumes [Technitium is already set up](technitium-dns-install-ubuntu-lxc.md) and the [split-horizon page](split-horizon-dns-technitium-npm.md) has been read, because the two are only useful together.

All addresses and domain names below are examples.

| Example value | What it is |
| --- | --- |
| `10.10.0.0/24` | The lab LAN |
| `10.10.0.3` | Technitium |
| `10.10.0.7` | Nginx Proxy Manager |
| `example.com` | The public domain |

## What this actually does here

Worth being clear about the role, because it is narrower than most guides assume.

External traffic reaches this lab through a [Cloudflare tunnel](cloudflaretunnel.md), not through a port forward. Nothing is published by opening 80 and 443 on the router.

Nginx Proxy Manager exists to terminate traffic on the LAN. A client inside the network resolves a service name to `10.10.0.7`, connects directly, and gets the service without leaving the network. That is the whole point of the split-horizon setup on the Technitium side.

The proxy also gives you one place to hold certificates, one place to see which hostnames exist, and one place to change a backend port without touching DNS.

## Container

Nginx Proxy Manager runs as a Docker container. Running Docker inside an unprivileged Proxmox LXC works, but it needs two features enabled that are off by default.

| Setting | Value |
| --- | --- |
| CT ID | `100` |
| Hostname | `npm` |
| Template | Debian 12 or Ubuntu 24.04 |
| Unprivileged | Yes |
| Features | `nesting=1`, `keyctl=1` |
| CPU | 2 cores |
| RAM | 1024 MB |
| Disk | 8 GB |
| Network | Bridged to the LAN, static IP `10.10.0.7` |
| Start at boot | Yes |

Set the features under **Options > Features** in the Proxmox UI, or from the host shell:

```bash
pct set 100 --features nesting=1,keyctl=1
```

Without `nesting`, Docker will not start. Without `keyctl`, some containers fail in ways that are hard to diagnose because the error surfaces inside the application rather than at the Docker layer.

A static IP is required. Every internal DNS record points at this address, so it cannot move.

## Install Docker

```bash
apt update && apt upgrade -y
apt install -y ca-certificates curl
curl -fsSL https://get.docker.com | sh
docker --version
docker compose version
```

## Deploy

```bash
mkdir -p /opt/npm && cd /opt/npm
```

Create `/opt/npm/docker-compose.yml`:

```yaml
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped

    ports:
      # These ports are in format <host-port>:<container-port>
      - '80:80'      # Public HTTP Port
      - '443:443'    # Public HTTPS Port
      - '81:81'      # Admin Web Port
      - '3389:3389'  # RDP, forwarded as a stream host
      # Add any other Stream port you want to expose
      # - '21:21'    # FTP

    environment:
      TZ: "America/New_York"

      # Uncomment this if you want to change the location of
      # the SQLite DB file within the container
      # DB_SQLITE_FILE: "/data/database.sqlite"

      # Uncomment this if IPv6 is not enabled on your host
      # DISABLE_IPV6: 'true'

    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
```

Start it:

```bash
docker compose up -d
docker compose logs -f
```

**Ports.** 80 and 443 are the proxy itself. 81 is the admin console. Anything beyond those three is a stream host, covered further down. Only publish what you are actually using. Every published port is a listener on the LAN.

**Time zone.** Use an IANA time zone name, which is always `Area/Location` where the area is a continent or ocean: `America/New_York`, `Europe/London`, `Asia/Tokyo`. A country name is not a valid area. If the value does not match a zone in the database, the container silently falls back to UTC rather than failing to start. Nothing breaks, but every timestamp in the access and error logs is then several hours off from wall clock, which makes correlating a proxy log against an application log needlessly painful. Confirm it took:

```bash
docker compose exec app date
```

**Volumes.** These two directories hold everything that matters: the SQLite database and proxy host definitions in `./data`, the certificates in `./letsencrypt`. Back them up and this container can be rebuilt from nothing.

**Container name.** There is no `container_name` set, so Compose derives one from the directory, giving `npm-app-1` for a project in `/opt/npm`. That is fine. Use `docker compose` commands from the project directory rather than `docker` commands with an explicit name, and it does not matter what the container is called.

**DISABLE_IPV6.** Leave it commented unless the host has no IPv6. With IPv6 disabled at the host level and this setting still off, nginx tries to bind `[::]` and the container restarts in a loop. That failure looks like a broken image rather than a network setting.

## First login

Open `http://10.10.0.7:81`.

Default credentials:

```
Email:    admin@example.com
Password: changeme
```

You are forced to change these on first login. Do it properly rather than setting something temporary, because Nginx Proxy Manager has no built-in multi-factor authentication. The password is the only thing protecting a console that can issue certificates for your domain and route traffic anywhere on the network.

Never publish port 81 through the tunnel or a port forward. Admin access stays on the LAN.

The console is plain HTTP. Nginx Proxy Manager has no TLS option for its own admin port, so the password crosses the network in cleartext on every login. On a wired lab LAN that is a low risk, but it is worth knowing before you reuse that password anywhere else.

You can proxy the console through the proxy itself to get TLS on it: create a proxy host for something like `npm.example.com` forwarding to `10.10.0.7:81` with the wildcard certificate. If you do this, leave port 81 reachable on the LAN as well. A broken proxy config or an expired certificate would otherwise lock you out of the only interface that can fix it.

## Wildcard certificate

This is the part that trips people up, and the reason matters.

Internal hostnames have no public DNS record pointing at this proxy. `audiobook.example.com` resolves publicly to a Cloudflare tunnel, not to `10.10.0.7`. HTTP-01 validation works by having Let's Encrypt connect to the name over the internet, so it cannot validate a name that does not route back to this box.

DNS-01 validation solves it. Instead of connecting to the host, Let's Encrypt asks for a TXT record to be created in the domain's DNS. Nginx Proxy Manager creates it through the Cloudflare API, Let's Encrypt reads it from public DNS, and the certificate issues without any inbound connection.

### Create the Cloudflare token

In the Cloudflare dashboard, under **My Profile > API Tokens > Create Token**, use the custom token option:

| Permission | Scope |
| --- | --- |
| Zone > DNS > Edit | `example.com` |
| Zone > Zone > Read | `example.com` |

Scope it to the single zone. Do not use a Global API Key. A global key is equivalent to your Cloudflare password and can modify every zone on the account, and it will be sitting in a config file inside this container.

### Request the certificate

**SSL Certificates > Add SSL Certificate > Let's Encrypt**

| Field | Value |
| --- | --- |
| Domain Names | `example.com`<br>`*.example.com` |
| Use a DNS Challenge | On |
| DNS Provider | Cloudflare |
| Credentials | `dns_cloudflare_api_token = <token>` |
| Propagation Seconds | `60` |

One wildcard certificate covers every service. Without it, you would be issuing a certificate per hostname, and each one would hit the same DNS-01 requirement anyway.

If issuance fails with a validation error, raise the propagation seconds before assuming the token is wrong. Cloudflare usually publishes the TXT record within seconds, but Let's Encrypt occasionally queries before it has propagated everywhere.

Renewal is automatic and uses the same token. If the token is ever revoked or rescoped, renewals fail silently until a certificate actually expires, so treat that token as infrastructure rather than a one-time setup step.

## Adding a service

**Hosts > Proxy Hosts > Add Proxy Host**

**Details tab**

| Field | Value |
| --- | --- |
| Domain Names | `audiobook.example.com` |
| Scheme | `http` |
| Forward Hostname / IP | The service's internal address |
| Forward Port | The service's port |
| Cache Assets | Off unless you have a reason |
| Block Common Exploits | On |
| Websockets Support | On for anything with a live UI |

Use `http` as the scheme even though clients connect over HTTPS. TLS terminates at the proxy. Re-encrypting to the backend inside your own LAN adds certificate management on every service for very little gain, unless something specific requires it.

Turn on Websockets Support for anything with a live-updating interface. Without it the page loads and then quietly stops updating, which reads like an application bug rather than a proxy setting.

**SSL tab**

| Field | Value |
| --- | --- |
| SSL Certificate | The wildcard certificate |
| Force SSL | On |
| HTTP/2 Support | On |
| HSTS Enabled | Only if you understand the commitment |

Leave HSTS off unless you are sure. It tells browsers to refuse plain HTTP for the domain for the duration of the max-age, and that instruction is cached client-side. Getting it wrong on a domain you also use publicly is difficult to undo.

Once the proxy host exists, add the matching record in Technitium. The split-horizon page covers whether that should be a plain A record or an APP record.

## Stream hosts

Proxy hosts handle HTTP and HTTPS. **Streams** handle raw TCP and UDP for protocols that are not HTTP at all, such as RDP.

**Hosts > Streams > Add Stream**

| Field | Value |
| --- | --- |
| Incoming Port | `3389` |
| Forward Host | The target machine's internal address |
| Forward Port | `3389` |
| TCP Forwarding | On |
| UDP Forwarding | Off unless the protocol needs it |

The incoming port has to be published on the container as well, which is why the compose file lists `3389:3389`. Adding a stream in the web console without adding the port to the compose file does nothing, because the container is not listening for it. Add the port, then `docker compose up -d` to recreate the container, then add the stream.

Understand what a stream is not. It forwards bytes. There is no TLS termination, no certificate, no authentication, and no access list. Whatever is listening on the other end is fully responsible for its own security, and the proxy will happily hand it every connection that arrives.

Keep stream ports on the LAN. RDP exposed to the internet is scanned and brute-forced continuously, and routing it through a proxy adds nothing except a second hop. If remote access to a Windows host is needed, put it behind the tunnel with an identity check in front, or reach it over a VPN.

## Access lists

**Access Lists** lets you put HTTP basic auth or an IP allowlist in front of a proxy host, applied before the request reaches the backend.

This is useful for services with weak or no authentication of their own. It is not a substitute for real authentication on anything that matters. If you are already running an identity provider, forward authentication through the **Advanced** tab is the better pattern, since it gives you one login and one place to revoke access rather than a separate basic-auth credential per service.

## Fitting with the Cloudflare tunnel

The tunnel and the proxy are two independent paths to the same services. Decide which one terminates external traffic and keep it consistent.

**Tunnel to the proxy.** `cloudflared` routes public hostnames to `http://10.10.0.7:80`, and the proxy routes onward by hostname. One place to add a service, one certificate, identical behavior inside and out. Cloudflare handles the public certificate at its edge, so the internal wildcard is only doing work for LAN clients.

**Tunnel direct to each service.** `cloudflared` maps each public hostname straight to a backend, bypassing the proxy entirely. Fewer hops, but every service is configured twice, and the two paths can drift until a service behaves differently depending on where you are sitting.

The first option is easier to keep straight once you are past a handful of services.

## Backup

Everything is in the two volumes.

```bash
cd /opt/npm
docker compose down
tar czf /root/npm-backup-$(date +%F).tar.gz data letsencrypt docker-compose.yml
docker compose up -d
```

Stop the container first. Copying the SQLite database while it is being written produces a backup that restores cleanly and then fails at runtime.

Back up the LXC through Proxmox Backup Server as well. That covers the whole container in one restore instead of a rebuild plus a file restore.

## Updating

```bash
cd /opt/npm
docker compose pull
docker compose up -d
docker image prune -f
```

Read the release notes before pulling. This container sits in front of every service in the lab, so an update that changes behavior takes everything with it. Take a backup first.

## Verify

```bash
# The proxy is answering
curl -sI http://10.10.0.7 | head -n 1

# The service resolves internally to the proxy
dig @10.10.0.3 audiobook.example.com +short

# End to end over TLS
curl -sI https://audiobook.example.com | head -n 1

# Certificate is the wildcard and not expired
echo | openssl s_client -connect audiobook.example.com:443 -servername audiobook.example.com 2>/dev/null \
  | openssl x509 -noout -subject -dates
```

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| 502 Bad Gateway | The backend is down, or the forward host and port are wrong. Test the backend address directly from inside the proxy container before touching the proxy config. |
| 504 Gateway Timeout | The backend is reachable but slow to respond. Usually the application, not the proxy. |
| Certificate error in the browser | The proxy host is not using the wildcard certificate, or the hostname is not covered by it. A wildcard covers one level only, so `a.b.example.com` needs its own certificate. |
| DNS challenge fails | Token scope, or propagation timing. Confirm the token has DNS Edit and Zone Read on the correct zone, then raise propagation seconds. |
| Page loads but never updates | Websockets Support is off on that proxy host. |
| Works externally, not internally | DNS, not the proxy. Check the internal record in Technitium. |
| Works internally, not externally | The tunnel, not the proxy. Check the `cloudflared` route for that hostname. |
| Docker will not start in the LXC | `nesting=1` is not set on the container. |
| A stream does nothing | The port is not published in the compose file. Add it and recreate the container. |
| Log timestamps are hours off | `TZ` is not a valid IANA zone, so the container fell back to UTC. |
| Container restart loop after a host change | IPv6 was disabled on the host without setting `DISABLE_IPV6`. |

## Notes

Two things will take this proxy down harder than anything else: the container not starting at boot, and the Cloudflare token expiring or losing scope. Neither produces an obvious error until something is already broken. Check both when a service stops working for no apparent reason.

---

## *References*

- [*Nginx Proxy Manager*](https://nginxproxymanager.com/): Project home and feature overview
- [*Setup Instructions*](https://nginxproxymanager.com/setup/): The official Compose deployment, including environment variables
- [*Full Setup Guide*](https://nginxproxymanager.com/guide/): Proxy hosts, streams, access lists, and certificate handling
- [*Advanced Configuration*](https://nginxproxymanager.com/advanced-config/): Custom Nginx directives and configuration overrides
- [*Nginx Proxy Manager on GitHub*](https://github.com/NginxProxyManager/nginx-proxy-manager): Source, releases, and issue tracker
- [*Install Docker Engine on Ubuntu*](https://docs.docker.com/engine/install/ubuntu/): The Docker and Compose install this page depends on
- [*Create a Cloudflare API Token*](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/): Scoping the token used for the DNS-01 challenge
- [*Let's Encrypt Challenge Types*](https://letsencrypt.org/docs/challenge-types/): Why DNS-01 is required here and HTTP-01 is not an option
