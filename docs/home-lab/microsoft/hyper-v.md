# Create a Virtual Internal VS with NAT Network in Hyper-V

A **Hyper-V Virtual Switch (VS)** is a software-based network switch that allows virtual machines (VMs) to communicate with each other, the host system, and external networks.  
It provides the foundation for networking in Hyper-V environments and supports three main types: **External**, **Internal**, and **Private**.  

- **External**: Connects VMs to the physical network through the host’s network adapter.  
- **Internal**: Allows communication between VMs and the host only (no direct internet access).  
- **Private**: Enables communication only between VMs (no host or external connectivity).  

This guide focuses on creating an **Internal Virtual Switch with NAT (Network Address Translation)**, which is especially useful for **lab or test environments**.  
By combining an internal switch with NAT, VMs can remain isolated from the production network while still having controlled internet access through the host system.  


---

## **🔧 Step-by-Step Instructions**


!!! warning "Run PowerShell as Administrator"
    All commands below require elevated privileges.
    Ensure that PowerShell is opened **with Administrator privileges**, otherwise the commands will fail.
---

### **🌐 1. Create a New Virtual Switch (Internal)**

```powershell
New-VMSwitch -SwitchName "LabSwitch" -SwitchType Internal
```

!!! note "Explanation"
    This creates an Internal Hyper-V virtual switch named LabSwitch.

    - Internal switches allow communication between host and VMs.
    - They do not provide internet connectivity directly.
    - You can rename `LabSwitch` to anything you prefer.

---

**Get the Interface Index of the New Adapter**
``` powershell
Get-NetAdapter
```

!!! info "How to Use"
    - Find the newly created `LabSwitch` interface.
    - Note the InterfaceIndex assigned to it (`e.g., 49`).
    - You’ll need this value in the next step.

---

**Assign a Static IP Address to LabSwitch**
``` powershell
New-NetIPAddress -IPAddress 10.0.0.1 -PrefixLength 24 -InterfaceIndex 49
```
!!! tip "Custom Subnets"
    - Replace 49 with the actual InterfaceIndex from step 3.
    - You can use any private IP subnet (`e.g., 192.168.100.1/24, 172.16.0.1/24, etc.`).

---
### **🌐 2. Create a NAT Network**

``` powershell
New-NetNat -Name "NatSwitch" -InternalIPInterfaceAddressPrefix 10.0.0.0/24
```

!!! note "Explanation"
    - This command enables NAT for the subnet attached to the virtual switch.
    - You can rename `NatSwitch` to anything you prefer.
    - Ensure the AddressPrefix matches the range you used in the previous step.


??? tip "Optional: Remove Network Components"
    - Remove the Virtual Switch
    ``` powershell
    Remove-VMSwitch "LabSwitch"
    ```

    - Remove NAT Object(s)
    ``` powershell
    Get-NetNat          # List all existing NATs
    Remove-NetNat -Name "NatSwitch"
    ```

    !!! warning "Cleanup Tip"
        Removing the NAT or switch will break VM connectivity.
        Only run these if you are decommissioning your lab network.

!!! tip "Networking Tips"
    - Attach VMs to the `LabSwitch` virtual adapter to connect them to the internal NAT network.
    - VMs will use `10.0.0.1` as their gateway for internet access.
    - Configure IPs via manual DHCP or static assignment in the subnet (`10.0.0.x/24`).

---

### **🔎 Network Diagram**

``` mermaid
flowchart TD
    Host[Host Machine] --- LabSwitch["LabSwitch (Internal Virtual Switch)"]
    LabSwitch --- VM1[VM1 - 10.0.0.10]
    LabSwitch --- VM2[VM2 - 10.0.0.11]
    LabSwitch --- VM3[VM3 - 10.0.0.12]

    LabSwitch --> Gateway["NAT Gateway (10.0.0.1)"]
    Gateway --> Internet((🌐 Internet))
```

!!! info "The above diagram shows:"

    - Host + VMs connected to `LabSwitch`
    - NAT Gateway (`10.0.0.1`) providing internet access
    - VMs using the same private subnet