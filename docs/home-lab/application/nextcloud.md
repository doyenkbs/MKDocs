# **Nextcloud Installation on Ubuntu 24.04 LTS**

---

## **Overview**

**Nextcloud** is a powerful platform for self-hosted collaboration, file synchronization, document editing, calendar, contacts, and much more. By the end of this guide, you’ll have a fully working Nextcloud server ready for personal or team use.

---

## **Prerequisites**

Before starting, make sure you have:

- A clean **Ubuntu 24.04 LTS** server  
- Root access or a **sudo-enabled user**  
- A valid **domain name** (optional, but required for HTTPS)  
- Reliable **Internet access**

---

## **1. Initial Server Setup**
Begin by creating a non-root user and updating your system packages to ensure you have the latest security updates and software.

### **Create a New User**
➡ This creates a new user with admin rights so you don’t need to use root directly.
``` bash
adduser <username>
usermod -aG sudo <username>
```

Log in as your new user after setup.

### **Update System Packages**
➡ Keeping your server up to date ensures security patches and latest features.
``` bash
sudo apt update
sudo apt dist-upgrade
sudo apt autoremove
```

### **Set Hostname & Hosts File**
➡ A proper hostname helps your server identify itself on the network. Update these system files and reboot to apply changes.
``` bash
sudo nano /etc/hostname
sudo nano /etc/hosts
```
> *Enter your server's hostname and domain name as needed.*
Reboot to apply changes:
``` bash
sudo reboot
```
!!! note
    *If you own a domain, make sure DNS points to your server’s IP.*

---

## **2. Download and Unpack Nextcloud**

Get the latest Nextcloud release from the official source, and unzip it to prepare for installation.
``` bash
wget https://download.nextcloud.com/server/releases/latest.zip
sudo apt install unzip
unzip latest.zip
```

---

## **3. Install and Configure MariaDB**
MariaDB will serve as the backend database. Install it, secure the installation, and create a database and user for Nextcloud.

### **Install MariaDB Server**
➡ Installs the database engine.
``` bash
sudo apt install mariadb-server
```
Check the status of mariadb service:
``` bash
systemctl status mariadb
```
### **Secure MariaDB**
➡ Runs a wizard to secure your database (set root password, remove test DB, etc.).
``` bash
sudo mysql_secure_installation
```
### **Create Nextcloud Database & User**
➡ Creates a dedicated database and user account for Nextcloud.
``` bash
sudo mariadb
```
Within MariaDB prompt:
``` bash
CREATE DATABASE nextcloud;
GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost' IDENTIFIED BY 'mypassword';
FLUSH PRIVILEGES;
EXIT;
```
---

## **4. Install Apache, PHP, and Required Modules**
These are the web server and PHP modules required by Nextcloud for full functionality.
➡ These modules give Nextcloud its features (file uploads, encryption, images, etc.).
``` bash
sudo apt install libmagickcore-6.q16-6-extra php php-apcu php-bcmath php-cli php-common php-curl php-gd php-gmp php-imagick php-intl php-mbstring php-mysql php-zip php-xml
```
Enable the recommended PHP extensions:
``` bash
sudo phpenmod apcu bcmath gmp imagick intl
```

---

## **5. Move Nextcloud Files and Set Permissions**
Move the Nextcloud files you extracted in step 2 into the web server’s root directory, then set the appropriate ownership and permissions.
➡ This ensures Apache can serve Nextcloud securely and disables the default page.

``` bash
mv nextcloud <your-domain>   #e.g. mv nextcoud nextcloud.example.com
sudo chown -R www-data:www-data <your-domain> # set permission
sudo mv <your-domain> /var/www/
sudo a2dissite 000-default.conf   #disable the default web page that ships with Apache since we won’t be needing it for anything
```

---

## **6. Configure Apache**
Set up your Apache virtual host to serve Nextcloud instance, enabling URL rewriting and access control.

### **Create a Virtual Host File**
``` bash
sudo nano /etc/apache2/sites-available/<your-domain>.conf
```
Paste and edit:
``` ini
<VirtualHost *:80>
    DocumentRoot "/var/www/<your-domain>"
    ServerName your-domain

    <Directory "/var/www/<your-domain>/">
        Options MultiViews FollowSymlinks
        AllowOverride All
        Order allow,deny
        Allow from all
    </Directory>

   TransferLog /var/log/apache2/<your-domain>_access.log
   ErrorLog /var/log/apache2/<your-domain>_error.log

</VirtualHost>
```
!!! note
    Replace <your-domain> with your nextcloud domain, e.g. `nextcloud.example.com`

Enable the site:
``` bash
sudo a2ensite <your-domain>.conf
```
➡ This tells Apache how to serve your Nextcloud site.

