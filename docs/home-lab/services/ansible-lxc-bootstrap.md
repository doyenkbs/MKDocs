---
tags:
  - Ansible
  - Automation
  - SSH Key Authentication
  - Service Account
---

# Ansible LXC Bootstrap Playbook

## Overview

Each new LXC starts the same way: create a user, add an SSH key, install the same baseline packages, and harden some defaults. Only then do you configure the service for the container. By hand, this takes 10 to 15 minutes for each container. Under time pressure, it is easy to skip a step (a missed `ufw` rule, a forgotten SSH key), and the problem shows only later.

This playbook changes that checklist into one command. Point it at the IP of a new LXC. The LXC comes back provisioned, secured to a standard baseline, and ready for the patch automation and config backup playbooks.

**What it does:**

- Creates the dedicated `ansible` service account with passwordless sudo
- Installs the SSH key used by the rest of the automation stack
- Installs a baseline package set
- Applies basic SSH hardening
- Sets hostname, timezone, and unattended-upgrades config
- Confirms the host is reachable and ready for future playbook runs

---

## Prerequisites

Since this playbook's whole job is to set up passwordless SSH access, it can't rely on that access existing yet. The **first connection** has to happen with a password (or an existing key you already have — e.g. the LXC's default root access from Proxmox).

```ini title="bootstrap_hosts.ini"
[new_lxc]
new-container ansible_host=192.168.1.50 ansible_user=root
```

Run this playbook using `--ask-pass` (or an existing root/admin key) the first time only. After it runs, the host graduates into your main inventory using the `ansible` account and key like everything else.

---

## The Playbook

```yaml title="bootstrap_lxc.yml"
---
- name: Bootstrap New LXC Container
  hosts: new_lxc
  become: yes
  vars:
    ansible_service_user: ansible
    ansible_pub_key_path: /root/.ssh/ansible_key.pub
    baseline_packages:
      - curl
      - wget
      - vim
      - htop
      - unattended-upgrades
      - ufw
      - fail2ban
      - net-tools
      - rsync
    lab_timezone: America/New_York

  tasks:

    - name: Update apt cache
      apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: Install baseline packages
      apt:
        name: "{{ baseline_packages }}"
        state: present

    - name: Create the ansible service account
      user:
        name: "{{ ansible_service_user }}"
        shell: /bin/bash
        create_home: yes
        password: "!"    # locked — key-only login

    - name: Grant passwordless sudo to the ansible account
      copy:
        dest: "/etc/sudoers.d/{{ ansible_service_user }}"
        content: "{{ ansible_service_user }} ALL=(ALL) NOPASSWD:ALL\n"
        mode: "0440"
        validate: "visudo -cf %s"

    - name: Install the automation SSH public key
      authorized_key:
        user: "{{ ansible_service_user }}"
        state: present
        key: "{{ lookup('file', ansible_pub_key_path) }}"

    - name: Set the system timezone
      timezone:
        name: "{{ lab_timezone }}"

    - name: Set the hostname
      hostname:
        name: "{{ inventory_hostname }}"
      when: inventory_hostname != "new-container"   # skip if using a placeholder name

    - name: Enable unattended security upgrades
      copy:
        dest: /etc/apt/apt.conf.d/50unattended-upgrades-local
        content: |
          Unattended-Upgrade::Allowed-Origins {
              "${distro_id}:${distro_codename}-security";
          };
          Unattended-Upgrade::Automatic-Reboot "false";
        mode: "0644"

    - name: Harden SSH — disable root login
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^#?PermitRootLogin'
        line: 'PermitRootLogin no'
      notify: restart ssh

    - name: Harden SSH — disable password authentication
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^#?PasswordAuthentication'
        line: 'PasswordAuthentication no'
      notify: restart ssh

    - name: Enable UFW and allow SSH
      ufw:
        rule: allow
        port: "22"
        proto: tcp

    - name: Set UFW default deny incoming
      ufw:
        state: enabled
        policy: deny
        direction: incoming

    - name: Confirm the ansible account can be used going forward
      debug:
        msg: >
          Bootstrap complete for {{ inventory_hostname }}.
          Move this host into the main inventory using the '{{ ansible_service_user }}'
          account and key-based auth from here on.

  handlers:
    - name: restart ssh
      service:
        name: ssh
        state: restarted
```

**What each part is doing:**

- **`password: "!"`** — locks password login for the `ansible` account entirely; it's key-only from the moment it's created.
- **`validate: "visudo -cf %s"`** — syntax-checks the sudoers file before it's written, so a typo can't lock out sudo access on the host.
- **`authorized_key` with `lookup('file', ...)`**: reads your existing automation public key from the control node and installs it. It uses the same key pair as your other playbooks. It does not make a new key for each host.
- **SSH hardening tasks**: disable root login and password authentication *after* the key is installed and works, not before. Thus, you cannot lock yourself out during the run.
- **`ufw` tasks** — default-deny firewall with SSH explicitly allowed; add more `ufw` allow tasks per-service later (e.g. port 443 for a web app) either here conditionally or in a follow-up playbook once the container's actual role is known.
- **`notify: restart ssh`** — SSH only restarts once, after both hardening changes, via the handler — avoids restarting the service twice and briefly dropping the connection mid-task.

!!! danger "Test SSH access in a second terminal before closing your current session"
    After the hardening tasks run, root password login is disabled. Before you disconnect, open a **second terminal** and confirm you can log in as `ansible` using the key:
    ```bash
    ssh -i ~/.ssh/ansible_key ansible@192.168.1.50 "sudo whoami"
    ```
    If that fails, do **not** close your original root session — fix the issue first using the still-open connection.

---

## Running It

```bash
ansible-playbook -i bootstrap_hosts.ini bootstrap_lxc.yml --ask-pass
```

You'll be prompted for the LXC's root/admin password once. Everything after that runs unattended.

For containers created via Proxmox with SSH key access already configured (no password), drop `--ask-pass` and make sure `ansible_ssh_private_key_file` points at whatever key currently has access.

---

## Promoting the Host to the Main Inventory

Once bootstrap completes, move the host from `bootstrap_hosts.ini` into your main `hosts.ini`, using the `ansible` account and automation key like every other managed host:

```ini title="hosts.ini"
[linux_servers]
new-container ansible_host=192.168.1.50
...

[linux_servers:vars]
ansible_user=ansible
ansible_become=yes
ansible_become_method=sudo
ansible_ssh_private_key_file=~/.ssh/ansible_key
```

Confirm it's reachable the normal way:

```bash
ansible new-container -i hosts.ini -m ping
```

From here, the host is fully onboarded — the [patch automation](ansible-patch.md) and [config backup](ansible-config-backup.md) playbooks will pick it up on their next scheduled run.

---

## Extending This Playbook

A few natural next additions, depending on what the container is for:

- **Docker + Docker Compose install task**: for each container that will run a Docker service (Mailcow, n8n-style apps), add a task block that installs Docker with the official convenience script or the repository method.
- **Authentik SSO pre-registration**: if the new service will be behind Authentik, document the manual SSO setup step here, even if the full integration stays manual.
- **Per-role variants**: when you have some container types (web app, database, monitoring agent), think about an Ansible **role** with one `vars` file for each type. This is better than one flat playbook for all types.

---

## Quick Reference

```bash
# First-time bootstrap (password auth)
ansible-playbook -i bootstrap_hosts.ini bootstrap_lxc.yml --ask-pass

# Bootstrap using an existing key instead of a password
ansible-playbook -i bootstrap_hosts.ini bootstrap_lxc.yml

# Verify the new host is reachable via the ansible account
ansible new-container -i hosts.ini -m ping

# Confirm SSH hardening took effect (should fail — root login disabled)
ssh root@192.168.1.50
```