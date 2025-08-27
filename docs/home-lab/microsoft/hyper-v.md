# Create a Virtual Internal VS with NAT Network in Hyper-V

This guide walks you through creating a **Hyper-V Internal Virtual Switch with NAT support** for use in labs or test environments — useful for setting up isolated virtual networks.

---

## **Step-by-Step Instructions**

### **🔧 1. Open PowerShell as Administrator**

!!! warning "Run as Administrator"
    Ensure that PowerShell is opened **with Administrator privileges**, otherwise the commands will fail.
---

### **🌐 2. Create a New Virtual Switch (Internal)**

```powershell
New-VMSwitch -SwitchName "LabSwitch" -SwitchType Internal
```

!!! note "Explanation"
    This creates an Internal Hyper-V virtual switch named LabSwitch.

    - Internal switches allow communication between host and VMs.
    - They do not provide internet connectivity directly.
    - You can rename `LabSwitch` to anything you prefer.

---

### **🔍 3. Get the Interface Index of the New Adapter**
``` powershell
Get-NetAdapter
```

!!! info "How to Use"
    - Find the newly created `LabSwitch` interface.
    - Note the InterfaceIndex assigned to it (`e.g., 49`).
    - You’ll need this value in the next step.

---

### **📡 4. Assign a Static IP Address to LabSwitch**
``` powershell
New-NetIPAddress -IPAddress 10.0.0.1 -PrefixLength 24 -InterfaceIndex 49
```
!!! tip "Custom Subnets"
    - Replace 49 with the actual InterfaceIndex from step 3.
    - You can use any private IP subnet (`e.g., 192.168.100.1/24, 172.16.0.1/24, etc.`).

---
### **🌐 5. Create a NAT Network**

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

flowchart TD
    Host[Host Machine] --- LabSwitch["LabSwitch (Internal Virtual Switch)"]
    LabSwitch --- VM1[VM1 - 10.0.0.10]
    LabSwitch --- VM2[VM2 - 10.0.0.11]
    LabSwitch --- VM3[VM3 - 10.0.0.12]

    LabSwitch --> Gateway["NAT Gateway (10.0.0.1)"]
    Gateway --> Internet((🌐 Internet))


### **🔎 Network Diagram**

            +-------------------+
            |   Host Machine    |
            +---------+---------+
                      |
                      |
              +-------+-------+
              |   LabSwitch   |  (Internal Virtual Switch)
              +---+---+---+---+
                  |   |   |
                  |   |   |
      +-----------+   |   +-----------+
      |               |               |
+-----+-----+   +-----+-----+   +-----+-----+
|   VM1     |   |   VM2     |   |   VM3     |
| 10.0.0.10 |   | 10.0.0.11 |   | 10.0.0.12 |
+-----------+   +-----------+   +-----------+

                  |
                  v
         +-------------------+
         |  NAT Gateway      |
         |   10.0.0.1        |
         +---------+---------+
                   |
                   v
             +-------------+
             |   Internet  |
             +-------------+


!!! info "Both diagrams show:"

    - Host + VMs connected to `LabSwitch`
    - NAT Gateway (`10.0.0.1`) providing internet access
    - VMs using the same private subnet