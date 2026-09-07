---
tags:
  - Technitium DNS
  - Networking
---

# Installing Technitium DNS Server on an Ubuntu LXC

This page covers a clean install of Technitium DNS Server in a Proxmox LXC and the initial setup: web console, forwarders, recursion, ad blocking, DHCP, and zones.

By the end you have a DNS server that hands out its own address over DHCP, filters ads for every client on the network, resolves an internal Active Directory domain through a conditional forwarder, and forwards everything else upstream over DNS-over-HTTPS.

Split-horizon DNS and the Nginx Proxy Manager integration are covered on separate pages, [Split-Horizon DNS](split-horizon-dns-technitium-npm.md) and [Nginx Proxy Manager](nginx-proxy-manager-install-config.md). Get this page working first.

All addresses and domain names on this page are examples. Substitute your own.

| Example value | What it is |
| --- | --- |
| `10.10.0.0/24` | The lab LAN |
| `10.10.0.3` | The Technitium container |
| `10.10.0.7` | Nginx Proxy Manager |
| `10.10.0.100`, `10.10.0.99` | Domain controllers |
| `example.com` | The public domain, also served internally |
| `lab.local` | The internal Active Directory domain |

## What you need first

- A Proxmox host and an Ubuntu 24.04 LXC template
- A static IP for the container. A DNS server cannot use DHCP for its own address.
- Nothing else on the network already listening on port 53
- A decision about DHCP. If a router or firewall currently runs DHCP, that has to be turned off before Technitium takes over. Two DHCP servers on one subnet hand out conflicting leases and produce failures that are hard to trace.

## Container

Create an unprivileged LXC from the Ubuntu 24.04 template.

| Setting | Value |
| --- | --- |
| CT ID | `101` |
| Hostname | `technitium` |
| Node | `pve1` |
| Template | Ubuntu 24.04 |
| Unprivileged | Yes |
| CPU | 2 cores |
| RAM | 1024 MB |
| Swap | 2048 MB |
| Disk | 16 GB |
| Network | Bridged to the LAN, static IP `10.10.0.3` |
| Start at boot | Yes |
| Tags | `linux`, `prod` |

**Start at boot is not optional.** If this container does not come up automatically, nothing on the network resolves after a host reboot, including the Proxmox web interface by name. Set it when you build the container, not after the first outage.

**Sizing.** These numbers come from a container that has been running the full setup described on this page: DNS, DHCP, three blocklists, and query logging.

| Resource | Allocated | Actual use |
| --- | --- | --- |
| CPU | 2 cores | Under 1% at idle |
| Memory | 1 GiB | Around 240 MiB, roughly 23% |
| Swap | 2 GiB | Around 160 MiB |
| Disk | 16 GB | Around 2.2 GB |

Technitium will run on 512 MB, but 1 GB gives room for blocklists and cache without touching swap under load. Do not go below 1 GB if you enable query logging.

Disk is where it is easy to overspend. The application, the OS, and the blocklists together sit near 2 GB. The reason to allocate more than that is the SQLite query log, which grows with query volume and is the only part of this install that gets meaningfully larger over time. 16 GB is comfortable. Allocating 50 GB is wasted space on the Proxmox storage pool, and growing an LXC disk later is a single command, so start small.

**Tags.** Proxmox tags cost nothing and make the container list readable once the lab passes ten guests. A `prod` tag on the DNS server is a useful reminder that a careless snapshot rollback here takes the whole network down with it.

DHCP has to reach clients by broadcast, so the container needs a bridged `veth` on the same bridge as the clients it serves. It will not work across a NAT'd or isolated bridge.

## Free up port 53

Ubuntu runs `systemd-resolved`, which binds a stub listener on `127.0.0.53:53`. Technitium cannot start until that is out of the way.

```bash
systemctl disable --now systemd-resolved
rm -f /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf
```

Confirm the port is free. This should return nothing:

```bash
ss -lntup | grep ':53'
```

## Install

The official installer handles the .NET runtime, the application files, and the systemd service.

