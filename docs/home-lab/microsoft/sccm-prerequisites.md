# **SCCM / MECM Server Setup – Prerequisites & Tools**


This guide walks you through preparing your **SCCM (Configuration Manager)** or **MECM** server by installing required Windows features, setting up SQL Server and Reporting Services, installing ADK/WinPE, and ensuring you’re ready to deploy OS images and manage software updates.

Click [Set up a Configuration Manager lab](https://learn.microsoft.com/en-us/intune/configmgr/core/get-started/set-up-your-lab) for detailed setup instructions and access to all necessary download links for the lab.

---

## **Prerequisite Windows Features**
Ensure the following roles and features are installed on the SCCM/MECM server:

- **Web Server (IIS)**  
- **.NET Framework 3.5** 
- **.NET Framework 4.7**  
- **Background Intelligent Transfer Service (BITS)**  
- **Remote Differential Compression (RDC)**  
- **Windows Server Update Services Tools** (under Remote Administration Tools)  
- **Windows Authentication**  
- **ASP.NET 3.5** (under Application Development)  
- **IIS 6 WMI Compatibility** (under Management Tools)  
- **IIS Management Scripts and Tools**

!!! tip 
    During installation, use **Specify an alternate source path** to point to the `sources\SXS` directory on the Windows Server installation ISO to load .NET 3.5 properly.

---

## **1. Install Required Roles and Features**
Install all of the above items through **Server Manager → Add Roles and Features**, and if prompted, use the alternate source path to the `SXS` folder from the installation ISO.

---

## **2. SQL Server Installation**
Install a **new SQL Server Stand-Alone** instance (e.g., Evaluation Edition):

- **Instance Features**: Select only *`Database Engine Services`*  
- **Instance ID**: Use the default  
- **Service Account**: Assign your domain’s admin account (e.g., `mydomain\Administrator`) for the first two services and configure them for **Automatic** startup  
- **Collation**: Default `SQL_Latin1_General_CP1_CI_AS` (required by SCCM)  
- **Server Configuration**: Add your `current user` as SQL Administrator

---

## **3. Install SQL Server Management Studio (SSMS)**
1. Install **SSMS** on the SCCM/MECM server.  
2. Grant full SQL permissions to your server system account (e.g., `SCCMSRV`):
   > - Open **Computer Management (`lusrmgr.msc`) → Local Users and Groups → Groups → Administrators**
   > - Add the computer account via **Add → Object Types (Computers)** → Type the name of the SCCM/MECM server (e.g., `SCCMSRV`)
3. In SSMS:
   > - Connect to your SQL instance
   > - Right-click the server → **Properties → Memory**
   > - Set **Minimum** to `8192 MB` and **Maximum** to `10240 MB`
   > - Click **OK** and close SSMS

---

## **4. Install SQL Reporting Services (SSRS)**
Run the **SQLServerReportingServices.exe** installer:

1. Select **Install Reporting Services** → choose *Evaluation* or *Developer* edition → **Next**  
2. Accept license and install. 
3. Restart your server
4. Launch the **Report Server Configuration Manager**:
   > - **Connect**
   > - **Web Server URL**: Keep defaults, then **Apply**  
   > - **Database**: Change database → Create a new report → Test connection → **Finish**  
   > - **Web Portal URL**: Use default virtual directory → **Apply** then Exit.

---

## **5. Install Windows ADK & WinPE Add-on**
Install the latest **Windows ADK** version (`e.g., ADK 10.1.26100.X or newer`) along with the **WinPE add-on** 

- Select only **Deployment Tools** and **User State Migration Tool (USMT)** during ADK setup 
- Download and install WinPE add-on separately  
- Perform a restart after installation

---

## **6. WinPE Boot Environment**
Install the **WinPE** add-on as part of ADK if you haven't already—this is required for SCCM's OS deployment boot images.

---

## **Visual Workflow**

```mermaid
flowchart TD
    A[Windows Feature Installation] --> B[SQL Server (DB Engine)]
    B --> C[SSMS Configuration (Memory Mgmt)]
    C --> D[SQL Reporting Services (SSRS)]
    D --> E[Windows ADK + WinPE]
    E --> F[Ready for SCCM/MECM Installation]
```