# Containers & Virtualization

The compute layer of the home lab: the hypervisors and the container platform that all other parts of this site run on (self-hosted apps, core services, and the Microsoft and Tanium labs).

## What's Covered

<div class="k-rack" markdown>

-   [
    <span class="k-rack-code">Hyp</span>
    <span class="k-rack-title">Proxmox VE</span>
    <span class="k-rack-desc">Primary hypervisor for the lab: VMs, LXC containers, and datacenter-wide management.</span>
    <span class="k-rack-go">&rarr;</span>
    ](proxmox/proxmox.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Esxi</span>
    <span class="k-rack-title">VMware ESXi</span>
    <span class="k-rack-desc">Enterprise-grade hypervisor used alongside Proxmox for select workloads.</span>
    <span class="k-rack-go">&rarr;</span>
    ](vmware/vmware.md){ .k-rack-row }

-   [
    <span class="k-rack-code">Ctr</span>
    <span class="k-rack-title">Docker</span>
    <span class="k-rack-desc">Containerization platform used throughout the Applications and Core Services sections.</span>
    <span class="k-rack-go">&rarr;</span>
    ](../docker.md){ .k-rack-row }

</div>

---

## Proxmox VE: Section Breakdown

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

## How This Section Fits the Rest of the Lab

Almost everything documented elsewhere on this site runs *on top of* what's covered here:

- **[Applications & Integrations](../application/index.md)** — most self-hosted apps (Nextcloud, Bookstack, Authentik, etc.) run in individual Proxmox LXC containers
- **[Core Services](../services/index.md)** — Mailcow, Cloudflare tunnels, and the Ansible automation stack all run on hosts provisioned here
- **[Microsoft Lab](../microsoft/index.md)** — the SCCM/MECM environment runs on Hyper-V VMs, documented separately since it uses a different virtualization stack for that specific lab

To set up a new service from a different part of this documentation, start in this section. Make the VM or LXC here first. Then go to the guide for the app.

---

## Choosing Between a VM and an LXC Container

A quick rule of thumb used throughout this lab:

- **LXC container** — default choice for most self-hosted apps (Nextcloud, Bookstack, Authentik, etc.). Lighter weight, faster to provision, shares the host kernel.
- **Full VM** — used when a workload needs its own kernel, isn't Linux, or needs strong isolation (e.g. the Microsoft Lab's Hyper-V-based Windows Server environment isn't applicable here, but any Windows workload on Proxmox itself would go this route).

See [Proxmox Virtual Machines](proxmox/vms.md) and [Proxmox Containers](proxmox/containers.md) for the actual creation steps once you've decided which fits.

---

## Related: New LXC Bootstrap Automation

After you create a new LXC here, the [Ansible LXC Bootstrap playbook](../services/ansible-lxc-bootstrap.md) in Core Services continues the work. It creates the automation service account, hardens SSH, and installs baseline packages. Then the LXC is ready for the [patch](../services/ansible-patch.md) and [backup](../services/ansible-config-backup.md) automation from the first day.