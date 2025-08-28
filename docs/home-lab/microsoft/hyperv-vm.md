# **Virtual Machine Creation & Initial Configuration**

---

This guide walks you through the **creation of Virtual Machines (VMs)** and the **initial configuration steps** after installation.  
These practices ensure a consistent and reliable lab environment for future setup.  

---

## **🖥️ 1. Create a Virtual Machine**

1. **Open Hyper-V Manager (or Proxmox/VMware/VirtualBox depending on your setup).**  
2. **Create a new VM:** 
   > - Assign a **name** (`e.g., DC01, SCCM01, CLIENT01`).  
   > - Specify the **generation** (`Generation 2` recommended for modern OS).  

3. **Assign Memory (RAM):**
   > - Domain Controller:`2–4 GB`  
   > - SCCM/Management Server: `8–16 GB ` 
   > - Client Machines: `2–4 GB `

4. **Configure Networking:**  
   > - Attach the VM to your **Internal/NAT/Bridged network** depending on your lab setup (e.g., `LabSwitch`).  

5. **Attach ISO:**  
   > - Use the Windows Server (or Client OS) ISO for installation.  

6. **Complete VM Creation Wizard** and start the VM.  
7. **Install the Operating System** inside the VM.  

---

## **🔧 2. Initial Configuration After Installation**

### **Rename All Virtual Machines**
> - Rename each virtual machine to match your lab naming convention.  
*Example: `DC01`, `SCCM01`, `CLIENT01`.*

---

### **Configure Each Server**

1. **Open Server Manager → Local Server**  
   Use the dashboard to quickly configure system properties.  

2. **Disable IPv6**  
   > - Go to: *Network Adapter Properties* → Uncheck **Internet Protocol Version 6 (TCP/IPv6)**.  
*Helps avoid unwanted conflicts when using IPv4 in lab setups.* 

3. **Rename the Server**  
   > - Open *System Properties* → Change Computer Name.  
*Use meaningful names for easy identification.*

4. **Disable IE Enhanced Security Configuration (ESC)** 
   > - Open *Server Manager*.  
   > - Under *Local Server*, click **IE Enhanced Security Configuration** → Set both Admin & User to **Off**.  
*Makes downloading files easier in lab/test environments.*

5. **Disable Automatic Windows Updates** 
   > - Run the following command:  
     ```
     sconfig
     ```
   > - Choose option **5 (Windows Update Settings)**.  
   > - Set to **Manual**.  
*Prevents unwanted reboots or patching during lab sessions.*  

