# Self-Hosted Applications

This section covers the self-hosted applications running in the home lab — file sharing, document management, media, monitoring, and asset tracking — along with **Authentik**, the identity provider tying most of them together under single sign-on.

## Applications

<div class="k-rack" markdown>

-   [
    <span class="k-rack-code">Media</span>
    <span class="k-rack-title">Audiobookshelf</span>
    <span class="k-rack-desc">Self-hosted audiobook and podcast server.</span>
    <span class="k-rack-go">&rarr;</span>
    ](audiobookshelf.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Wiki</span>
    <span class="k-rack-title">Bookstack</span>
    <span class="k-rack-desc">Documentation and wiki platform for organizing lab notes and guides.</span>
    <span class="k-rack-go">&rarr;</span>
    ](bookstack.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Files</span>
    <span class="k-rack-title">Nextcloud</span>
    <span class="k-rack-desc">Private cloud storage, file sync, and collaboration suite.</span>
    <span class="k-rack-go">&rarr;</span>
    ](nextcloud.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Xfer</span>
    <span class="k-rack-title">Pairdrop</span>
    <span class="k-rack-desc">Local network file sharing, a self-hosted alternative to AirDrop.</span>
    <span class="k-rack-go">&rarr;</span>
    ](pairdrop.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Docs</span>
    <span class="k-rack-title">Paperless-NGX</span>
    <span class="k-rack-desc">Document management with OCR and automated indexing.</span>
    <span class="k-rack-go">&rarr;</span>
    ](paperless.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Asset</span>
    <span class="k-rack-title">Snipe-IT</span>
    <span class="k-rack-desc">IT asset management and inventory tracking.</span>
    <span class="k-rack-go">&rarr;</span>
    ](snipeit.md){ .k-rack-row }

</div>

!!! note "Not documented yet"

    Zabbix runs in the lab for infrastructure and service monitoring, but the
    write-up is still in progress, so there is no page to link to yet.

---

## Identity: Authentik

<div class="k-rack" markdown>

-   [
    <span class="k-rack-code">Sso</span>
    <span class="k-rack-title">Authentik</span>
    <span class="k-rack-desc">Self-hosted identity provider (OIDC/SAML/LDAP) providing SSO and MFA across most services in this lab.</span>
    <span class="k-rack-go">&rarr;</span>
    ](authentik.md){ .k-rack-row }

</div>

### Authentik Integrations

Once Authentik is running, each of these walks through connecting a specific app to it for SSO:

| App | Integration Guide |
|---|---|
| Audiobookshelf | [Audiobookshelf Integration](audiobookshelfintegration.md) |
| Bookstack | [Bookstack Integration](bookstackintegration.md) |
| Cloudflare Access | [Cloudflare Integration](cloudflareIntegration.md) |
| Nextcloud | [Nextcloud Integration](nextcloudintegration.md) |
| Paperless-NGX | [Paperless-NGX Integration](paperlessintegration.md) |

---

## Why Authentik Ties This Section Together

Most of the apps above support external authentication, and rather than managing separate logins (and separate MFA setups) per service, this lab routes them all through Authentik as a single identity provider:

- **One account, one MFA setup** — enrolled once in Authentik, applies everywhere it's connected
- **Centralized access control** — enable, disable, or restrict access to a service from one place
- **Consistent audit trail** — logins across every integrated app are visible from a single admin panel

If you're setting this section up from scratch, a sensible build order is: get the base application running and confirm it works standalone → deploy [Authentik](authentik.md) → then work through that app's specific integration guide above.

---

## Section Notes

- **OpenVPN** provides remote network access into the lab and is documented under [Core Services](../services/openvpn.md) rather than here, since it's infrastructure-level access rather than an individual application.
- Most applications here run in their own LXC container on Proxmox — see [Containers & Virtualization](../virtualization/index.md) for the hosting layer these apps sit on top of.