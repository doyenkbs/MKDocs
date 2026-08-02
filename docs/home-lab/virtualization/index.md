# **<span style="color:#009688;">Containers & Virtualization**

The compute layer of the home lab — the hypervisors and containerization platform that everything else in this site (self-hosted apps, core services, the Microsoft and Tanium labs) actually runs on top of.

## <span style="color:#009688;">What's Covered

<div class="grid cards" markdown>

-   :simple-proxmox: **Proxmox VE**

    ---

    Primary hypervisor for the lab — VMs, LXC containers, and datacenter-wide management.

    [:octicons-arrow-right-24: Start here](proxmox/proxmox.md)

-   :simple-vmware: **VMware ESXi**

    ---

    Enterprise-grade hypervisor used alongside Proxmox for select workloads.

    [:octicons-arrow-right-24: Start here](vmware/vmware.md)

-   :material-docker: **Docker**

    ---

    Containerization platform for lightweight, portable service deployment — used throughout the Applications & Core Services sections.

    [:octicons-arrow-right-24: Start here](../docker.md)

</div>

---

## <span style="color:#009688;">Proxmox VE: Section Breakdown

Proxmox is the primary hypervisor for this lab, so its section is the deepest:

| Page | Covers |
|---|---|
| [Overview](proxmox/proxmox.md) | What Proxmox VE is and why it's used here |
| [Installation](proxmox/proxmox-installation.md) | Initial install on bare metal |
| [Post-Installation](proxmox/proxmox-configuration.md) | Baseline configuration after a fresh install |
| [Virtual Machines](proxmox/vms.md) | Creating and managing VMs |
| [Containers](proxmox/containers.md) | Creating and managing LXC containers |
| [Datacenter Manager](proxmox/pdmanager.md) | Multi-node management |

---

## <span style="color:#009688;">How This Section Fits the Rest of the Lab

Almost everything documented elsewhere on this site runs *on top of* what's covered here:

- **[Applications & Integrations](../application/index.md)** — most self-hosted apps (Nextcloud, Bookstack, Authentik, etc.) run in individual Proxmox LXC containers
- **[Core Services](../services/index.md)** — Mailcow, Cloudflare tunnels, and the Ansible automation stack all run on hosts provisioned here
- **[Microsoft Lab](../microsoft/index.md)** — the SCCM/MECM environment runs on Hyper-V VMs, documented separately since it uses a different virtualization stack for that specific lab

If you're setting up a new service anywhere else in this documentation, this is the section to start from: provision the VM or LXC here first, then move on to the app-specific guide.

---

## <span style="color:#009688;">Choosing Between a VM and an LXC Container

A quick rule of thumb used throughout this lab:

- **LXC container** — default choice for most self-hosted apps (Nextcloud, Bookstack, Authentik, etc.). Lighter weight, faster to provision, shares the host kernel.
- **Full VM** — used when a workload needs its own kernel, isn't Linux, or needs strong isolation (e.g. the Microsoft Lab's Hyper-V-based Windows Server environment isn't applicable here, but any Windows workload on Proxmox itself would go this route).

See [Proxmox Virtual Machines](proxmox/vms.md) and [Proxmox Containers](proxmox/containers.md) for the actual creation steps once you've decided which fits.

---

## <span style="color:#009688;">Related: New LXC Bootstrap Automation

Once a new LXC is created here, the [Ansible LXC Bootstrap playbook](../services/ansible-lxc-bootstrap.md) in Core Services takes over — creating the automation service account, hardening SSH, and installing baseline packages — so it's ready for the [patch](../services/ansible-patch.md) and [backup](../services/ansible-config-backup.md) automation from day one.