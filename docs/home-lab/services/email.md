# **Mailcow Installation Guide (Ubuntu)**

This guide provides a streamlined, step-by-step process to install Mailcow mail server on Ubuntu 22.04 using **Docker** and **Docker Compose**. Mailcow is a modern mail server suite designed for ease of deployment and management.

---

## **Prerequisites**

### **System Requirements**
- **OS:** Ubuntu 22.04 LTS or newer  
- **RAM:** Minimum 6 GB (+1 GB swap)  
- **Disk:** At least 20 GB free  
- **Domain:** A fully qualified domain name (FQDN), e.g., `mail.example.com`
- Open ports: 80, 443, 25, 465, 587 (check firewall rules)

### **Essential Packages**
Update your system and install required tools:

```bash
sudo apt update
sudo apt install -y git openssl curl gawk coreutils grep jq apt-transport-https ca-certificates software-properties-common
```

👉 These tools are needed for cloning the repository, generating configs, and running setup scripts.

### **Firewall Setup**
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
## **Step 1: Install Docker & Docker Compose**
Mailcow runs entirely inside Docker containers, so Docker is required. To install Docker and Docker Compose, please refer to the detailed [Installation Guide](https://kabason.net/home-lab/docker.html) within this documentation.

---

## **Step 2: Clone the Mailcow Repository**
All Mailcow files are hosted on GitHub.

``` bash
cd /opt
sudo git clone https://github.com/mailcow/mailcow-dockerized
cd mailcow-dockerized
```
👉 This downloads Mailcow’s code into `/opt/mailcow-dockerized`.

---

## **Step 3: Generate Mailcow Configuration**

Run the configuration script to create your `mailcow.conf`.

``` bash
sudo ./generate_config.sh
```
👉 This will ask for your mail server FQDN (e.g., mail.example.com) and create a mailcow.conf with settings.

(Optional) Edit configuration:
``` bash
sudo nano mailcow.conf
```
👉 Adjust network interfaces, timezone, or domain details if needed.

---

## **Step 4: Start Mailcow Docker Containers**

Pull the latest images and start the Mailcow service containers in detached mode.
``` bash
sudo docker compose pull
sudo docker compose up -d
```
👉 This downloads all required containers (Postfix, Dovecot, Nginx, etc.) and runs them in the background.

### **Verify Mailcow Status**
Check if all containers are running:
``` bash
sudo docker compose ps
```

---

## **Step 5: Access Mailcow Web Interface**
Once running, log in via browser:**
> `https://<your-domain>/admin`

!!! note
    *The first time, you may get a warning about a self-signed SSL certificate.*

Default credentials:
- Username: `admin`
- Password: `moohoo`

👉 Login and immediately update the admin password under Admin UI → Configuration → Change Password.

---

## **Step 6: Configure DNS Records**

### **Configure Base DNS Records**
At minimum, add:
- **A record** → `mail.example.com` → `Server IP`
- **MX record** → `example.com` → `mail.example.com`

👉 Without these, other mail servers won’t know where to deliver your domain’s email.

### **SPF, DKIM, and DMARC Setup**
Proper DNS authentication ensures your emails don’t end up in spam.

1. **SPF Record**
Create a TXT record:
``` bash
Name: @
Type: TXT
Value: v=spf1 mx -all
```
👉 This allows only your MX servers to send mail for your domain, blocking all others.

If you also send via Google/Microsoft (Optional), add:
``` bash
v=spf1 mx include:_spf.google.com include:spf.protection.outlook.com -all
```

2. **DKIM Record**
DKIM signs outgoing emails so recipients can verify authenticity.

- In Mailcow **Admin UI → Configuration → ARC/DKIM Keys**
- Generate a **2048-bit DKIM key**
- Add the provided **TXT record** in DNS

Example:
``` makefile
Name: dkim._domainkey.example.com
Type: TXT
Value: v=DKIM1; k=rsa; p=MIGfMA0GCSqG...IDAQAB
```
👉 Once DNS propagates, Mailcow will automatically sign outgoing mail with this key.

3. **DMARC Record**
DMARC ties SPF & DKIM together and provides reporting.
Add a TXT record:
``` makefile
Name: _dmarc
Type: TXT
Value: v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@example.com; ruf=mailto:dmarc-reports@example.com; sp=none; aspf=s
```
> *Replace `mailto:dmarc-reports@example` and `dmarc-reports@example.com` with your email.*
👉 This tells other mail servers to quarantine suspicious emails and send you reports.

---

## **Step 7: Verify Setup**

### **Check DNS Records**
Run:
``` bash
dig TXT example.com
dig TXT dkim._domainkey.example.com
dig TXT _dmarc.example.com
```
👉 Ensure SPF, DKIM, and DMARC show correctly.

### **Testing Tools (optional) **

- [mail-tester](https://www.mail-tester.com/) (DKIM, DMARC, SPF)
- [MX Toolbox](https://mxtoolbox.com/SuperTool.aspx) (DNS, SMTP, RBL)
- Check Gmail headers for:

> - `SPF=pass`
> - `DKIM=pass`
> - `DMARC=pass`

- [Postmaster Tool](https://gmail.com/postmaster/)
👉 If any fail, recheck DNS entries.

---

## **Troubleshooting**

View Logs:
``` bash
sudo docker compose logs -f
```
Restart Stack:
``` bash
sudo docker compose down
sudo docker compose up -d
```

---

## ***References***

- *[Mailcow Documentation](https://docs.mailcow.email/getstarted/install/)*
- *[Mailcow GitHub Repository](https://github.com/mailcow/mailcow-dockerized)*
- *[SPF, DKIM, DMARC Guide](https://docs.mailcow.email/getstarted/prerequisite-dns/)*

---

🎉 Congratulations! You now have a fully functional Mailcow mail server running on your Ubuntu system.