---

## **7. PHP Configuration**
Tune PHP settings for optimal performance and stability with Nextcloud.

``` bash
sudo nano /etc/php/8.3/apache2/php.ini
```
Update these values:
> `memory_limit = 512M`
> `upload_max_filesize = 200M`
> `max_execution_time = 360`
> `post_max_size = 200M`
> `date.timezone = Your/Timezone` `(e.g. America/Detroit)`
> `opcache.enable=1`
> `opcache.interned_strings_buffer=16`
> `opcache.max_accelerated_files=10000`
> `opcache.memory_consumption=128`
> `opcache.save_comments=1`
> `opcache.revalidate_freq=1`

Enable important modules:
``` bash
sudo a2enmod dir env headers mime rewrite ssl
```
Enable APCu for CLI:
``` bash
sudo nano /etc/php/8.3/mods-available/apcu.ini
```
Add the following to the end of the file:
``` ini
apc.enable_cli=1
```
Restart Apache to apply changes:
``` bash
sudo systemctl restart apache2
```

---

## **8. Final Database and Security Tweaks**

### **Tune Nextcloud Database**
Add missing database indices using Nextcloud’s command line tool to improve database performance.

``` bash
sudo chmod +x /var/www/<your-domain>/occ
sudo /var/www/<your-domain>/occ db:add-missing-indices
sudo chmod -x /var/www/<your-domain>/occ
```

---

## **9. Obtain a TLS Certificate (Let's Encrypt)**
Set up free, trusted [SSL certificates](https://certbot.eff.org/instructions?ws=apache&os=ubuntufocal) to encrypt your site’s traffic.
➡ This encrypts traffic so your files and logins are secure.

``` bash
sudo apt install snapd
sudo snap install core; sudo snap refresh core
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
sudo certbot --apache
```
Follow prompts carefully to secure your installation.

---

## **10. Miscellaneous Adjustments**

### **Protect config.php**
Limit access to critical config files for security.

```bash
sudo chmod 660 /var/www/<your-domain>/config/config.php
sudo chown root:www-data /var/www/<your-domain>/config/config.php
```

### **Enable Memory Caching**
Improve performance by enabling APCu caching in your Nextcloud config:

``` bash
sudo nano /var/www/<your-domain>/config/config.php
```
Add the following line to the bottom:
``` php
'memcache.local' => '\OC\Memcache\APCu',
'default_phone_region' => 'US',
```

### **Enable Strict Transport Security**
Improve security with HTTP Strict Transport Security.

``` bash
sudo nano /etc/apache2/sites-available/<your-domain>-le-ssl.conf
```
Add the following line after the server name:
``` apache
<IfModule mod_headers.c>
    Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains"
</IfModule>
```

Restart Apache:
``` bash
sudo systemctl restart apache2
```
➡ Forces browsers to always use HTTPS.

---

### **Completion 🎉**

Your Nextcloud server is ready!
Visit:
> `https://<your-domain>`

Follow the installer to create your admin account and connect to the database.

---

## **Troubleshooting**

### **Apache shows a blank page**

Ensure permissions are correct:
``` bash
sudo chown -R www-data:www-data /var/www/<your-domain>
```
Restart Apache:
``` bash
sudo systemctl restart apache2
```

### **Database connection errors**

Double-check your database credentials in:
``` bash
sudo nano /var/www/<your-domain>/config/config.php
```
Make sure MariaDB is running:
``` bash
systemctl status mariadb
```

### **HTTPS certificate fails**

Ensure your domain points to your server’s public IP.
``` bash
sudo certbot renew --dry-run
```

### **File upload too large**

Increase upload limit in php.ini:
``` ini
upload_max_filesize = 512M
post_max_size = 512M
```

### **Nextcloud says “memory caching not configured”**

Edit config.php:
``` php
'memcache.local' => '\OC\Memcache\APCu',
```
Restart Apache.
``` bash
sudo systemctl restart apache2
```

### **“Trusted Domain” error**

Add your domain to the trusted list:
``` php
'trusted_domains' =>
  array (
    0 => 'localhost',
    1 => 'your-domain.com',
  ),
```

---
## ***Reference***
> [*Nextcloud Documentation*](https://docs.nextcloud.com/server/latest/admin_manual/installation/system_requirements.html)
> [*Learn Linux TV: Complete Walkthrough for Installing Nextcloud on Ubuntu 24.04*](https://www.learnlinux.tv/complete-walkthrough-for-installing-nextcloud-on-ubuntu-24-04/)
> [*Certbot Instructions*](https://certbot.eff.org/instructions?ws=apache&os=ubuntufocal)






