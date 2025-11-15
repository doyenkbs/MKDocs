---
tags:
  - Proxmox
---

## **<span style="color:#009688;">Initial Configuration</span>**

**Update system:**
```bash
apt update && apt full-upgrade -y
```
(Optional) Remove subscription nag:

```bash
sed -i.bak "s|data.status !== 'Active'|false|" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
systemctl restart pveproxy
```
Add no-subscription repo in `/etc/apt/sources.list.d/pve-enterprise.list`:

```bash
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
```
Add SSH key for secure login.

Set up storage — configure `local-lvm` or add additional disks via `ZFS` or `ext4`.

---

### **Setting Up a Linux Bridge in Proxmox**

A Linux bridge is required to give your VMs and containers network access through your host’s physical NIC.

**1. Log in to the Proxmox Web GUI:** `https://<proxmox-ip>:8006`

**2. Go to:** `Datacenter → Node Name → System → Network`

**3. Click:** `Create → Linux Bridge`

!!! example "**Configure:**"
    - **Name:** `vmbr0` (default bridge name)  
    - **IPv4/CIDR:** Set if this bridge will have an IP (optional if only bridging traffic)  
    - **Gateway (IPv4):** Your network gateway (only if assigning IP)  
    - **Bridge ports:** Your physical NIC (e.g., `eno1` or `eth0`)  

**4. Click:** `Create`

**5. Apply changes:** Click **Apply Configuration** and confirm.

**6. (Optional):** Edit your VM or LXC container’s network settings to use `vmbr0` as the bridge.
