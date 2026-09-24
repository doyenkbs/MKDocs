---
tags:
  - Red Hat
  - RHEL
  - Proxmox
  - Patch Management
  - Vulnerability Remediation
  - Cockpit
  - Subscription Manager
---

# Running Red Hat Enterprise Linux in a Proxmox Home Lab

## Overview

Most home labs run Ubuntu, Debian, or a RHEL rebuild like Rocky or AlmaLinux. Those are fine, but if you work in an environment that runs Red Hat Enterprise Linux, practicing on the real thing is worth the extra setup. You get `subscription-manager`, Red Hat errata, and the same kernel patching workflow that shows up in vulnerability remediation tickets.

This guide covers getting RHEL at no cost, building the VM on Proxmox VE, installing and registering it, the post-installation setup, and the problems worth knowing about before you hit them.

**What you'll end up with:**

- A registered RHEL 9 virtual machine pulling updates from Red Hat's CDN
- A non-root administrative account with sudo and key-based SSH
- Cockpit, a browser-based admin interface, running on the host
- A working kernel patching and verification workflow
- A fallback local repository built from the installation media

**Estimated time:** 45 to 60 minutes, most of it waiting on the ISO download.

!!! note "Placeholders"
    All hostnames, IP addresses, interface names, and account names on this page are examples. Substitute your own. The interface name in particular (`enp6s18` here) depends on your hardware and will differ.

---

## Jump To

