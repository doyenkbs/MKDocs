---
tags:
  - Snipe-IT
---

# Snipe-IT Installation on Ubuntu 24.04

This guide explains how to install <span class="prod-app">Snipe-IT</span>, a self-hosted IT asset management system, on Ubuntu 24.04 using Nginx, MariaDB, and PHP 8.3.

> Reference: [Snipe-IT Official Installation Guide](https://snipe-it.readme.io/docs/installation)

## 1. Update the System

``` bash
sudo apt update && sudo apt upgrade -y
```

## 2. Install Required Packages

Install Nginx, MariaDB server, PHP 8.3, and all required PHP extensions.
``` bash
sudo apt install nginx mariadb-server php-bcmath php-common php-ctype php-curl php-fileinfo php-fpm php-gd php-iconv php-intl php-mbstring php-mysql php-soap php-xml php-xsl php-zip git -y
```

## 3. Install Composer

``` bash
sudo apt install composer -y
```

## 4. Create the Snipe-IT Database

Start the MariaDB shell:
```bash
sudo mysql
```

In the MariaDB shell, run:
``` sql
CREATE DATABASE snipeit;
GRANT ALL ON snipeit.* TO 'snipeit'@'localhost' IDENTIFIED BY 'yourStrongPassword';
FLUSH PRIVILEGES;
EXIT;
```
!!! note 
    Replace 'yourStrongPassword' with a strong password of your choice.

## 5. Download Snipe-IT

```bash linenums="1"
cd /var/www/html
sudo git clone https://github.com/snipe/snipe-it
cd snipe-it
```

## 6. Create and Configure the Environment File

Copy the example environment file and edit it:
```bash
sudo cp .env.example .env
sudo nano .env
```

Edit the following variables:
``` text
APP_URL=http://your-server-ip
DB_DATABASE=snipeit
DB_USERNAME=snipeit
DB_PASSWORD=yourStrongPassword
```
!!! note
    Replace your-server-ip and yourStrongPassword as appropriate.

## 7. Set Permissions

``` bash
sudo chown -R www-data: /var/www/html/snipe-it
sudo chmod -R 755 /var/www/html/snipe-it
```

## 8. Install Dependencies with Composer

``` bash
sudo composer update --no-plugins --no-scripts
sudo composer install --no-dev --prefer-source --no-plugins --no-scripts
```

## 9. Generate the Application Key

``` bash
sudo php artisan key:generate
```
!!! warning 
    Save a copy of your APP_KEY in a secure location. It is required to decrypt any encrypted fields in the database.

## 10. Check PHP-FPM Version

``` bash
sudo systemctl list-units --type=service | grep php
```
!!! note
    Ensure that PHP 8.3 (or your current version) is installed and running.

## 11. Enable PHP-FPM

``` bash
sudo systemctl start php8.3-fpm
sudo systemctl enable php8.3-fpm
```

## 12. Create Nginx Configuration for Snipe-IT

Create the site configuration file:

``` bash
sudo nano /etc/nginx/conf.d/snipeit.conf
```
Paste the following content (adjust server_name and PHP version if needed):

``` text
server {
    listen 80;
    server_name your-server-ip;
    root /var/www/html/snipe-it/public;

    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include fastcgi.conf;
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
```
!!! note
    Replace your-server-ip with your server's IP address if needed. Adjust PHP socket path/version if you are using a different PHP release.

## 13. Enable the Site

Create a symlink to enable the site:
``` bash
sudo ln -s /etc/nginx/conf.d/snipeit.conf /etc/nginx/sites-enabled/snipeit.conf
```

## 14. Update Nginx Main Config

Edit Nginx's main configuration file:
``` bash
sudo nano /etc/nginx/nginx.conf
```
Add the following line inside the http block:
``` text
server_names_hash_bucket_size 64;
```

## 15. Restart Nginx

```bash
sudo systemctl restart nginx
```

## 16. Access the Snipe-IT Web Interface

Open your web browser and visit:

> http://your-server-ip
Follow the web-based setup wizard to complete installation.

{==

Your <span class="prod-app">Snipe-IT</span> instance should now be running. Refer to the [*Snipe-IT Official documentation*](https://snipe-it.readme.io/docs/installation) for advanced configuration and troubleshooting.

==}