```bash
curl -sSL https://download.technitium.com/dns/install.sh | sudo bash
```

When it finishes you will have:

```
/opt/technitium/dns     application files, install.log, start.sh, systemd.service
/opt/dotnet             bundled .NET runtime
```

The installer also drops a `resolv.conf.bak` in the application directory, so the original resolver config is recoverable if you need it.

Check the service:

```bash
systemctl status dns.service
journalctl -u dns -f
ss -lntup | grep ':53'
```

## First login

Open `http://10.10.0.3:5380`.

Default credentials are `admin` / `admin`. Change the password immediately under the account menu. This server controls name resolution for every client on the network.

The dashboard shows a version banner in the top right when an update is available. Updating is covered at the end of this page.

## Settings

### General

| Field | Value | Why |
| --- | --- | --- |
| DNS Server Domain | `ns01.example.com` | The name this server uses to identify itself. It shows up in SOA and NS records, so pick it before creating zones. |
| DNS Server Local End Points | `10.10.0.3:53` | Bind to the LAN address rather than everything. |
| DNS Server IPv4 Source Addresses | `0.0.0.0` | Default. |
| Default Record TTL | `600` | Ten minutes. Short enough that a record change propagates quickly while you are still building the lab. |
| Default NS Record TTL | `14400` | Default. |

### Web Service

| Field | Value |
| --- | --- |
| Web Service HTTP Port | `5380` |
| Enable HTTPS | On |
| Enable HTTP to HTTPS Redirection | On |
| Use A Self Signed TLS Certificate When TLS Certificate File Path Is Unspecified | On |
| Web Service HTTPS Port | `53443` |
| Real IP Header | `X-Real-IP` |

The console is then reachable at `https://10.10.0.3:53443`. The browser will warn about the self-signed certificate, which is expected on a LAN-only console.

The Real IP Header setting only matters if you later put the console behind a reverse proxy. Without it, every entry in the admin logs shows the proxy's address instead of the actual client.

### Optional Protocols

Enable **DNS-over-HTTPS** if you want clients to be able to query this server over encrypted DNS. Leave the rest off unless you have a reason. Each protocol you enable is another listener to secure.

### Recursion

| Field | Value |
| --- | --- |
| Recursion | Allow Recursion Only For Private Networks |
| QNAME Minimization | On |

Do not select **Allow Recursion**. That turns the server into an open resolver. If it is ever reachable from the internet, it will be found and used for DNS amplification attacks. The private-networks option is the correct choice for a lab resolver.

QNAME minimization sends only the label the upstream server needs at each step instead of the full name, so intermediate servers see less of what you are looking up.

### Proxy & Forwarders

| Field | Value |
| --- | --- |
| Forwarders | `https://1.1.1.1/dns-query`<br>`https://1.0.0.1/dns-query` |
| Forwarder Protocol | DNS-over-HTTPS |
| Enable Concurrent Forwarding | On |
| Forwarder Concurrency | 2 |

Anything the server is not authoritative for and cannot answer from cache goes here. DNS-over-HTTPS means the upstream lookups are encrypted, so the ISP sees a TLS connection instead of a stream of plaintext queries.

Concurrent forwarding queries both forwarders at once and takes whichever answers first, rather than working through them in order. It costs a little extra upstream traffic and removes the timeout delay when one forwarder is slow.

### Blocking

| Field | Value |
| --- | --- |
| Enable Blocking | On |
| Allow TXT Blocking Report | On |
| Blocking Type | NX Domain |
| Blocking Answer TTL | `30` |

Add blocklist URLs under **Allow / Block List URLs**. The StevenBlack hosts lists are a reasonable starting point, and the repository publishes themed variants so you can pick how aggressive the filtering is:

```
https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn/hosts
https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts
```

`NX Domain` tells the client the name does not exist, which most applications handle cleanly. The alternative, returning `0.0.0.0`, leaves the client trying to connect to an address that will never answer and often produces a slower timeout instead of a fast failure.

The short blocking TTL of 30 seconds matters when you have to unblock something. Add the domain to the allowed list and clients pick up the change within half a minute instead of holding a bad answer for hours.

