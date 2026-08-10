---
tags:
  - Mailcow
  
---

# Mailcow Installation Guide (Ubuntu)

This guide explains how to install and configure **<span class="prod-app">Mailcow: dockerized</span>** on **Ubuntu 22.04+**, with firewall setup, **SPF, DKIM, and DMARC**, and best practices for **VPS self-hosting**.

---

## Why Use a VPS for Mailcow?

Running a mail server requires:

- **A static, public IP address**  
- **Correct reverse DNS (PTR record)** for your mail domain  
- **No ISP blocking** of port 25 (many home ISPs block it)

👉 Because of these requirements, hosting Mailcow on a **VPS provider** (like **Contabo, Hetzner, Linode, or DigitalOcean**) is strongly recommended.  

**Reverse DNS (rDNS)**: 

- This is a PTR record mapping your **server IP → hostname** (e.g., `1.2.3.4 → mail.example.com`).  
- Mail servers like Gmail, Outlook, and Yahoo will **reject or spam-flag emails** if rDNS is missing or mismatched.  
- Most VPS providers allow you to set this in their control panel.  

---

## Prerequisites

### System Requirements
- **Server:** VPS with Ubuntu 22.04 or newer (e.g., Contabo VPS S with 6 GB RAM) 
- **RAM:** Minimum 6 GB (+1 GB swap)  
- **Disk:** At least 20 GB free  
- **Domain:** A fully qualified domain name (FQDN), e.g., `mail.example.com`
- **Static IP with rDNS set to match your mail domain** 

!!! info "Essential Packages"
    These tools are required for cloning the repository, generating configs,  
    and running setup scripts.

    ```bash
    sudo apt update
    sudo apt install -y git openssl curl gawk coreutils grep jq \
    apt-transport-https ca-certificates software-properties-common
    ```

### Firewall Setup
Open Ports with UFW.    
Mailcow needs email and web ports open:

``` bash
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 25/tcp    # SMTP
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 110/tcp   # POP3
sudo ufw allow 143/tcp   # IMAP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 465/tcp   # SMTPS
sudo ufw allow 587/tcp   # Submission
sudo ufw allow 993/tcp   # IMAPS
sudo ufw allow 995/tcp   # POP3S
sudo ufw allow 4190/tcp  # Sieve
```
Enable firewall:
``` bash
sudo ufw enable
sudo ufw status verbose
```
👉 This ensures only essential services are exposed.

---
## Step 1: Install Docker & Docker Compose
Mailcow runs entirely inside Docker containers, so Docker is required.  
To install Docker and Docker Compose, refer to the [Docker Installation Guide](https://kabason.net/home-lab/docker.html) in this documentation.

---

## Step 2: Clone the Mailcow Repository
All Mailcow files are hosted on GitHub.

``` bash
cd /opt
sudo git clone https://github.com/mailcow/mailcow-dockerized
cd mailcow-dockerized
```
👉 This downloads Mailcow’s code into `/opt/mailcow-dockerized`.

---

## Step 3: Generate Mailcow Configuration

Run the configuration script to create your `mailcow.conf`.

``` bash
sudo ./generate_config.sh
```
👉 This will ask for your mail server FQDN (e.g., mail.example.com) and create a mailcow.conf.

(Optional) Edit configuration:
``` bash
sudo nano mailcow.conf
```
👉 Adjust network interfaces, timezone, or domain details if needed.

---

## Step 4: Start Mailcow Docker Containers

Pull images and start Mailcow in detached mode.
``` bash
sudo docker compose pull
sudo docker compose up -d
```
👉 This downloads all required containers (Postfix, Dovecot, Nginx, etc.) and runs them in the background.

### Verify Mailcow Status
Check if all containers are running:
``` bash
sudo docker compose ps
```

---

## Step 5: Access Mailcow Web Interface
Once running, log in via browser:
> `https://<your-domain>/admin`

!!! note
    *The first time, you may get a warning about a self-signed SSL certificate.*

!!! danger "Default Credentials"
    - Username: `admin`  
    - Password: `moohoo`  

    ⚠️ Login and **immediately update the admin password** under  
    *Admin UI → Configuration → Change Password*.

---

## Step 6: Configure DNS Records

### Configure Base DNS Records
At minimum, add:
!!! example "Base DNS Records"
    - **A record** → `mail.example.com` → Server IP  
    - **MX record** → `example.com` → `mail.example.com`

    👉 Without these, other mail servers won’t know where to deliver your domain’s email.

### SPF, DKIM, and DMARC Setup

!!! tip "SPF, DKIM, and DMARC"
    Add TXT records for SPF, DKIM, and DMARC to ensure email delivery.  
    Without these, your mail may end up in spam.

### 1. SPF Record

!!! example "Create a TXT record:"
    ``` bash
    Name: @
    Type: TXT
    Value: v=spf1 mx -all
    ```
    👉 This allows only your MX servers to send mail for your domain, blocking all others.

If you also send via Google/Microsoft (Optional), add:
!!! tip
    ``` bash
    v=spf1 mx include:_spf.google.com include:spf.protection.outlook.com -all
    ```

### 2. DKIM Record
DKIM signs outgoing emails so recipients can verify authenticity.

- In Mailcow **Admin UI → Configuration → ARC/DKIM Keys**
- Generate a **2048-bit DKIM key**
- Add the provided **TXT record** in DNS

!!! example
    ``` makefile
    Name: dkim._domainkey.example.com
    Type: TXT
    Value: v=DKIM1; k=rsa; p=MIGfMA0GCSqG...IDAQAB
    ```
👉 Once DNS propagates, Mailcow will automatically sign outgoing mail with this key.

### 3. DMARC Record

DMARC ties SPF & DKIM together and provides reporting.
!!! example "Add a TXT record:"
    ``` makefile
    Name: _dmarc
    Type: TXT
    Value: v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@example.com; ruf=mailto:dmarc-reports@example.com; sp=none; aspf=s
    ```
> *Replace `mailto:dmarc-reports@example` and `dmarc-reports@example.com` with your email.*

👉 This tells other mail servers to quarantine suspicious emails and send you reports.

---

## Step 7: Verify Setup

### Check DNS Records
Run:
``` bash
dig TXT example.com
dig TXT dkim._domainkey.example.com
dig TXT _dmarc.example.com
```
👉 Ensure SPF, DKIM, and DMARC show correctly.

### Testing Tools (optional)

- [mail-tester](https://www.mail-tester.com/) (DKIM, DMARC, SPF)
- [MX Toolbox](https://mxtoolbox.com/SuperTool.aspx) (DNS, SMTP, RBL)
- Check Gmail headers for:

> - `SPF=pass`
> - `DKIM=pass`
> - `DMARC=pass`

- [Postmaster Tool](https://gmail.com/postmaster/)
👉 If any fail, recheck DNS entries.

---

??? bug "Troubleshooting"
    ```bash
    sudo docker compose logs -f
    sudo docker compose down
    sudo docker compose up -d
    ```
    Use these commands to debug or restart the Mailcow stack.

---

## *References*

- *[Mailcow Documentation](https://docs.mailcow.email/getstarted/install/)*
- *[Mailcow GitHub Repository](https://github.com/mailcow/mailcow-dockerized)*
- *[SPF, DKIM, DMARC Guide](https://docs.mailcow.email/getstarted/prerequisite-dns/)*

---

🎉 Congratulations! You now have a fully functional <span class="prod-app">Mailcow</span> mail server running on your Ubuntu system.

