# **Install SCCM Admin Console on a Workstation**

This guide explains how to install the **SCCM (Configuration Manager) Admin Console** on an administrator workstation. This is useful when you want to manage Configuration Manager without logging directly into the site server.

---

## **1. Prerequisites**

Before starting, ensure:

- The **SCCM Primary Site** is already installed and operational.  
- You have access to the **SCCM installation media** or a network share with the console installer.  
- Workstation meets minimum requirements (Windows 10/11 Pro or Enterprise).  

📖 Reference: [List of prerequisite checks](https://learn.microsoft.com/en-us/intune/configmgr/core/servers/deploy/install/list-of-prerequisite-checks)

---

## **2. Locate the Console Installer**

1. On the SCCM installation media or site server, browse to:  
```
<SCCM_Install_Media>\Tools\ConsoleSetup
```
or on the site server itself:  
```
C:\Program Files\Microsoft Configuration Manager\Tools\ConsoleSetup
```


2. Copy the **`AdminConsole.msi`** file (and supporting files) to your workstation.

---

## **3. Run the Installer**

1. On the workstation, run:  
```
AdminConsole.msi
```

2. Follow the installation wizard prompts.  

- Accept the default installation path, unless you need a custom location.  
- When prompted for the **site server name**, enter the **FQDN** of your SCCM site server (e.g., `CM01.lab.local`).  

---

## **4. Verify Installation**

1. After installation, launch the **Configuration Manager Console** from the Start Menu.  
2. Confirm it connects to the site server without errors.  
3. You should now be able to perform administrative tasks from your workstation.

---

✅ The **SCCM Admin Console** is now installed and ready for use on your workstation.


