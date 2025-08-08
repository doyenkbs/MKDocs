### **Creating a Virtual Machine (VM)**

#### **Steps:**

1. **Upload ISO** to `local` or `local-lvm` storage.  
2. Go to **Create VM** in the Proxmox Web GUI.  
" - **General:** - **Name:** e.g.:`ubuntu-server`
" - **OS:** - Select the uploaded ISO image
" - **System:** - Use default (`**UEFI**` or `**BIOS**`)
" - **Hard Disk:**
  :   - Choose `local-lvm`  
      - Set desired disk size
" - **CPU & Memory:** - e.g.: `**2 cores**`, `**4GB RAM**`
` - **Network:** - Select `vmbr0` (bridge to LAN)
` - **Confirm** and finish the VM creation wizard.

---

#### **Post-VM Setup:**
1. **Start** the VM.  
2. Install your chosen OS (e.g., `Ubuntu, Debian, Windows`).  
3. Inside the guest OS:  
   " - Set a **static IP address**  
   ` - Install the **Proxmox guest agent**:
```bash
apt update && apt install qemu-guest-agent -y
systemctl enable --now qemu-guest-agent
```

---

## **VM Templates**

### **Using and Creating Templates**

Creating VM templates allows you to rapidly deploy new virtual machines based on a pre-configured image.

#### **Steps to create a VM template:**

" 1. **Create and configure a VM**  
   - Install the desired OS (e.g., Ubuntu minimal)  
   - Configure the VM settings, install software, and perform updates as needed

2. **Shutdown the VM**  
   - Ensure the VM is powered off before proceeding

3. **Convert the VM to a template**  
   - In the Proxmox Web GUI, right-click the VM  
   - Select **Convert to Template**
   
!!! note
    You can also use Proxmox Shell to comvert a VM to a template:
    ```bash
    qm template <vmid>
    ```


#### **Using VM Templates**

- When creating a new VM, select **Clone** and choose the template as the source  
- You can create either a **full clone** or a **linked clone** depending on your storage and performance needs

---

✅ Using templates streamlines VM deployment and maintains consistency across your virtual infrastructure.
