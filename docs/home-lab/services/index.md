# Core Services & Integrations

The base infrastructure for the rest of the lab: automation, secure remote access, email, and tunnels. **Containers & Virtualization** is the compute layer, and **Applications** run on it. This section connects everything and keeps it reachable, patched, and secure.

## What's Covered

<div class="k-rack" markdown>

-   [
    <span class="k-rack-code">Cfg</span>
    <span class="k-rack-title">Automation Playbooks</span>
    <span class="k-rack-desc">Ansible lifecycle automation for the Linux stack: bootstrap, patching, and config backup, with scheduling and recovery guidance.</span>
    <span class="k-rack-go">&rarr;</span>
    ](ansible-lifecycle-overview.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Net</span>
    <span class="k-rack-title">Cloudflare</span>
    <span class="k-rack-desc">Zero-trust tunneling and access control for exposing self-hosted services without opening inbound ports.</span>
    <span class="k-rack-go">&rarr;</span>
    ](cloudflare.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Dns</span>
    <span class="k-rack-title">DNS &amp; Reverse Proxy</span>
    <span class="k-rack-desc">Technitium DNS with split-horizon resolution and Nginx Proxy Manager, so internal hostnames resolve on the LAN instead of hairpinning through the Cloudflare tunnel.</span>
    <span class="k-rack-go">&rarr;</span>
    ](technitium-dns-install-ubuntu-lxc.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Mta</span>
    <span class="k-rack-title">Mailcow</span>
    <span class="k-rack-desc">Self-hosted mail server powering alerts, notifications, and authentication email for the lab.</span>
    <span class="k-rack-go">&rarr;</span>
    ](email.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Vpn</span>
    <span class="k-rack-title">OpenVPN</span>
    <span class="k-rack-desc">Remote, encrypted access into the home network for managing the lab from anywhere.</span>
    <span class="k-rack-go">&rarr;</span>
    ](openvpn.md){ .k-rack-row }

</div>

## Why This Section Exists
All other parts of the lab (the containers, the self-hosted apps, and the Microsoft and Tanium environments) need these services to work. Automation keeps systems patched without manual work. Cloudflare and OpenVPN control how (and if) users reach anything from outside the network. Mailcow makes sure that alerts and account notifications arrive. DNS and the reverse proxy decide how users reach those services from inside the network. Do the three pages under **DNS & Reverse Proxy** in order: [install Technitium](technitium-dns-install-ubuntu-lxc.md), then [split-horizon DNS](split-horizon-dns-technitium-npm.md), then [Nginx Proxy Manager](nginx-proxy-manager-install-config.md).

If it's not a specific app and not a hypervisor concern, it probably belongs here.