---
tags:
  - Technitium DNS
  - Nginx Proxy Manager
  - Networking
---

# Split-Horizon DNS with the Technitium Split Horizon App and Nginx Proxy Manager

Most services in this lab are published to the internet through a Cloudflare tunnel. That works, but it means a laptop sitting three feet from the server was resolving `app.example.com` to the Cloudflare edge, going out to the internet, and coming back in through the tunnel to reach a machine on the same switch.

Split-horizon DNS fixes that. The same hostname resolves to the local Nginx Proxy Manager address when the client is on the LAN, and to the Cloudflare tunnel when it is not.

This page assumes [Technitium is already installed](technitium-dns-install-ubuntu-lxc.md) and serving the network, and that [Nginx Proxy Manager](nginx-proxy-manager-install-config.md) is running or about to be. Addresses and domain names below are examples.

| Example value | What it is |
| --- | --- |
| `10.10.0.3` | Technitium |
| `10.10.0.7` | Nginx Proxy Manager |
| `example.com` | The public domain, also served internally |

## Why the internal zone uses the real domain

Everything on this page follows from one decision: the internal zone is named `example.com`, the same domain that is published publicly, rather than an internal-only name like `lab.internal`.

That decision is what creates the need for split horizon in the first place. It is also what makes the setup worth building.

**What it buys.** One hostname works everywhere. `audiobook.example.com` is the address on the LAN, on the phone off-network, and over VPN. That matters more than it sounds:

- A single wildcard certificate for `*.example.com` is valid on both paths, so browsers do not complain in either location.
- Bookmarks, mobile apps, and saved credentials work without a second set of entries.
- Anything with a configured base URL keeps working. Applications behind single sign-on are the strict case here. An OAuth or OIDC redirect URI is registered as an exact string, so a service reached under a different hostname internally fails the redirect and the login breaks. Keeping one name avoids maintaining a second set of redirect URIs, or discovering the problem the first time someone signs in from the couch.

**What it costs.** Naming the zone after a domain you also own publicly makes Technitium authoritative for that entire domain on the LAN. From that moment:

- Every hostname that is not recreated locally disappears from the internal view, including names that were working fine because public DNS was answering for them.
- You have to know which public records actually need an internal copy. Most do not.
- Answers that need to differ by network require the Split Horizon app rather than plain records.

The mail hostname failure described further down this page is the direct result of this decision. It is a known cost, not a surprise.

**The alternative.** Naming the internal zone something that does not exist publicly avoids all of it. No shadowing, no recreated records, no APP records, no app to install. The price is that every internal hostname differs from its public one, which pushes the complexity into certificates, bookmarks, and application configuration instead of into DNS.

**How to choose.** If the services are internal only and never published, use a separate internal domain. If they are already published through a tunnel or reverse proxy and you want one URL that works from anywhere, use the real domain and accept that you now own the internal copy of every name clients need. This lab took the second path deliberately.

## How traffic flows

**On the LAN**

Client → Technitium → private answer `10.10.0.7` → Nginx Proxy Manager → service

**Off the LAN**

Client → Cloudflare public DNS → tunnel → Nginx Proxy Manager → service

Both paths end at the same reverse proxy, so certificates, access rules, and proxy settings are maintained in one place.

## The mechanism

Technitium does not do this with plain A records. It uses a DNS application called **Split Horizon**, installed from **Apps > App Store**.

The app adds a record type called **APP**. Instead of holding a fixed value, an APP record calls the application, which decides what to return based on the network the query came from.

There are two classes to know:

| Class path | Returns | Use it for |
| --- | --- | --- |
| `SplitHorizon.SimpleAddress` | A and AAAA records | Answers that are IP addresses on both sides |
| `SplitHorizon.SimpleCNAME` | A CNAME | Answers that are hostnames, including Cloudflare tunnel targets |

Picking the wrong class is the most common mistake here. `SimpleAddress` expects IP addresses. A Cloudflare tunnel target is a hostname like `<tunnel-uuid>.cfargotunnel.com`, not an address, so it belongs in a `SimpleCNAME` record.

