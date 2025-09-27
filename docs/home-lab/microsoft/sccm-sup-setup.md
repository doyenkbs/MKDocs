---
title: "Setup Software Updates in Configuration Manager"
tags:
  - SCCM
  - Configuration Manager
  - Microsoft
  - Software Updates
summary: This guide walks through a straightforward process to enable and deploy software updates in MECM.
---

# **Setup Software Updates in Configuration Manager (MECM)**

This guide walks through planning, configuring, and maintaining software updates in Microsoft Endpoint Configuration Manager (MECM).

---
## **Quick overview**
1. **Plan** where your Software Update Point(s) (SUP) and WSUS servers will live (top-level site first).  
2. **Prepare** servers (WSUS/IIS/.NET/BITS/etc.) and accounts.  
3. **Install & configure** the Software Update Point role in the ConfigMgr console.  
4. **Synchronize** updates, create update groups/packages, distribute content.  
5. **Deploy & monitor** compliance, maintain WSUS and SUP health.  

---

## **Prerequisites**
- SCCM/MECM and site servers are installed and running.  
- You have administrative rights on the SCCM server.  
- A supported **Windows Server** with the **WSUS role** and required features (IIS, .NET, BITS, RPC, Windows Update Services).  
- Sufficient disk space allocated for the WSUS content store (plan for growth).  
- Ensure site servers and SUP servers meet all **Configuration Manager prerequisites** (ports, accounts, permissions).  
- Decide on the synchronization source: **Microsoft Update** (requires internet access at top-level site) or an upstream WSUS/SUP.  

---

## **Planning the SUP infrastructure**
1. Decide which sites require a SUP (Central Administration Site and all primary sites must have at least one SUP to do compliance assessment).  
2. Choose whether the SUP and WSUS run on the same server or remote — the first SUP installed at a site becomes the **synchronization source**; additional SUPs act as replicas.  
3. Consider scale (number of clients), distribution points, network topology, and internet-based clients.  

---

## **Prepare the WSUS server(s)**
1. Install the **WSUS role** and required IIS features on the chosen server(s).  
2. Configure WSUS initial settings (content directory, update source, proxy settings).  
3. If the SUP is remote from the site server and the site computer account lacks access, create a **WSUS Server Connection Account** (must be local admin on the WSUS server and in the WSUS Administrators group).  

!!! tip
    Run WSUS cleanup and maintenance tasks before your first large sync.


## **Install and Configure the Software Update Point (SUP)**
### 1. Add the SUP site system role:
   - In the SCCM console, go to **Administration → Site Configuration → Servers and Site System Roles**.  
   - Right-click your server and select **Add Site System Roles**.  
   - Choose **Software Update Point** on the Role Selection page.

### 2. Configure WSUS:
   - Open the **WSUS console** on the server.  
   - **Upstream synchronization source**: *`Microsoft Update`* (top-level site) or an upstream WSUS/SUP.  
   - Select required **languages, products, and update classifications** (e.g., Security, Critical Updates).  
   - Configure synchronization schedule and proxy if needed.  
   - Complete the wizard and perform the initial sync. 

!!! note
    On the top-level site, it’s recommended to clear classifications/products on the first install, perform an initial sync, then configure them again for a full sync.

---

## **Synchronize Software Updates**
#### 1. Run initial synchronization:  
   - In the SCCM console, go to **Software Library → Software Updates**.  
   - Click **All Software Updates**, then in the ribbon select **Synchronize Software Updates**.  

#### 2. Monitor sync progress:  
   - Check `wsyncmgr.log` and `WCM.log` on the site server for sync status.  
#### 3. Confirm updates appear under **Software Library → Overview → Software Updates**.

---

## **Create a Software Update Group**
### 1. Filter and add updates:  
   - Use search criteria like *Product*, *Expired*, *Superseded* to refine the list.  
   - Select required updates, right-click, and choose **Create Software Update Group**.  

### 2. Name the group clearly, e.g.:  
   - `Windows 10 2025-09 Security Updates`  

---

## **Download Update Content and Distribute**
1. With the Update Group selected, right-click and choose **Download**.  
2. Specify **Distribution Points** to store the update content.  

---

## **Deploy Updates**
#### 1. Right-click the **Update Group** and select **Deploy**.  
#### 2. Configure deployment settings:  
   - Provide a **name and description**.  
   - Select the **target device collection** (e.g., All Workstations).  
   - Choose deployment type:  
     - **Required** → automatic install  
     - **Available** → user-initiated  
   - Set **schedule** (as soon as possible, or specific date/time).  
   - Configure **user experience** (prompt for restart, deadline behavior).  
   - Adjust **download settings** for slow/fast network locations.  

#### 3. Complete the wizard to create the deployment.  

---

## **Monitor Deployment**
- In the console, monitor distribution via **Monitoring → Content Status** and deployment compliance under **Monitoring → Deployments**.
- Select the deployment to view compliance status and error details.  


---

## **Client configuration & policies**
1. Ensure client settings (or GPO) point Windows Update to ConfigMgr.  
2. Confirm client scan/reporting status (`WUAHandler.log`, `UpdatesHandler.log`).  
3. Use pilot collections for staged rollouts.  

---

## **Maintenance & best practices**
- Run **WSUS cleanup** regularly (decline superseded/expired updates).  
- Monitor SUP and WSUS performance (IIS pool, memory).  
- Schedule syncs during off-hours in large environments.  

---

## **Third-party updates (optional)**
- Use **third-party catalogs** with ConfigMgr (or SCUP legacy).  
- Manage distribution and deployment like Microsoft updates.  

---

## **Troubleshooting checklist (quick)**
- **SUP install failures**: check `SMSSetup` logs, `WCM.log`.  
- **Sync fails**: review `wsyncmgr.log`, network/proxy, outbound connectivity.  
- **Client scan issues**: check `WindowsUpdate.log`, `WUAHandler.log`, `UpdatesStore.log`.  
- **WSUS permission errors**: validate the **WSUS Server Connection Account**.  

---

## **Appendix — Useful console locations & logs**
- Console: **Administration → Site Configuration → Servers and Site System Roles** (add SUP role).  
- Console: **Software Library → Overview → Software Updates** (view/manage updates).  
- Logs on site server: `wsyncmgr.log`, `wcm.log`, `SMS_SQL_*`.  
- Logs on client: `WUAHandler.log`, `UpdatesHandler.log`, `WindowsUpdate.log`.  


!!! note "## Additional Notes"
    - Use **Automatic Deployment Rules (ADR)** for recurring updates (e.g., Patch Tuesday).  
    - For **third-party updates**, configure catalogs and publishing in SUP settings. 

---

## **References / further reading**
- [Plan for software updates — Microsoft Docs](https://learn.microsoft.com/mem/configmgr/sum/plan-design/plan-for-software-updates)  
- [Prepare for software updates management](https://learn.microsoft.com/mem/configmgr/sum/plan-design/prepare-for-software-updates)  
- [Install and configure a software update point](https://learn.microsoft.com/mem/configmgr/sum/get-started/install-a-software-update-point)  
- [Prerequisites for software updates](https://learn.microsoft.com/mem/configmgr/sum/plan-design/prerequisites-for-software-updates)  
- [Best practices for software updates](https://learn.microsoft.com/mem/configmgr/sum/plan-design/best-practices-for-software-updates)  