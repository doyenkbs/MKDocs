---
tags:
  - Paperless-NGX
  - Docker
---

# **<span style="color:#009688;">Paperless-ngx Installation on Debian 12</span>**
---
## **<span style="color:#009688;">Overview</span>**

<span style="color:#009688;">Paperless-ngx</span> is a self-hosted document management system that indexes, OCRs, and organizes scanned documents and PDFs. This guide explains how to install <span style="color:#009688;">Paperless-ngx</span> on Debian 12 using the official installation script with Docker Compose.

<span style="color:#009688;">Paperless-ngx</span> provides an interactive setup script that automates configuration. The script collects your preferences, generates the necessary Docker Compose files, pulls images, starts the application, and sets up your superuser account.

## **<span style="color:#009688;">1. Install Docker & Docker Compose</span>**

{==

Before proceeding, ensure that Docker and Docker Compose are installed on your Debian 12 system. Please follow the detailed [Docker Installation Guide](https://kabason.net/home-lab/docker.html) in this documentation to set up Docker and Docker Compose correctly.

==}

## **<span style="color:#009688;">2. Run the Official Paperless-ngx Installation Script</span?**

Download and execute the setup script directly from the <span style="color:#009688;">Paperless-ngx</span> project:

``` bash
bash -c "$(curl --location --silent --show-error https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/main/install-paperless-ngx.sh)"
```

Follow the interactive prompts to complete the configuration. The script will:
- Ask for your configuration options (e.g., installation path, admin email/password)
- Download all required Docker images
- Set up configuration files and environment variables
- Start <span style="color:#009688;">Paperless-ngx</span> and perform initial setup

## **<span style="color:#009688;">3. Access the Paperless-ngx Web Interface</span>**

Once the script finishes, open your browser and visit:

    * http://<your-server-ip>:8000

Log in with the superuser credentials you defined during setup.

{==

Adapt this guide if your directory structure or environment differs. For advanced configuration (backups, environment files, custom compose options), see the official documentation.

==}

***References***
- [*Paperless-ngx GitHub Repository*](https://github.com/paperless-ngx/paperless-ngx)
- [*Docker Installation Guide for Debian*](https://docs.docker.com/engine/install/debian)
- [*Official Paperless-ngx Documentation*](https://docs.paperless-ngx.com)