## App configuration

**Apps > Split Horizon > Config**

```json
{
  "appPreference": 40,
  "networks": {
    "custom-networks": []
  },
  "enableAddressTranslation": false,
  "domainGroupMap": {
    "example.com": "local"
  },
  "networkGroupMap": {
    "0.0.0.0/0": "External"
  },
  "groups": [
    {
      "name": "External",
      "enabled": true,
      "translateReverseLookups": false,
      "externalToInternalTranslation": {}
    }
  ]
}
```

The app ships with built-in `private` and `public` groups. `private` covers RFC 1918 address space, which is every client on the LAN. `public` covers everything else. For a single-subnet lab that is all you need, and the record data below uses those two names directly.

`custom-networks` is where you would define named network ranges if you needed more than two views. For example, a guest VLAN that should get a different answer from the main LAN. Leave it empty until you have that requirement.

The app reloads its config automatically after you save. No service restart.

## Adding an APP record

**Zones > example.com > Add Record**

| Field | Value |
| --- | --- |
| Name | `audiobook` |
| Type | `APP` |
| TTL | `600` |
| App Name | `Split Horizon` |
| Class Path | `SplitHorizon.SimpleAddress` |

Record data for a service where both answers are addresses:

```json
{
  "private": [
    "10.10.0.7"
  ],
  "public": [
    "203.0.113.10"
  ]
}
```

For a service published through a Cloudflare tunnel, the public answer is a hostname, so use `SplitHorizon.SimpleCNAME` instead:

```json
{
  "private": "10.10.0.7",
  "public": "<tunnel-uuid>.cfargotunnel.com"
}
```

Every proxied service points at the same private address, because they all terminate at Nginx Proxy Manager. The proxy decides which backend to hit based on the hostname in the request.

## When a plain A record is the right answer

Not everything needs an APP record. Use a normal A record when the name resolves to the same place regardless of where the client is, or when it only exists internally:

| Name | Type | Value | Why |
| --- | --- | --- | --- |
| `npm` | A | `10.10.0.7` | The proxy's own management interface, internal only |
| `mail` | A | `203.0.113.25` | Same answer everywhere |

An APP record for one of these adds a lookup and a decision for no benefit. Reach for the app only when the answer actually differs by network.

## The record shadowing problem

Creating a primary zone for `example.com` makes Technitium authoritative for that domain on the LAN. It now answers every query under it, and anything not defined locally returns an empty answer rather than falling through to public DNS.

The scope of that is narrower than it first appears, and being precise about it matters. Mirroring records you do not need creates maintenance work and a second copy to drift out of sync for no benefit.

### What does not need mirroring: SPF, DKIM, DMARC

These are checked by the receiving mail server, not the sending one. When your mail server delivers a message, the recipient's server looks up SPF, DKIM, and DMARC for your domain using its own resolver, which reads public DNS. Your internal Technitium is never in that path.

Leave them out of the internal zone. Mail authentication keeps working with nothing mirrored.

### What usually does not need mirroring: MX

An MX record only matters to a client that performs an MX lookup to decide where to deliver mail for the domain.

Applications configured with a smarthost do not do this. When an app is told to relay through `mail.example.com` on port 587, it resolves that hostname directly and connects. No MX lookup happens, so an internal zone without an MX record changes nothing for it.

Add an MX record to the internal zone only if you have something on the LAN that resolves delivery by MX rather than by an explicit relay host. A mail server doing its own routing is the usual case.

### What does need creating: A records for names clients use

This is the actual gap, and it is where the outage came from.

Once the zone exists, every hostname under the domain resolves only if it is defined locally. Names that had never been in the internal zone because public DNS handled them simply stop working on the LAN:

| Name | Type | Value | Why it is needed |
| --- | --- | --- | --- |
| `mail` | A | The mail server address | Webmail and admin interfaces stop loading in the browser without it |
| Any published subdomain | A or APP | The proxy or the public address | Same reason |

