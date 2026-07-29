# Home

# Kabason Labs Documentation

Guides, configs, and troubleshooting notes from my self-hosted home lab — covering
Proxmox virtualization, SSO with Authentik, Microsoft SCCM/MECM lab builds, Tanium
administration, and the core services that tie it all together.

This site exists as a living reference: written as I build, break, and fix things,
so it's as much a record for future-me as it is a resource for anyone else running
a similar stack.

---

## 🖥️ Lab at a Glance

| | |
|---|---|
| **Hypervisor** | Proxmox VE on a Dell Precision 3450 SFF |
| **Identity** | Authentik SSO across most services |
| **Networking** | Cloudflare Tunnels, Pangolin, Technitium DNS |
| **Notable services** | Nextcloud, Gitea, Wazuh, Open WebUI / Ollama, Mailcow, Nginx Proxy Manager |
| **Enterprise lab** | Microsoft SCCM/MECM environment, Tanium |

---

## 📚 Explore the Docs

<div class="grid cards" markdown>

-   :material-server-network:{ .lg .middle } **Containers & Virtualization**

    ---

    Docker, Proxmox VE setup and post-install, VMs, containers, and VMware ESXi.

    [:octicons-arrow-right-24: Start here](home-lab/virtualization/index.md)

-   :material-apps:{ .lg .middle } **Applications & Integrations**

    ---

    Self-hosted apps like Nextcloud, Bookstack, Paperless-NGX, and Authentik SSO integrations.

    [:octicons-arrow-right-24: Start here](home-lab/application/index.md)

-   :material-cloud-outline:{ .lg .middle } **Core Services**

    ---

    Cloudflare Tunnel/Access, Home Assistant, OpenVPN, and email setup.

    [:octicons-arrow-right-24: Start here](home-lab/services/index.md)

-   :material-microsoft-windows:{ .lg .middle } **Microsoft Lab**

    ---

    A full SCCM/MECM lab build: Hyper-V, Active Directory, and software update deployment.

    [:octicons-arrow-right-24: Start here](home-lab/microsoft/index.md)

-   :material-shield-search:{ .lg .middle } **Tanium**

    ---

    Administration guides and packaging notes from hands-on Tanium work.

    [:octicons-arrow-right-24: Start here](home-lab/tanium/local_user_removal.md)

</div>

---

## 🌟 Why a Home Lab?

A **home lab** is a personal environment for testing, learning, and running your own
IT infrastructure — full control over your data, more privacy, and room to
experiment with new technologies without production risk.

[About this site](about.md){ .md-button }
[Tags](tags.md){ .md-button }