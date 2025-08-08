# Proxmox Datacenter Manager (PDM)

**Proxmox Datacenter Manager** (PDM) is an open-source centralized management platform for overseeing multiple Proxmox VE nodes and clusters. It offers foundational control, visibility, and orchestration through a modern, Rust-powered user interface. This tool is currently in **alpha stage**, with beta and stable releases planned through 2025.:contentReference[oaicite:0]{index=0}

---

##  Alpha Features & Early User Feedback

- **Centralized Overview:** Monitor resource usage across all nodes and clusters, including basic operations like starting, stopping, rebooting, and migrating guests.:contentReference[oaicite:1]{index=1}  
- **Modern UI:** Built entirely in **Rust** using a Yew-based widget toolkit for enhanced responsiveness, speed, and accessibility.:contentReference[oaicite:2]{index=2}  
- **Scalable Design:** Demonstrated capability in managing setups with thousands of nodes and virtual guests in testing.:contentReference[oaicite:3]{index=3}  
- **User Feedback Highlights:**  
  > “Interface for viewing the list of VMs and containers … constrained … not resizable” – suggestions for better usability including resizable panels, pagination, or full-screen modes.:contentReference[oaicite:4]{index=4}  
  Other users praised VM migration across clusters and expressed interest in adding SDN and translation support.:contentReference[oaicite:5]{index=5}

---

##  Roadmap Overview (through 2025 and beyond)

Planned enhancements include:

- **Health Monitoring:** Status of subscriptions, updates, backups, repository validity.:contentReference[oaicite:6]{index=6}  
- **Resource Organization:** Grouping resources across remotes via hierarchical structures or resource pools.:contentReference[oaicite:7]{index=7}  
- **Remote-Join Endpoint:** Simplified setup for connecting new nodes or clusters with trust and security in mind.:contentReference[oaicite:8]{index=8}  
- **Administrative Tools:** Node updates, backup-job visibility, firewall/SDN integration.:contentReference[oaicite:9]{index=9}  
- **Advanced Networking:** Support for EVPN, multi-VRF environments, and off-site guest replication for manual recovery.:contentReference[oaicite:10]{index=10}  
- **High Availability:** Potential active-standby architecture to avoid single points of failure.:contentReference[oaicite:11]{index=11}

---

##  Installation & Initial Setup

1. **Install PDM** either:
   - **Via the ISO installer** (similar to Proxmox VE) 
   - **Community Script Installer**:
     You can also install Proxmox Datacenter Manager using a community-maintained script:
     ```bash
     curl -sSL https://community-scripts.github.io/ProxmoxVE/install-pdm.sh | bash
     ```
     !!! note
        This method automates repository setup and package installation, making setup quicker and simpler.
   - **Or on Debian Bookworm by adding the PDM repository and installing packages**:  
     ```bash
     echo 'deb http://download.proxmox.com/debian/pdm bookworm pdm‑test' >/etc/apt/sources.list.d/pdm-test.list
     wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
     apt update
     apt install proxmox-datacenter-manager proxmox-datacenter-manager-ui
     ```
     Then access the interface at  
     ```markdown
     https://<pdm-host>:8443
     ```  
     (Login as `root@pam`.):contentReference[oaicite:12]{index=12}

2. **Add Proxmox VE Remotes**:
   - Use the “Remote” or “Dashboard” wizard  
   - Input the node or cluster address and fingerprint (found in the PVE SSL certificate)  
   - Authenticate using root credentials or API tokens  
   - After connection, the nodes and guests appear in your dashboard with real-time status.:contentReference[oaicite:13]{index=13}

---

##  Summary

PDM is a promising yet evolving tool offering centralized management for distributed Proxmox environments. It’s ideal for home labs and multi-site setups—just be cautious in production until later stable releases.:contentReference[oaicite:14]{index=14}

Would you like a dedicated **MkDocs page outline** including troubleshooting tips, feature comparisons, or graphical diagrams?
::contentReference[oaicite:15]{index=15}

***Reference:***
- [Proxmox Datacenter Manager Roadmap](https://pve.proxmox.com/wiki/Proxmox_Datacenter_Manager_Roadmap)
- [Proxmox Support Forum](https://forum.proxmox.com/threads/proxmox-datacenter-manager-first-alpha-release.159323/)