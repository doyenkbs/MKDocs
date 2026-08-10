---
tags:
  - Proxmox
---

# Proxmox Datacenter Manager (PDM)

**<span class="prod-app">Proxmox Datacenter Manager</span>** (PDM) is an open-source centralized management platform for overseeing multiple Proxmox VE nodes and clusters. It offers foundational control, visibility, and orchestration through a modern, Rust-powered user interface. This tool is currently in **alpha stage**.

 **Centralized Overview:** Monitor resource usage across all nodes and clusters, including basic operations like starting, stopping, rebooting, and migrating guests.:contentReference

---

##  Installation & Initial Setup

1. **Install PDM** either:

> - **Via the ISO installer** (similar to Proxmox VE)

> - **Community Script Installer**: You can also install Proxmox Datacenter Manager using a community-maintained script:
     ```bash
     curl -sSL https://community-scripts.github.io/ProxmoxVE/install-pdm.sh | bash
     ```
!!! note
    This method automates repository setup and package installation, making setup quicker and simpler.

> - **Or on Debian Bookworm by adding the PDM repository and installing packages**:  
```bash
echo 'deb http://download.proxmox.com/debian/pdm bookworm pdm‑test' >/etc/apt/sources.list.d/pdm-test.list
wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
apt update
apt install proxmox-datacenter-manager proxmox-datacenter-manager-ui
```
     Then access the interface at: 
```markdown
https://<pdm-host>:8443
```  
     Login as `root@pam`.

!!! info "**Add Proxmox VE Remotes:**"
     - Use the “Remote” or “Dashboard” wizard  
     - Input the node or cluster address and fingerprint (found in the PVE SSL certificate)  
     - Authenticate using root credentials or API tokens  
     - After connection, the nodes and guests appear in your dashboard with real-time status.

---

##  Summary

PDM is a promising yet evolving tool offering centralized management for distributed Proxmox environments. It’s ideal for home labs and multi-site setups—just be cautious in production until later stable releases.

***Reference:***

- [*Proxmox Datacenter Manager Roadmap*](https://pve.proxmox.com/wiki/Proxmox_Datacenter_Manager_Roadmap)
- [*Proxmox Support Forum*](https://forum.proxmox.com/threads/proxmox-datacenter-manager-first-alpha-release.159323/)