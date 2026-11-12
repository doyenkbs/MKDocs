# Ansible Config Backup Playbook

## Overview

Patches keep systems current, but they do not protect against other failures: a bad manual edit, a failed upgrade that damages a config file, or a container that you must build again. This playbook copies important configuration files from each managed host and stores them in one place. Thus, you can restore a broken service. You do not have to build it again from memory.

Full disk and VM backups are a different task (the Proxmox layer does them). This playbook is only for **application and system configuration**. These are the small files that are easy to lose and slow to make again by hand: SSO provider settings, mail server configs, database connection strings, and environment files.

**What it does:**

- Connects to every host in the inventory
- Archives a defined list of config paths per host
- Pulls the archive back to a central backup location on the control node
- Timestamps each backup and prunes old ones beyond a retention window

---

## Why Config Backups Matter More Than They Seem To

A full VM/LXC snapshot answers the question "how do I restore this full container?" A config backup answers a smaller but more common question: "what did I change in this file three weeks ago, and can I get it back without a restore of the full container?" It also helps when snapshots do not. For example, you want the *current* Authentik SSO provider settings, but you do not want to roll back the full container and lose other changes.

Good candidates for this playbook in a typical self-hosted lab:

| Service type | Example paths |
|---|---|
| Identity/SSO | Authentik `.env`, blueprint exports |
| Mail | Mailcow's `mailcow.conf`, `data/conf/` |
| Reverse proxy | Nginx Proxy Manager's `data/` and `letsencrypt/` volumes |
| Databases | `/etc/mysql/`, `/etc/postgresql/` |
| DNS | Technitium DNS config export |
| General system | `/etc/network/`, `/etc/ssh/sshd_config`, crontabs, `/etc/fstab` |

---

## Inventory Considerations

Config backup targets vary a lot more per-host than patch targets do — every host has different config paths worth saving. Use `host_vars` to define what each host needs backed up, rather than one global list.

```ini title="hosts.ini"
[linux_servers]
authentik-host ansible_host=192.168.1.20
mailcow-host   ansible_host=192.168.1.21
proxy-host     ansible_host=192.168.1.22
```

```yaml title="host_vars/authentik-host.yml"
backup_paths:
  - /opt/authentik/.env
  - /opt/authentik/media
  - /opt/authentik/certs
```

```yaml title="host_vars/mailcow-host.yml"
backup_paths:
  - /opt/mailcow-dockerized/mailcow.conf
  - /opt/mailcow-dockerized/data/conf
```

If a host has no `backup_paths` defined, the playbook should skip it gracefully rather than fail — handled below with a `when` guard.

---

## The Playbook

```yaml title="backup_configs.yml"
---
- name: Backup Critical Configuration Files
  hosts: linux_servers
  become: yes
  vars:
    backup_root_local: /root/ansible-backups
    backup_date: "{{ ansible_date_time.iso8601_basic_short }}"
  tasks:

    - name: Skip hosts with no backup_paths defined
      meta: end_host
      when: backup_paths is not defined or backup_paths | length == 0

    - name: Create remote staging directory
      file:
        path: /tmp/config_backup_{{ backup_date }}
        state: directory
        mode: "0700"

    - name: Copy each config path into the staging directory
      synchronize:
        src: "{{ item }}"
        dest: "/tmp/config_backup_{{ backup_date }}/"
        mode: pull
        rsync_opts:
          - "--relative"
      loop: "{{ backup_paths }}"
      delegate_to: "{{ inventory_hostname }}"
      ignore_errors: yes   # don't fail the whole run if one path is missing

    - name: Archive the staged files
      archive:
        path: /tmp/config_backup_{{ backup_date }}
        dest: /tmp/{{ inventory_hostname }}_{{ backup_date }}.tar.gz
        format: gz

    - name: Pull the archive back to the control node
      fetch:
        src: /tmp/{{ inventory_hostname }}_{{ backup_date }}.tar.gz
        dest: "{{ backup_root_local }}/{{ inventory_hostname }}/"
        flat: yes

    - name: Clean up remote staging files
      file:
        path: "{{ item }}"
        state: absent
      loop:
        - /tmp/config_backup_{{ backup_date }}
        - /tmp/{{ inventory_hostname }}_{{ backup_date }}.tar.gz

    - name: Report backup status
      debug:
        msg: "Backup complete for {{ inventory_hostname }} → {{ backup_root_local }}/{{ inventory_hostname }}/"
```

