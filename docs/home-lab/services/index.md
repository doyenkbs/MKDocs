# Core Services & Integrations

Foundational infrastructure that powers the rest of the lab — automation, secure remote access, email, and tunneling. If **Containers & Virtualization** is the compute layer and **Applications** are what runs on top of it, this section is the plumbing that ties everything together and keeps it reachable, patched, and secure.

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
Every other part of the lab — the containers, the self-hosted apps, the Microsoft and Tanium environments — depends on these services being solid. Automation keeps systems patched without manual effort, Cloudflare and OpenVPN control how (and whether) anything is reachable from outside the network, and Mailcow makes sure alerts and account notifications actually land somewhere.

If it's not a specific app and not a hypervisor concern, it probably belongs here.