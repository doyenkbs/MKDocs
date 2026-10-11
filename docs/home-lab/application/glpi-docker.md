---
tags:
  - GLPI
  - Docker
---

# GLPI 11 with Docker Compose

This page installs <span class="prod-app">GLPI</span> 11 with the official GLPI Docker image. GLPI is an open source IT service management tool: tickets, asset inventory, a knowledge base, and change management in one application. It can create tickets from incoming email and send email notifications.

The stack has two containers:

- **glpi**: the GLPI application, with Apache and PHP built in, plus a background worker that runs GLPI's scheduled tasks every minute.
- **db**: MySQL 8.4, which holds the GLPI database.

A reverse proxy (Nginx Proxy Manager in this guide) handles HTTPS in front of it.

All names and addresses on this page are examples. Replace them with your own:

| Example value | Replace with |
|---|---|
| `glpi.example.com` | The hostname for GLPI |
| `192.168.1.50` | The IP address of the Docker host |
| `192.168.1.10` | The IP address of Nginx Proxy Manager |
| `mail.example.com` | Your mail server hostname |
| `helpdesk@example.com` | The mailbox GLPI uses for tickets |
| `America/New_York` | Your time zone |

Tested with GLPI 11.0.11 on Debian 13.

> Reference: [GLPI Docker images (official)](https://github.com/glpi-project/docker-images)

---

## Pin the version

The official example file uses the image tag `glpi/glpi:latest`. Since October 2026, `latest` points to **GLPI 12**, not 11.

The image also updates the GLPI database automatically every time the container starts. If the tag ever moves to a newer major version, the next restart upgrades your database to that version, and there is no automatic way back.

This guide pins an exact 11.x version (`glpi/glpi:11.0.11`). To see the current tags, open [hub.docker.com/r/glpi/glpi/tags](https://hub.docker.com/r/glpi/glpi/tags).

---

## Prerequisites

- A Debian 13 VM or LXC. 2 vCPU, 4 GB RAM, and 20 GB of disk is enough for a home lab.
- SSH access with a user that can run `sudo`.
- A reverse proxy that can forward a hostname to `http://192.168.1.50:8080`.
- A DNS record for `glpi.example.com` that points at the reverse proxy.

---

## Step 1: Install Docker

Install Docker Engine and the Compose plugin from Docker's own repository:

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Check that Docker works:

```bash
sudo docker run --rm hello-world
```

Expected output includes `Hello from Docker!`.

---

## Step 2: Create the stack files

Create a folder for the stack:

```bash
sudo mkdir -p /opt/glpi
cd /opt/glpi
```

Create the Compose file:

```bash
sudo nano /opt/glpi/docker-compose.yml
```

Paste this content, then save with ++ctrl+o++, ++enter++, and exit with ++ctrl+x++:

```yaml title="/opt/glpi/docker-compose.yml"
name: glpi

services:
  glpi:
    # Pinned to 11.x on purpose. "latest" points to GLPI 12,
    # and the automatic database update would migrate to it.
    image: "glpi/glpi:11.0.11"
    container_name: glpi
    restart: unless-stopped
    env_file: .env
    environment:
      TZ: ${TZ}
    volumes:
      # config, files, logs, and marketplace plugins all live under /var/glpi
      - glpi_data:/var/glpi
    depends_on:
      db:
        condition: service_healthy
    ports:
      # The reverse proxy forwards to http://<docker-host-ip>:8080
      - "8080:80"

  db:
    image: "mysql:8.4"
    container_name: glpi-db
    restart: unless-stopped
    environment:
      TZ: ${TZ}
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${GLPI_DB_NAME}
      MYSQL_USER: ${GLPI_DB_USER}
      MYSQL_PASSWORD: ${GLPI_DB_PASSWORD}
    volumes:
      - db_data:/var/lib/mysql
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -uroot -p$$MYSQL_ROOT_PASSWORD --silent"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

volumes:
  glpi_data:
  db_data:
```

What differs from the official example file:

| Change | Why |
|---|---|
| GLPI pinned to `11.0.11` | `latest` is GLPI 12 (see [Pin the version](#pin-the-version)). |
| MySQL pinned to `8.4` | The untagged `mysql` image pulls MySQL 9.x. |
| Root password set in `.env` | The official file generates a random root password and prints it in the container log. Setting it yourself keeps it out of the logs. |
| Host port `8080` | Leaves port 80 free on the host. The reverse proxy handles HTTPS. |
| Database health check | GLPI waits until MySQL is ready instead of failing on first start. |

Generate two passwords, one for the GLPI database user and one for the MySQL root account. This command prints a random password on screen:

```bash
openssl rand -base64 24 | tr -d '/+='
```

Create the environment file:

```bash
sudo nano /opt/glpi/.env
```

Paste this content and replace both `CHANGE_ME` values with the passwords you generated:

```ini title="/opt/glpi/.env"
TZ=America/New_York

GLPI_DB_HOST=db
GLPI_DB_PORT=3306
GLPI_DB_NAME=glpi
GLPI_DB_USER=glpi
GLPI_DB_PASSWORD=CHANGE_ME_glpi_db_password

MYSQL_ROOT_PASSWORD=CHANGE_ME_mysql_root_password
```

> **Note:** `CHANGE_ME_glpi_db_password` and `CHANGE_ME_mysql_root_password` are placeholders. Replace each one with a password you generated with the `openssl` command above, and use a different password for each:
>
> | Placeholder | Replace with |
> |---|---|
> | `CHANGE_ME_glpi_db_password` | The first generated password. GLPI uses it to connect to its database. |
> | `CHANGE_ME_mysql_root_password` | The second generated password. It is the MySQL administrator password, used for maintenance such as Step 6 and backups. |
>
> Replace the whole value, including the `CHANGE_ME_` part, and leave no spaces or quotes around it. MySQL only reads these passwords the very first time the stack starts. If you start the stack with the placeholders still in place, see [Troubleshooting](#troubleshooting).

Limit who can read it, because it holds passwords:

```bash
sudo chmod 600 /opt/glpi/.env
```

> **Note:** All five `GLPI_DB_*` variables are required. If any is missing, the image skips the automatic install and shows the web installation wizard instead.

---

## Step 3: Start GLPI

```bash
cd /opt/glpi
sudo docker compose up -d
sudo docker compose logs -f glpi
```

On the first start, the container creates the GLPI database tables. Wait until the log stops scrolling and shows Apache running, then press ++ctrl+c++ to stop following the log. The containers keep running.

Check that both containers are up:

```bash
sudo docker compose ps
```

Expected output: `glpi` shows `Up` and `glpi-db` shows `Up (healthy)`.

Quick test from the Docker host:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080
```

Expected output: `200` or `302`.

---

## Step 4: Reverse proxy and DNS

### DNS

Create an A record for `glpi.example.com` that points at the reverse proxy (`192.168.1.10`). If you use split-horizon DNS, add it to the internal zone. See [Split-Horizon DNS](../services/split-horizon-dns-technitium-npm.md).

### Nginx Proxy Manager

1. Open the Nginx Proxy Manager admin page (`http://192.168.1.10:81`).
2. Go to **Hosts › Proxy Hosts** and click **Add Proxy Host**.
3. On the **Details** tab:

    | Field | Value |
    |---|---|
    | Domain Names | `glpi.example.com` |
    | Scheme | `http` |
    | Forward Hostname / IP | `192.168.1.50` |
    | Forward Port | `8080` |
    | Block Common Exploits | On |

4. On the **SSL** tab, select **Request a new SSL Certificate**, turn on **Force SSL**, and accept the Let's Encrypt terms. If `glpi.example.com` is not reachable from the internet, turn on **Use a DNS Challenge** and pick your DNS provider.
5. Click **Save**.

Open `https://glpi.example.com`. The GLPI login page should load.

---

## Step 5: First login and default accounts

The automatic install creates four accounts with well-known passwords:

| Username | Password | Profile |
|---|---|---|
| `glpi` | `glpi` | Super-Admin |
| `tech` | `tech` | Technician |
| `normal` | `normal` | Normal user |
| `post-only` | `postonly` | Self-service |

1. Sign in as `glpi` / `glpi`.
2. GLPI shows a warning listing the accounts that still use default passwords. Change each one:
    1. Go to **Administration › Users**.
    2. Click the username.
    3. Enter a new password in **Password** and **Password confirmation**.
    4. Click **Save**.
3. Disable any account you do not need: open it, set **Active** to **No**, and click **Save**.

---

## Step 6: Enable time zone support

GLPI can show dates in each user's time zone. It needs read access to MySQL's time zone table first. These commands use the passwords from `.env` inside the containers and do not print them:

```bash
cd /opt/glpi
sudo docker compose exec db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "GRANT SELECT ON mysql.time_zone_name TO '\''glpi'\''@'\''%'\''; FLUSH PRIVILEGES;"'
sudo docker compose exec glpi /var/www/glpi/bin/console database:enable_timezones
```

---

## Step 7: Email

GLPI sends notifications over SMTP and creates tickets from a mailbox over IMAP. Use a dedicated mailbox such as `helpdesk@example.com`.

### Outbound notifications

1. Go to **Setup › Notifications**.
2. Set **Enable followups via email** to **Yes** and click **Save**.
3. Click **Email followups configuration** and fill in:

    | Field | Value |
    |---|---|
    | Administrator email address | `helpdesk@example.com` |
    | Way of sending emails | SMTP+SSL |
    | SMTP host | `mail.example.com` |
    | Port | `465` |
    | SMTP login | `helpdesk@example.com` |
    | SMTP password | The mailbox password (or app password) |
    | Email sender | `helpdesk@example.com` |

4. Click **Save**, then **Send a test email to the administrator**.

### Inbound tickets (mail receiver)

1. Go to **Setup › Receivers** and click **Add**.
2. Fill in:

    | Field | Value |
    |---|---|
    | Name (email address) | `helpdesk@example.com` |
    | Active | Yes |
    | Server | `mail.example.com` |
    | Connection options | IMAP, SSL |
    | Port | `993` |
    | Login | `helpdesk@example.com` |
    | Password | The mailbox password (or app password) |

3. Click **Add**, then open the receiver again and click **Get email tickets now** to test.

> **Note:** GLPI ignores email sent from the receiver's own address, to avoid loops. Test from a different mailbox.

### Scheduled tasks

The image runs GLPI's scheduled tasks (sending queued email, collecting mail) every minute by itself. Do not add a cron job on the host for GLPI.

To check them, go to **Setup › Automatic actions**. The **Last run** column should update every few minutes for `queuednotification` and `mailgate`.

---

## Back up

Back up the database to a file in the current folder:

```bash
cd /opt/glpi
sudo docker compose exec -T db sh -c 'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --no-tablespaces glpi' > glpi-$(date +%F).sql
```

Uploaded documents and configuration live in the `glpi_data` volume. To find where Docker stores it on disk:

```bash
sudo docker volume inspect glpi_glpi_data --format '{{ .Mountpoint }}'
```

---

## Update GLPI

1. Back up the database (see [Back up](#back-up)).
2. Check the release notes at [github.com/glpi-project/glpi/releases](https://github.com/glpi-project/glpi/releases).
3. Change the image tag in `/opt/glpi/docker-compose.yml`, for example from `11.0.11` to the next 11.x release.
4. Pull and restart:

    ```bash
    cd /opt/glpi
    sudo docker compose pull
    sudo docker compose up -d
    sudo docker compose logs -f glpi
    ```

The container updates the database on start. Moving to GLPI 12 is a major upgrade: test it on a copy first.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| The web installation wizard appears instead of the login page | One of the five `GLPI_DB_*` variables is missing or misspelled in `.env`. | Fix `.env`, then `sudo docker compose up -d --force-recreate glpi`. |
| `glpi-db` never becomes healthy | Wrong `MYSQL_ROOT_PASSWORD`, or the volume was created earlier with a different password. | MySQL only reads the passwords on the very first start. For a fresh install, remove the volume (`sudo docker compose down -v`, which deletes all data) and start again. |
| The stack was started with the `CHANGE_ME_` placeholders still in `.env` | MySQL created the database users with the placeholder passwords on first start. Editing `.env` afterwards does not change them. | On a fresh install with no data yet: `sudo docker compose down -v` (deletes the database and GLPI data volumes), put real passwords in `.env`, then `sudo docker compose up -d`. |
| GLPI is on version 12 after a restart | The image tag is `latest`. | Restore the database backup and pin an 11.x tag. |
| Test email fails | Wrong port and encryption pair, or a password the mail server rejects. | Use 465 with SSL, or 587 with TLS. If the mail server uses single sign-on, create an app password for the mailbox. |
| Mail stays in the inbox and no ticket appears | The receiver is inactive, the sender is the receiver's own address, or the automatic action `mailgate` is not running. | Check **Setup › Receivers** and **Setup › Automatic actions**. |
