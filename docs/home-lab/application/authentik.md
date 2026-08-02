# **<span style="color:#009688;">Authentik</span>**

## **<span style="color:#009688;">Overview</span>**

**Authentik** is a self-hosted identity provider (IdP) supporting OIDC, SAML, LDAP, and more. In this lab, it's the single sign-on layer sitting in front of most self-hosted applications — one login, one MFA enrollment, centralized access control and audit logging across everything it's connected to.

If you're setting up integrations for a specific app, see the [Authentik Integrations](index.md#authentik-integrations) table on the Applications overview page. This page covers getting Authentik itself installed and kept up to date.

**Architecture at a glance:**

| Component | Role |
|---|---|
| `server` | Web UI, API, and authentication flows |
| `worker` | Background tasks — flows, outposts, scheduled jobs |
| PostgreSQL | Primary datastore |
| Redis | Caching and background task broker |

All four run as containers via Docker Compose — this is the officially supported deployment method and the one used here.

---

## ***<span style="color:#009688;">Prerequisites</span>***

- A dedicated LXC or VM with Docker and Docker Compose installed
- At minimum **2 vCPU / 2GB RAM** for a home lab deployment (Authentik's own recommendation; more if you'll integrate many apps)
- A domain or subdomain to reach the Authentik UI (e.g. `auth.example.com`), ideally behind [Cloudflare Tunnel](../services/cloudflaretunnel.md) or a reverse proxy with valid TLS

---

## **<span style="color:#009688;">Installation</span>**

### **1. Create a project directory**

```bash
mkdir -p /opt/authentik && cd /opt/authentik
```

### **2. Download the latest `docker-compose.yml`**

```bash
curl -O https://goauthentik.io/docker-compose.yml
```

!!! tip "Always pull from the official source at install time"
    Authentik ships frequent releases. Rather than copying a compose file from a guide (including this one), pull the current one directly from `goauthentik.io` so you're starting from a version-matched, supported baseline.

### **3. Generate secrets and create the `.env` file**

```bash
echo "PG_PASS=$(openssl rand -base64 36 | tr -d '\n')" >> .env
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')" >> .env
```

Both values are generated randomly and should never be reused elsewhere.

### **4. (Recommended) Pin an explicit version**

```bash
echo "AUTHENTIK_TAG=2026.6" >> .env
```

!!! warning "Check the current release before pinning"
    Substitute the latest stable tag from the [Authentik releases page](https://github.com/goauthentik/authentik/releases) at the time you install. Pinning to an explicit version (rather than `latest`) means upgrades are a deliberate, controlled action later — see [Upgrading](#upgrading) below.

### **5. Set the initial admin password (optional but recommended)**

```bash
echo "AUTHENTIK_BOOTSTRAP_PASSWORD=<a-strong-password>" >> .env
echo "AUTHENTIK_BOOTSTRAP_EMAIL=admin@example.com" >> .env
```

Without this, Authentik prompts you to set the initial admin account through the setup wizard on first login instead.

### **6. Start the stack**

```bash
docker compose pull
docker compose up -d
```

First startup runs database migrations — give it a minute or two before the web UI becomes reachable.

### **7. Complete initial setup**

Navigate to `https://<your-host-or-domain>:9443/if/flow/initial-setup/` and follow the setup wizard (skip this if you set `AUTHENTIK_BOOTSTRAP_*` values above — the admin account already exists).

---

## **<span style="color:#009688;">Post-Install Recommendations</span>**

- **Put Authentik behind a reverse proxy or tunnel** with valid TLS rather than exposing the default port directly — see [Cloudflare Tunnel](../services/cloudflaretunnel.md).
- **Enable MFA on the admin account first**, before connecting any other applications.
- **Back up `.env` and the Postgres volume regularly** — losing either means losing every configured SSO integration. The [Ansible Config Backup playbook](../services/ansible-config-backup.md) covers this pattern; add Authentik's `.env` and media directory to that host's `backup_paths`.

---

## **<span style="color:#009688;">Upgrading</span>**

Authentik releases fairly often, and upgrades are generally low-risk if done in order — but always review the release notes first, since occasional versions include breaking changes or required manual migration steps.

### **1. Check the release notes for the target version**

Read the [release notes](https://goauthentik.io/docs/releases/) for every version between your current one and the target — not just the target version — since breaking changes are called out per release.

### **2. Back up first**

```bash
docker compose exec postgresql pg_dumpall -U authentik > /opt/authentik/backup_$(date +%F).sql
```

Don't skip this — a failed migration mid-upgrade is much easier to recover from with a fresh dump than without one.

### **3. Update the version tag**

```bash
sed -i 's/AUTHENTIK_TAG=.*/AUTHENTIK_TAG=<new-version>/' .env
```

### **4. Pull and restart**

```bash
docker compose pull
docker compose up -d
```

Compose will recreate containers on the new version; database migrations run automatically on `server` startup.

### **5. Verify**

- Check `docker compose logs -f server` for migration errors during startup
- Log in and confirm existing integrations (Cloudflare Access, Nextcloud, etc.) still authenticate correctly
- Check the **System Tasks** section in the admin UI for any failed background jobs post-upgrade

!!! danger "Never skip multiple major versions at once"
    Jump one version at a time if you're several releases behind, rather than going straight from a very old version to the latest. Each release's migrations assume the previous version's schema — skipping versions can leave the database in a state the migration scripts don't expect.

### **<span style="color:#009688;">Rolling back</span>**

If an upgrade fails and the fresh dump from step 2 is needed:

```bash
docker compose down
sed -i 's/AUTHENTIK_TAG=.*/AUTHENTIK_TAG=<previous-version>/' .env
docker compose up -d postgresql
docker compose exec -T postgresql psql -U authentik < /opt/authentik/backup_<date>.sql
docker compose up -d
```

---

## **Next Steps**

- Connect your first application — see the [Authentik Integrations](index.md#authentik-integrations) table for per-app guides already documented in this lab.
- Review [Cloudflare Access + Authentik](../services/cloudflare.md#pairing-with-authentik) if you're pairing Authentik with Cloudflare Tunnel for externally reachable apps.