---
tags:
  - ITFlow
---

# ITFlow Installation (Official Script) with Email Ticketing

This page installs <span class="prod-app">ITFlow</span> on Debian 13 with the official install script, puts it behind Nginx Proxy Manager, and connects a mailbox on a self-hosted Stalwart mail server so that ITFlow:

- **sends** ticket notifications, invoices, and quotes over SMTP, and
- **reads** the mailbox over IMAP and turns incoming email into tickets and ticket replies.

ITFlow is an open source tool for small IT teams and MSPs: IT documentation, ticketing, assets, and invoicing.

All names and addresses on this page are examples. Replace them with your own:

| Example value | Replace with |
|---|---|
| `itflow.example.com` | The hostname for ITFlow |
| `192.168.1.60` | The IP address of the ITFlow VM |
| `192.168.1.10` | The IP address of Nginx Proxy Manager |
| `mail.example.com` | Your mail server hostname |
| `support@example.com` | The mailbox ITFlow uses for tickets |
| `America/New_York` | Your time zone |

> Reference: [ITFlow Docs: Installation (script)](https://docs.itflow.org/installation_script)

---

## How it fits together

```
  Browser
     |  https://itflow.example.com
     v
+-----------------------+   https (self-signed)   +--------------------------------+
| Nginx Proxy Manager   | ----------------------> | ITFlow VM (Debian 13)          |
| Let's Encrypt cert    |                         | Apache, PHP, MariaDB           |
+-----------------------+                         | cron: cron.php every minute    |
                                                  +--------------------------------+
                                                       |                  ^
                                         SMTP 465 (send)|                  | IMAP 993 (read)
                                                       v                  |
                                                  +--------------------------------+
                                                  | Stalwart (mail.example.com)    |
                                                  | mailbox: support@example.com   |
                                                  +--------------------------------+
```

---

## Why the official script and not Docker

ITFlow publishes a Docker image, but the project states that it was built by a community member, is not officially supported, and is not meant for production use. The install script is the method the ITFlow project recommends, and it targets Debian 13.

---

## Prerequisites

- A **fresh** Debian 13 VM. The script installs Apache, MariaDB, and PHP and replaces the default Apache site, so do not run it on a server that already hosts other things. 2 vCPU, 2 to 4 GB RAM, and 20 GB of disk is enough.
- Root access on the VM.
- A reverse proxy (this guide uses Nginx Proxy Manager).
- A mailbox for tickets (`support@example.com`) that can sign in over IMAP and SMTP with a password. If your mail server uses Authentik single sign-on, you need an **app password** for this mailbox (see [Step 6](#step-6-prepare-the-support-mailbox)).

---

## Step 1: Create the Debian 13 VM

1. Create a VM in Proxmox and install Debian 13 from the netinst ISO.
2. At **Software selection**, select only **SSH server** and **standard system utilities**. Clear any desktop environment.
3. Give the VM a fixed IP address (`192.168.1.60`), either statically or with a DHCP reservation.

Set the server's time zone and host name before running the script:

```bash
su -
timedatectl set-timezone America/New_York
hostnamectl set-hostname itflow
```

---

## Step 2: Run the install script

As root, download and run the script with options, so it does not ask questions:

```bash
apt update && apt install -y wget
wget https://github.com/itflow-org/itflow-install-script/raw/main/itflow_install.sh
bash itflow_install.sh -d itflow.example.com -t America/New_York -b master -s selfsigned -u
```

What the options mean:

| Option | Value | Meaning |
|---|---|---|
| `-d` | `itflow.example.com` | The hostname ITFlow is reached at. The script uses it for the Apache site and the web folder name. |
| `-t` | `America/New_York` | Time zone. |
| `-b` | `master` | Stable branch. `develop` is the development branch. |
| `-s` | `selfsigned` | SSL type (see the next table). |
| `-u` | | Unattended mode: no questions. |

Run `bash itflow_install.sh` without options to answer the same questions one by one instead.

### Choosing the SSL type

| SSL type | When to use it |
|---|---|
| `letsencrypt` (script default) | Only when the VM has a public IP and ports 80 and 443 reach it from the internet. The script runs certbot, which fails behind a reverse proxy. |
| `selfsigned` (used here) | Behind a reverse proxy. ITFlow stays HTTPS-only, and the reverse proxy holds the real certificate. |
| `none` | Plain HTTP only. The script also turns off ITFlow's HTTPS-only setting. Not recommended. |

### What the script does

- Installs Apache, MariaDB, PHP, certbot, git, and cron.
- Raises the PHP upload limit to 500 MB and the script time limit to 300 seconds.
- Creates the Apache site for `itflow.example.com` and disables the default site.
- Clones ITFlow into `/var/www/itflow.example.com`.
- Creates the `itflow` database and database user with a random password.
- Writes `/var/www/itflow.example.com/config.php`, which holds the database password.
- Writes the cron file `/etc/cron.d/itflow`.

The install log is at `/var/log/itflow_install.log`.

---

## Step 3: Check the scheduled tasks (cron)

ITFlow sends email, reads the mailbox, and runs nightly maintenance from scheduled tasks. Check the cron setup now; a wrong cron setup causes most email problems.

```bash
cat /etc/cron.d/itflow
crontab -l -u www-data
```

Expected output:

- `/etc/cron.d/itflow` contains **exactly one line**: `* * * * * www-data /usr/bin/php /var/www/itflow.example.com/cron/cron.php`
- The second command prints `no crontab for www-data`.

Running `cron.php` **every minute is correct**. In current ITFlow versions, `cron.php` is a dispatcher: each minute it checks which jobs are due (send mail, read the mailbox, nightly tasks, domain and certificate checks) and runs only those. It also locks each job so two runs never overlap.

> **Warning:** Do not add other ITFlow lines to cron, and do not add a crontab for `www-data`. Older guides list separate cron lines for `mail_queue.php` and `ticket_email_parser.php`, and older installs ran `cron.php` once a night. Mixing those with the dispatcher runs jobs twice. On older versions, an extra `cron.php` line firing every minute flooded the notifications table with millions of rows.

If `crontab -l -u www-data` shows ITFlow lines, remove that crontab:

```bash
crontab -r -u www-data
```

---

## Step 4: DNS and reverse proxy

### DNS

Create an A record for `itflow.example.com` that points at the reverse proxy (`192.168.1.10`). If you use split-horizon DNS, add it to the internal zone. See [Split-Horizon DNS](../services/split-horizon-dns-technitium-npm.md).

### Nginx Proxy Manager

1. Open the Nginx Proxy Manager admin page (`http://192.168.1.10:81`).
2. Go to **Hosts › Proxy Hosts** and click **Add Proxy Host**.
3. On the **Details** tab:

    | Field | Value |
    |---|---|
    | Domain Names | `itflow.example.com` |
    | Scheme | `https` |
    | Forward Hostname / IP | `192.168.1.60` |
    | Forward Port | `443` |
    | Block Common Exploits | On |

4. On the **SSL** tab, select **Request a new SSL Certificate**, turn on **Force SSL**, and accept the Let's Encrypt terms. If `itflow.example.com` is not reachable from the internet, turn on **Use a DNS Challenge** and pick your DNS provider.
5. Click **Save**.

The scheme is `https` and the port is `443` because the VM serves ITFlow with the self-signed certificate. Nginx Proxy Manager does not check the backend certificate, so the self-signed certificate causes no error.

---

## Step 5: First login

1. Open `https://itflow.example.com`.
2. Complete the first-run setup: company details and the first administrator account.
3. Turn on scheduled tasks: go to **Administration › Settings › Cron** and enable cron. In newer releases this page is under **Administration › Maintenance › Cron**, which also shows each job's last run and last error.

### Back up the configuration file and encryption key

ITFlow encrypts stored credentials with a master key. Without it, a restored database cannot decrypt them. Follow [ITFlow Docs: Backups](https://docs.itflow.org/backups) to export the master key, and keep a copy of `config.php` off the VM.

> **Note:** `config.php` contains the database password in plain text. Copy the file instead of printing it on screen.

---

## Step 6: Prepare the support mailbox

ITFlow signs in to the mailbox with a plain username and password. It supports OAuth only for Microsoft 365 and Google Workspace.

If your Stalwart server uses Authentik single sign-on (see [Stalwart and Bulwark with Authentik SSO](../services/stalwart-authentik-sso.md)), the mailbox's Authentik password does not work over IMAP and SMTP. Create an **app password** for the mailbox:

1. Sign in to `https://mail.example.com/admin` **as the support mailbox** (`support@example.com`), not as your own admin account. Each mailbox creates its own app passwords; an admin cannot add one to another account.
2. Switch to the account view (the person icon at the bottom of the left sidebar).
3. Go to **Credentials › App Passwords** and click **Create App password**.
4. Enter a **Description** such as `ITFlow`.
5. Leave **Allowed IPs** empty, or enter the **public** IP address the ITFlow VM uses to reach the internet. A private address such as `192.168.1.60` never matches, because the mail server sees your public IP.
6. Save, and copy the password into a password manager. It is shown only once.

### Test the mailbox from the ITFlow VM

First check that the mail server name resolves to its public address from the VM:

```bash
apt install -y dnsutils curl
dig +short mail.example.com
```

The output must be the mail server's public IP. If it shows a private address, an internal DNS zone is overriding the name; fix that first.

Then test the IMAP login. curl asks for the password and does not display it:

```bash
curl --user "support@example.com" "imaps://mail.example.com/"
```

Lines starting with `* LIST` mean the login works. Do not add `-v`: verbose mode prints the login command, including the password in base64.

---

## Step 7: Mail settings in ITFlow

Go to **Administration › Settings › Mail**.

### SMTP (sending)

| Field | Value |
|---|---|
| SMTP Provider | **Standard SMTP (Username/Password)** |
| SMTP Host | `mail.example.com` |
| SMTP Port | `465` |
| Encryption | SSL |
| SMTP Username | `support@example.com` |
| SMTP Password | The app password from Step 6 |

Click **Save**.

### IMAP (reading the ticket inbox)

| Field | Value |
|---|---|
| IMAP Provider | **Standard IMAP (Username/Password)** |
| IMAP Host | `mail.example.com` |
| IMAP Port | `993` |
| IMAP Encryption | SSL |
| IMAP Username | `support@example.com` |
| IMAP Password | The app password from Step 6 |

Leave **Microsoft OAuth Connect (Web)** and every OAuth field empty. That section is only for mailboxes hosted in Microsoft 365 or Google Workspace, even though the page shows it for every provider.

Click **Save**.

### From addresses

Further down the same page, ITFlow has separate sender settings for tickets, invoices, and quotes. Set every **From email** to `support@example.com` and every **From name** to the name customers should see (for example `Example IT Support`). Click **Save**.

> **Warning:** The sender address must belong to the mailbox that signs in. A mail server rejects mail that the account `support@example.com` tries to send as another address. This is the usual reason email stops working after moving ITFlow to a new domain: the SMTP login uses the new address, but the From fields still show the old one.

### Test

At the bottom of the page, use the test buttons: send a test email, and test the IMAP connection. A green **Connected successfully** message appears at the top of the page when a test passes.

> **Warning:** If a setting is wrong (for example SSL on a port that expects TLS), ITFlow can hang while it waits for the mail server. Use 465 with SSL, or 587 with TLS. Never mix them.

---

## Step 8: Turn on email-to-ticket

1. Go to **Administration › Settings › Ticket**.
2. Turn on **Email-to-ticket parsing**.
3. Decide which senders may open tickets:
    - **Default:** only senders whose email domain is registered to a client in ITFlow, or who already exist as a contact. Mail from anyone else stays in the inbox for manual review.
    - **Create tickets for emails from unknown senders/domains:** turn this on to accept mail from anyone. In a home lab with no client domains set up yet, turn it on.
4. Click **Save**.

---

## Step 9: Test end to end

1. From a different mailbox, send an email to `support@example.com`.
2. Wait about one minute.
3. In ITFlow, go to **Tickets**. A new ticket should appear with the email's subject.
4. In the mailbox, the message has moved to a folder named **ITFlow**.
5. Reply to the ticket in ITFlow. The sender receives the reply from `support@example.com`, with a ticket number such as `[TCK-001]` in the subject.
6. Reply to that email. The reply is added to the same ticket.

### How email-to-ticket decides what to do

1. Each minute, the dispatcher runs the mailbox job, which checks the inbox for **unread** messages.
2. It marks each unread message as read and looks for a ticket number such as `[TCK-001]` in the subject.
3. **Ticket number found:** if the ticket is open, the email is added as a reply. If the ticket is closed, the sender gets an automatic response and ITFlow raises a notification. Closed tickets are not reopened.
4. **No ticket number:** ITFlow looks for a contact with that email address, then for a client that owns the sender's domain, and opens the ticket there. If neither matches, the message stays in the inbox, unless unknown senders are allowed.
5. Processed messages move to the **ITFlow** folder.

> **Note:** Only **unread** mail is processed. If you open a message in webmail before ITFlow picks it up, it is marked as read and ITFlow skips it. Mark it as unread to have it processed.

---

## Troubleshooting

### Where to look

| What | Where |
|---|---|
| Outgoing mail and send errors | **Administration › Settings › Mail Queue**. Failed messages show the error and can be retried. |
| Scheduled job status | **Administration › Maintenance › Cron** (newer releases): last run, last status, and last error for each job. |
| Application errors | **Administration › Audit Logs**. Filter by type, for example *Cron* or *Mail*. |
| Apache errors | `/var/log/apache2/error.log` |
| Install log | `/var/log/itflow_install.log` |

Run the mailbox job by hand to see its output directly:

```bash
sudo -u www-data php /var/www/itflow.example.com/cron/ticket_email_parser.php
```

### Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Test passes, but notifications never arrive; Mail Queue shows failures | A **From email** field still holds an old address that the mailbox does not own. | Set every From email to the SMTP username (Step 7). Retry the queued messages. |
| No new tickets, mail stays unread in the inbox | Cron is not running, cron is disabled in ITFlow, or email-to-ticket parsing is off. | Check `/etc/cron.d/itflow` (Step 3), the Cron page (Step 5), and the Ticket setting (Step 8). |
| No new tickets, mail is already marked as read | The message was opened in webmail first. | Mark it as unread. |
| Mail stays in the inbox, marked as read and flagged | The sender matched no contact or client domain. | Add the sender as a contact, register the client's domain, or allow unknown senders (Step 8). |
| IMAP or SMTP test fails with an authentication error | The Authentik password was used instead of an app password, the app password belongs to another account, or the username lacks the domain. | Create the app password while signed in as `support@example.com` and use the full address as the username (Step 6). |
| Stalwart log shows `Unsupported credentials type for OIDC backend` | ITFlow is sending the Authentik password. | Use an app password (Step 6). |
| Logins suddenly fail after several bad attempts | Stalwart banned the ITFlow VM's public IP after repeated failures. | Fix the password first, then remove the ban in Stalwart. Each wrong attempt from cron adds to the count every minute. |
| Test IMAP reports a missing PHP extension | The PHP mail parsing extension is not installed. | `apt install -y php-mailparse && systemctl restart apache2`, then test again. |
| ITFlow page hangs after saving mail settings | Wrong port and encryption pair. | Use 465 with SSL, or 587 with TLS. |
| Redirect loop when opening ITFlow through the proxy | The proxy forwards with `http` to port 80 while ITFlow is HTTPS-only. | Set the proxy host to scheme `https`, port `443` (Step 4). |
| Notifications table grows to millions of rows, pages run out of memory | An extra or older cron line runs `cron.php` alongside other ITFlow cron entries. | Keep only the single dispatcher line in `/etc/cron.d/itflow` and remove any `www-data` crontab (Step 3). |