When an application breaks right after you enable blocking, check **Dashboard > Top Blocked Domains** before assuming the application is at fault. Blocklists routinely take out click-tracking links in email and telemetry endpoints that some apps treat as a hard dependency.

## DHCP

**DHCP > Scopes > Add Scope**

| Field | Value |
| --- | --- |
| Name | `Lab` |
| Scope range | `10.10.0.20` to `10.10.0.70` |
| Subnet mask | `255.255.255.0` |
| Router | `10.10.0.1` |
| DNS servers | `10.10.0.3` |
| Domain name | `example.com` |
| Interface | `10.10.0.3` |

The DNS servers field is the point of running DHCP here. It puts every client on Technitium without touching individual machines.

Reserve the space above and below the scope range. Static infrastructure lives outside it. A range of `.20` to `.70` on a `/24` leaves the low addresses for servers and the high addresses for anything you add later.

Technitium registers leases as A records in the matching forward zone automatically, and the records carry a comment noting which scope created them. Those show up alongside your manual records in the zone view, which is normal. Do not delete them by hand. They expire with the lease.

Turn off the old DHCP server before enabling the scope, not after.

## Zones

Zone type is the decision that matters most on this page. The wrong type causes outages that do not look like DNS problems.

### Primary zone

A primary zone makes Technitium authoritative for that domain on your network.

**Zones > Add Zone > Primary Zone**, name `example.com`.

Two things to know before creating a zone for a domain you also own publicly:

1. Technitium now answers for every name under it. Anything not defined in the local zone returns an empty answer instead of falling through to public DNS.
2. Names that were working purely because public DNS answered for them will stop resolving on the LAN. Webmail, admin interfaces, and any published subdomain all need an A record in the internal zone.

Be precise about what actually needs recreating. SPF, DKIM, and DMARC do not. Those are read by the receiving mail server using public DNS, so your internal resolver never participates and mail authentication is unaffected. An MX record only matters if something on the LAN resolves mail delivery by MX rather than through a configured relay host, which most applications do not.

What breaks is plain hostname resolution. Walk your public records after creating the zone and recreate the names clients need to reach.

None of this applies if you name the zone something that does not exist publicly, such as `lab.internal`. Choosing the real domain is a deliberate trade: internal and external hostnames stay identical, and in exchange you own the internal copy of every name. The split-horizon page covers that trade in full. Make the choice before you create the zone, because changing it later means reissuing certificates and updating every application that has the hostname baked into its configuration.

A reverse zone is worth creating alongside it. **Add Zone > Primary Zone**, name `0.10.10.in-addr.arpa`. This gives you working PTR lookups, which makes logs and monitoring readable.

### Conditional forwarder zone

A conditional forwarder sends queries for one domain to a specific server without making Technitium authoritative for it.

**Zones > Add Zone > Conditional Forwarder Zone**, name `lab.local`.

Inside the zone, add FWD records:

| Name | Type | Protocol | Forwarder |
| --- | --- | --- | --- |
| `@` | FWD | UDP | `10.10.0.100` |
| `dc02` | FWD | UDP | `10.10.0.99` |

The `@` record forwards the whole domain to the first domain controller. A named record forwards one specific host to a different server, which is useful when a second DC is the faster or more reliable answer for its own name.

Do not create a primary zone for an Active Directory domain. The domain controller has to stay authoritative for it. AD registers its own SRV records dynamically, and those records are how domain-joined machines locate the DC, find the global catalog, and complete Kerberos authentication. If Technitium answers for the AD domain instead of forwarding to the DC, those lookups return nothing and domain-joined machines stop authenticating.

With the conditional forwarder in place, the DCs, SCCM server, and domain-joined clients resolve normally, and everything outside the AD domain still goes out through the regular forwarders.

### Zone options

Open a primary zone and click **Options**.

| Tab | Setting | Value |
| --- | --- | --- |
| Query Access | | Allow Only Private Networks |
| Zone Transfer | | Allow Only Name Servers In Zone |
| Dynamic Updates | | Deny (default) |

