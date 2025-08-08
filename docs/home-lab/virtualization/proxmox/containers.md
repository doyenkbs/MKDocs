### 🧱 4. Creating an LXC Container
**LXC (Linux Containers)** is a lightweight virtualization method that uses containerization to run multiple isolated Linux systems (containers) on a single host. Unlike full virtual machines, LXC shares the host kernel, making it more resource-efficient and faster to start, ideal for lightweight workloads and testing environments.

#### Steps:

1. **Download or upload an LXC template** to your Proxmox storage (e.g., `local`).

2. Go to **Create CT** in the Proxmox Web GUI.

**General:**
- **Hostname:** e.g., `ubuntu-container`

**Template:**
- Select the desired LXC template (e.g., `ubuntu-22.04-standard`)

**Root Disk:**
- Choose `local-lvm` or other storage  
- Set disk size

**CPU & Memory:**
- Example: **1-2 cores**, **2GB RAM**

**Network:**
- Select `vmbr0` (bridge to LAN)  
- Set IP configuration (DHCP or static IP)

3. **Confirm** and finish the container creation wizard.

---

#### Post-Container Setup:
1. **Start** the container.  
2. Access the container console via Proxmox GUI or SSH.  
3. Inside the container, update packages and install necessary software:  

---
#### LXC Templates

LXC templates allow you to quickly deploy containers with pre-installed operating systems and configurations.
#### Creating LXC Templates

#### Steps to use or add LXC templates:

1. **Download templates directly from the Proxmox GUI**  
   - Navigate to **Node Name → Local (storage) → Content**  
   - Click **Templates**  
   - Select and download the desired LXC template (e.g., `ubuntu-22.04-standard`)

2. **Or upload a custom `.tar.gz` template manually**  
   - Upload your custom LXC template archive to the storage’s `templates` folder, usually at:  
     ```
     /var/lib/vz/template/cache/
     ```


#### Using LXC Templates

- When creating a new container, select the downloaded or uploaded template as the base image  
- Proceed with container creation as usual

---

✅ Leveraging LXC templates speeds up container deployment and ensures environment consistency.
