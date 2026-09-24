---
tags:
  - About
---

# About This Site

## Why This Site Exists

I'm Christian Kaba, and this is where I document my self-hosted home lab, partly
for myself and partly for anyone else building something similar.

I started keeping notes because I kept solving the same problems twice: forgetting
a config flag, re-discovering a fix I'd already found six months earlier, or
rebuilding something from scratch after a hardware change. This site is the
result, a running record of what I've set up, how, and why, written as I go.

Everything here runs on hardware in my house, so the notes reflect what actually
worked rather than what the vendor documentation says should work. That includes
the parts that took three attempts.

## What's Covered Here

| Section | What's in it |
|---|---|
| **Containers & Virtualization** | Docker, and Proxmox VE end to end: install, post-install config, virtual machines, LXC containers, and Datacenter Manager. VMware ESXi alongside it |
| **Applications & Integrations** | Self-hosted apps including Nextcloud, Bookstack, Paperless-NGX, Snipe-IT, Audiobookshelf, Kasm Workspaces, and Pairdrop, plus the Authentik SSO integration for each one that supports it |
| **Core Services** | The layer everything else depends on: Ansible automation playbooks for patching, config backup, and LXC bootstrap; Cloudflare Tunnel; Technitium DNS and split-horizon resolution; Nginx Proxy Manager; Pangolin; Mailcow; OpenVPN |
| **Microsoft Lab** | A full SCCM/MECM build on Hyper-V, from domain controller and Active Directory through to software update deployment |
| **Linux** | Red Hat Enterprise Linux on Proxmox: no-cost developer subscriptions, repository and entitlement management, Cockpit, and the kernel patching workflow behind vulnerability remediation |
| **Tanium** | PowerShell packages, custom sensors, and Deploy guides from hands-on endpoint management work |

## How It's Organized

Pages are grouped by function rather than by the order I built things. If you're
looking for how a specific piece fits together, start from whichever section
matches what you're trying to do, not the nav order.

Most pages follow the same shape: what the thing is, the prerequisites, the
steps, then a troubleshooting section covering what actually went wrong. The
troubleshooting entries are usually the reason the page exists.

Commands are written to be copied and run. Where a path or value differs between
environments, the page gives the command that finds it rather than telling you to
go look. Lab-specific domains, hostnames, and IP addresses are replaced with
placeholders throughout, so substitute your own.

If you're looking for a topic rather than a section, [browse by tag](tags.md).

## How It's Built

[MkDocs](https://www.mkdocs.org/) with the
[Material](https://squidfunk.github.io/mkdocs-material/) theme, deployed through
Cloudflare. The source is on
[GitHub](https://github.com/doyenkbs/MKDocs).

## Get in Touch

If something here is wrong, out of date, or you just want to talk shop:

- **Email:** [support@kabason.net](mailto:ckaba@kabason.net)
- **LinkedIn:** [linkedin.com/in/christian-kaba-b8247a157](https://linkedin.com/in/christian-kaba-b8247a157)
