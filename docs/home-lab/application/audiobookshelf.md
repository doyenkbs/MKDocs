# **<span style="color:coral;">Audiobookshelf Installation via Proxmox VE Helper Scripts</span>**

<span style="color:coral;">Audiobookshelf</span> is a self-hosted audiobook and podcast server with a web user interface and apps. This guide will show you how to deploy it in an LXC container using the Proxmox VE Helper-Scripts.


## **Step-by-Step Instructions**

**1. Launch the Installer Script**

Open the Proxmox VE Shell on your desired node and run:
``` bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/audiobookshelf.sh)"
```
    * This will start an interactive wizard to deploy <span style="color:coral;">Audiobookshelf</span>.
    * The script will download and set up everything needed automatically.

**2. Fill in the Prompts**

During installation, you'll be prompted for the following settings:

|Prompt	            |Example / Recommendation                                   |
|-------------------|-----------------------------------------------------------|
|Container ID	    |905 (or any unused ID)                                     |
|Hostname	        |audiobookshelf                                             |
|Network Bridge	    |vmbr0 (default)                                            |
|Static IP Address	|e.g., 172.30.0.x                                           |
|Gateway IP         |e.g., 172.30.0.1                                           |
|Storage Location	|e.g., local-lvm                                            |
|Enable Root SSH?	|Optional                                                   |
|Media Folder Mount	|Path to your media library or keep the default             |

Adjust these to match your local network and storage configuration.

**3. Configuration File Location**

After installation, the config file is located at:
``` text
/usr/share/audiobookshelf/config
```

**4. Accessing Audiobookshelf**

Once setup is complete, open:
``` text
http://<your-static-ip>:13378
```
> Replace 'your-static-ip' with the IP you assigned to the container.

**5. Transferring Media Files**

To transfer files from your main system to the Audiobookshelf container, you can use scp. For example:
``` bash
scp "/path/to/your/file" user@<container-ip>:/<media-folder>/
```

!!! note
    Replace /path/to/your/file, user, 'container-ip', and 'media-folder' with the appropriate values for your environment.

??? tip "**Additional Notes**"
    - This script is designed to make deployment on Proxmox seamless and repeatable.
    - You can reference the [Proxmox Community Scripts](https://community-scripts.github.io/ProxmoxVE/scripts?id=audiobookshelf) repository for updates and more container options.
    - See the container logs in Proxmox UI if troubleshooting is needed.

***Reference:***
> - [Audiobookshelf Helper Script](https://community-scripts.github.io/ProxmoxVE/scripts?id=audiobookshelf)
> - [Audiobookshelf Docs](https://www.audiobookshelf.org/docs)
