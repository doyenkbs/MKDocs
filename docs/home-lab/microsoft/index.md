---
title: SCCM Lab Setup Guide
tags:
  - SCCM
  - Configuration Manager
  - Microsoft
  - Systems Management
---

# SCCM Lab Setup Guide

---

In this project, I established a comprehensive **<span class="prod-app">SCCM (System Center Configuration Manager)</span>** lab environment to facilitate advanced software deployment, management, and reporting. The setup involved configuring SCCM on either **Microsoft Azure**, a **local machine using Proxmox VMs** or **Hyper-v**, ensuring a robust and scalable test environment.

---

## Key Tasks Included

- **Deployment and Configuration:** Installed and configured SCCM, deploying essential software packages, applications, Office 365, PowerShell scripts, and Windows updates.  
- **Infrastructure Setup:** Created boundary groups, users, and device collections to streamline management and deployment processes.  
- **Reporting and Analysis:** Developed custom reports and queries, utilizing SQL Management Studio for in-depth reporting and analysis.  
- **Advanced Configurations:** Created task sequences to automate deployment tasks and implemented PXE boot to facilitate network-based installations.  

This project demonstrated my ability to design and implement a scalable SCCM environment, leveraging both cloud and local resources to enhance software management and deployment capabilities.

---

## Lab Architecture

- **Domain Server:** DC, DNS, DHCP  
- **MECM/SCCM Server:** Database, MP (Management Point), DP (Distribution Point), SMS Provider, and SCP (Service Connection Provider)  
- **Client PC:** Windows 10 or Windows 11  

---

This series of pages outlines the complete setup of an **<span class="prod-app">SCCM (System Center Configuration Manager)</span>** or **<span class="prod-app">MECM</span>** lab environment.  

👉 [**Set up a Configuration Manager Lab**](https://learn.microsoft.com/en-us/mem/configmgr/core/get-started/set-up-your-lab) for detailed setup instructions and access to all necessary download links for the lab.
