---
title: Automatic Deployment Rules (ADR)
tags:
  - SCCM
  - Configuration Manager
  - Microsoft
  - Software Updates
  - ADR
---

# **<span style="color:#009688;">Automatic Deployment Rules (ADR)**

**Automatic Deployment Rules (ADR)** in SCCM/MECM allow you to automatically create, download, and deploy software updates on a defined schedule. This is especially useful for recurring updates such as **Patch Tuesday** releases.

---

##  **<span style="color:#009688;">Table of Contents**
- [Overview](#overview)
- [Benefits of ADR](#benefits-of-adr)
- [Steps to Create an ADR](#steps-to-create-an-adr)
- [Best Practices](#best-practices)

---

##  **<span style="color:#009688;">Overview**
An ADR automates the software update lifecycle by:  
- Synchronizing new updates that match defined criteria.  
- Creating **Software Update Groups** automatically.  
- Downloading update content to distribution points.  
- Deploying updates to device collections on schedule.  

---

##  **<span style="color:#009688;">Benefits of ADR**
- Reduces manual effort for monthly updates.  
- Ensures updates are applied consistently across devices.  
- Improves compliance reporting.  
- Helps enforce patch management SLAs.  

---

##  **<span style="color:#009688;">Steps to Create an ADR**

1. In the SCCM console, go to **Software Library → Software Updates → Automatic Deployment Rules**.  
2. Click **Create Automatic Deployment Rule**.  
3. Provide a **name and description**.  
4. Define **update criteria**:  
   - Products (e.g., Windows 10, Office 365)  
   - Classifications (e.g., Security, Critical Updates)  
   - Languages  
5. Configure the **schedule** (e.g., run every 2nd Tuesday of the month at 2:00 AM).  
6. Choose deployment settings:  
   - Target **collections** (e.g., *All Workstations*)  
   - Deployment type (**Required** or **Available**)  
   - Deadlines and restart behavior  
7. Configure **content download** to distribution points.  
8. Finish the wizard and allow ADR to automatically create/update the deployment.  

---

##  **<span style="color:#009688;">Best Practices**
- Start with **pilot collections** before broad deployment.  
- Use **maintenance windows** to control install timing.  
- Regularly review and refine ADR criteria.  
- Combine ADR with **compliance reports** to track patch success.  
