---
title: Prepare AD for SCCM Publishing
tags:
  - SCCM
  - Configuration Manager
  - Microsoft
  - Systems Management
  - AD 
summary: This section explains how to configure firewall rules via **Group Policy (GPO) on the Domain Controller.
---

# **<span style="color:#009688;">Prepare AD for SCCM Publishing**

---

This section describes how to prepare **Active Directory (AD)** for **System Center Configuration Manager (SCCM)** by extending the AD schema, creating the **System Management container**, and delegating permissions to the SCCM server. These steps ensure SCCM can publish its site information into Active Directory.

Click [Set up a Configuration Manager lab](https://learn.microsoft.com/en-us/intune/configmgr/core/get-started/set-up-your-lab) for detailed setup instructions and access to all necessary download links for the lab.

---

## **Steps:**

---

### **<span style="color:#009688;">1. Extend the AD Schema**

- Run the schema extension tool:  
  ``` powershell
  extadsch.exe
  ```
- Verify success in the log file:
`C:\extadsch.log`

!!! info "The extadsch.exe tool is located in:"
    `SMSSETUP\BIN\X64` folder on the Configuration Manager installation media.
    Run this tool from the command line to view feedback while it runs.

---

### **<span style="color:#009688;">2. Create the System Management Container**

- Open Server Manager → Tools → ADSI Edit and Active Directory Users and Computers (ADUC).
- In ADSI Edit, right-click ADSI Edit → Connect.
- Expand CN=System.
- ERight-click CN=System → New → Object → Container.
- Name the container:
``` sql
System Management
```
!!! warning
    Case sensitive – type exactly as shown.

- Follow the prompts to complete.

---

### **<span style="color:#009688;">3. Delegate Permissions to SCCM Server**

- Open Active Directory Users and Computers (ADUC) → Enable `Advanced View`.
- Navigate to the `System Management` container.
- Right-click `System Management` → Delegate Control.
- Add the SCCM server computer account (e.g., `SCCMSRV`).

    > - Click Add → Object Types → select Computers.
    > - Enter the SCCM server name.
    
- Select Create a custom task to delegate.
- Grant Full Control permissions.

--- 

<!-- 

### **Visual Workflow**

``` mermaid
flowchart TD
    A["📂 Active Directory Schema"] -- B["⚙️ Run extadsch.exe\n(Extend Schema)"]
    B -- C["📜 C:\\extadsch.log\n(Verify Success)"]

    A -- D["🗂️ CN=System Container"]
    D -- E["📦 Create 'System Management' Container\n(Case Sensitive)"]

    E -- F["👤 Delegate Control via ADUC\n(Advanced Features Enabled)"]
    F -- G["🖥️ SCCM Server (e.g., SCCMSRV)\nGranted Full Control"]
```
-->

✅ At this point, Active Directory is prepared for SCCM publishing and the SCCM server can publish site information to AD. 