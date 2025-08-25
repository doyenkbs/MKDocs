---
tags:
  - Proxmox
---

# **<span style="color:#F38020;">Proxmox VE Installation</span>**

!!! info "**Requirements**"
    Before starting, make sure you have:

    - **CPU** with virtualization support (**Intel VT-x** / **AMD-V**)  
    !!! tip
        You can check this in your BIOS or with `lscpu` in Linux._

    - **8GB+ RAM** (16GB recommended)
    - **SSD/HDD storage**
    - **Bootable USB** with the Proxmox ISO

---

## **Installation Steps**
### **1. Download the Latest ISO**
Get the latest <span style="color:#F38020;">Proxmox VE</span> ISO from the official site:  
➡️ [**Proxmox Downloads**](https://www.proxmox.com/en/downloads)  

![Proxmox Download Page](/assets/images/proxmox.png)

---

### **2. Create a Bootable USB Drive**
You can use **Rufus** (Windows) or the `dd` command (Linux/macOS).  

??? info "**Windows (Rufus):**"
    1. Insert your USB drive. 
    2. Open Rufus and select the downloaded ISO.  
    3. Click **Start**.

??? info "**Linux/macOS (`dd` command):**"
    ```bash
    sudo dd if=proxmox-ve.iso of=/dev/sdX bs=4M status=progress && sync
    ```

    !!! note
        Replace /dev/sdX with your USB drive’s device path.

---

### **3. Boot and Install Proxmox VE**
1. Boot your system from the USB drive.  
!!! example "Follow the installation wizard:"
    - Accept the EULA  
    - Select the target disk (_use ZFS if you want snapshots or have multiple disks_)  
    - Set your country, time zone, and keyboard layout  
    - Create the **root password** and enter your email address  
    - Assign a static IP, hostname (e.g., `proxmox.local`), and gateway  

---

### **4. Reboot and Access the Web GUI**
After installation, reboot your server and open the web interface in your browser:  

`https://<proxmox-ip>:8006`

