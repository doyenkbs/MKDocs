# **<span style="color:#2496ED;">What is Docker and Docker Compose?</span>**

---
## **Docker**

<span style="color:#2496ED;">Docker</span> is an open-source platform that enables you to automate the deployment, scaling, and management of applications inside lightweight, portable containers. Containers isolate your applications from the host system, making them portable and consistent across different environments. Unlike virtual machines, containers share the host OS kernel, which makes them more resource-efficient.

<span style="color:#2496ED;">Docker</span> is ideal for running single services or applications in isolated environments and provides all the necessary commands to build, run, and manage containers.

---
## **Docker Compose**

<span style="color:#2496ED;">Docker Compose</span> is a tool for defining and managing multi-container Docker applications. With <span style="color:#2496ED;">Docker Compose</span>, you define your application’s services, networks, and volumes in a single YAML file (typically called docker-compose.yml). Compose allows you to start, stop, and manage multiple containers as a single application with just one command. It is especially useful for applications consisting of several interdependent services (like a web server, database, and cache).

---
## **Key differences:**

<span style="color:#2496ED;">Docker</span> is best for running and managing single containers.

<span style="color:#2496ED;">Docker Compose</span> is designed to organize and manage multiple containers together as one application stack, handling configuration and network setup automatically.

---
## **Installing Docker & Docker Compose**

Below are the installation steps for <span style="color:#2496ED;">Docker</span> and <span style="color:#2496ED;">Docker Compose</span> on Debian and Ubuntu.
### **Install Docker & Docker Compose on Debian**
```bash
# Update package lists and install dependencies
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg lsb-release

# Add Docker’s official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker’s repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine and Docker Compose (v2 is now included as a plugin)
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker service
sudo systemctl enable --now docker
sudo service docker start
```

---
### **Install Docker & Docker Compose on Ubuntu**
```bash
# Update package lists and install dependencies
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg lsb-release

# Add Docker’s official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker’s repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine and Docker Compose (v2 as plugin)
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker service
sudo systemctl enable --now docker
sudo service docker start
```

---

### **Linux Post-Installation Steps for Docker**

These **optional** steps help configure your Linux system for easier <span style="color:#2496ED;">Docker</span> usage.

### **Run Docker Without `sudo`**

By default, <span style="color:#2496ED;">Docker</span> requires `sudo` because the <span style="color:#2496ED;">Docker</span> daemon runs as `root` and listens on a Unix socket owned by `root`.

To allow your user to run D<span style="color:#2496ED;">ocker</span> without `sudo`:

```bash
# 1. Create the docker group (skip if it already exists)
sudo groupadd docker

# 2. Add your user to the docker group
sudo usermod -aG docker $USER

# 3. Apply changes
newgrp docker
```

---
### ***References***
- [Docker Documentation](https://docs.docker.com/get-started)
- [Install Docker Engine](https://docs.docker.com/engine/install/)
- [What is Docker Compose?](https://cyberpanel.net/blog/docker-compose-vs-docker) - CyberPanel
