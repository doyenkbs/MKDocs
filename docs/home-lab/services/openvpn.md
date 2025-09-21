---
title: OpenVPN Installation Guide
tags:
  - OpenVPN
  - VPN
  - Networking
  - Security
summary: Step-by-step guide to install and configure OpenVPN using the community installation script, including server setup, client configuration, and router port forwarding.
---

# **<span style="color:#43A047;">OpenVPN Installation Guide**

This guide walks you through installing and configuring an OpenVPN server using a community script. It also covers creating client profiles and connecting from devices.

---

## **<span style="color:#43A047;">1. Download the Installation Script**

Run the following command to download the OpenVPN installer script:
```bash
wget https://git.io/vpn -O openvpn-install.sh
```
---

## **<span style="color:#43A047;">2. Make the Script Executable**

Grant execution permissions to the script:
```bash
sudo chmod +x openvpn-install.sh
```
---

## **<span style="color:#43A047;">3. Run the Installer**

Execute the script to install OpenVPN and create your first client profile.
``` bash
sudo bash openvpn-install.sh
```

Accept the default settings when prompted.</br>
Provide a name for your first client (e.g., `Client1`).

!!! tip "Manage Additional Clients"
    To create additional clients, simply rerun the script:
    ``` bash
    bash sudo bash openvpn-install.sh
    ```
    You can repeat this process for as many devices as you need.

!!! tip
    If you plan to connect multiple devices, give each profile a descriptive name
    (e.g., `laptop`, `phone`, `tablet`) to make management easier.

---

## **<span style="color:#43A047;">4. Configure Port Forwarding**

Log into your router and forward the port chosen during installation (default is 1194/UDP, unless you selected TCP).

!!! warning
    Without port forwarding, external clients will not be able to connect to your VPN.

!!! warning
    Exposing ports directly to the internet increases your attack surface.</br>
    Always ensure your server is patched and protected with strong credentials.

---

## **<span style="color:#43A047;">5. (Optional) Copy Client Configuration**

By default, client profiles are stored in /root/.</br>
For easier access, copy your client file to your home directory:
``` bash
sudo cp /root/Client1.ovpn ~
```
> Replace `Client1.ovpn` with the actual client profile name you provided.

---

## **<span style="color:#43A047;">6. Import Client Configuration**

- Install the OpenVPN client on your device (Windows, macOS, Linux, iOS, or Android) from [openvpn.net/client](https://openvpn.net/client).

- Import the .ovpn file you generated.

- Connect to your VPN using the client app.

!!! note
    On mobile devices, you can use the official OpenVPN Connect app from the App Store (iOS) or Play Store (Android).

---

## **<span style="color:#43A047;">✅ Next Steps**

- Test your VPN connection from outside your home network.

!!! tip
    Test your connection by visiting https://whatismyipaddress.com to confirm your public IP matches your VPN server.

- Add additional clients by rerunning the installer.

- Secure your server by keeping your system updated.

---

## **<span style="color:#43A047;">📚 References**

[OpenVPN Community Downloads](https://openvpn.net/community-downloads/)</br>

[OpenVPN Documentation](https://openvpn.net/community-resources/how-to/)</br>

[Nyr’s OpenVPN Install Script (GitHub)](https://github.com/Nyr/openvpn-install)



