# Automating Linux Patching with Ansible

## Overview

Keeping a fleet of Linux servers patched by hand doesn't scale — logging into each box, running `apt update && apt upgrade`, checking for reboots, and repeating it weekly gets tedious and error-prone fast.

[Ansible](https://www.ansible.com/) solves this by letting you describe *what* you want ("all servers patched and rebooted if needed") in a simple YAML file, then push that out to every server at once over SSH. There's no agent to install on the servers you're managing — Ansible just connects over SSH and runs the commands for you.

This guide walks through setting up Ansible from zero: preparing your servers, connecting them securely, writing your first patch playbook, testing it safely, and scheduling it to run automatically.

**What you'll end up with:**

- A central "control node" that can securely manage all your servers
- An inventory file listing every server you want to patch
- A playbook that updates packages, cleans up old ones, and reboots only if needed
- A cron job that runs the whole thing on a schedule, with logs you can review

**Estimated time:** 30–45 minutes for your first few servers.

---

## Key Concepts (Read This First)

If you're new to Ansible, these four terms will come up constantly:

| Term | What it means |
|---|---|
| **Control node** | The machine you run Ansible *from*. This is the only place Ansible needs to be installed. |
| **Managed node** | A server Ansible connects to and configures. No agent software required — just SSH access. |
| **Inventory** | A text file listing which servers Ansible should manage, and how to connect to them. |
| **Playbook** | A YAML file describing the tasks you want performed (e.g. "update packages, then reboot if needed"). |

Ansible connects to managed nodes over SSH using key-based authentication — no passwords typed in, no agent installed on the target machines. This is what makes the setup lightweight and secure.

---

## Step 1: Choose and Prepare Your Control Node

Pick one machine to act as your control node. It can be a small VM, a container, or even your own workstation — it just needs network access to every server you want to patch.

Install Ansible:

=== "Debian / Ubuntu"
    ```bash
    sudo apt update
    sudo apt install -y ansible
    ```

=== "RHEL / Rocky / AlmaLinux"
    ```bash
    sudo dnf install -y ansible-core
    ```

=== "macOS (via Homebrew)"
    ```bash
    brew install ansible
    ```

Confirm it installed correctly:

```bash
ansible --version
```

You should see version info, the config file path, and the Python interpreter being used.

---

## Step 2: Create a Dedicated Service Account on Each Server

Instead of connecting as `root` or your personal user, create a dedicated `ansible` account on every server you plan to manage. This keeps access scoped, auditable, and easy to revoke later if needed.

On **each managed server**:

```bash
sudo useradd -m -s /bin/bash ansible
sudo passwd -l ansible          # locks password login — SSH key only
```

Give it passwordless sudo access (needed for package updates and reboots):

```bash
echo "ansible ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ansible
sudo chmod 440 /etc/sudoers.d/ansible
```

!!! tip "Why passwordless sudo?"
    Ansible runs unattended, often via cron in the middle of the night. There's no way to type a sudo password interactively during an automated run, so the service account needs `NOPASSWD` sudo rights scoped to system administration tasks.

---

## Step 3: Generate an SSH Key on the Control Node

Back on your **control node**, generate a dedicated SSH keypair just for Ansible (don't reuse your personal SSH key — keeping this separate makes it easy to rotate or revoke later without affecting your own access).

```bash
ssh-keygen -t ed25519 -C "ansible-automation" -f ~/.ssh/ansible_key
```

- Press **Enter** to skip a passphrase (needed for unattended cron runs) — or set one and use `ssh-agent` if you want extra security and don't mind the added complexity.
- This creates two files: `ansible_key` (private — keep this secret) and `ansible_key.pub` (public — safe to distribute).

---

## Step 4: Upload the SSH Key to Every Managed Server

Now copy the **public** key to each server so the `ansible` account can log in without a password.

The easiest method is `ssh-copy-id`, run once per server:

```bash
ssh-copy-id -i ~/.ssh/ansible_key.pub ansible@<server-ip>
```

You'll be prompted for the `ansible` account's password one final time — after this, key-based login takes over.

!!! note "If `ansible-copy-id` fails or password login is disabled"
    If the server doesn't accept password login at all (common on hardened servers), copy the key manually:
    ```bash
    cat ~/.ssh/ansible_key.pub
    ```
    Paste the output into `/home/ansible/.ssh/authorized_keys` on the target server (create the `.ssh` directory and file if they don't exist, and set permissions: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`).

Repeat this step for **every server** you plan to manage.

### Verify key-based login works

```bash
ssh -i ~/.ssh/ansible_key ansible@<server-ip> "hostname"
```

If this returns the server's hostname with no password prompt, you're good. If you're prompted for a password, double check the key was copied correctly and that `/etc/ssh/sshd_config` on the target allows `PubkeyAuthentication yes`.

---

## Step 5: Build Your Inventory File

The inventory tells Ansible which servers exist and how to reach them. Create a project folder and an inventory file:

```bash
mkdir -p ~/ansible-patching
cd ~/ansible-patching
nano hosts.ini
```

```ini title="hosts.ini"
[linux_servers]
web01 ansible_host=192.168.1.10
web02 ansible_host=192.168.1.11
db01  ansible_host=192.168.1.20

[linux_servers:vars]
ansible_user=ansible
ansible_become=yes
ansible_become_method=sudo
ansible_ssh_private_key_file=~/.ssh/ansible_key
```

!!! tip "Use named hosts, not raw IPs"
    Giving each server a friendly name (`web01`, `db01`) instead of just an IP makes playbook output and logs far easier to read — especially once you're managing more than a handful of servers.

You can organize servers into multiple groups (e.g. `[web_servers]`, `[db_servers]`) if you want to target subsets differently later.

---

## Step 6: Test Connectivity

Before writing any automation, confirm Ansible can actually reach every server:

```bash
ansible linux_servers -i hosts.ini -m ping
```

Every host should return something like:

```
web01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

If a host fails here, fix that connection issue **before** moving on — nothing downstream will work reliably until this passes cleanly for every server.

**Common causes of failure at this stage:**

- SSH key not copied correctly → re-run Step 4
- Firewall blocking port 22 → check `ufw status` / security group rules
- Wrong `ansible_user` or `ansible_host` in inventory → double-check `hosts.ini`
- Host key verification prompt hanging → run once manually first: `ssh -i ~/.ssh/ansible_key ansible@<ip>` and accept the fingerprint

---

## Step 7: Write the Patch Playbook

Create the playbook that will actually perform the updates:

```bash
nano update_lab.yml
```

```yaml title="update_lab.yml"
---
- name: Linux Patch Management
  hosts: linux_servers
  become: yes
  serial: 2   # Update 2 servers at a time — limits blast radius if something breaks
  tasks:

    - name: Update package cache and upgrade all packages
      apt:
        update_cache: yes
        upgrade: dist       # Full dist-upgrade, handles kernel updates cleanly
        autoremove: yes     # Remove packages no longer needed
        purge: yes          # Fully remove old kernel config files
        autoclean: yes      # Clear out old downloaded package files
      register: apt_update_result

    - name: Check if a reboot is required
      stat:
        path: /var/run/reboot-required
      register: reboot_required_file

    - name: Reboot the server if required
      reboot:
        msg: "Ansible triggered reboot after patching"
        connect_timeout: 5
        reboot_timeout: 300
        pre_reboot_delay: 0
        post_reboot_delay: 30
      when: reboot_required_file.stat.exists

    - name: Report update status
      debug:
        msg: >
          Patches applied.
          Reboot status: {{ 'Server was rebooted' if reboot_required_file.stat.exists else 'No reboot needed' }}.
```

**What each part does, in plain terms:**

- **`serial: 2`** — Patches two servers at a time instead of all at once, so a bad update doesn't take your whole environment down simultaneously. Adjust this number based on how much risk you're comfortable with.
- **`apt` module** — This example targets Debian/Ubuntu. For RHEL-based systems, swap this task to use the `dnf` module instead (see the box below).
- **`stat` + `reboot`** — Only reboots a server if the update actually requires one, avoiding unnecessary downtime.
- **`debug`** — Prints a clear summary at the end of each server's run, useful when reading logs later.

!!! info "Managing RHEL / Rocky / AlmaLinux instead of Debian/Ubuntu"
    Replace the `apt` task with:
    ```yaml
    - name: Update and upgrade all packages
      dnf:
        name: "*"
        state: latest
        update_cache: yes
      register: dnf_update_result
    ```
    And check for reboot requirements using the `needs-restarting` command instead of the `/var/run/reboot-required` file, since that file is Debian-specific:
    ```yaml
    - name: Check if a reboot is required
      command: needs-restarting -r
      register: reboot_required
      failed_when: false
      changed_when: false
    ```
    If you manage a mixed environment, split servers into separate host groups (e.g. `[debian_servers]` and `[rhel_servers]`) and write a play for each.

---

## Step 8: Dry-Run Before Trusting It

Before letting this touch real servers, run it in check mode — Ansible will report what *would* change without actually changing anything:

```bash
ansible-playbook -i hosts.ini update_lab.yml --check
```

Review the output carefully. If everything looks sane, do a real run against just one server first:

```bash
ansible-playbook -i hosts.ini update_lab.yml --limit web01
```

Once you're confident, run it against the full inventory:

```bash
ansible-playbook -i hosts.ini update_lab.yml
```

---

## Step 9: Automate It with Cron

Once you trust the playbook, schedule it to run on its own. Edit root's crontab (or the crontab of whichever user runs Ansible):

```bash
crontab -e
```

Add a line like this to run every Sunday at 3:00 AM:

```cron
0 3 * * 0 ANSIBLE_HOST_KEY_CHECKING=False /usr/bin/ansible-playbook -i /root/ansible-patching/hosts.ini /root/ansible-patching/update_lab.yml >> /var/log/ansible-patching.log 2>&1
```

**Breaking down the cron syntax:**

| Field | Value | Meaning |
|---|---|---|
| Minute | `0` | On the hour |
| Hour | `3` | 3 AM |
| Day of month | `*` | Every day |
| Month | `*` | Every month |
| Day of week | `0` | Sunday |

**What the extra pieces do:**

- `ANSIBLE_HOST_KEY_CHECKING=False` — skips the interactive SSH fingerprint prompt, since cron has no terminal to answer it.
- `>> /var/log/ansible-patching.log 2>&1` — appends both normal output and errors to a log file you can review later.

!!! warning "Test the cron job manually first"
    Copy the exact command from the crontab line and run it manually once (without `>>` if you want to see the output live) to confirm it works outside of cron's stripped-down environment before trusting it to run unattended.

---

## Step 10: Review Logs Regularly

After each scheduled run, check the log to confirm everything succeeded:

```bash
tail -100 /var/log/ansible-patching.log
```

Search for failures specifically:

```bash
grep -n "fatal:" /var/log/ansible-patching.log
```

At the end of every playbook run, Ansible prints a **PLAY RECAP** summarizing results per host:

```
web01  : ok=4  changed=1  unreachable=0  failed=0  skipped=1
web02  : ok=4  changed=1  unreachable=0  failed=0  skipped=1
```

- `failed=0` and `unreachable=0` across the board means a clean run.
- Any `failed` or `unreachable` count above 0 means that server needs manual investigation.

---

## Troubleshooting Common Issues

| Symptom | Likely Cause | Fix |
|---|---|---|
| `UNREACHABLE! Failed to create temporary directory` | The `ansible` user's home directory doesn't exist or has wrong permissions | Check `ls -la /home/ansible` on the target; recreate the user with `-m` to force home dir creation |
| Prompted for password despite key setup | Public key not copied, or `authorized_keys` permissions wrong | Re-run `ssh-copy-id`, or verify `chmod 600 ~/.ssh/authorized_keys` on the target |
| `sudo: a password is required` | Sudoers entry missing or malformed | Recheck `/etc/sudoers.d/ansible` on the target; must have valid syntax and correct file permissions (`440`) |
| Playbook works manually but not via cron | Environment variables or PATH differ under cron | Use full paths to binaries (`/usr/bin/ansible-playbook`) and set variables explicitly in the crontab line |
| One server always shows `changed=1` even with nothing to update | Timestamps or metadata changing on every apt cache refresh | Usually harmless — confirm with `--check` mode that no packages are actually different |

---

## Next Steps

Once basic patch automation is stable, consider building on it:

- **Named host groups** — split servers by role (`web_servers`, `db_servers`) to apply different rules or schedules
- **`host_vars` / `group_vars`** — override settings per host (e.g. disable auto-reboot on a sensitive server)
- **Ansible Vault** — encrypt any secrets (API tokens, credentials) referenced in playbooks, rather than storing them in plaintext
- **Roles** — once playbooks grow beyond simple patching, break them into reusable roles for better organization
- **A UI/scheduler** — tools like AWX (the open-source upstream of Red Hat Ansible Tower) add a web dashboard, scheduling, and role-based access on top of plain Ansible

---

## Quick Reference

```bash
# Test connectivity to all hosts
ansible linux_servers -i hosts.ini -m ping

# Dry run — see what would change
ansible-playbook -i hosts.ini update_lab.yml --check

# Run against one host only
ansible-playbook -i hosts.ini update_lab.yml --limit web01

# Full run
ansible-playbook -i hosts.ini update_lab.yml

# Run an ad-hoc command on all hosts
ansible linux_servers -i hosts.ini -a "uptime"

# View recent log output
tail -100 /var/log/ansible-patching.log
```