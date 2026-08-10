---
template: home.html
title: Home
hide:
  - navigation
  - toc
---

## Sections { #sections }

<div class="k-rack" markdown>

-   [
    <span class="k-rack-code">Hyp</span>
    <span class="k-rack-title">Containers &amp; Virtualization</span>
    <span class="k-rack-desc">Docker, Proxmox VE install and post-install, VMs, LXC containers, and VMware ESXi.</span>
    <span class="k-rack-go">&rarr;</span>
    ](home-lab/virtualization/index.md){ .k-rack-row }

-   [
    <span class="k-rack-code">App</span>
    <span class="k-rack-title">Applications &amp; Integrations</span>
    <span class="k-rack-desc">Nextcloud, Bookstack, Paperless-NGX, Snipe-IT, and the Authentik SSO integrations that tie them together.</span>
    <span class="k-rack-go">&rarr;</span>
    ](home-lab/application/index.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Svc</span>
    <span class="k-rack-title">Core Services</span>
    <span class="k-rack-desc">Ansible lifecycle automation, Cloudflare Tunnel, Mailcow, and OpenVPN.</span>
    <span class="k-rack-go">&rarr;</span>
    ](home-lab/services/index.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Mecm</span>
    <span class="k-rack-title">Microsoft Lab</span>
    <span class="k-rack-desc">A full SCCM/MECM build on Hyper-V, from domain controller to software update deployment.</span>
    <span class="k-rack-go">&rarr;</span>
    ](home-lab/microsoft/index.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Epm</span>
    <span class="k-rack-title">Tanium</span>
    <span class="k-rack-desc">Administration guides and packaging notes from hands-on Tanium work.</span>
    <span class="k-rack-go">&rarr;</span>
    ](home-lab/tanium/local_user_removal.md){ .k-rack-row }

</div>

## Lab at a Glance

<dl class="k-spec" markdown>

<div markdown>
<dt>Hypervisor</dt>
<dd>Proxmox VE on a Dell Precision 3450 SFF</dd>
</div>

<div markdown>
<dt>Identity</dt>
<dd>Authentik SSO across most services</dd>
</div>

<div markdown>
<dt>Networking</dt>
<dd>Cloudflare Tunnels, Pangolin, Technitium DNS</dd>
</div>

<div markdown>
<dt>Notable services</dt>
<dd>Nextcloud, Gitea, Wazuh, Open WebUI / Ollama, Mailcow</dd>
</div>

<div markdown>
<dt>Enterprise lab</dt>
<dd>Microsoft SCCM/MECM environment, Tanium</dd>
</div>

<div markdown>
<dt>Backup &amp; monitoring</dt>
<dd>Proxmox Backup Server, Uptime Kuma</dd>
</div>

</dl>

## Why a Home Lab?

A home lab is a personal environment for testing, learning, and running your own
IT infrastructure: full control over your data, more privacy, and room to
experiment with new technologies without production risk.

Everything documented here runs on hardware sitting in my house, so the notes
reflect what actually worked rather than what the vendor documentation says
should work.

[About this site](about.md){ .md-button .md-button--primary }
[Browse tags](tags.md){ .md-button }
