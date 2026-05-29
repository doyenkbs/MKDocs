---
title: Third-Party Updates
tags:
  - SCCM
  - Configuration Manager
  - Microsoft
  - Software Updates
  - ADR
  - Third-Party Updates
---

# **<span style="color:#009688;">Third-Party Updates in SCCM/MECM**

SCCM/MECM supports publishing and deploying **third-party updates** for applications such as Adobe Reader, Java, Chrome, and other non-Microsoft software. This extends patch management beyond Windows and Office to ensure a more secure environment.

---

##  **<span style="color:#009688;">Table of Contents**
- [Overview](#overview)
- [Benefits of Third-Party Updates](#benefits-of-third-party-updates)
- [Enable Third-Party Updates](#enable-third-party-updates)
- [Import and Manage Catalogs](#import-and-manage-catalogs)
- [Deploy Third-Party Updates](#deploy-third-party-updates)
- [Best Practices](#best-practices)

---

##  **<span style="color:#009688;">Overview**
Third-party software often contains vulnerabilities that need timely patching. By integrating third-party updates into SCCM, you can use the same infrastructure and processes already in place for Microsoft updates.

---

##  **<span style="color:#009688;">Benefits of Third-Party Updates**
- Centralized patch management for both Microsoft and non-Microsoft apps.  
- Reduced security risk by keeping third-party apps updated.  
- Improved compliance with organizational and regulatory requirements.  

---

##  **<span style="color:#009688;">Enable Third-Party Updates**
1. In the SCCM console, go to **Administration → Site Configuration → Sites**.  
2. Select your site and click **Configure Site Components → Software Update Point**.  
3. In the SUP settings, check **Enable third-party software updates**.  
4. Ensure the **WSUS Signing Certificate** is configured and deployed to clients.  

---

##  **<span style="color:#009688;">Import and Manage Catalogs**
1. Go to **Software Library → Software Updates → Third-Party Software Update Catalogs**.  
2. Choose from built-in catalogs (e.g., Adobe, Dell) or import custom ones.  
3. Subscribe to the vendor catalog and synchronize updates.  
4. Published updates will appear alongside Microsoft updates in the console.  

---

##  **<span style="color:#009688;">Deploy Third-Party Updates**
- Manage deployments the same way as Microsoft updates:  
  1. Add updates to a **Software Update Group**.  
  2. **Download content** and distribute to distribution points.  
  3. **Deploy** to device collections.  

---

##  **<span style="color:#009688;">Best Practices**
- Start with a **pilot deployment** before broad rollout.  
- Regularly update vendor catalogs to fetch the latest patches.  
- Monitor deployments in the **Monitoring → Deployments** workspace.  
- Combine with **Automatic Deployment Rules (ADR)** if the vendor catalog supports frequent updates.  
