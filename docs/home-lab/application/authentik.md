# Authentik

## Overview

**Authentik** is a self-hosted identity provider (IdP) supporting OIDC, SAML, LDAP, and more. In this lab, it's the single sign-on layer sitting in front of most self-hosted applications: one login, one MFA enrollment, centralized access control and audit logging across everything it's connected to.

If you're setting up integrations for a specific app, see the [Authentik Integrations](index.md#authentik-integrations) table on the Applications overview page. This page covers getting Authentik itself installed and kept up to date.

**Architecture at a glance:**

| Component | Role |
|---|---|
| `server` | Web UI, API, and authentication flows |
| `worker` | Background tasks, flows, outposts, scheduled jobs |
| PostgreSQL | Primary datastore, and the background task broker |

All three run as containers via Docker Compose, which is the officially supported deployment method and the one used here.

Outposts (proxy, LDAP, RADIUS, RAC) run as separate containers. When an outpost is attached through a Docker connection, the Authentik worker creates and manages that container itself over the Docker socket, naming it `ak-outpost-<slug>`. Those containers do not appear in `docker-compose.yml` and are not covered by `docker compose ps`.

!!! note "Older guides mention a Redis container"
    Authentik moved the task broker onto PostgreSQL and dropped Redis from the stack. If a guide or an older compose file references a `redis` service, it predates that change. The compose file in use here defines exactly three services and one named volume (`database`).

---

## *Prerequisites*

