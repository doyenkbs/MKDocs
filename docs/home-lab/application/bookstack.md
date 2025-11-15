---
tags:
  - Bookstack
---

# **<span style="color:#009688;">BookStack Installation on Ubuntu 24.04</span>**

This page documents the complete process for installing <span style="color:#009688;">BookStack</span>, a self-hosted wiki and knowledge base, on a fresh Ubuntu 24.04 server. <span style="color:#009688;">BookStack</span> is used as my primary knowledge repository.

> Reference: [BookStack Official Installation Guide](https://www.bookstackapp.com/docs/admin/installation/)

!!! info "**Prerequisites**"
    - Fresh Ubuntu 24.04 LTS server (minimal install, recommended as LXC or VM)
    - Root or sudo access
    - Static IP address

## **Ubuntu 24.04 Installation Script**

A script is available to install <span style="color:#009688;">Bookstack</span> on a fresh Ubuntu 24.04 instance.

!!! warning
    This script is for a clean OS only and will install Apache, MySQL 8.0, and PHP 8.3.
    It may overwrite existing web setup and does not configure mail or server security. You are responsible for those steps separately.

### **Running the Script**
``` bash
# Download the installation script
wget https://codeberg.org/bookstack/devops/raw/branch/main/scripts/installation-ubuntu-24.04.sh

# Make the script executable
chmod a+x installation-ubuntu-24.04.sh

# Run the script with admin permissions
sudo ./installation-ubuntu-24.04.sh
```
The script will output a log file in your working directory for debugging. File and directory permissions will be set based on the user running the script.

## **Change BookStack Instance URL**

**1. Set Domain Name**

- Set up a DNS record (e.g., wiki.example.com) to point to your server’s public IP. You may use a service like Cloudflare Tunnel.

**2. Configure the BookStack ***.env*** file**

- Edit the environment file to use your domain name:
``` bash
sudo nano /var/www/bookstack/.env
```

- Change the following line to match your domain:
``` text
APP_URL=https://wiki.example.com
```

- Then restart Apache:
``` bash
sudo systemctl restart apache2
```

## **Set Up HTTPS with Let’s Encrypt (Optional but Recommended)**

Install Certbot and request a certificate for your domain:
``` bash
sudo apt install certbot python3-certbot-apache
sudo certbot --apache -d wiki.example.com
```
Certbot will handle obtaining and installing your SSL certificate.

## **Mail Setup (Recommended)**

**1. Edit ***.env*** for Mail Settings**
Open your environment config:
``` bash
sudo nano /var/www/bookstack/.env
```

Add or edit the following section:
``` text
MAIL_DRIVER=smtp
MAIL_HOST=smtp.example.com
MAIL_PORT=587
MAIL_USERNAME=your_email@example.com
MAIL_PASSWORD=your_password
MAIL_ENCRYPTION=tls
MAIL_FROM=your_email@example.com
MAIL_FROM_NAME="BookStack"
```

!!! note
    Replace values with those from your email provider.

**2. Clear Config Cache (recommended after changing .env):**
```bash
# From the BookStack installation directory:
php artisan config:clear
```

## First Login
Once installation and setup are complete, access <span style="color:#009688;">Bookstack</span> in your browser at:

> *http(s)://your-domain-or-server-ip*

Follow the on-screen prompts to finish setup.

For more details and troubleshooting, consult the [*BookStack installation documentation*](https://www.bookstackapp.com/docs/admin/installation/).