**Query Access** set to private networks only means the zone is never served to a public client, even if the server somehow becomes reachable from outside. On a zone that holds internal addresses, this is the setting that keeps your internal layout from leaking.

**Zone Transfer** restricted to name servers in the zone stops anyone from pulling the entire zone in one request. An unrestricted zone transfer hands over a complete inventory of every host you have named.

**Dynamic Updates** set to deny blocks RFC 2136 updates from clients. This does not affect the DHCP scope registering leases, which happens inside the server rather than over the wire.

## Apps

**Apps > App Store** installs DNS applications that extend the server.

Two worth installing:

- **Split Horizon.** Returns different answers depending on which network the client is on. This is the basis of the split-horizon page.
- **Query Logs (Sqlite).** Writes query logs to a local database so the **Logs** tab becomes searchable. Useful when tracking down which client is asking for what. It does add write load, so on a busy server watch disk usage.

## Verify

From a Windows client, confirm it actually picked up the new resolver:

```powershell
ipconfig /all
Get-DnsClientServerAddress -AddressFamily IPv4
Clear-DnsClientCache
```

Then test each resolution path:

```bash
# Recursive lookup through the forwarders
dig @10.10.0.3 example.org +short

# Internal name from the primary zone
dig @10.10.0.3 npm.example.com +short

# AD domain, answered by the domain controller through the conditional forwarder
dig @10.10.0.3 lab.local SOA +short

# AD service record, proves the forwarder is working properly
dig @10.10.0.3 _ldap._tcp.lab.local SRV +short

# Blocked domain, should return NXDOMAIN
dig @10.10.0.3 doubleclick.net

# Reverse lookup
dig @10.10.0.3 -x 10.10.0.7 +short
```

The dashboard shows live query counts and a client total. If it stays near zero after leases renew, clients are still pointed somewhere else.

## Maintenance

```bash
systemctl restart dns.service
systemctl status dns.service
journalctl -u dns -n 100 --no-pager
```

**Backup.** Use **Administration > Backup** in the console to export a zip containing settings, zones, apps, and blocklists. Do that before any zone change. The on-disk config lives outside the application directory:

```bash
ls -la /etc/dns
```

Back up the container itself too. Proxmox Backup Server handles this at the LXC level, which is faster to restore than rebuilding the service.

**Updating.** The dashboard shows a banner when a new version is available. See the next section.

## Upgrading

Check what you are on before you start. **About** shows the running version and the banner in the top right shows what is available. The gap between those two numbers decides how much care this takes.

| Upgrade | What happens |
| --- | --- |
| Point release, same major version (15.0 to 15.4) | Application files replaced, configuration untouched, no runtime change |
| Major version (14.x to 15.x) | New .NET runtime required, config format converted on first load, service account and paths may change |

v15 moved to the ASP.NET Core 10 runtime and switched the service to a non-root `dns-server` account. If you installed .NET yourself through apt instead of letting the installer manage it, a major upgrade extracts cleanly and then the service fails to start, because the new binaries need a runtime that is not there. The installer script updates the runtime for you, which is the main reason to use it over a manual extract.

Config conversion runs one way. Once a v15 server has loaded and converted the config, an older binary cannot read it. That is why the rollback that matters is a container-level restore, not swapping application files back.

### Back up first

Snapshot the container if the storage supports it:

```bash
pct list
pct snapshot 101 pre_upgrade
```

Snapshot names are validated as Proxmox configuration IDs. Letters, digits, and underscores only, starting with a letter. `pre-15.4` and `pre.15.4` are both rejected with `invalid configuration ID`.

If the command returns `snapshot feature is not available`, the container's storage cannot snapshot. Plain LVM and directory storage holding raw volumes do not support it, and a bind mount on the container disables the feature regardless of storage type. Confirm which applies:

```bash
pct config 101
pvesm status
```

Match the storage named on the `rootfs:` line against its Type in `pvesm status`. Any `mp0:` line pointing at a host path is a bind mount. Where snapshots are unavailable, take a backup instead:

