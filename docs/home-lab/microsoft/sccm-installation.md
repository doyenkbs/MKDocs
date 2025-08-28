# **SCCM Admin Console Installation**

---

The **SCCM (System Center Configuration Manager) Admin Console** is a management interface that allows administrators to connect to and manage an existing SCCM site from a workstation.  
Installing the console on a separate machine provides flexibility, enabling day-to-day administration without requiring direct login to the SCCM site server.  

This guide walks through the prerequisites, download sources, and installation steps for setting up the **Configuration Manager (SCCM) Admin Console** on both the server and a workstation, ensuring proper integration with your SCCM environment.

---

## **1. Prerequisites**

Before installing the SCCM Admin Console, ensure the following are in place:

- **Windows ADK (Assessment and Deployment Kit)**  
    !!! note "Install only:"

        - **Deployment Tools**  
        - **User State Migration Tool (USMT)**  

- **Windows PE Addon for ADK**  
  > - Required for OS deployment scenarios.

- **SQL Server**  
  >- Installed and configured (default instance recommended).  

- **Active Directory Domain Services (AD DS)**  
  > - Domain Controller configured.  

📖 See Microsoft docs for prerequisites:  
- [*Prepare to install sites*](https://learn.microsoft.com/en-us/intune/configmgr/core/servers/deploy/install/prepare-to-install-sites)  

- [*Prerequisites for installing sites*](https://learn.microsoft.com/en-us/intune/configmgr/core/servers/deploy/install/prerequisites-for-installing-sites)

---

## **2. Download SCCM Installation Media**

1. Go to the **Microsoft Evaluation Center** and download the latest evaluation version of **Configuration Manager**.
   [*Get installation media*](https://learn.microsoft.com/en-us/intune/configmgr/core/servers/deploy/install/get-install-media)

2. **Decompress** the downloaded ISO into your predefined installation directory.  

---

## **3. Run the Configuration Manager Setup Wizard**

Launch the **`Splash.hta`** from the decompressed media and follow the guided wizard.  

Reference: [*Setup Wizard for Primary Site*](https://learn.microsoft.com/en-us/intune/configmgr/core/servers/deploy/install/setup-wizard-central-primary)

### **Key Steps and Selections:**

| Wizard Step | Selection / Input |
|-------------|------------------|
| **Step 4 – Product Key** | Select **Evaluation** |
| **Step 7 – Prerequisite Downloads** | Select **Download required files** and specify your predefined location |
| **Step 10 – Site and Installation Settings** | - **Site code**: e.g. `LAB`<br>- **Site name**: e.g. `MyLab`<br>- **Installation folder**: predefined location |
| **Step 11 – Primary Site Installation** | Select **Install the primary site as a stand-alone site**, then click **Next** |
| **Step 12 – Database Installation** | - **SQL Server FQDN**: input your SQL Server hostname (e.g., `sql.lab.local`)<br>- **Instance name**: leave blank (use default)<br>- **Service Broker Port**: leave as default (`4022`) |
| **Step 13 – Database Installation (continued)** | Accept defaults |
| **Step 14 – SMS Provider** | Accept defaults |
| **Step 15 – Client Communication Settings** | Ensure **“All site system roles accept only HTTPS communication from clients”** is **not selected** |
| **Step 16 – Site System Roles** | Enter your **FQDN**, confirm HTTPS-only setting is still **deselected** |

---

## 4. Install the Admin Console

Once the **primary site installation** completes:  

1. The **SCCM Admin Console** is installed automatically on the site server.  
2. To install the Admin Console on another workstation:  
   >- Run **`AdminConsole.msi`** from the `\Tools\ConsoleSetup` folder in your installation media.  
   >- Follow the wizard to complete installation.  

📖 More details: [*List of prerequisite checks*](https://learn.microsoft.com/en-us/intune/configmgr/core/servers/deploy/install/list-of-prerequisite-checks)

---

## **5. Post-Installation Checks**

- Launch the **SCCM Admin Console** from the Start Menu.  
- Confirm connection to the site database.  
- Verify installation by checking:  
  > - **Site code**  
  > - **Database connection**  
  > - **Component status**

---

---

## **Next Steps**

Once your SCCM Primary Site is installed and running, you may want to install the **SCCM Admin Console** on your administrator workstation.  

📖 [*Install SCCM Admin Console on a Workstation*](./admin-console.md)

---


✅ At this stage, your **SCCM Admin Console** is ready for use.  