**What each part is doing:**

- **`meta: end_host`** — cleanly skips any host without `backup_paths` defined, instead of erroring out or backing up nothing meaningfully.
- **`synchronize` (rsync)**: copies each defined path into a staging directory on the *remote* host first. It keeps relative paths with `--relative`, so the archive has the same directory structure as the original.
- **`archive`** — compresses everything into a single dated `.tar.gz` per host.
- **`fetch`** — pulls that archive back to the control node, organized into a per-host folder.
- **Cleanup task** — removes the temporary staging files and archive from the remote host so backups don't pile up on the managed hosts themselves.

!!! note "Why stage and archive on the remote host instead of syncing straight back?"
    Pulling many small files individually over the network is slow and creates a lot of SSH overhead. Archiving on the remote side first means only one file transfers back per host — much faster, especially over a VPN link or across sites.

---

## Retention: Pruning Old Backups

Without cleanup, this grows forever. Add a retention task on the control node side (run separately, not per-host):

```yaml title="prune_backups.yml"
---
- name: Prune old configuration backups
  hosts: localhost
  connection: local
  vars:
    backup_root_local: /root/ansible-backups
    retention_days: 30
  tasks:
    - name: Find backup archives older than retention window
      find:
        paths: "{{ backup_root_local }}"
        recurse: yes
        age: "{{ retention_days }}d"
        patterns: "*.tar.gz"
      register: old_backups

    - name: Delete backups past retention
      file:
        path: "{{ item.path }}"
        state: absent
      loop: "{{ old_backups.files }}"
```

Adjust `retention_days` based on how far back you realistically need to roll back — 30 days is a reasonable default for a homelab.

---

## Scheduling

Run this on a separate, offset schedule from patching — daily is reasonable for config backups since they're lightweight, compared to weekly for full patch cycles:

```cron
# Daily config backup at 1:00 AM
0 1 * * * ANSIBLE_HOST_KEY_CHECKING=False /usr/bin/ansible-playbook -i /root/ansible-backups/hosts.ini /root/ansible-backups/backup_configs.yml >> /var/log/ansible-backup.log 2>&1

# Weekly prune, Sunday 2:00 AM (before the 3 AM patch run)
0 2 * * 0 /usr/bin/ansible-playbook -i /root/ansible-backups/hosts.ini /root/ansible-backups/prune_backups.yml >> /var/log/ansible-backup.log 2>&1
```

---

## Restoring From a Backup

Restoring is manual by design — automating a *restore* carries real risk of overwriting good data if run against the wrong host, so this playbook intentionally only handles the backup direction.

```bash
# Extract a specific host's backup
tar -xzvf /root/ansible-backups/authentik-host/authentik-host_20260801T090000.tar.gz -C /tmp/restore_test

# Review contents before copying anything back
ls -la /tmp/restore_test

# Copy the specific file(s) needed back to the target host
scp /tmp/restore_test/opt/authentik/.env ansible@192.168.1.20:/opt/authentik/.env
```

Always restore into a temporary location first and review before overwriting a live config.

---

## Next Steps

- Consider syncing the `backup_root_local` directory itself off the control node (e.g. to Nextcloud, a separate VPS, or Cloudflare R2) — a local-only backup doesn't protect against the control node itself failing.
- Encrypt sensitive config backups (e.g. anything containing secrets or API tokens) using Ansible Vault or simple `gpg` encryption before long-term storage.
- Use this with the [Ansible Patch Automation](ansible-patch.md) playbook. Run backups *before* patches in the same maintenance window. Then a bad patch always has a config snapshot from the same day.

---

## Quick Reference

```bash
# Run a backup manually
ansible-playbook -i hosts.ini backup_configs.yml

# Run for a single host only
ansible-playbook -i hosts.ini backup_configs.yml --limit authentik-host

# Prune old backups manually
ansible-playbook -i hosts.ini prune_backups.yml

# List what's currently backed up for a host
ls -la /root/ansible-backups/authentik-host/
```