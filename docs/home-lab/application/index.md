# **<span style="color:#009688;">Self-Hosted Applications</span>**

This section covers the self-hosted applications running in the home lab — file sharing, document management, media, monitoring, and asset tracking — along with **Authentik**, the identity provider tying most of them together under single sign-on.

## **<span style="color:#009688;">Applications</span>**

<div class="grid cards" markdown>

-   :material-headphones: **Audiobookshelf**

    ---

    Self-hosted audiobook and podcast server.

    [:octicons-arrow-right-24: Start here](audiobookshelf.md)

-   :material-book-open-page-variant-outline: **Bookstack**

    ---

    Documentation and wiki platform for organizing lab notes and guides.

    [:octicons-arrow-right-24: Start here](bookstack.md)

-   :material-cloud-outline: **Nextcloud**

    ---

    Private cloud storage, file sync, and collaboration suite.

    [:octicons-arrow-right-24: Start here](nextcloud.md)

-   :material-transfer: **Pairdrop**

    ---

    Local network file sharing — a self-hosted alternative to AirDrop.

    [:octicons-arrow-right-24: Start here](pairdrop.md)

-   :material-file-document-outline: **Paperless-NGX**

    ---

    Document management with OCR and automated indexing.

    [:octicons-arrow-right-24: Start here](paperless.md)

-   :material-barcode-scan: **Snipe-IT**

    ---

    IT asset management and inventory tracking.

    [:octicons-arrow-right-24: Start here](snipeit.md)

-   :material-chart-line: **Zabbix**

    ---

    Infrastructure and service monitoring across the lab.

    [:octicons-arrow-right-24: Start here](zabbix.md)

</div>

---

## **<span style="color:#009688;">Identity: Authentik</span>**

<div class="grid cards" markdown>

-   :material-account-key-outline: **Authentik**

    ---

    Self-hosted identity provider (OIDC/SAML/LDAP) providing SSO and MFA across most services in this lab.

    [:octicons-arrow-right-24: Start here](authentik.md)

</div>

### **<span style="color:#009688;">Authentik Integrations</span>**

Once Authentik is running, each of these walks through connecting a specific app to it for SSO:

| App | Integration Guide |
|---|---|
| Audiobookshelf | [Audiobookshelf Integration](audiobookshelfintegration.md) |
| Bookstack | [Bookstack Integration](bookstackintegration.md) |
| Cloudflare Access | [Cloudflare Integration](cloudflareaccess.md) |
| Nextcloud | [Nextcloud Integration](nextcloudintegration.md) |
| Paperless-NGX | [Paperless-NGX Integration](paperlessintegration.md) |

---

## **<span style="color:#009688;">Why Authentik Ties This Section Together</span>**

Most of the apps above support external authentication, and rather than managing separate logins (and separate MFA setups) per service, this lab routes them all through Authentik as a single identity provider:

- **One account, one MFA setup** — enrolled once in Authentik, applies everywhere it's connected
- **Centralized access control** — enable, disable, or restrict access to a service from one place
- **Consistent audit trail** — logins across every integrated app are visible from a single admin panel

If you're setting this section up from scratch, a sensible build order is: get the base application running and confirm it works standalone → deploy [Authentik](authentik.md) → then work through that app's specific integration guide above.

---

## Section Notes

- **OpenVPN** provides remote network access into the lab and is documented under [Core Services](../services/openvpn.md) rather than here, since it's infrastructure-level access rather than an individual application.
- Most applications here run in their own LXC container on Proxmox — see [Containers & Virtualization](../virtualization/index.md) for the hosting layer these apps sit on top of.