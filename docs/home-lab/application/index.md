# Self-Hosted Applications

This section covers the self-hosted applications in the home lab: file sharing, document management, media, monitoring, and asset tracking. It also covers **Authentik**, the identity provider that connects most of them through single sign-on.

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
    <span class="k-rack-code">Itsm</span>
    <span class="k-rack-title">GLPI</span>
    <span class="k-rack-desc">IT service management: tickets, asset inventory, and knowledge base, run with Docker Compose.</span>
    <span class="k-rack-go">&rarr;</span>
    ](glpi-docker.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Psa</span>
    <span class="k-rack-title">ITFlow</span>
    <span class="k-rack-desc">IT documentation, ticketing, and invoicing, with email-to-ticket from a self-hosted mailbox.</span>
    <span class="k-rack-go">&rarr;</span>
    ](itflow-install.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Vdi</span>
    <span class="k-rack-title">Kasm Workspaces</span>
    <span class="k-rack-desc">Browser-based containerized desktops and apps, plus fixed RDP servers.</span>
    <span class="k-rack-go">&rarr;</span>
    ](kasm-workspaces-install.md){ .k-rack-row }

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

-   [
    <span class="k-rack-code">Ai</span>
    <span class="k-rack-title">Wardrowbe</span>
    <span class="k-rack-desc">AI wardrobe organizer and outfit suggestions, with hosted AI (Gemini primary, Groq fallback through LiteLLM) and Authentik sign-in.</span>
    <span class="k-rack-go">&rarr;</span>
    ](wardrowbe.md){ .k-rack-row }

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
| Kasm Workspaces | [Kasm Workspaces Integration](kasm-authentik-oidc.md) |
| Nextcloud | [Nextcloud Integration](nextcloudintegration.md) |
| Paperless-NGX | [Paperless-NGX Integration](paperlessintegration.md) |
| Wardrowbe | [Step 8 of the Wardrowbe guide](wardrowbe.md#step-8-configure-authentik-oidc) |

---

## Why Authentik Ties This Section Together

Most of the apps above support external authentication. This lab does not keep a separate login (and a separate MFA setup) for each service. It sends all of them through Authentik as one identity provider:

- **One account, one MFA setup** — enrolled once in Authentik, applies everywhere it's connected
- **Centralized access control** — enable, disable, or restrict access to a service from one place
- **Consistent audit trail** — logins across every integrated app are visible from a single admin panel

If you set up this section from the start, use this order: install the base application and make sure that it works alone → deploy [Authentik](authentik.md) → then do the integration guide for that app above.

---

## Section Notes

- **OpenVPN** gives remote network access to the lab. Its page is under [Core Services](../services/openvpn.md), not here, because it is infrastructure access, not a single application.
- Most applications here run in their own LXC container on Proxmox — see [Containers & Virtualization](../virtualization/index.md) for the hosting layer these apps sit on top of.