| I need to... | Section |
|---|---|
| Get RHEL without paying | [Getting RHEL at no cost](#getting-rhel-at-no-cost) |
| Pick between the DVD and Boot ISO | [Choosing your ISO](#choosing-your-iso) |
| Build the VM with the right settings | [Creating the VM in Proxmox](#creating-the-vm-in-proxmox) |
| Work through the installer | [Installing RHEL](#installing-rhel) |
| Create a user and grant sudo | [Creating users and granting sudo](#creating-users-and-granting-sudo) |
| Understand where repos are defined | [Where repository definitions live](#where-repository-definitions-live) |
| Turn a repository on or off | [Enabling and disabling repositories](#enabling-and-disabling-repositories) |
| Pin the system to a minor release | [Locking to a specific minor release](#locking-to-a-specific-minor-release) |
| Set up the web interface | [Cockpit](#cockpit) |
| Practice the patching workflow | [Practicing the patching workflow](#practicing-the-patching-workflow) |
| Look up a command | [Useful commands](#useful-commands) |
| Fix something that went wrong | [Troubleshooting](#troubleshooting) |

---

## Getting RHEL at no cost

Red Hat offers the **Developer Subscription for Individuals**. It is free, self-supported, and covers up to 16 systems, physical or virtual. Red Hat describes it as intended for personal servers, home labs, and small projects.

Self-supported means you get the Customer Portal, the knowledge base, and documentation, but no technical support entitlement. That distinction matters if you ever need help, and the [troubleshooting section](#troubleshooting) below covers where to go instead.

### Create the account

1. Go to `https://developers.redhat.com/register`.
2. Fill in the registration form and create a Red Hat login.
3. On the profile completion screen, check **I have read and agree to the Red Hat Developer Subscription for Individuals**. This checkbox is what attaches the subscription.
4. The "Notify me about products, services, and events" checkbox is optional marketing. Uncheck it if you prefer.
5. Click **Submit**.

### Verify the subscription attached

Before downloading anything, confirm the subscription actually exists on the account:

1. Go to `https://access.redhat.com/management/subscriptions`.
2. You should see **Red Hat Developer Subscription for Individuals**, SKU RH00798, with an Active status and a one year term.

If it is not listed, go back to `https://developers.redhat.com/products/rhel/download` while logged in and complete whatever the page asks for.

!!! warning "Check this before you install, not after"
    Registration during installation can succeed while the subscription grants nothing, which leaves you with a registered system and no repositories. Confirming the subscription on the portal first rules out the most frustrating failure on this page.

---

## Choosing your ISO

The download page offers two ISO formats per release.

| ISO | Size | Contains packages | Needs network during install |
|---|---|---|---|
| Binary DVD | ~10 GB | Yes, all of them | No |
| Boot ISO | ~1 GB | No | Yes |

**Use the DVD.** The Boot ISO downloads every package from Red Hat's CDN during installation, which means the install depends on working DNS, working TLS, and a working entitlement before you have a shell to troubleshoot with. The DVD carries everything locally and installs offline.

### Download

1. Go to `https://developers.redhat.com/products/rhel/download`.
2. Under **Release-specific downloads**, expand the RHEL version you want.
3. Download **Binary DVD** for **x86_64**.

!!! tip "Which version?"
    Pick RHEL 9.x rather than 10.x unless you have a specific reason. Most enterprise environments run 8 and 9 today, so 9.x is closer to what you will actually support.

---

## Creating the VM in Proxmox

### Upload the ISO

In the Proxmox web interface:

1. Click **Datacenter** in the left sidebar.
2. Expand your node (for example **pve**).
3. Click the storage that holds ISOs (usually **local**).
4. Click **ISO Images** in the middle panel.
5. Click **Upload**, select the downloaded ISO, and click **Upload**.

Large ISOs take a while. If the browser upload times out, use **Download from URL** instead, or copy the file to `/var/lib/vz/template/iso/` on the Proxmox host over SSH.

### Create the VM

Click **Create VM** in the top right of the Proxmox interface and work through the tabs.

**General**

| Field | Value |
|---|---|
| Node | your node |
| VM ID | leave the default |
| Name | `rhel9-lab` |

**OS**

| Field | Value |
|---|---|
| ISO image | the RHEL ISO you uploaded |
| Type | Linux |
| Version | 6.x - 2.6 Kernel |

**System**

| Field | Value |
|---|---|
| Graphic card | Default |
| Machine | q35 |
| BIOS | OVMF (UEFI) |
| Add EFI Disk | checked, on your storage |
| SCSI Controller | VirtIO SCSI single |
| Qemu Agent | checked |

**Disks**

| Field | Value |
|---|---|
| Bus/Device | SCSI, 0 |
| Disk size | 32 GB |
| Discard | checked |
| SSD emulation | checked if backed by SSD |

**CPU**

| Field | Value |
|---|---|
| Sockets | 1 |
| Cores | 2 |
| Type | **host** |

!!! danger "The CPU type is the one people get wrong"
    Proxmox defaults to `kvm64`, which does not present the x86-64-v2 instruction set. RHEL 9 requires x86-64-v2 and RHEL 10 requires x86-64-v3, so a VM left on the default will not boot.

    Setting **Type** to `host` passes your physical CPU features through and avoids the problem. The tradeoff is that live migration to a host with a different CPU will not work, which does not matter in a single node lab.

**Memory**

| Field | Value |
|---|---|
| Memory | 4096 MB |

RHEL 9 needs 1.5 GiB minimum for a local media install. 4 GB gives you room to actually use the system.

**Network**

| Field | Value |
|---|---|
| Bridge | vmbr0 |
| Model | VirtIO (paravirtualized) |

Click **Finish**, then start the VM and open **Console**.

---

## Installing RHEL

The installer is called **Anaconda**. It is Red Hat's OS installer, used across RHEL, Fedora, CentOS, Rocky, and AlmaLinux. It is unrelated to the Anaconda Python distribution that shares the name.

At the boot menu, select **Install Red Hat Enterprise Linux**.

You land on the **Installation Summary** screen. Items with a warning triangle must be completed before the **Begin Installation** button becomes active.

### Localization

Set **Keyboard**, **Language Support**, and **Time & Date** to match your location. Nothing unusual here.

### Connect to Red Hat

This registers the system with your developer subscription so it can pull updates after installation.

1. Click **Connect to Red Hat**.
2. Leave **Authentication** on **Account**.
3. Enter your Red Hat username and password.
4. Uncheck **Connect to Red Hat Insights** unless you want it.
5. Leave **Set System Purpose** unchecked.
6. Click **Register**, wait for the status to change to registered, then click **Done**.

!!! note "About Insights"
    Insights uploads system inventory and configuration data to Red Hat and installs an agent that reports on a schedule. It is genuinely useful, and it is included with the developer subscription, but it is extra noise on a first lab build. You can turn it on later with `insights-client --register`.

### Installation Source

!!! warning "Check this immediately after registering"
    Registering can switch the installation source from your local DVD to the Red Hat CDN, which silently turns an offline install into a network install. If the summary screen shows **Installation Source: Red Hat CDN** when you meant to use the DVD, fix it here.

1. Click **Installation Source**.
2. Select **Auto-detected installation media**. It should show your DVD.
3. Click **Done**.

Registration stays in place regardless of which source you pick. You keep the subscription for post-install updates while the packages come off the DVD.

### Software Selection

1. Click **Software Selection**.
2. Under **Base Environment**, select **Server**.
3. Under **Additional software**, check **Guest Agents** and **Performance Tools**.
4. Click **Done**.

Choose **Server**, not **Server with GUI**. The GUI costs several GB and a lot of install time for a desktop you will never open, and real RHEL servers rarely run one.

**Guest Agents** installs `qemu-guest-agent`, which lets Proxmox report the VM's IP address and shut it down cleanly. **Performance Tools** adds `sar`, `iotop`, and similar diagnostics. Everything else on that list can be added later with `dnf install`.

### Installation Destination

1. Click **Installation Destination**.
2. Select your virtual disk.
3. Leave **Storage Configuration** on **Automatic**.
4. Click **Done**.

### Root Password

1. Click **Root Password**.
2. Set a strong password.
3. Leave **Allow root SSH login with password** unchecked.
4. Click **Done**.

### User Creation

!!! danger "Do not skip this screen"
    If you leave it at "No user will be created", root becomes your only account. RHEL 9 disables root SSH login by default, which leaves you working from the Proxmox console until you create a user by hand.

1. Click **User Creation**.
2. Enter a full name and username, for example `labadmin`.
3. Check **Make this user administrator**. This adds the account to the `wheel` group, which grants sudo.
4. Set a password.
5. Click **Done**.

Click **Begin Installation**, wait for it to finish, then **Reboot System**.

---

## Post-installation setup

Log in at the console with the user account you created.

### Creating users and granting sudo

If you skipped User Creation during the install, or you want a second account, create one now.

```bash
sudo useradd -m -c "Lab Administrator" labadmin
sudo passwd labadmin
```

What the options do:

| Option | Does |
|---|---|
| `-m` | Creates the home directory at `/home/labadmin` |
| `-c` | Sets the comment field, normally the person's full name |
| `-s /bin/bash` | Sets the login shell, optional since bash is the default |
| `-G <group>` | Adds the account to supplementary groups at creation |

**Granting sudo.**

```bash
sudo usermod -aG wheel labadmin
```

!!! warning "On RHEL the sudo group is `wheel`, not `sudo`"
    `sudo` is a Debian and Ubuntu convention. Running `usermod -aG sudo labadmin` on RHEL creates or references a group that grants nothing, and it fails silently, so the account looks configured but cannot elevate.

    The `-a` also matters. `usermod -G wheel labadmin` without `-a` **replaces** every supplementary group the account belongs to, which can strip the user out of groups they need.

Or create the account with sudo in one step:

```bash
sudo useradd -m -G wheel -c "Lab Administrator" labadmin
sudo passwd labadmin
```

**Verify it worked:**

```bash
id labadmin
groups labadmin
```

You should see `wheel` in the output. Group membership is only read at login, so the user has to log out and back in before sudo works.

Then, logged in as that user:

```bash
sudo -l
```

That lists what the account is permitted to run.

**Other useful account commands:**

| Command | Does |
|---|---|
| `sudo passwd -l labadmin` | Lock the account password |
| `sudo passwd -u labadmin` | Unlock it |
| `sudo usermod -L labadmin` | Lock the account |
| `sudo chage -l labadmin` | Show password ageing and expiry |
| `sudo userdel -r labadmin` | Delete the account and its home directory |
| `getent passwd labadmin` | Look up the account entry |

**Key based SSH** is worth setting up straight away. From your own machine:

```bash
ssh-keygen -t ed25519
ssh-copy-id labadmin@192.168.1.50
```

To then disable password authentication on the server, edit `/etc/ssh/sshd_config`, set `PasswordAuthentication no`, and restart the service:

```bash
sudo systemctl restart sshd
```

!!! warning "Test the key first"
    Confirm key login works in a second terminal before disabling password authentication, or you will lock yourself out of SSH and have to recover through the Proxmox console.

### Set the hostname

```bash
sudo hostnamectl set-hostname rhel9.example.com
```

### Find the IP address

```bash
ip -4 addr show
```

From here on you can work over SSH instead of the Proxmox console:

```bash
ssh labadmin@192.168.1.50
```

### Enable the guest agent in Proxmox

You installed the agent during setup. Confirm it is running:

```bash
systemctl status qemu-guest-agent
```

Then enable it on the Proxmox side. In the Proxmox web interface: your VM, then **Options**, then **QEMU Guest Agent**, then **Edit**, then check **Enabled**. The VM's IP address will now appear on the **Summary** page.

### Verify the subscription

```bash
sudo subscription-manager status
sudo subscription-manager list --installed
sudo dnf repolist
```

You should see the system registered and two repositories listed:

```
rhel-9-for-x86_64-baseos-rpms
rhel-9-for-x86_64-appstream-rpms
```

If `dnf repolist` returns "No repositories available", jump to [Registration succeeds but no repositories appear](#troubleshooting).

---

## Managing repositories

### Where repository definitions live

Subscription based repositories are not written by hand. They live in:

```
/etc/yum.repos.d/redhat.repo
```

That file is generated automatically by `subscription-manager` from your entitlement certificate. Every repository that `subscription-manager repos --list` prints comes from there. The file carries a warning at the top saying changes will be overwritten, and they will be, on the next refresh.

To see the full list of repositories your subscription grants:

```bash
sudo subscription-manager repos --list
```

That output is long. To see only what is currently switched on:

```bash
sudo subscription-manager repos --list-enabled
```

Your own repositories, for third party software or a local mirror, go in separate files in the same directory, for example `/etc/yum.repos.d/local-dvd.repo`. Those are yours and are never overwritten.

### Enabling and disabling repositories

Two repositories are enabled by default on a fresh install: BaseOS and AppStream. Others, such as CodeReady Builder or the supplementary channels, are available but switched off.

Enable one:

```bash
sudo subscription-manager repos --enable=codeready-builder-for-rhel-9-x86_64-rpms
```

Enable several at once:

```bash
sudo subscription-manager repos \
  --enable=rhel-9-for-x86_64-baseos-rpms \
  --enable=rhel-9-for-x86_64-appstream-rpms
```

Disable one:

```bash
sudo subscription-manager repos --disable=codeready-builder-for-rhel-9-x86_64-rpms
```

Disable everything, then enable only what you want, which is a common approach when building a controlled baseline:

```bash
sudo subscription-manager repos --disable="*"
sudo subscription-manager repos --enable=rhel-9-for-x86_64-baseos-rpms
```

Confirm the result:

```bash
sudo dnf repolist
```

For repositories that are not subscription based, use `dnf config-manager` instead:

```bash
sudo dnf config-manager --set-enabled epel
sudo dnf config-manager --set-disabled local-baseos
```

!!! note "Two tools, two jobs"
    `subscription-manager repos` manages what gets written into `redhat.repo`. `dnf config-manager` edits the `enabled=` line in any repo file.

    Using `dnf config-manager` on a Red Hat repository works, but the change can be reverted the next time `subscription-manager` regenerates the file. Use `subscription-manager` for Red Hat repos and `dnf config-manager` for everything else.

### Locking to a specific minor release

By default a RHEL system tracks the latest minor release in its major version. Run `dnf update` on a 9.6 system after 9.8 is out and it becomes 9.8.

You can pin it. This is called a release lock:

```bash
sudo subscription-manager release --set=9.6
sudo dnf clean all
sudo dnf update
```

The system now pulls only 9.6 content and stays there. You still receive security errata published for 9.6 while it remains supported, but you do not move to 9.7 or 9.8.

Check the current setting:

```bash
sudo subscription-manager release --show
```

List what you can pin to:

```bash
sudo subscription-manager release --list
```

Remove the lock and resume tracking the latest:

```bash
sudo subscription-manager release --unset
sudo dnf clean all
```

**When this is used:**

| Reason | Detail |
|---|---|
| Application certification | Vendor software certified against 9.6 and not yet validated on 9.8. Pinning keeps the platform where the vendor supports it |
| Change control | A minor release upgrade brings new package versions and behaviour changes across the whole system. Pinning lets monthly patching apply security fixes without the platform moving underneath it |
| Fleet consistency | Servers built months apart end up on different minor versions unless the release is pinned. Pinning means a host built today matches one built in March |
| Extended Update Support | EUS channels provide extended maintenance for specific minor releases and require a release lock to use |

!!! warning "A release lock is a schedule, not an escape"
    A pinned release eventually falls out of support and stops receiving fixes. Pinning controls *when* you upgrade, it does not avoid upgrading. Track the end of support date for whatever minor release you pin to.

!!! danger "Document every release lock"
    A lock nobody knows about breaks vulnerability scanning in a way that wastes hours. A scanner flags a package as outdated when the fix only exists in a later minor release the system is deliberately not tracking, the remediation ticket goes to whoever owns the host, and the fix genuinely cannot be applied. If you pin something, write it down where the people reading scan results will find it.

Note that a release lock does **not** stop kernel updates. You still receive kernel errata published for the pinned release, so the patching workflow below works the same way.

### First update

```bash
uname -r
sudo dnf update -y
sudo reboot
```

After it comes back:

```bash
uname -r
rpm -q kernel
```

More on why those two commands matter in [Practicing the patching workflow](#practicing-the-patching-workflow).

---

## Cockpit

Cockpit is a web based administration interface. It gives you system stats, service management, log browsing, storage, networking, user accounts, software updates, SELinux status, and a terminal, all in a browser. You log in with your Linux credentials.

It ships with RHEL and just needs enabling:

```bash
sudo systemctl enable --now cockpit.socket
```

Browse to `https://192.168.1.50:9090`.

The `cockpit` service is permitted in the default firewalld zone on RHEL 9, so no firewall change is normally needed. If the page does not load, confirm it:

```bash
sudo firewall-cmd --list-services
```

If `cockpit` is not in the output, add it:

```bash
sudo firewall-cmd --permanent --add-service=cockpit
sudo firewall-cmd --reload
```

Cockpit uses a self-signed certificate by default, so your browser will warn you. That is expected on a lab system.

Once logged in, click **Administrative access** in the top right to elevate. Without it, most panels are read only.

### What the panels do

| Panel | Use |
|---|---|
| Overview | CPU, memory, disk, and a health summary |
| Logs | journald, filtered by priority and service |
| Storage | Disks, partitions, LVM, filesystems |
| Networking | Interfaces, bonds, bridges, firewall |
| Accounts | Create users, set passwords, manage SSH keys |
| Services | systemd units, start, stop, enable, view logs per unit |
| SELinux | Current mode and any denials, with suggested fixes |
| Software updates | Available updates and errata |
| Terminal | A shell in the browser |

!!! warning "Careful in the Networking panel"
    Changing an interface over a connection that runs through that interface can cut you off. Cockpit usually rolls a change back if it loses you, but not always. On a VM you can always recover through the Proxmox console, which is not true of a physical host.

### Cockpit on other distributions

Cockpit is not RHEL only. It packages for Fedora, Debian, Ubuntu, openSUSE, and Arch:

```bash
sudo apt install cockpit          # Debian, Ubuntu
sudo zypper install cockpit       # openSUSE
sudo pacman -S cockpit            # Arch
```

The enable step is the same everywhere:

```bash
sudo systemctl enable --now cockpit.socket
```

Module availability varies by distribution. The storage, SELinux, and subscription panels are most complete on RHEL family systems.

### Managing multiple hosts

Install `cockpit-machines` on whichever host you use as your entry point:

```bash
sudo dnf install -y cockpit-machines
```

Then click the host name in the top left corner of the Cockpit interface and select **Add new host**. It connects over SSH.

Set up key based authentication first, or you will be prompted for a password every time you switch hosts:

```bash
ssh-keygen -t ed25519
ssh-copy-id labadmin@192.168.1.51
```

!!! note "This is host switching, not a fleet view"
    You see one machine at a time and switch between them. There is no aggregated "all users across all hosts" view. For genuine central management, look at Ansible for configuration and a directory service for accounts.

---

## Practicing the patching workflow

This is the reason to run real RHEL rather than a rebuild. Vulnerability remediation tickets for Red Hat systems usually read "apply patch, upgrade kernel to remediate CVE-XXXX-XXXXX, using tools like yum". Here is that workflow end to end.

### Check what is currently running

```bash
uname -r
```

### See what security updates are available

```bash
sudo dnf updateinfo summary
sudo dnf updateinfo list security
```

### Check a specific CVE

```bash
sudo dnf updateinfo info --cve CVE-2026-12345
```

If it returns nothing, either the CVE does not affect your system or the fix is already installed.

### Apply and verify

```bash
sudo dnf update kernel
sudo reboot
```

After the reboot:

```bash
uname -r
rpm -q kernel
```

### Why both commands matter

`rpm -q kernel` lists every kernel package installed. `uname -r` shows the kernel currently running. They disagree between the update and the reboot:

```console
$ uname -r
5.14.0-687.5.3.el9_8.x86_64

$ rpm -q kernel
kernel-5.14.0-687.5.3.el9_8.x86_64
kernel-5.14.0-687.50.1.el9_8.x86_64
```

The new kernel is installed but not running.

!!! danger "This is why kernel remediation tickets do not close"
    Vulnerability scanners check the **running** kernel. A host where the package was installed but the reboot never happened still reports the finding, and the ticket stays open while everyone involved believes it was patched.

    When a Linux team reports a kernel CVE remediated, `uname -r` is what proves it.

RHEL keeps previous kernels by default so you can boot back into one if an update breaks something. The count is controlled by `installonly_limit` in `/etc/dnf/dnf.conf`.

---

## Useful commands

**Subscription**

| Command | Does |
|---|---|
| `subscription-manager status` | Registration state and content access mode |
| `subscription-manager list --installed` | Products the system reports to Red Hat |
| `subscription-manager refresh` | Re-pull entitlement data |
| `subscription-manager repos --list` | Every repository the subscription grants |
| `subscription-manager repos --list-enabled` | Only what is switched on |
| `subscription-manager release --show` | Current release lock, if any |
| `rct cat-cert /etc/pki/entitlement/<serial>.pem` | Decode an entitlement certificate |

**Packages**

| Command | Does |
|---|---|
| `dnf repolist` | Enabled repositories |
| `dnf search nginx` | Find a package by name or description |
| `dnf provides */htpasswd` | Which package would provide a file you do not have yet |
| `dnf info httpd` | Version, size, repository, and description |
| `dnf list installed \| grep kernel` | Filter installed packages |
| `dnf history` | Transaction history with IDs |
| `dnf history info 12` | What one transaction changed |
| `dnf history undo 12` | Roll back a transaction |
| `dnf history undo last` | Roll back the most recent transaction |
| `dnf updateinfo list security` | Pending security errata |
| `dnf updateinfo info --cve CVE-2026-12345` | Whether a specific CVE has a pending fix |
| `dnf remove --oldinstallonly kernel` | Remove old kernels past the keep limit |
| `rpm -qf /usr/sbin/sshd` | Which package owns a file already on disk |
| `rpm -ql chrony` | Every file a package installed |
| `rpm -qi httpd` | Package metadata for something installed |

**Services and logs**

| Command | Does |
|---|---|
| `systemctl status sshd` | Unit state and recent log lines |
| `systemctl restart sshd` | Restart a service |
| `systemctl enable --now chronyd` | Start now and at every boot |
| `systemctl disable --now cockpit.socket` | Stop now and at boot |
| `systemctl list-units --failed` | Everything currently failing |
| `systemctl list-timers` | Scheduled systemd timers |
| `systemctl cat sshd` | Show the unit file |
| `systemd-analyze blame \| head -10` | What is slowing down boot |
| `journalctl -u sshd -n 50 --no-pager` | Last 50 lines for a unit, unpaged |
| `journalctl -u httpd -f` | Follow one service while reproducing a problem |
| `journalctl -p err -b` | Errors since last boot |
| `journalctl -f` | Follow the whole log live |
| `journalctl --since "1 hour ago"` | Time bounded search |

**Networking**

| Command | Does |
|---|---|
| `nmcli device status` | Interface states |
| `nmcli connection show` | Configured connection profiles |
| `nmcli connection show enp6s18` | Full settings for one profile |
| `nmcli connection up enp6s18` | Bring a connection up |
| `firewall-cmd --list-all` | Active zone and its rules |
| `firewall-cmd --list-services` | Services permitted in the active zone |
| `firewall-cmd --get-active-zones` | Which zone each interface is in |
| `firewall-cmd --get-services` | Every service definition available to add |
| `ss -tlnp` | Listening TCP ports and their processes |
| `ss -tlnp \| grep 9090` | What is listening on a specific port |
| `ip route` | Routing table |

**SELinux**

| Command | Does |
|---|---|
| `getenforce` | Current mode |
| `sestatus` | Full status |
| `ausearch -m avc -ts recent` | Recent denials |
| `restorecon -Rv /path` | Reset contexts to policy defaults |

**Storage**

| Command | Does |
|---|---|
| `lsblk` | Block devices and mount points |
| `df -h` | Filesystem usage |
| `pvs`, `vgs`, `lvs` | LVM physical volumes, volume groups, logical volumes |

---

## Common configuration tasks

### Setting a static IP address

```bash
sudo nmcli connection modify enp6s18 \
  ipv4.method manual \
  ipv4.addresses 192.168.1.50/24 \
  ipv4.gateway 192.168.1.1 \
  ipv4.dns "192.168.1.10 1.1.1.1"
sudo nmcli connection up enp6s18
```

Switch back to DHCP:

```bash
sudo nmcli connection modify enp6s18 ipv4.method auto
sudo nmcli connection up enp6s18
```

Substitute your interface name from `nmcli device status`.

### Opening a firewall port

By named service, which is preferred when one exists:

```bash
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

By raw port number:

```bash
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

To test a rule without committing to it, leave off `--permanent`. The rule applies immediately and disappears on the next `--reload` or reboot:

```bash
sudo firewall-cmd --add-port=9000/tcp
```

List what is available to add:

```bash
sudo firewall-cmd --get-services
```

### Rolling back a bad update

```bash
sudo dnf history
sudo dnf history info 12
sudo dnf history undo 12
```

`dnf history` lists every transaction with an ID. `info` shows exactly which packages a transaction changed, so you can confirm you are reversing the right one.

### Diagnosing a failed service

```bash
systemctl list-units --failed
journalctl -u <unit-name> -n 50 --no-pager
systemctl cat <unit-name>
```

Start with the failed list, read the unit's recent log lines, then look at the unit file if the log does not explain it.

---

## Troubleshooting

| Symptom | Likely cause | Jump to |
|---|---|---|
| Software Selection greyed out, "Error downloading package metadata" | Anaconda cannot read repository metadata from the selected source | [Details](#ts-metadata) |
| Metadata fails and the log points at the CD-ROM | Anaconda chose the attached Boot ISO, which has no `repodata` | [Details](#ts-cdrom) |
| Ctrl+Alt+F2 does nothing in the Proxmox console | The browser or local OS intercepts the combination | [Details](#ts-ctrlalt) |
| `curl` reports a self-signed certificate for cdn.redhat.com | Expected. Red Hat signs the CDN with its own internal CA | [Details](#ts-selfsigned) |
| Registered, but `dnf repolist` returns nothing | Entitlement certificate issued with no content sets | [Details](#ts-norepos) |
| Need working `dnf` while an entitlement is broken | Build a local repository from the installation media | [Details](#ts-localrepo) |
| Interface stuck at "connecting (getting IP configuration)" | DHCP is not being answered, or the profile was changed | [Details](#ts-dhcp) |
| VM will not boot at all | Proxmox CPU type does not meet the x86-64-v2 requirement | [Details](#ts-cpu) |

### Software Selection is greyed out during installation { #ts-metadata }

??? warning "Error downloading package metadata"

    **Symptom.** The Software Selection item on the Installation Summary screen is greyed out, sometimes with "Error downloading package metadata" beneath it.

    **Cause.** Anaconda cannot read the repository metadata from whatever installation source it is currently using.

    **Fix.** First, wait. If the source is the Red Hat CDN, Anaconda is downloading metadata over the network and that can take several minutes on a slow connection.

    If it does not clear, force a retry by clicking **Installation Source**, then **Done**, without changing anything.

    If you are installing from the DVD, confirm the source is right. The summary screen should read **Installation Source: Local media**. If it says **Red Hat CDN**, click through and select **Auto-detected installation media** instead. Registering with Red Hat earlier in the installer can switch this without telling you.

### Anaconda tries to use the CD-ROM with a Boot ISO { #ts-cdrom }

??? warning "base repo (CDROM ...) not valid -- removing it"

    **Symptom.** Metadata download fails repeatedly. The installer log shows the base repository pointing at the CD-ROM.

    To read the log, switch to a shell with ++ctrl+alt+f2++ and run:

    ```bash
    tail -50 /tmp/packaging.log
    ```

    You will see something like:

    ```
    url='file:///run/install/sources/mount-0002-cdrom'
    base repo (CDROM file:///run/install/sources/mount-0002-cdrom) not valid -- removing it
    reason for repo removal: Failed to download metadata for repo 'anaconda'
    ```

    **Cause.** Anaconda auto-detected the attached ISO and chose it as the installation source. The Boot ISO contains no `repodata` directory, so that lookup can never succeed no matter how many times it retries.

    **Fix.** Click **Installation Source** and explicitly select **Red Hat CDN** rather than the auto-detected media.

    The simpler answer is to use the DVD ISO, where the same auto-detection is correct rather than wrong.

### Cannot press Ctrl+Alt+F2 in the Proxmox console { #ts-ctrlalt }

??? warning "Key combination never reaches the VM"

    **Symptom.** ++ctrl+alt+f2++ does nothing, because your local operating system or browser consumes the combination before it reaches the guest.

    **Fix, noVNC.** In the Proxmox console window:

    1. Click the small tab on the left edge of the console to slide out the control bar.
    2. Click the keyboard icon labelled **Show Extra Keys**.
    3. Click **Ctrl**, then **Alt**, so both stay pressed. They highlight when sticky.
    4. Press **F2** on your physical keyboard.

    Repeat with **F6** to return to the graphical installer.

    **Fix, SPICE.** SPICE passes key combinations through more reliably. In the Proxmox web interface: your VM, then **Hardware**, then **Display**, then **Edit**, then set **Graphic card** to **SPICE (qxl)**. Open the console with **Console**, then **SPICE**. You will need `virt-viewer` installed on your own machine.

### curl reports a self-signed certificate for the Red Hat CDN { #ts-selfsigned }

??? note "This one is not an error"

    **Symptom.**

    ```
    curl: (60) SSL certificate problem: self-signed certificate in certificate chain
    ```

    **Cause.** Expected behaviour, not a fault. Red Hat signs the CDN with their own internal certificate authority rather than a public one, so plain `curl` has nothing in its trust store to validate against.

    **Fix.** Nothing to fix. To verify the connection properly, point curl at Red Hat's CA:

    ```bash
    curl -I --cacert /etc/rhsm/ca/redhat-uep.pem https://cdn.redhat.com
    ```

    A `403 Forbidden` response is correct and means TLS worked. The CDN also requires a client certificate, which `curl` is not presenting.

    **Ruling out TLS inspection.** If you do suspect something on your network is intercepting traffic, check who signed the certificate:

    ```bash
    openssl s_client -connect cdn.redhat.com:443 -showcerts </dev/null 2>/dev/null | grep -i issuer
    ```

    A Red Hat issuer, such as `CN=Red Hat Entitlement Operations Authority`, means the connection is direct. Anything else, such as a security product's own CA, means TLS inspection is in the path and needs a bypass rule for `*.redhat.com`.

### Registration succeeds but no repositories appear { #ts-norepos }

??? danger "Registered, entitled, and still no content"

    **Symptom.** `subscription-manager status` reports Registered, but `dnf repolist` returns "No repositories available" and `/etc/yum.repos.d/redhat.repo` contains only its header comments.

    **Cause.** The entitlement certificate was issued with no content sets in it. Under Simple Content Access, `redhat.repo` is generated from that certificate, so an empty certificate produces an empty repo file.

    **Diagnosis.** Check whether the certificate contains any content:

    ```bash
    sudo rct cat-cert /etc/pki/entitlement/<serial>.pem | grep -c "Content:"
    ```

    Use the `.pem` file, not the `-key.pem` file. Passing a wildcard matches both and produces a Python traceback from the key file, which is noise rather than a second problem. A result of `0` confirms the certificate has no content sets.

    Then confirm the product certificate is present, since the entitlement is built from the products the system reports:

    ```bash
    ls -l /etc/pki/product/
    sudo subscription-manager list --installed
    ```

    RHEL 9 x86_64 is product ID 479, so `/etc/pki/product/479.pem` should exist. If it only exists in `/etc/pki/product-default/`, copy it across and re-register:

    ```bash
    sudo cp /etc/pki/product-default/479.pem /etc/pki/product/
    sudo subscription-manager unregister
    sudo subscription-manager clean
    sudo cp /etc/pki/product-default/479.pem /etc/pki/product/
    sudo subscription-manager register --username youraccount
    sudo dnf repolist
    ```

    The second copy is deliberate, since `clean` can remove it again.

    **If that does not work, it is not your system.** When the subscription shows Active on the account, the product certificate is present, `subscription-manager list --installed` correctly reports the OS, the system registers cleanly, and the certificate still has zero content sets, the subscription pool needs refreshing on Red Hat's side. Nothing local will fix it.

    Contact **Customer Service**, not technical support:

    ```
    https://access.redhat.com/support/contact/customerService/
    ```

    The developer subscription is self-supported, so the technical case form rejects you with "Missing entitlement" before you can submit anything. Customer Service handles account, subscription, and entitlement problems regardless of support level.

    Describe it as a subscription problem rather than a Linux problem, or it gets routed to the wrong queue. Include the SKU, that Simple Content Access is enabled, that the product certificate is present, and that the entitlement certificate contains no content sets. Set the issue type to **Entitlements** if the form offers it.

    In my case a Red Hat representative refreshed the subscription pool on their side, and both repositories appeared on the next unregister and re-register. Turnaround was under one business day.

### Working without repositories: mount the DVD as a local repo { #ts-localrepo }

??? tip "A working dnf while you wait"

    If you are waiting on an entitlement fix, or you just want package management before sorting the subscription out, the installation media gives you both immediately.

    Attach the ISO to the VM in Proxmox: your VM, then **Hardware**, then **CD/DVD Drive**, then **Edit**, then select the DVD ISO. Then:

    ```bash
    sudo mkdir -p /mnt/iso
    sudo mount /dev/sr0 /mnt/iso
    ls /mnt/iso
    ```

    You should see `BaseOS` and `AppStream` directories. Create the repository definition:

    ```bash
    sudo tee /etc/yum.repos.d/local-dvd.repo > /dev/null <<'EOF'
    [local-baseos]
    name=Local BaseOS
    baseurl=file:///mnt/iso/BaseOS
    enabled=1
    gpgcheck=1
    gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

    [local-appstream]
    name=Local AppStream
    baseurl=file:///mnt/iso/AppStream
    enabled=1
    gpgcheck=1
    gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
    EOF

    sudo dnf repolist
    ```

    Make the mount survive a reboot:

    ```bash
    echo '/dev/sr0  /mnt/iso  iso9660  ro,nofail  0 0' | sudo tee -a /etc/fstab
    sudo mount -a
    ```

    The `nofail` option is not optional. Without it, the system drops to emergency mode at boot if you ever detach the ISO in Proxmox.

    **What this gives you and what it does not.** Every package that shipped with the release, which covers package management, systemd, SELinux, LVM, networking, and users. Nothing newer than the release, so you cannot practice kernel updates from it.

    When the subscription repositories start working, disable the local ones so `dnf` prefers the CDN:

    ```bash
    sudo dnf config-manager --set-disabled local-baseos,local-appstream
    ```

### Interface stuck at "connecting (getting IP configuration)" { #ts-dhcp }

??? warning "No IP address, SSH and Cockpit unreachable"

    **Symptom.** `ip -4 addr show` shows only the loopback interface. SSH and Cockpit both time out.

    **Diagnosis.** From the Proxmox console:

    ```bash
    nmcli device status
    ip link show
    ```

    If the device shows `connecting (getting IP configuration)` while `ip link show` reports the interface as `UP`, the link is fine and DHCP is simply not being answered.

    **Fix.** Bounce the connection first:

    ```bash
    sudo nmcli connection down enp6s18
    sudo nmcli connection up enp6s18
    ```

    Check whether the profile was changed, which can happen after editing networking in Cockpit:

    ```bash
    nmcli connection show enp6s18 | grep -i ipv4
    ```

    If `ipv4.method` is not `auto`, set it back:

    ```bash
    sudo nmcli connection modify enp6s18 ipv4.method auto
    sudo nmcli connection up enp6s18
    ```

    If DHCP genuinely is not answering, set a static address to regain access:

    ```bash
    sudo nmcli connection modify enp6s18 \
      ipv4.method manual \
      ipv4.addresses 192.168.1.50/24 \
      ipv4.gateway 192.168.1.1 \
      ipv4.dns "192.168.1.10"
    sudo nmcli connection up enp6s18
    ```

    Substitute your interface name from `ip link show`.

    Also check upstream. If your DHCP server runs in the same lab, the problem may be there rather than on this VM. Confirm whether anything else on that subnet is still getting a lease.

### RHEL will not boot on Proxmox { #ts-cpu }

??? danger "Wrong CPU type"

    **Symptom.** The VM fails to boot the installer or the installed system, often with a CPU related error or an immediate reset.

    **Cause.** The Proxmox default CPU type, `kvm64`, does not present the x86-64-v2 instruction set that RHEL 9 requires. RHEL 10 requires x86-64-v3.

    **Fix.** Shut the VM down, then in the Proxmox web interface: your VM, then **Hardware**, then **Processors**, then **Edit**, then set **Type** to `host`.

---

## What about LXC?

You can run a RHEL compatible container on Proxmox, but not for this purpose.

!!! danger "You cannot patch a kernel inside a container"
    An LXC container shares the Proxmox host kernel. There is no kernel of its own to upgrade, so the entire patching workflow above is impossible in one. If kernel remediation is what you are practicing, it has to be a VM.

Proxmox also does not ship a RHEL template, since Red Hat does not distribute freely redistributable container images that way. Run `pveam available` and you will see AlmaLinux, Rocky, CentOS, and Fedora instead.

Containers are fine for practicing `dnf`, users and permissions, systemd services, and SELinux basics. Use an AlmaLinux or Rocky template for that:

```bash
pveam update
pveam available | grep -i alma
```

For anything involving kernels or patching, use a VM.

---

## Next Steps

With a working RHEL system, the obvious things to build on:

- **LVM** — add a second disk in Proxmox and build volume groups, logical volumes, and filesystems on it
- **SELinux** — deliberately break a service's file contexts, then diagnose the denial with `ausearch` and repair it with `restorecon`
- **systemd** — write your own unit files and timers rather than only managing the ones that shipped
- **Firewall zones** — move interfaces between zones with `firewall-cmd` and watch what changes
- **Ansible** — Red Hat's own automation tool, and the natural next step for managing more than one host. Learn the playbooks before reaching for a web interface on top of them
- **Red Hat Insights** — included with the developer subscription, and gives vulnerability and patch visibility across every registered system, which overlaps directly with remediation work

---

## Quick Reference

```bash
# Registration and entitlement
subscription-manager status
subscription-manager list --installed
subscription-manager repos --list-enabled
subscription-manager refresh

# Repositories
dnf repolist
subscription-manager repos --enable=<repo-id>
subscription-manager repos --disable=<repo-id>
dnf config-manager --set-disabled <repo-id>

# Release lock
subscription-manager release --show
subscription-manager release --set=9.6
subscription-manager release --unset

# Patching workflow
uname -r
dnf updateinfo list security
dnf updateinfo info --cve CVE-2026-12345
dnf update kernel
reboot
uname -r
rpm -q kernel

# Rollback
dnf history
dnf history info <id>
dnf history undo <id>

# Cockpit
systemctl enable --now cockpit.socket
firewall-cmd --list-services
```
