# **<span style="color:#009688;">Core Services & Integrations**

Foundational infrastructure that powers the rest of the lab — automation, secure remote access, email, and tunneling. If **Containers & Virtualization** is the compute layer and **Applications** are what runs on top of it, this section is the plumbing that ties everything together and keeps it reachable, patched, and secure.

## <span style="color:#009688;">What's Covered</span>

<div class="grid cards" markdown>

-   :material-robot-outline: **Automation Playbooks**

    ---

    Ansible-based lifecycle automation for the Linux stack — bootstrap, patching, and config backup, tied together with scheduling and recovery guidance.

    [:octicons-arrow-right-24: Start here](ansible-lifecycle-overview.md)

-   :simple-cloudflare: **Cloudflare**

    ---

    Zero-trust tunneling and access control for exposing self-hosted services securely, without opening inbound ports.

    [:octicons-arrow-right-24: Start here](cloudflare.md)

-   :material-email-outline: **Mailcow**

    ---

    Self-hosted mail server powering alerts, notifications, and authentication email for the lab.

    [:octicons-arrow-right-24: Start here](email.md)

-   :material-vpn: **OpenVPN**

    ---

    Remote, encrypted access into the home network for managing the lab from anywhere.

    [:octicons-arrow-right-24: Start here](openvpn.md)

</div>

## <span style="color:#009688;">Why This Section Exists
</span>
Every other part of the lab — the containers, the self-hosted apps, the Microsoft and Tanium environments — depends on these services being solid. Automation keeps systems patched without manual effort, Cloudflare and OpenVPN control how (and whether) anything is reachable from outside the network, and Mailcow makes sure alerts and account notifications actually land somewhere.

If it's not a specific app and not a hypervisor concern, it probably belongs here.