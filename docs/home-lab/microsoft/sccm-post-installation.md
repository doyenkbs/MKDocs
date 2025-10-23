---
title: SCCM Post Installation
tags:
  - SCCM
  - Configuration Manager
  - Microsoft
  - Systems Management
  - Post Installation
summary: Step-by-step guide to configuring SCCM after installation, including resource discovery, boundaries, client push, client settings, and collections.
---


# **<span style="color:#009688;">SCCM Post Installation Guide</span>**

This guide walks through essential SCCM configuration after installation, focusing on Active Directory resource discovery, boundaries, client installation, client settings, and collections.

---

## **<span style="color:#009688;">A. Create a Client Setting**

{== **`Administration → Client Settings → Right-click Create Custom Client Device Settings`** ==}

- Name: `Client Settings for LAB`

Select and configure:

- **Client Cache**
  > - Enable  
  > - Size: `10240 MB` (allows downloads of files >5GB)

- **Client Policy**  
  > - Reporting interval: every 3 minutes (lab)

- **Computer Agent** 
  > - Org Display: Company name  
  > - Install Permission: All Users  
  > - PowerShell Execution Policy: Bypass

- **PC Restart** → Yes

- **Hardware Inventory**
  > - Schedule: every 1 hour (lab)  
  > - Classes: (Filter by category)  
        - Asset Intelligence → Select all  
        - Windows client/server classes → Select useful items (e.g., AppV Client Applicaton, Autostart, Boot config, Network login profile, Battery, etc.)

- **Remote Tools** 
    > - Configure Settings (Enable and Select : Domain, Private, and Public)
    > - Set Viewers (Admin or any groups allowed to remote in)

- **Software Center** → Yes (customize UI)

- **Software Inventory**
  > - Set types: `*.exe, *.msi, *.xml, *.mp4, *.mp3` (etc.)

- **Software Update** → Enable (manageement of the Office 365 Client Agent)

- **Software Metering** → Every 3 minutes (lab)

- **User and Device Affinity** → As preferred

**Deployment:**  
Right-click the new setting → **Deploy** → Choose target collection.  

!!! tip "To force a policy refresh:"  
    **`Assets and Compliance → Device Collection → Right-click collection → Client Notification → Download Device Policy`**

---

## **<span style="color:#009688;">B. Configure Client Push Install and Client Installation**

Configure SCCM to deploy clients automatically to new or existing devices.

### **Client Push Setup:**  

{== 
**`Administration → Site Configuration → Sites`**  
Right-click your **`Primary Site → Client Installation Settings → Client Push Installation`**
==}

- Check **Enable automatic site-wide client push installation**  
- Ensure servers, workstations, and configuration manager are checked  
- Under the **Accounts Tab** → Add a domain admin account (orange button), enter credentials and test (Optional: Test with `\\srvdc01\C$` for example).
- Apply changes.

*This auto-installs the client on new devices joining the domain/SCCM.*  
For existing PCs: select → Right-click → **Install Client**.

### **Verify Client Install:**

- **Folder:** `C:\Windows\ccmsetup\`
- **Log:** `C:\Program Files\SMS_CCM\Logs\ClientIDManagerStartup.log`  
  *(Check if client talks to correct management point)*
- **Services:** ***SMS Agent Host*** should be running
- **Control Panel:** ***Configuration Manager*** should be listed

!!! warning
    If the client doesn’t appear in **Control Panel**, check the logs first.  
    Most install issues are caused by account permissions or boundary misconfiguration.

---


## **<span style="color:#009688;">C. Discover Resources**

SCCM resource discovery enables management of computers, users, and groups within a domain.
</br>
Open the SCCM console and navigate to:

{== **`Administration → Hierarchy Configuration → Discovery Methods`** ==}  
(Enable all that start with **Active Directory**)

- **AD Forest Discovery**  
  Right-click → Properties → Check **Enable**. (Setup schedule is optional)

- **AD Group Discovery**  
  Right-click → Properties → Check **Enable**.  
  Add → Locations → Name it for example `Groups` → Browse → Select your domain → OK → Apply → OK.  
  *(This discovers all groups from your domain controller.)*

- **AD System Discovery**  
  Right-click → Properties → Check **Enable**.  
  Under **AD Containers**, click the orange button → Browse → Expand your domain.  
  > - Select **Computers** container → OK  
  > - Repeat → Select **Domain Controllers** container → OK </br>
  *(This discovers all devices in Computers and Domain Controllers.)*

- **AD User Discovery**  
  Right-click → Properties → Check **Enable**.  
  Add containers → Browse → Expand your domain → Select the **Users** container.  
  *(This discovers all AD users.)*

- **Heartbeat Discovery**  
  Enabled by default for PCs not in the domain but with SCCM client/agent installed.

- **Network Discovery**  
  Disabled by default (SCCM does not manage routers, modems, etc.).

!!! note "**Log Locations:**"
    ```
    C:\Program Files\Microsoft Configuration Manager\Logs
    C:\Program Files\SMS_CCM\Logs
    ```

---

## **<span style="color:#009688;">D. Boundary and Boundary Group**

### **Boundary**  

Boundaries help define network locations and resources, using four creation methods: IPv4 range, IPv6, AD site, and IP Subnet.

**Example:**  
{== **`Administration → Boundaries → Right-click Create`** ==}

- **Description:** `Lab PC Boundary`  
- **Type:** IP Address Range (or other type)  
- Enter Starting IP and Ending IP → Apply → OK

### **Boundary Group**  

Used to assign a site.

**Example:**  
{== **`Administration → Boundary Groups → Right-click Create`** ==}  

- **Name:** `Site Server Assignment for Lab PC`  
- **Add:** Select the IP range  
- **Preferences tab:** Check **`Use this boundary group for site assignment`**  
- **Add:** Choose your site from the list → OK → Apply → OK

!!! tip
    Boundaries define **where resources live**.</br> 
    Boundary groups define **how they are assigned** to a site.

---


## **<span style="color:#009688;">E. Collections**

Helps organize/manage user and device groups.

### Example 1: Device Collection (Direct Rule)

1. {== `Assets and Compliance → Device Collection → Right-click Create Collection` ==}  
2. Name it  
3. Choose target collection  
4. Add Rule → **Direct Rule**  
5. Under Value: `%` → Next → Select devices → Finish

### Example 2: Device Collection (Query Rule)

1. {== `Assets and Compliance → Device Collection → Right-click Create Collection` ==}  
2. Name it  
3. Choose target collection  
4. Add Rule → **Query Rule**  
5. Enter a name → Edit Query Statement  
6. Criteria tab → New (`Select...`)
   > - Attribute Class: `Operating System`  
   > - Attribute: `Caption`  
   > - Value: Choose desired OS  
7. Enable **Use incremental update** for auto-discovery of new devices.  

!!! note
    **Direct Rule** = manually add devices  
    **Query Rule** = dynamically discover devices (recommended for larger environments)