- A dedicated LXC or VM with Docker and Docker Compose installed
- At minimum **2 vCPU / 2GB RAM** for a home lab deployment (Authentik's own recommendation; more if you'll integrate many apps)
- **At least 40GB of disk.** The server image is roughly 400MB compressed and expands to about 1.5GB. Every upgrade leaves the old image behind, so a 20GB disk fills up after a handful of version bumps. See [Disk maintenance](#disk-maintenance).
- A domain or subdomain to reach the Authentik UI (e.g. `auth.example.com`), ideally behind [Cloudflare Tunnel](../services/cloudflaretunnel.md) or a reverse proxy with valid TLS

---

## Installation

### 1. Create a project directory

```bash
mkdir -p /opt/authentik && cd /opt/authentik
```

### 2. Download the current compose file

```bash
curl -fL -o docker-compose.yml https://docs.goauthentik.io/compose.yml
ls -lh docker-compose.yml
```

The `-f` flag makes curl return non-zero on an HTTP error instead of writing the error page to disk. Check the size before continuing.

!!! tip "Always pull from the official source at install time"
    Authentik ships frequent releases. Rather than copying a compose file from a guide (including this one), pull the current one directly from the official docs so you're starting from a version-matched, supported baseline.

!!! warning "Keep the filename `docker-compose.yml`"
    Upstream now names the file `compose.yml`. Compose resolves `compose.yaml`, `compose.yml`, `docker-compose.yaml`, `docker-compose.yml` in that order, so if both names end up in `/opt/authentik`, `compose.yml` silently wins and the other is ignored. Pick one name and keep it. This lab uses `docker-compose.yml`.

### 3. Generate secrets and create the `.env` file

```bash
echo "PG_PASS=$(openssl rand -base64 36 | tr -d '\n')" >> .env
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')" >> .env
```

Both values are generated randomly and should never be reused elsewhere. Do not shorten `AUTHENTIK_SECRET_KEY` or set it by hand: Django rejects keys under 50 characters or with fewer than 5 unique characters, and logs `security.W009` on every boot until it is fixed. Rotating it later invalidates all sessions and some stored tokens, so get it right at install time.

### 4. (Recommended) Pin an explicit version

```bash
echo "AUTHENTIK_TAG=<latest-stable>" >> .env
docker compose config | grep 'image:'
```

Substitute the latest stable tag from the [Authentik releases page](https://github.com/goauthentik/authentik/releases). Pinning an explicit version rather than tracking the compose file's default means upgrades are a deliberate, controlled action later. See [Upgrading](#upgrading) below.

!!! danger "Verify the variable is actually being read"
    The compose file references `${AUTHENTIK_TAG:-<some-version>}`, so a misspelled or missing variable in `.env` does not error. Compose falls back to the baked-in default and everything appears to work. A typo like `ATHENTIK_TAG` can sit in `.env` for months doing nothing, until an upgrade lands you on an unintended version. The `docker compose config | grep 'image:'` line above is the check: it prints the fully resolved tag. Run it after every `.env` change.

### 5. Set the initial admin password (optional but recommended)

```bash
echo "AUTHENTIK_BOOTSTRAP_PASSWORD=<a-strong-password>" >> .env
echo "AUTHENTIK_BOOTSTRAP_EMAIL=admin@example.com" >> .env
```

Without this, Authentik prompts you to set the initial admin account through the setup wizard on first login instead.

### 6. Start the stack

```bash
docker compose pull
docker compose up -d
```

First startup runs database migrations, so give it a minute or two before the web UI becomes reachable.

### 7. Complete initial setup

Navigate to `https://<your-host-or-domain>:9443/if/flow/initial-setup/` and follow the setup wizard (skip this if you set `AUTHENTIK_BOOTSTRAP_*` values above, since the admin account already exists).

---

## Post-Install Recommendations

- **Put Authentik behind a reverse proxy or tunnel** with valid TLS rather than exposing the default port directly. See [Cloudflare Tunnel](../services/cloudflaretunnel.md).
- **Enable MFA on the admin account first**, before connecting any other applications.
- **Back up `.env` and the Postgres volume regularly.** Losing either means losing every configured SSO integration. The [Ansible Config Backup playbook](../services/ansible-config-backup.md) covers this pattern; add Authentik's `.env` and media directory to that host's `backup_paths`.
- **Monitor the outpost containers, not just the stack.** See [Monitoring outposts](#monitoring-outposts).
- **Cap the journal and prune old images on a schedule.** See [Disk maintenance](#disk-maintenance).

---

## Monitoring outposts

Outpost containers are the blind spot in this deployment. They are created and managed by the Authentik worker rather than by Compose, so they do not appear in `docker compose ps` and a failing one produces no obvious signal.

Run this periodically, not only during upgrades:

```bash
docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | grep -i goauthentik
```

Every `ak-outpost-*` container should be `Up` and `(healthy)`, and its image tag should match the running server version.

Check the restart counters:

```bash
for c in $(docker ps -a --format '{{.Names}}' | grep '^ak-outpost-'); do
  docker inspect "$c" --format "$c restarts={{.RestartCount}} image={{.Config.Image}}"
done
```

A `RestartCount` in the thousands means a crash loop that has been running for weeks. A crash-looping outpost re-runs the full API handshake on every restart, which floods `authentik_tasks` and `authentik_tasks_log`.

To see the reconnect pattern in the server log:

```bash
docker compose logs --since 10m server | grep -o 'ws/outpost/[a-f0-9-]*' | sort | uniq -c
```

A healthy outpost holds one websocket open and appears once or twice. Anything appearing every few seconds, or once per minute on a steady cadence, is restarting.

!!! warning "Read the container log before removing a crash-looping outpost"
    `docker rm -f` destroys the only record of why it was failing. Run `docker logs --tail=200 <container>` first and save the output. Once the container is gone the failure cannot be diagnosed, only reproduced.

    The log usually names the cause in one line. An outpost with **no provider assigned** panics on startup with `no ldap provider defined` (or the equivalent for its type) and exits with code 2. That is a configuration problem, not a version problem: the fix is to assign a provider, or to delete the outpost if nothing uses it.

!!! danger "Removing the container does not trigger a rebuild"
    `outpost_controller` is event-driven. Deleting a container with `docker rm -f` does not cause the worker to notice or recreate it. The reliable trigger is saving the outpost in the admin UI: **Applications > Outposts >** select the outpost **> Edit >** change nothing **> Update**. That is what actually re-enqueues the task.

---

## Disk maintenance

Each upgrade leaves the previous server image on disk. Three version hops in one session is enough to fill a small lab disk, and a full disk fails an image pull in a way that is easy to miss (see [step 7](#7-pull-and-restart) below).

Check current usage:

```bash
df -h /
docker system df
```

Reclaim space. Only the running images are in use, so `-a` is safe here:

```bash
docker image prune -a -f
docker system df
```

Cap the systemd journal permanently. An uncapped journal on a chatty host reaches multiple GB:

```bash
journalctl --disk-usage
sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=500M/' /etc/systemd/journald.conf
grep '^SystemMaxUse' /etc/systemd/journald.conf
systemctl restart systemd-journald
journalctl --vacuum-size=200M
```

Check what else is growing:

```bash
du -sh /var/log/* | sort -h | tail -10
```

!!! note "The `logging:` block in this deployment"
    `server` and `worker` use the syslog driver pointed at `udp://127.0.0.1:514`. That forwards Authentik's output to the local rsyslog, which writes it to `/var/log/syslog`, while journald also captures it. Confirm the forwarding is actually going somewhere useful (a central collector) rather than just doubling local disk writes:

        grep -rn '514' /etc/rsyslog.conf /etc/rsyslog.d/ 2>/dev/null

Add `docker image prune -a -f` to the weekly Ansible patch run so this never becomes an emergency mid-upgrade.

---

## Upgrading

Authentik releases often. Upgrades are low risk when done in order, but read the release notes first, since some versions include breaking changes or manual migration steps.

### 1. Determine the upgrade path

Upgrade to the **latest patch within the current major** first, then move to the **next major release**. Do not skip a major, and do not jump majors while behind on patches.

Example, going from 2026.2.2 to 2026.8.1:

```text
2026.2.2  ->  2026.2.6  ->  2026.5.6  ->  2026.8.1
```

!!! note "Patch numbers go in the tag, major numbers go in URLs"
    `AUTHENTIK_TAG` takes a full patch version (`2026.5.6`). Upstream publishes one compose file per major, so its URL takes the major only (`/version/2026.5/`). Putting a patch number in the URL returns 404. Full versions and majors both appear throughout this section and they are not interchangeable.

Read the [release notes](https://docs.goauthentik.io/releases/) for every major in the path, not just the target. Two things to look for specifically:

- **PostgreSQL minimum version.** A bump (for example 16 to 17) is a separate dump-and-restore job, not part of the Authentik upgrade. Budget a separate window for it.
- **Volume and variable renames.** The `./data:/data`, `./certs:/certs`, and `./custom-templates:/templates` mounts have moved between releases, as have the `COMPOSE_PORT_*` variable names. If either changes, the local customizations in this deployment need to move with them.

### 2. Preflight

**Confirm disk space.** Each hop pulls a ~400MB image that expands to ~1.5GB, on top of everything already there:

```bash
df -h /
docker system df
```

Leave at least 5GB free before starting a multi-hop upgrade. If usage is high, run the cleanup in [Disk maintenance](#disk-maintenance) first.

**Confirm break-glass access.** Most services in this lab authenticate through Authentik. Before starting, confirm there is a path back in that does not depend on it:

```bash
ssh root@<proxmox-host-ip>
```

Then confirm `https://<proxmox-host-ip>:8006` loads by direct IP, with no Authentik proxy outpost in front of it. If it does not, fix that before touching the stack.

**Confirm the current version is actually pinned:**

```bash
cd /opt/authentik
grep '^AUTHENTIK_TAG=' .env
docker compose config | grep 'image:'
```

Both must agree. If `grep` returns nothing while the stack is running, the version is coming from the compose file's fallback rather than from `.env`, and the steps below will not behave as written. Fix the variable before continuing.

**Take an outpost inventory.** Run the checks in [Monitoring outposts](#monitoring-outposts) now, before anything changes. Knowing which outposts were already broken saves you from blaming the upgrade for a failure that predates it.

### 3. Snapshot the container first

This is the rollback point. It goes before every other action in this section, including the file copies and the database dump, so that reverting returns the host to a state predating any change.

From the **Proxmox host** shell:

```bash
pct list          # LXC containers
qm list           # virtual machines
vzdump <CTID or VMID> --mode snapshot --storage local --compress zstd
```

`--mode snapshot` keeps the guest running. The result is crash-consistent, which PostgreSQL recovers from cleanly on start. The logical dump in the next step is the finer-grained option; this is the blunt one, and it is the one that actually saves you when migrations leave the schema unusable.

### 4. Back up config and database

Now, inside the Authentik container:

```bash
cd /opt/authentik
cp docker-compose.yml docker-compose.bak-$(date +%F).yml
cp .env .env.bak-$(date +%F)
ls -l docker-compose* .env.bak-*
```

```bash
docker compose exec -T postgresql pg_dumpall -U authentik | gzip > backup_$(date +%F).sql.gz
ls -lh backup_$(date +%F).sql.gz
```

!!! warning "The `-T` flag is not optional"
    Without `-T`, `docker compose exec` allocates a TTY, which translates `\n` to `\r\n` in the redirected output. The dump looks valid and is the right size, but fails on restore. Always pass `-T` when redirecting `exec` output to a file.

Copy the dump and the `.env` backup off this host. A backup stored inside the container being upgraded is not a backup, and leaving old dumps in `/opt/authentik` contributes to the disk problem above.

!!! danger "Both files contain secrets"
    `.env` holds `PG_PASS` and `AUTHENTIK_SECRET_KEY`. The dump holds every credential, token, and certificate Authentik manages. Treat both as secrets in transit and at rest, and do not park them on a general-purpose share.

### 5. Update the compose file (major upgrades only)

Skip this step for patch upgrades inside the same major, where only the tag changes. Across majors, upstream changes the compose file itself (service definitions, image versions, volume paths), so changing only the tag runs new code against an old service topology.

```bash
curl -fL -o docker-compose.<target-major>.yml \
  https://goauthentik.io/version/<target-major>/lifecycle/container/compose.yml
ls -lh docker-compose.<target-major>.yml
diff docker-compose.yml docker-compose.<target-major>.yml
```

The URL takes the **major** only, for example `2026.5`. Use `curl -fL` rather than `wget -O`: `wget -O` creates the output file before it knows the response code, so a 404 leaves a silent zero-byte file. `curl -f` returns non-zero and writes nothing.

Merge local customizations into the new file by hand. In this deployment that means:

- The `logging:` blocks on `server` and `worker` (syslog driver to `udp://127.0.0.1:514`, tag `authentik`)
- Any volume mounts not present upstream

Port mappings live in `.env` as `COMPOSE_PORT_HTTP` and `COMPOSE_PORT_HTTPS`, so they survive a compose file replacement, as long as the new file still references those same variable names. Confirm that in the diff.

```bash
cp docker-compose.<target-major>.yml docker-compose.yml
docker compose config | grep -A4 'logging:'
```

### 6. Set the version tag

```bash
grep -q '^AUTHENTIK_TAG=' .env \
  && sed -i 's/^AUTHENTIK_TAG=.*/AUTHENTIK_TAG=<new-version>/' .env \
  || echo "AUTHENTIK_TAG=<new-version>" >> .env
grep '^AUTHENTIK_TAG=' .env
```

!!! warning "A plain `sed` can silently do nothing"
    `sed -i 's/AUTHENTIK_TAG=.*/.../'` exits 0 whether or not it matched. If the line is absent or misspelled, the compose fallback keeps driving the version, `pull` and `up -d` both report success, and the stack stays where it was. The `grep`/`||` form above adds the line when it is missing. The `^` anchor also prevents matching a commented-out line.

### 7. Pull and restart

```bash
docker compose config | grep 'image:'
```

That must print the tag set in step 6 for both `server` and `worker`. Do not continue until it does.

Pull as its own command and check that it succeeded:

```bash
docker compose pull
echo "pull exit: $?"
```

!!! danger "A failed pull does not stop `up -d`"
    If the pull dies partway (`no space left on device`, `failed to register layer`, a network drop), Compose will still start the containers on whichever image is already present, print `[+] up 3/3`, and report every container healthy. The application logs show no error because nothing is wrong with the running version, it is just the old one. Read the pull output before continuing.

```bash
docker compose up -d
docker compose logs -f server worker
```

Migrations run automatically on `server` startup. Watch until they finish. A patch upgrade inside the same major often reports `No migrations to apply`, which is normal. The worker also reports `No migrations to apply` on its own pass, because the server already applied them.

!!! note "Health check errors during startup are expected"
    The Rust router starts before gunicorn does, so `/health/live/` returns 500 on the server and 503 on the worker for the first 30 to 90 seconds, with a full stack trace each time. Both flip to 200 once gunicorn is listening. Only worry if they are still failing after migrations complete.

**Verify what is actually running, not what is configured:**

```bash
docker compose logs --since 5m server worker | grep -o '"version": "[0-9.]*"' | sort -u
```

`docker compose config` reports what you asked for. This reports what booted.

### 8. Verify outposts

The server and all outposts must run the same version. This does not happen on its own.

The embedded outpost follows the server automatically. Docker-connected outposts are recreated by `outpost_controller` after the server restarts, but that is best effort and frequently does not happen.

```bash
docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | grep -i goauthentik
```

Every image tag must match the tag set in step 6. Cross-check against the server log, which records the version of every outpost that connects:

```bash
docker compose logs --since 10m server | grep -o 'goauthentik.io/outpost/[0-9.]*' | sort | uniq -c
```

**If an outpost is stale or missing:**

1. Check its restart count first: `docker inspect <container> --format '{{.RestartCount}}'`. A high count means it was already broken before the upgrade, and the version is a symptom rather than the problem. Capture `docker logs --tail=200 <container>` before doing anything else.
2. In the admin UI: **Applications > Outposts >** select the outpost **> Edit >** change nothing **> Update**. Saving is the trigger, and it works even when nothing changed.
3. Wait and re-check:

```bash
sleep 90
docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | grep -i goauthentik
```

**Before rebuilding a failed outpost, check whether anything uses it.** In **Applications > Outposts**, look at the providers assigned to it. An outpost with no active providers crash-loops rather than idling, and is better deleted in the UI than repaired.

Confirm the reconnect churn has stopped:

```bash
docker compose logs --since 5m server | grep -o 'ws/outpost/[a-f0-9-]*' | sort | uniq -c
```

Each healthy outpost should appear once or twice over five minutes, not once per minute or faster.

### 9. Verify the rest

- Admin **Overview** dashboard: Version matches the tag set in step 6, System Status is OK, Workers is at least 1
- `docker compose logs --tail=200 server worker | grep -iE 'error|traceback'`
- Log in through a real downstream app (Nextcloud, Mailcow, Cloudflare Access) rather than only the Authentik UI
- Check **Dashboards > System Tasks** in the admin UI for failed background jobs

Repeat steps 3 through 9 for each hop in the path. Each hop gets its own snapshot and its own dump.

### 10. Clean up

Once the new version is confirmed working and you have moved on from the previous one:

```bash
docker images ghcr.io/goauthentik/server
docker image prune -a -f
df -h /
```

Doing this after each hop, rather than after all of them, keeps the disk from filling mid-upgrade.

!!! note "Harmless log lines"
    Two warnings appear on every boot and are not upgrade problems. The Go router logs `POSTGRES_PASSWORD ... Environment variable not found, using fallback`, because it checks for a variable the Python side supplies as `PG_PASS`. Sessions created before the upgrade log `Pickled model instance's Django version ... does not match`, which clears as those sessions expire.

### Rolling back

!!! danger "Authentik does not support downgrading"
    Once migrations have run, the previous image will not start against the new schema. Reverting `AUTHENTIK_TAG` is not a rollback.

**Preferred path.** Stop the stack, then restore the snapshot from step 3 on the Proxmox host:

```bash
cd /opt/authentik
docker compose down
```

**If no snapshot is available.** The database has to be recreated empty before the dump goes back in, because the schema on disk is already migrated:

```bash
cd /opt/authentik
docker compose down

docker volume ls | grep database        # confirm the exact name first
docker volume rm authentik_database

cp docker-compose.bak-<date>.yml docker-compose.yml
sed -i 's/^AUTHENTIK_TAG=.*/AUTHENTIK_TAG=<last-good-version>/' .env

docker compose up -d postgresql
until docker compose exec -T postgresql pg_isready -U authentik; do sleep 2; done

docker compose exec -T postgresql dropdb -U authentik --if-exists authentik
gunzip -c backup_<date>.sql.gz | docker compose exec -T postgresql psql -U authentik -d postgres

docker compose up -d
```

The volume name is prefixed with the compose project name, which defaults to the directory name (`authentik`). The `dropdb` is required: removing the volume causes the Postgres image to run `initdb` and create an empty `authentik` database from `POSTGRES_DB`, which then collides with the `CREATE DATABASE` statement inside the `pg_dumpall` output. Connecting with `-d postgres` avoids restoring into the database being dropped and recreated.

After any rollback, re-check the outposts. They are not covered by the database restore and will need to be rebuilt at the older version through the UI save described in step 8.

---

## Next Steps

- Connect your first application. See the [Authentik Integrations](index.md#authentik-integrations) table for per-app guides already documented in this lab.
- Review [Cloudflare Access + Authentik](../services/cloudflare.md#pairing-with-authentik) if you're pairing Authentik with Cloudflare Tunnel for externally reachable apps.
