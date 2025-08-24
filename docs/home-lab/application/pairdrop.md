# **<span style="color:#F57C00;">PairDrop Installation via Proxmox VE Helper-Scripts</span>**

This guide covers how to install <span style="color:#F57C00;">PairDrop</span>, local file transfer solution—in an LXC container on Proxmox VE using the Proxmox VE Helper-Scripts. These community scripts make deploying new apps, like <span style="color:#F57C00;">PairDrop</span>, fast, standardized, and repeatable.

> For official script documentation, visit: [PairDrop Helper Script](https://community-scripts.github.io/ProxmoxVE/scripts?id=pairdrop)

## **Step-by-Step Instructions**

**1. Launch the Installation Script**

Open the Proxmox VE Shell on your chosen node and run:
``` bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/pairdrop.sh)"
```
This command will start an interactive installation menu managed by the helper script.

**2. Follow the Installation Prompts**

The script will guide you through several basic setup options. Common prompts include:

|Prompt	                |Example / Recommendation       |
|-----------------------|-------------------------------|
|Container ID	        |100 (or any unused ID)         |
|Hostname	            |pairdrop                       |
|Network Bridge	        |vmbr0 (default, usually fine)  |
|Static IP Address	    |e.g., 172.30.0.x               |
|Gateway IP	            |e.g., 172.30.0.1               |
|Storage Location	    |e.g., local-lvm                |
|Root Password	        |Set a secure password          |
|Enable SSH/Nesting	    |Optional                       |

Adjust these as needed for your lab's environment and network.

**3. Wait for Setup to Complete**

* After you confirm your settings, the script will:
    - Download the latest Debian 12 template
    - Create an LXC container
    - Install Docker inside the container
    - Deploy the PairDrop Docker image
This process is automated—wait for it to finish and note any output or log locations for future reference.

**4. Access the PairDrop Web Interface**

After installation is complete, open your browser and go to:
``` text
http://<your-static-ip>:3000
```
!!! note
    Replace <your-static-ip> with the IP you assigned in setup. You will now be able to use the PairDrop web UI.

## **Additional Notes**

* You can review or update your container’s configuration from the Proxmox web UI.
* For container management and updates, check the official helper scripts and project repository.
* PairDrop works cross-browser and is accessible on your LAN unless you configure additional network access.

***References:***
> - [*PairDrop Helper Script*](https://community-scripts.github.io/ProxmoxVE/scripts?id=pairdrop)