The fix was a single A record for `mail.example.com`. Nothing else about mail needed to change.

The general rule: after creating the zone, walk your public DNS records and recreate the names that clients on the LAN actually need to reach. Ignore the records that only exist for other mail servers to read.

## Zone access

Open the zone options and confirm:

| Tab | Setting |
| --- | --- |
| Query Access | Allow Only Private Networks |
| Zone Transfer | Allow Only Name Servers In Zone |

With query access restricted to private networks, the zone is never served to a public client. That is worth understanding alongside the APP records: the `public` half of each record is a fallback that this server will not actually serve, because a query from a public network is refused before it gets that far. Real external clients are answered by Cloudflare, not by this server.

Keep the public values accurate anyway. They document what the external answer should be, and they matter if the zone access setting ever changes.

## Nginx Proxy Manager

Every private answer points here, so each service needs a proxy host.

| Field | Value |
| --- | --- |
| Domain Names | `audiobook.example.com` |
| Scheme | `http` |
| Forward Hostname / IP | The service's internal address |
| Forward Port | The service's port |
| Block Common Exploits | On |
| Websockets Support | On for anything with a live UI |

**Certificates.** Internal names have no public A record pointing at your proxy, so HTTP-01 validation will not work for them. Use a DNS-01 challenge with a Cloudflare API token scoped to `Zone:DNS:Edit` on the domain. A single wildcard certificate for `*.example.com` covers every service and avoids issuing a new certificate each time you add one.

## Verify

Compare the internal answer against the public answer. The service hostname should differ. The mail records should match exactly.

```bash
# Service name: internal should return the proxy, public should return Cloudflare
dig @10.10.0.3 audiobook.example.com +short
dig @1.1.1.1 audiobook.example.com +short

# Any hostname that exists in public DNS must also resolve internally
dig @10.10.0.3 mail.example.com +short
dig @1.1.1.1 mail.example.com +short
```

The second pair is the check that catches shadowing. If the internal lookup returns nothing while the public one returns an address, that name is missing from the zone.

From a client, confirm the request is actually reaching the proxy locally rather than going out and back:

```bash
curl -sI https://audiobook.example.com | head -n 1
traceroute audiobook.example.com
```

A local trace should be one or two hops. If it leaves the network, the client is not using Technitium.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Internal name resolves to the public address | Client is not using Technitium. Check the DHCP lease and any static DNS on the adapter. |
| Webmail or another published hostname stops loading on the LAN | The internal zone is authoritative and that name was never created locally. Add the A record. |
| A subdomain returns nothing internally but works externally | Same cause. Public DNS still answers for it, your internal resolver does not. |
| APP record returns nothing | Class path mismatch. A hostname in a `SimpleAddress` record will not resolve. Move it to `SimpleCNAME`. |
| Answer is correct but the site does not load | DNS is fine. The problem is the proxy host or the backend. Test the internal address and port directly. |
| Certificate renewal fails | HTTP-01 cannot validate a name with no public record pointing at the proxy. Switch to DNS-01. |
| Old answer keeps coming back | Cache. Flush the client cache, flush the Technitium cache from the **Cache** tab, and check the record TTL. |

## Notes

Keep the internal zone small. Every record in it is a record that has to be maintained in two places. If a service does not need a different answer inside the lab, leave it on public DNS.

---

## *References*

- [*Split Horizon App Source*](https://github.com/TechnitiumSoftware/DnsServer/tree/master/Apps/SplitHorizonApp): The application behind the APP records on this page, including the class paths
- [*Technitium DNS Apps*](https://github.com/TechnitiumSoftware/DnsServer/tree/master/Apps): Every app available from the App Store, useful when Split Horizon is not the right tool
- [*Technitium DNS Help*](https://technitium.com/dns/help.html): Zone and record reference, including APP record fields
- [*Nginx Proxy Manager Guide*](https://nginxproxymanager.com/guide/): The proxy side of this setup, where the internal answers actually terminate
