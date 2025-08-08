# **Proxmox VE Installation**

## **Requirements**
Before starting, make sure you have:

- **CPU** with virtualization support (**Intel VT-x** / **AMD-V**)  
  _Tip: You can check this in your BIOS or with `lscpu` in Linux._
- **8GB+ RAM** (16GB recommended)
- **SSD/HDD storage**
- **Bootable USB** with the Proxmox ISO

---

## **Installation Steps**
### **1. Download the Latest ISO**
Get the latest Proxmox VE ISO from the official site:  
➡️ [**Proxmox Downloads**](https://www.proxmox.com/en/downloads)  

![Proxmox Download Page](images/proxmox.png)

---

### **2. Create a Bootable USB Drive**
You can use **Rufus** (Windows) or the `dd` command (Linux/macOS).  

**Windows (Rufus):**  
1. Insert your USB drive.  
2. Open Rufus and select the downloaded ISO.  
3. Click **Start**.

**Linux/macOS (`dd` command):**
```bash
sudo dd if=proxmox-ve.iso of=/dev/sdX bs=4M status=progress && sync
```
!!! note
    Replace /dev/sdX with your USB drive’s device path.

---

### **3. Boot and Install Proxmox VE**
1. Boot your system from the USB drive.  
2. Follow the installation wizard:  
> - Accept the EULA  
> - Select the target disk (_use ZFS if you want snapshots or have multiple disks_)  
> - Set your country, time zone, and keyboard layout  
> - Create the **root password** and enter your email address  
> - Assign a static IP, hostname (e.g., `proxmox.local`), and gateway  

---

### **4. Reboot and Access the Web GUI**
After installation, reboot your server and open the web interface in your browser:  

`https://<proxmox-ip>:8006`

