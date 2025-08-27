# **Firewall Configuration via GPO**

This section explains how to configure firewall rules via **Group Policy (GPO)** on the **Domain Controller**.

---

## **Steps**

1. Open **Group Policy Management**  

2. Create a new GPO:  
   > - Name: **SCCM Firewall Policy**

3. Edit the GPO and configure the following:

---
### **Remote Desktop Settings**
- **Computer Configuration → Policies → Administrative Templates → Windows Components → Remote Desktop Services → RD Session Host → Connections**  
  - **Allow users to connect remotely** → **Enable**  

- **Computer Configuration → Policies → Administrative Templates → Windows Components → Remote Desktop Services → RD Session Host → Security**  
  - **Require user authentication for remote connections** → **Enable**  

---

### **Firewall Inbound Rules (Custom Ports)**

- **Computer Configuration → Windows Settings → Security Settings → Windows Defender Firewall → Windows Defender → Inbound Rules**  
  - Right-click → **New Rule** → **Port**  
  - Select **TCP** and enter the following ports:  
    ```
    80, 443, 1433, 4022, 8530, 8531, 3389 
    ```
  - Accept defaults and **name the rule: SCCM Firewall Policy**  

---

### **Firewall Predefined Rules**

- **Computer Configuration → Windows Settings → Security Settings → Windows Defender Firewall → Windows Defender → Inbound Rules**  
  - Right-click → **New Rule** → **Predefined** → Select **File and Printer Sharing** → Follow prompts  

- **Computer Configuration → Windows Settings → Security Settings → Windows Defender Firewall → Windows Defender → Inbound Rules**  
  - Right-click → **New Rule** → **Predefined** → Select **Windows Management Instrumentation (WMI)** → Follow prompts  

- **Computer Configuration → Windows Settings → Security Settings → Windows Defender Firewall → Windows Defender → Outbound Rules**  
  - Right-click → **New Rule** → **Predefined** → Select **File and Printer Sharing** → Choose **Allow the connection**  

---

## **Firewall Rules Summary**

| Port  | Protocol | Service / Purpose            |
|-------|----------|------------------------------|
| 80    | TCP      | HTTP (Web / SCCM / WSUS)     |
| 443   | TCP      | HTTPS (Secure Web)           |
| 1433  | TCP      | SQL Server                   |
| 4022  | TCP      | SQL Service Broker           |
| 8530  | TCP      | WSUS (HTTP)                  |
| 8531  | TCP      | WSUS (HTTPS)                 |
| 3389  | TCP      | Remote Desktop (RDP)         |

**Predefined Rules**
- **File and Printer Sharing** (Inbound & Outbound)  
- **Windows Management Instrumentation (WMI)**  

---

## **GPO Firewall Policy Flow**

``` mermaid
flowchart TD
    DC["🖥️ Domain Controller\n(GPO: SCCM Firewall Policy)"]
    GPO["📜 Group Policy Object\n(Firewall Rules)"]
    Clients["💻 Domain-Joined Clients"]

    DC --> GPO
    GPO --> Clients

    subgraph Rules["Firewall Rules Applied via GPO"]
        RDP["🔓 Allow RDP (3389)"]
        HTTP["🌐 Allow HTTP (80)"]
        HTTPS["🌐 Allow HTTPS (443)"]
        SQL["🗄️ SQL Server (1433, 4022)"]
        WSUS["📦 WSUS (8530, 8531)"]
        FNP["🖨️ File & Printer Sharing"]
        WMI["📊 Windows Management Instrumentation (WMI)"]
    end

    GPO --> Rules
```

``` mermaid
graph TD
    A["Computer Configuration"] --> B["Policies"]
    B --> C["Administrative Templates"]
    C --> D["Windows Components"]
    D --> E["Remote Desktop Services"]
    E --> F["RD Session Host"]
    F --> G["Connections → Allow users to connect remotely (Enable)"]
    F --> H["Security → Require user authentication (Enable)"]

    A --> I["Windows Settings"]
    I --> J["Security Settings"]
    J --> K["Windows Defender Firewall"]

    K --> L["Inbound Rules"]
    L --> M["New Rule → Port → 80, 443, 1433, 4022, 8530, 8531, 3389 (SCCM Firewall Policy)"]
    L --> N["New Rule → Predefined → File and Printer Sharing"]
    L --> O["New Rule → Predefined → Windows Management Instrumentation (WMI)"]

    K --> P["Outbound Rules"]
    P --> Q["New Rule → Predefined → File and Printer Sharing (Allow Connection)"]
```

✅ At this point, all firewall rules are centrally managed by GPO and applied automatically to all domain-joined machines.