---
tags:
  - Proxmox
---

### Creating an LXC Container

**<span class="prod-app">LXC (Linux Containers)</span>** is a lightweight virtualization method that uses containerization to run multiple isolated Linux systems (containers) on a single host. Unlike full virtual machines, LXC shares the host kernel, making it more resource-efficient and faster to start, ideal for lightweight workloads and testing environments.

#### Steps:

1. **Download or upload an LXC template** to your Proxmox storage (e.g., `local`).

2. Go to **Create CT** in the Proxmox Web GUI.
!!! example "Fill in"
    - **General:** **Hostname:** e.g., `ubuntu-container`
    - **Template:** Select the desired LXC template (e.g., `ubuntu-22.04-standard`)
    - **Root Disk:**

3. Choose `local-lvm` or other storage  
4. Set disk size

!!! example "Fill in"
    - **CPU & Memory:** Example: `1-2 cores`, `2GB RAM`
    - **Network:**

5. Select `vmbr0` (bridge to LAN)  
6. Set IP configuration (DHCP or static IP)

7. **Confirm** and finish the container creation wizard.

---

#### Post-Container Setup:

* **Start** the container.  
* Access the container console via Proxmox GUI or SSH.  
* Inside the container, update packages and install necessary software:  

---
#### LXC Templates

LXC templates allow you to quickly deploy containers with pre-installed operating systems and configurations.

#### Creating LXC Templates

#### Steps to use or add LXC templates:

1. **Download templates directly from the Proxmox GUI**  
> - Navigate to **Node Name → Local (storage) → Content**  
> - Click **Templates**  
> - Select and download the desired LXC template (e.g., `ubuntu-22.04-standard`)

2. **Or upload a custom `.tar.gz` template manually**  
> - Upload your custom LXC template archive to the storage’s `templates` folder, usually at:  
     ```
     /var/lib/vz/template/cache/
     ```

!!! note "**Using LXC Templates**"
    - When creating a new container, select the downloaded or uploaded template as the base image  
    - Proceed with container creation as usual

---

✅ Leveraging LXC templates speeds up container deployment and ensures environment consistency.