```bash
pvesm status --content backup
vzdump 101 --mode stop --compress zstd --storage <backup-storage>
```

`--mode stop` produces a clean, consistent copy at the cost of a short DNS and DHCP outage while it runs. Substitute a real storage name for `<backup-storage>`, and confirm the file landed with `pvesm list <backup-storage> --content backup | grep 101`.

Either way, grab the configuration itself. It is small and it restores in seconds:

```bash
tar -czf /root/technitium-config-$(date +%F).tar.gz /etc/dns
```

Copy it off the container from the Proxmox host so it survives a container-level problem:

```bash
pct pull 101 /root/technitium-config-$(date +%F).tar.gz /root/technitium-config.tar.gz
```

The console export under **Administration > Backup** is worth taking as well, with one limitation: an export from a pre-v14 server will not restore into v14 or later through the UI.

### Run the upgrade

Same script as the install. It handles the runtime, the application files, permissions, and the service restart.

```bash
curl -sSL https://download.technitium.com/dns/install.sh | sudo bash
```

A successful run reports the runtime update, the download, the permission fix, and the service restart, ending with `Technitium DNS Server was installed successfully!`.

The manual method is the documented alternative if you want to control each step:

```bash
cd /tmp
wget -O DnsServerPortable.tar.gz https://download.technitium.com/dns/DnsServerPortable.tar.gz
systemctl stop dns.service
tar -zxf DnsServerPortable.tar.gz -C /opt/technitium/dns
chown -R dns-server:dns-server /opt/technitium/dns
systemctl start dns.service
journalctl --unit dns --follow
rm -f DnsServerPortable.tar.gz
```

The `chown` is the step people miss. Extracting as root leaves the new files owned by root while the service runs as `dns-server`, so the server starts but cannot write where it needs to. Stopping the service before extracting also avoids overwriting `.dll` files underneath a running process. Neither concern exists with the installer script, which does both.

### Verify

```bash
systemctl status dns.service --no-pager
```

Reload the console with Ctrl+F5 and check that **About** shows the new version. A normal refresh serves cached scripts from the previous version, which makes console buttons appear broken and looks like a failed upgrade.

Then test each resolution path, same as the install verification:

```bash
dig @10.10.0.3 example.org +short          # recursion through the forwarders
dig @10.10.0.3 npm.example.com +short      # internal primary zone
dig @10.10.0.3 dc02.lab.local +short       # conditional forwarder to the DC
```

Confirm the DHCP tab still shows active leases before you consider it done.

### Loopback queries refused after an upgrade

```
dig @127.0.0.1 example.org
;; communications error to 127.0.0.1#53: connection refused
```

This is not an upgrade failure. **Settings > DNS Server Local End Points** in this guide is bound to the LAN address only, so nothing listens on loopback. Confirm what the server is actually bound to:

```bash
ss -lntup | grep ':53'
```

A listener on `10.10.0.3:53` with nothing on `127.0.0.1:53` is the expected result. Test against the LAN address instead, or add `127.0.0.1` to the endpoint list if you want loopback available for troubleshooting from inside the container.

## Next

The [split-horizon setup](split-horizon-dns-technitium-npm.md) with [Nginx Proxy Manager](nginx-proxy-manager-install-config.md) builds directly on this configuration.

---

## *References*

- [*Technitium DNS Server*](https://technitium.com/dns/): Product page and installer downloads
- [*Technitium DNS Help*](https://technitium.com/dns/help.html): Official configuration reference for settings, zones, and DHCP
- [*Technitium DNS Server on GitHub*](https://github.com/TechnitiumSoftware/DnsServer): Source, issue tracker, and release notes
- [*Technitium Changelog*](https://github.com/TechnitiumSoftware/DnsServer/blob/master/CHANGELOG.md): What changed between versions before you update
- [*StevenBlack/hosts*](https://github.com/StevenBlack/hosts): The blocklists used in the ad blocking section, including the themed variants
- [*Proxmox VE Linux Containers*](https://pve.proxmox.com/wiki/Linux_Container): LXC container creation and configuration on the Proxmox side
