---
tags:
  - Ansible
  - Patch Management
  - Automation
  - Proxmox
  - SSH Key Authentication
  - Service Account
---

# Automating Linux Patching with Ansible

## Overview

Keeping a fleet of Linux servers patched by hand doesn't scale — logging into each box, running `apt update && apt upgrade`, checking for reboots, and repeating it weekly gets tedious and error-prone fast.

[Ansible](https://www.ansible.com/) solves this by letting you describe *what* you want ("all servers patched and rebooted if needed") in a simple YAML file, then push that out to every server at once over SSH. There's no agent to install on the servers you're managing — Ansible just connects over SSH and runs the commands for you.

This guide walks through setting up Ansible from zero: preparing your servers, connecting them securely, writing your first patch playbook, testing it safely, and scheduling it to run automatically.

**What you'll end up with:**

- A central "control node" that can securely manage all your servers
- An inventory file listing every server you want to patch, grouped by how much risk a bad patch carries
- A playbook that updates packages, cleans up old ones, and reboots only if needed
- A second playbook for infrastructure hosts that reports instead of rebooting
- Cron jobs that run both on a schedule, with logs you can review

**Estimated time:** 30–45 minutes for your first few servers.

---

## Jump To

| I need to... | Section |
|---|---|
| Understand the terminology | [Key Concepts](#key-concepts-read-this-first) |
| Set up the `ansible` account on a host | [Step 2](#step-2-create-a-dedicated-service-account-on-each-server) |
| Install the SSH key, including on hardened hosts | [Step 4](#step-4-upload-the-ssh-key-to-every-managed-server) |
| Write or restructure the inventory | [Step 5](#step-5-build-your-inventory-file) |
| Fix a host that suddenly won't connect | [Handling a Changed Host Key](#handling-a-changed-host-key) |
| Write the patch playbook | [Step 7](#step-7-write-the-patch-playbook) |
| Schedule it with cron | [Step 9](#step-9-automate-it-with-cron) |
| Patch a hypervisor or public VPS safely | [Step 10](#step-10-patching-infrastructure-hosts) |
| Diagnose a failing host | [Troubleshooting](#troubleshooting-common-issues) |
| Look up a command | [Quick Reference](#quick-reference) |

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

!!! tip "Which machine am I typing this on?"
    The single most common source of confusion when following any Ansible guide. The rule for this page:

    - Anything starting with `ansible` or `ansible-playbook` runs on the **control node**.
    - Everything else runs on the **managed node** being changed.

    A command run from the wrong machine produces a confusing but perfectly logical error. For example, running `ssh ansible@<ip>` from a managed node instead of the control node offers that node's key rather than the control node's, and you get `Permission denied (publickey)` even though everything is configured correctly.

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

The `-m` flag creates the home directory owned by the new user. This matters more than it looks: Ansible writes temporary files to `/home/ansible/.ansible/tmp` on every single task, so a home directory that exists but is owned by root causes every playbook run against that host to fail.

Verify it immediately:

```bash
ls -ld /home/ansible
```

You want `drwxr-x--- ansible ansible` or tighter. If it shows `root root`, fix it now:

```bash
sudo chown -R ansible:ansible /home/ansible
sudo chmod 700 /home/ansible
```

Give it passwordless sudo access (needed for package updates and reboots):

```bash
echo "ansible ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ansible
sudo chmod 440 /etc/sudoers.d/ansible
sudo visudo -c
```

`visudo -c` must print `parsed OK` for every file it checks. Never leave a managed host without running it — a malformed sudoers file breaks sudo entirely, including your own ability to fix it.

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

The easiest method is `ssh-copy-id`, run once per server from the control node:

```bash
ssh-copy-id -i ~/.ssh/ansible_key.pub ansible@<server-ip>
```

You'll be prompted for the `ansible` account's password one final time — after this, key-based login takes over.

### If password login is disabled on the target

Common on hardened servers and any host where you already ran the [bootstrap playbook](ansible-lxc-bootstrap.md). Copy the key by hand instead.

**On the control node**, display the key and copy the whole line:

```bash
cat ~/.ssh/ansible_key.pub
```

**On the managed server**, as root, paste it in:

```bash
mkdir -p /home/ansible/.ssh
chmod 700 /home/ansible/.ssh
nano /home/ansible/.ssh/authorized_keys
```

Paste as a single line with no wrapping, save, then fix permissions:

```bash
chmod 600 /home/ansible/.ssh/authorized_keys
chown -R ansible:ansible /home/ansible
ls -la /home/ansible/.ssh
```

You want `drwx------` on the directory and `-rw-------` on the file, both owned by `ansible`.

### Check for SSH restrictions before troubleshooting the key

On hardened hosts, a correct key still fails if the SSH daemon refuses the user outright. Check on the managed server:

```bash
grep -iE '^(Port|PermitRootLogin|PasswordAuthentication|AllowUsers|AllowGroups|PubkeyAuthentication)' /etc/ssh/sshd_config
ls /etc/ssh/sshd_config.d/ 2>/dev/null && grep -riE '^(Port|AllowUsers|AllowGroups)' /etc/ssh/sshd_config.d/
```

The second command matters. Hardening guides and cloud-init both drop override files into `sshd_config.d/`, and those settings won't appear in the main config file.

If `AllowUsers` or `AllowGroups` is set and `ansible` isn't listed, add it, then:

```bash
sshd -t && systemctl reload ssh
```

`sshd -t` validates the config first. Never restart SSH on a remote host without it — a syntax error leaves the daemon dead and you locked out.

If `Port` is not 22, that belongs in the inventory as `ansible_port=<port>`, not worked around at the SSH layer.

### Verify key-based login works

From the control node:

```bash
ssh -i ~/.ssh/ansible_key -o BatchMode=yes ansible@<server-ip> 'hostname; sudo -n true && echo sudo-ok'
```

Two lines back — the hostname, then `sudo-ok` — means the key and sudo are both correct. `BatchMode=yes` prevents it from silently falling back to a password prompt and masking a broken key.

Repeat for **every server** you plan to manage.

---

## Step 5: Build Your Inventory File

The inventory tells Ansible which servers exist and how to reach them. Create a project folder and an inventory file:

```bash
mkdir -p ~/ansible-patching
cd ~/ansible-patching
nano hosts.ini
```

### Group by risk, not just by existence

The instinct is to put every Linux host in one group. Don't. A bad patch on a container running a wiki is an annoyance. The same patch on the hypervisor that hosts every other container, or on a public-facing mail server, is an outage.

Split the inventory by how much a bad run costs:

```ini title="hosts.ini"
# Application containers — safe to patch and reboot unattended
[linux_servers]
web01           ansible_host=192.168.1.10
web02           ansible_host=192.168.1.11
db01            ansible_host=192.168.1.20

# Hypervisors — patched separately, never rebooted unattended
[proxmox]
pve             ansible_host=192.168.1.2
pve1            ansible_host=192.168.1.3

# Public-facing VPS — patched separately, never rebooted unattended
[vps]
mail            ansible_host=<public-ip>
app             ansible_host=<public-ip>

[linux_servers:vars]
ansible_user=ansible
ansible_become=yes
ansible_become_method=sudo
ansible_ssh_private_key_file=~/.ssh/ansible_key

[proxmox:vars]
ansible_user=ansible
ansible_become=yes
ansible_become_method=sudo
ansible_ssh_private_key_file=~/.ssh/ansible_key

[vps:vars]
ansible_user=ansible
ansible_become=yes
ansible_become_method=sudo
ansible_ssh_private_key_file=~/.ssh/ansible_key
```

!!! danger "Group variables are not inherited — every group needs its own `:vars` block"
    A `[groupname:vars]` section applies **only** to that one group. Adding a new group without its own vars block means those hosts fall back to Ansible's defaults, which is connecting as the user running the playbook — usually `root`.

    On any host with `PermitRootLogin no`, that produces `Permission denied (publickey)`, which looks exactly like a broken SSH key. It isn't.

    Two ways this goes wrong in practice:

    - **The block is missing entirely.** Easy to spot once you know to look.
    - **The block is present but empty.** A `[vps:vars]` header immediately followed by another `[groupname:vars]` header means the variables below belong to the *second* group, not the first. The file looks correct at a glance.

    Verify what Ansible actually resolved rather than trusting the file:

    ```bash
    ansible-inventory -i hosts.ini --host <hostname>
    ```

    The output must include `"ansible_user": "ansible"`. If it only shows `ansible_host`, the vars block isn't reaching that host.

!!! tip "Use named hosts, not raw IPs"
    Giving each server a friendly name instead of just an IP makes playbook output and logs far easier to read, and means an IP change is one value to edit rather than a hunt through the file.

    It also solves a real problem: an inventory of bare IPs contains no record of what each address is. If an IP gets reassigned to a different application, Ansible will happily patch the new machine under the old entry, and nothing in the output tells you.

### Generating a named inventory from an existing IP-only one

If you already have a working inventory of bare IPs, let the hosts name themselves. Run on the **control node**:

```bash
cd ~/ansible-patching
for ip in $(awk '/^[0-9]/ {print $1}' hosts.ini); do
  name=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
         ansible@"$ip" hostname 2>/dev/null)
  if [ -n "$name" ]; then
    printf '%-24s ansible_host=%s\n' "$name" "$ip"
  else
    printf '# UNREACHABLE            ansible_host=%s\n' "$ip"
  fi
done | tee hosts-named.txt
```

Unreachable hosts come back commented rather than silently dropped, so you can see what needs attention. Review the output, sort hosts into groups, and rebuild `hosts.ini` from it.

Watch for duplicate hostnames in the output. If two containers both report `ubuntu` or `localhost`, Ansible silently uses only one of the entries.

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

Test every group, not just the first one:

```bash
ansible proxmox -i hosts.ini -m ping
ansible vps -i hosts.ini -m ping
```

If a host fails here, fix that connection issue **before** moving on — nothing downstream will work reliably until this passes cleanly for every server.

**Common causes of failure at this stage:**

- Missing or empty `[group:vars]` block → Ansible connects as `root`, which is refused. Check with `ansible-inventory -i hosts.ini --host <name>`
- `/home/ansible` owned by root → `Failed to create temporary directory`. Fix with `chown -R ansible:ansible /home/ansible`
- SSH key not copied correctly → re-run Step 4
- Firewall blocking SSH → check `ufw status` / security group rules
- Host key changed after an IP reassignment → see [Handling a Changed Host Key](#handling-a-changed-host-key) below

---

## Handling a Changed Host Key

When an IP gets reassigned to a different machine, SSH refuses to connect because the cached fingerprint no longer matches. This shows up as a host key warning interactively, and as an unreachable host in Ansible.

Fix it on the **control node**, as the user that runs the playbook. If cron runs as root, the relevant file is `/root/.ssh/known_hosts`, not your own:

```bash
ssh-keygen -f /root/.ssh/known_hosts -R <ip>
ssh-keyscan -H -t ed25519 <ip> >> /root/.ssh/known_hosts
ssh -o BatchMode=yes ansible@<ip> 'hostname; sudo -n true && echo sudo-ok'
```

For a host on a non-standard port, `ssh-keyscan` needs `-p <port>` too.

!!! warning "Clearing the fingerprint is only half the fix"
    The new machine at that address also won't have your control node's public key in `authorized_keys`. Expect to go from a host key error straight to `Permission denied (publickey)`, and plan to redo Step 4 for that host.

    Also update the inventory entry to reflect what actually lives at that IP now. An inventory that still names the old application is worse than one that fails, because it patches the wrong machine successfully.

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

    - name: Check for Docker
      ansible.builtin.stat:
        path: /usr/bin/docker
      register: docker_bin

    - name: Prune unused Docker images
      ansible.builtin.command: docker image prune -a -f
      register: docker_prune
      when: docker_bin.stat.exists
      changed_when: "'Total reclaimed space: 0B' not in docker_prune.stdout"

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
- **Docker prune tasks** — Every container image update leaves the old image behind. On a host that runs a few Docker services, this accumulates fast enough to fill a 20GB disk in a handful of upgrades. See the note below on placement.
- **`stat` + `reboot`** — Only reboots a server if the update actually requires one, avoiding unnecessary downtime.
- **`debug`** — Prints a clear summary at the end of each server's run, useful when reading logs later.

!!! note "Put the Docker prune before the reboot task, not after"
    Task order matters here. Placed after the reboot task, the prune waits through a full 300-second reboot cycle on any host that needs one before it runs. Placed before, it runs while the host is definitely up.

!!! tip "Verify the Docker binary path across your fleet before trusting the `stat` check"
    The `stat` check assumes `/usr/bin/docker`. A snap or manual install puts it elsewhere, and the task silently skips those hosts. Confirm once:

    ```bash
    ansible linux_servers -i hosts.ini -m shell -a "command -v docker || echo NO-DOCKER" --one-line
    ```

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
ansible-playbook -i hosts.ini update_lab.yml --syntax-check
ansible-playbook -i hosts.ini update_lab.yml --check
```

`--syntax-check` catches YAML errors instantly and costs nothing. Run it every time you edit a playbook.

Note that `--check` skips `command` tasks entirely, so it won't exercise the Docker prune. It still confirms the playbook parses and targets the right hosts.

Review the output carefully. If everything looks sane, do a real run against just one server first:

```bash
ansible-playbook -i hosts.ini update_lab.yml --limit web01
```

Pick a host you know the current state of. Once you're confident, run it against the full group:

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

!!! warning "`ANSIBLE_HOST_KEY_CHECKING=False` has a real cost"
    It disables host key verification entirely for that run. That's why a changed fingerprint can break your interactive SSH while the cron job keeps working silently.

    The tradeoff: any machine substituted at a managed IP gets patched with root privileges and no warning. Acceptable in a private lab, worth thinking twice about anywhere else.

!!! warning "Test the cron job manually first"
    Copy the exact command from the crontab line and run it manually once (without `>>` if you want to see the output live) to confirm it works outside of cron's stripped-down environment before trusting it to run unattended.

---

## Step 10: Patching Infrastructure Hosts

Hypervisors and public-facing servers need a different playbook, not just a different schedule.

The lab playbook reboots automatically. That's correct for an application container. It is not correct for a hypervisor, where a reboot takes every guest down with it, or for a mail server, where it drops SMTP mid-delivery.

A separate file also means a separate log, so a bad run on infrastructure is obvious rather than buried in 14 hosts of application output.

```bash
nano update_infra.yml
```

```yaml title="update_infra.yml"
---
- name: Patch Proxmox hosts
  hosts: proxmox
  become: yes
  serial: 1
  tasks:
    - name: Update apt cache and upgrade packages
      apt:
        update_cache: yes
        upgrade: dist
      register: pve_upgrade

    - name: Check if a reboot is required
      stat:
        path: /var/run/reboot-required
      register: pve_reboot

    - name: Report reboot status
      debug:
        msg: >
          {{ inventory_hostname }}: patches applied.
          {{ 'REBOOT REQUIRED, schedule manually' if pve_reboot.stat.exists
             else 'No reboot needed' }}.

- name: Patch VPS hosts
  hosts: vps
  become: yes
  serial: 1
  tasks:
    - name: Update apt cache and upgrade packages
      apt:
        update_cache: yes
        upgrade: dist
        autoremove: yes
      register: vps_upgrade

    - name: Check for Docker
      ansible.builtin.stat:
        path: /usr/bin/docker
      register: docker_bin

    - name: Prune unused Docker images
      ansible.builtin.command: docker image prune -a -f
      register: docker_prune
      when:
        - docker_bin.stat.exists
        - inventory_hostname != 'mail'
      changed_when: "'Total reclaimed space: 0B' not in docker_prune.stdout"

    - name: Check if a reboot is required
      stat:
        path: /var/run/reboot-required
      register: vps_reboot

    - name: Report reboot status
      debug:
        msg: >
          {{ inventory_hostname }}: patches applied.
          {{ 'REBOOT REQUIRED, schedule manually' if vps_reboot.stat.exists
             else 'No reboot needed' }}.
```

### What differs from the lab playbook, and why

**No reboot task anywhere.** Both plays detect and report. You reboot these hosts by hand, when you're awake and can watch them come back.

**`serial: 1` on Proxmox.** Prevents concurrent package operations across your entire virtualization layer, even without reboots involved.

**No `autoremove` or `purge` on Proxmox.** PVE keeps multiple kernels deliberately. `autoremove` on a Proxmox host has removed running kernels for people, and `purge` compounds it by deleting configs. The Proxmox-documented upgrade path is `apt update && apt dist-upgrade`, nothing more.

**Mailcow excluded from the Docker prune.** Mailcow's own `update.sh` manages its image lifecycle. `docker image prune -a -f` there can remove images the updater still references. Adjust the `inventory_hostname !=` condition to match your host's name.

### Verify the Proxmox repos before the first run

The playbook's first action is `update_cache: yes`. If `apt update` fails, the whole play aborts before patching anything.

The usual cause is an enabled enterprise repo without a subscription, which returns 401.

```bash
ansible proxmox -i hosts.ini -m shell -a "apt update 2>&1 | tail -20"
```

If you see 401s from `enterprise.proxmox.com`, disable those repos on the host.

!!! note "Proxmox 9 / Debian 13 use the deb822 `.sources` format"
    Repos moved from `/etc/apt/sources.list.d/*.list` to `*.sources`, which use `Types:`, `URIs:`, and `Suites:` fields instead of `deb` lines. A `grep '^deb '` finds nothing on these hosts and makes it look like no repos are configured.

    List them properly:

    ```bash
    ansible proxmox -i hosts.ini -m shell -a "grep -rhE '^(Types|URIs|Suites|Components|Enabled):' /etc/apt/sources.list.d/*.sources 2>/dev/null"
    ```

    Disable a repo by adding `Enabled: false` inside its stanza rather than commenting lines out. Check whether it's already there before adding it — a duplicate `Enabled` field is harmless but confusing.

!!! tip "Watch for duplicate repos across both formats"
    A host upgraded from an older Proxmox release often has both `pve-no-subscription.list` and `proxmox.sources` defining the same repo. `apt update` reports it:

    ```
    Warning: Target Packages (pve-no-subscription/binary-amd64/Packages) is configured
    multiple times in .../proxmox.sources:1 and .../pve-no-subscription.list:1
    ```

    Not harmful, but it doubles index downloads and means future repo changes have to be made in two places. Move the legacy `.list` files aside rather than deleting them:

    ```bash
    mkdir -p /root/apt-backup
    mv /etc/apt/sources.list.d/pve-no-subscription.list /root/apt-backup/
    mv /etc/apt/sources.list.d/ceph.list /root/apt-backup/
    mv /etc/apt/sources.list.d/pve-enterprise.list /root/apt-backup/
    apt update
    ```

    Leave genuine third-party repos alone (Tailscale, Cloudflare, Netbird) — those have no deb822 twin.

### Test and schedule

```bash
ansible-playbook -i hosts.ini update_infra.yml --syntax-check
ansible-playbook -i hosts.ini update_infra.yml --limit <one-host>
```

Start with whichever host has the fewest pending updates. A run with nothing to install still exercises the playbook mechanics at zero risk.

Once you've run it manually for a few weeks and trust the reboot-required reporting, schedule it in its own log:

```cron
0 4 * * 0 ANSIBLE_HOST_KEY_CHECKING=False /usr/bin/ansible-playbook -i /root/ansible-patching/hosts.ini /root/ansible-patching/update_infra.yml >> /var/log/ansible-infra.log 2>&1
```

An hour after the lab run, so the two never overlap.

!!! danger "Don't automate this on day one"
    These are the hosts where an unattended surprise costs the most. Run it by hand for two or three cycles, read the output each time, and confirm the reboot detection behaves before adding the cron line.

---

## Step 11: Review Logs Regularly

After each scheduled run, check the log to confirm everything succeeded:

```bash
tail -100 /var/log/ansible-patching.log
tail -100 /var/log/ansible-infra.log
```

Search for failures specifically:

```bash
grep -n "fatal:\|UNREACHABLE" /var/log/ansible-patching.log
```

At the end of every playbook run, Ansible prints a **PLAY RECAP** summarizing results per host:

```
web01  : ok=4  changed=1  unreachable=0  failed=0  skipped=1
web02  : ok=4  changed=1  unreachable=0  failed=0  skipped=1
```

- `failed=0` and `unreachable=0` across the board means a clean run.
- Any `failed` or `unreachable` count above 0 means that server needs manual investigation.

!!! warning "A host that fails every week fails silently"
    Nothing alerts you when one host in a group has been unreachable for a month. The rest of the run succeeds, the recap scrolls past in a log nobody reads, and that host quietly stops getting patched.

    A host out of disk is the classic case: it fails with `Failed to create temporary directory ... No space left on device`, which looks like a permissions problem and gets ignored.

    Make the check part of the routine:

    ```bash
    grep -c "UNREACHABLE" /var/log/ansible-patching.log
    ```

---

## Troubleshooting Common Issues

| Symptom | Likely Cause | Fix |
|---|---|---|
| `UNREACHABLE! Failed to create temporary directory` | `/home/ansible` exists but is owned by root, so the `ansible` user can't write to it | `chown -R ansible:ansible /home/ansible && chmod 700 /home/ansible` on the target. Recreating the user won't help — the directory already exists |
| Same error, but ending in `No space left on device` | Target host disk is full | Free space on that host. This is a host problem, not an Ansible problem |
| `Permission denied (publickey)` and the error shows `root@<ip>` | The group's `:vars` block is missing or empty, so Ansible fell back to connecting as root | Add a `[groupname:vars]` block with `ansible_user=ansible`. Verify with `ansible-inventory -i hosts.ini --host <name>` |
| `Permission denied (publickey)` showing the correct user | Key not installed, wrong permissions, or `AllowUsers` excludes `ansible` | Re-check Step 4, including the `sshd_config.d/` override files |
| Prompted for password despite key setup | Public key not copied, or `authorized_keys` permissions wrong | Re-run `ssh-copy-id`, or verify `chmod 600` on `authorized_keys` and `chmod 700` on `.ssh` |
| `sudo: a password is required` | Sudoers entry missing or malformed | Recheck `/etc/sudoers.d/ansible` on the target; run `visudo -c` to validate |
| Host key verification failure after an IP change | Cached fingerprint belongs to the previous machine | See [Handling a Changed Host Key](#handling-a-changed-host-key) |
| `ansible-inventory --host` shows only `ansible_host` | Group vars aren't reaching that host | The `:vars` header may be present but empty — check that the variable lines below it aren't actually under a *different* group's header |
| Playbook works manually but not via cron | Environment variables or PATH differ under cron | Use full paths to binaries (`/usr/bin/ansible-playbook`) and set variables explicitly in the crontab line |
| Proxmox host fails at the first task | Enterprise repo enabled without a subscription, returning 401 on `apt update` | Add `Enabled: false` to the enterprise stanza in `/etc/apt/sources.list.d/pve-enterprise.sources` |
| One server always shows `changed=1` even with nothing to update | Timestamps or metadata changing on every apt cache refresh | Usually harmless — confirm with `--check` mode that no packages are actually different |

---

## Next Steps

Once basic patch automation is stable, consider building on it:

- **`host_vars` / `group_vars`** — override settings per host (e.g. disable the Docker prune on one specific machine) instead of adding conditions to the playbook
- **Ansible Vault** — encrypt any secrets (API tokens, credentials) referenced in playbooks, rather than storing them in plaintext
- **Roles** — once playbooks grow beyond simple patching, break them into reusable roles for better organization
- **Alerting on failures** — a task that posts the PLAY RECAP to a notification channel closes the "silently failing host" gap that log review alone doesn't
- **A UI/scheduler** — tools like AWX (the open-source upstream of Red Hat Ansible Tower) add a web dashboard, scheduling, and role-based access on top of plain Ansible

---

## Quick Reference

```bash
# Test connectivity, per group
ansible linux_servers -i hosts.ini -m ping
ansible proxmox -i hosts.ini -m ping
ansible vps -i hosts.ini -m ping

# See the variables Ansible actually resolved for a host
ansible-inventory -i hosts.ini --host web01

# List which hosts a group contains
ansible linux_servers -i hosts.ini --list-hosts

# Validate playbook syntax
ansible-playbook -i hosts.ini update_lab.yml --syntax-check

# Dry run — see what would change
ansible-playbook -i hosts.ini update_lab.yml --check

# Run against one host only
ansible-playbook -i hosts.ini update_lab.yml --limit web01

# Full application run
ansible-playbook -i hosts.ini update_lab.yml

# Infrastructure run (Proxmox + VPS, no auto-reboot)
ansible-playbook -i hosts.ini update_infra.yml

# Run an ad-hoc command on all hosts
ansible linux_servers -i hosts.ini -a "uptime"

# Check Docker presence across the fleet
ansible linux_servers -i hosts.ini -m shell -a "command -v docker || echo NO-DOCKER" --one-line

# Clear a stale host key after an IP reassignment
ssh-keygen -f /root/.ssh/known_hosts -R <ip>
ssh-keyscan -H -t ed25519 <ip> >> /root/.ssh/known_hosts

# View recent log output
tail -100 /var/log/ansible-patching.log
tail -100 /var/log/ansible-infra.log
```

---
