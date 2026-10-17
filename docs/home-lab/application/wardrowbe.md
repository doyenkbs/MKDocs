---
tags:
  - Wardrowbe
  - Docker
  - Authentik
  - AI
---

# Wardrowbe: Self-Hosted AI Wardrobe

This page installs <span class="prod-app">Wardrowbe</span>, a self-hosted wardrobe app. You photograph each clothing item, an AI model tags it (type, color, pattern, style), and the app suggests outfits based on your clothes, the weather, and the occasion.

This build is meant for a home lab whose hardware cannot run a local AI model. Instead of Ollama, it uses hosted AI APIs:

- **Google Gemini** as the main AI model.
- **Groq** as an automatic fallback when Gemini is unavailable or out of quota.
- **LiteLLM**, a small proxy container, which sends each request to Gemini first and to Groq if Gemini fails. LiteLLM does not run a model, so it needs very little CPU and memory.

Sign-in goes through **Authentik** (OIDC), and the app is published through an **existing Cloudflare Tunnel**. No ports are opened on the router.

All names and addresses on this page are examples. Replace them with your own:

| Example value | Replace with |
|---|---|
| `wardrobe.example.com` | The public hostname for Wardrowbe |
| `auth.example.com` | Your Authentik hostname |
| `192.168.1.50` | The IP address of the Wardrowbe LXC |
| `192.168.1.1` | Your LAN gateway |
| `150` | The Proxmox container ID |
| `vmbr0` / `local-lvm` | Your Proxmox bridge and storage |
| `wardrobe-users` | The Authentik group allowed to sign in |

Tested with Wardrowbe 1.11.0, Authentik 2026.8, and Debian 12 in a Proxmox LXC.

> Reference: [Wardrowbe on GitHub](https://github.com/Anyesh/wardrowbe)

---

## How it works

```
Browser / phone
      |
      v
Cloudflare Tunnel (existing connector)
      |
      v
nginx (in the stack, port 8080 on the LXC)
      |-- /api/auth/*  --> frontend (Next.js, sign-in)
      |-- /api/*       --> backend (FastAPI)
      |-- everything else --> frontend
                              |
backend, worker, image-worker --+--> PostgreSQL (items, outfits, users)
                                |--> Redis (job queue)
                                |--> LiteLLM --> Gemini (primary)
                                                 Groq (fallback)
```

| Container | Job |
|---|---|
| `postgres` | Database |
| `redis` | Queue for background jobs |
| `backend` | API |
| `worker` | Sends photos to the AI for tagging, builds outfit suggestions |
| `image-worker` | Rotation and background removal, done locally on the CPU |
| `frontend` | Web interface and sign-in |
| `nginx` | Routes requests between frontend and backend |
| `litellm` | AI router with Gemini primary and Groq fallback |

---

## Before you start

### Costs and limits of the AI providers

Read this before choosing free or paid. These numbers were current in October 2026 and change often.

- **Each clothing photo uses at least 2 AI requests** (one for tags, one for the description). Retries add more.
- **The Gemini free tier allowed only 20 requests per day** for the Flash model. That is about 10 photos a day. When the limit is reached, Google returns `429 Too Many Requests` with a message like `Quota exceeded for metric: generate_content_free_tier_requests, limit: 20`.
- **On the free tier, Google may use your requests to improve its products.** Here that means photos of your clothes. The paid tier does not.
- **Gemini paid tier with Prepay** has a $5 minimum. Usage is taken from the prepaid balance, and when the balance reaches $0 the requests fail instead of charging more. Estimated cost is under $0.01 per photo, so $5 covers several hundred photos plus months of outfit suggestions.
- **Groq** has a free tier with its own limits. Check them in the Groq console under **Settings › Limits**.

!!! tip "Recommendation"
    Use Gemini on Prepay as the main model and the Groq free tier as the fallback. The free Gemini tier is fine for testing, but a first import of a whole wardrobe will hit the daily limit within minutes.

### Requirements

- Proxmox VE with a Debian 12 LXC template downloaded.
- An Authentik instance reachable over HTTPS.
- An existing Cloudflare Tunnel whose connector can reach the LXC's IP on the LAN.
- A Google account for Gemini and an account at [console.groq.com](https://console.groq.com).

---

## Step 1: Create the LXC

Run these on the **Proxmox host shell** (Datacenter › your node › **Shell**).

1. Check the exact name of your Debian 12 template:

    ```bash
    pveam list local
    ```

    Example output line: `local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst`

2. Create and start the container. Use the template name from step 1:

    ```bash
    pct create 150 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
      --hostname wardrowbe --cores 2 --memory 4096 --swap 1024 \
      --rootfs local-lvm:32 --unprivileged 1 --features nesting=1,keyctl=1 \
      --net0 name=eth0,bridge=vmbr0,ip=192.168.1.50/24,gw=192.168.1.1 \
      --onboot 1 --password
    pct start 150
    pct enter 150
    ```

    - `nesting=1,keyctl=1` lets Docker run inside an unprivileged LXC.
    - 4 GB of RAM is needed because background removal runs locally on the CPU.
    - `--password` asks you to set the container's root password.

---

## Step 2: Install Docker and set the time zone

Run these **inside the LXC**:

```bash
apt update && apt -y upgrade
apt -y install curl git openssl
curl -fsSL https://get.docker.com | sh
timedatectl set-timezone America/New_York
```

Set the time zone so the nightly backup in Step 12 runs at night in your time, not in UTC.

Check that Docker works:

```bash
docker run --rm hello-world
```

---

## Step 3: Get the nginx config from the release

The stack uses the nginx config that ships with Wardrowbe. Clone the release tag and copy only that folder:

```bash
mkdir -p /opt/wardrowbe
git clone --depth 1 --branch wardrowbe-v1.11.0 https://github.com/Anyesh/wardrowbe.git /tmp/wardrowbe-src
cp -r /tmp/wardrowbe-src/nginx /opt/wardrowbe/
ls /opt/wardrowbe/nginx
```

Expected output: `nginx.conf  templates`

---

## Step 4: Create the Docker Compose file

This file is based on the upstream `docker-compose.prod.yml`, with these changes:

- Image versions pinned through `WARDROWBE_VERSION` in `.env`.
- Log rotation on every container.
- OIDC settings required, so the app cannot start with the passwordless development login.
- A `litellm` service for the AI fallback.
- nginx listens on the LXC's LAN address so the existing tunnel connector can reach it.

Create the file:

```bash
cd /opt/wardrowbe
nano docker-compose.yml
```

Paste the following, then replace `192.168.1.50` in the nginx `ports` line with your LXC's IP.

Do not put any passwords or keys in this file. Every `${...}` value is read from the `.env` file you create in Step 7, so leave them exactly as written.

```yaml title="/opt/wardrowbe/docker-compose.yml"
name: wardrowbe

x-logging: &default-logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

x-backend-env: &backend-env
  PUID: ${PUID:-1000}
  PGID: ${PGID:-1000}
  DATABASE_URL: postgresql+asyncpg://${POSTGRES_USER:-wardrobe}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB:-wardrobe}
  REDIS_URL: redis://redis:6379
  SECRET_KEY: ${SECRET_KEY:?Set SECRET_KEY in .env}
  STORAGE_PATH: /data/uploads
  APP_URL: ${APP_URL:?Set APP_URL in .env}
  LOG_LEVEL: ${LOG_LEVEL:-INFO}
  AI_BASE_URL: ${AI_BASE_URL:?Set AI_BASE_URL in .env}
  AI_API_KEY: ${AI_API_KEY:?Set AI_API_KEY in .env}
  AI_VISION_MODEL: ${AI_VISION_MODEL:?Set AI_VISION_MODEL in .env}
  AI_TEXT_MODEL: ${AI_TEXT_MODEL:?Set AI_TEXT_MODEL in .env}
  AI_TIMEOUT: ${AI_TIMEOUT:-120}
  AI_MAX_RETRIES: ${AI_MAX_RETRIES:-3}
  AI_TAGGING_CONCURRENCY: ${AI_TAGGING_CONCURRENCY:-2}
  AI_REASONING_EFFORT: ${AI_REASONING_EFFORT-low}
  MAX_IMAGE_MEGAPIXELS: ${MAX_IMAGE_MEGAPIXELS:-50}
  # Optional notifications. Empty values fall back to the app defaults.
  SMTP_HOST: ${SMTP_HOST:-}
  SMTP_PORT: ${SMTP_PORT:-}
  SMTP_USER: ${SMTP_USER:-}
  SMTP_PASSWORD: ${SMTP_PASSWORD:-}
  SMTP_USE_TLS: ${SMTP_USE_TLS:-}
  SMTP_FROM_NAME: ${SMTP_FROM_NAME:-}
  SMTP_FROM_EMAIL: ${SMTP_FROM_EMAIL:-}
  NTFY_SERVER: ${NTFY_SERVER:-}
  NTFY_TOKEN: ${NTFY_TOKEN:-}

services:
  postgres:
    image: postgres:15-alpine
    container_name: wardrobe_postgres
    restart: unless-stopped
    logging: *default-logging
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-wardrobe}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD in .env}
      POSTGRES_DB: ${POSTGRES_DB:-wardrobe}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-wardrobe}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks: [wardrobe_net]

  redis:
    image: redis:7-alpine
    container_name: wardrobe_redis
    restart: unless-stopped
    logging: *default-logging
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks: [wardrobe_net]

  backend:
    image: ghcr.io/anyesh/wardrowbe:backend-${WARDROWBE_VERSION:?Set WARDROWBE_VERSION in .env}
    container_name: wardrobe_backend
    restart: unless-stopped
    logging: *default-logging
    environment:
      <<: *backend-env
      OIDC_ISSUER_URL: ${OIDC_ISSUER_URL:?Set OIDC_ISSUER_URL in .env}
      OIDC_CLIENT_ID: ${OIDC_CLIENT_ID:?Set OIDC_CLIENT_ID in .env}
      OIDC_CLIENT_SECRET: ${OIDC_CLIENT_SECRET:?Set OIDC_CLIENT_SECRET in .env}
      # Cloudflare Tunnel and nginx both sit in front of the API
      TRUSTED_PROXY_COUNT: ${TRUSTED_PROXY_COUNT:-2}
    volumes:
      - uploads_data:/data/uploads
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks: [wardrobe_net]

  worker:
    image: ghcr.io/anyesh/wardrowbe:backend-${WARDROWBE_VERSION}
    container_name: wardrobe_worker
    restart: unless-stopped
    logging: *default-logging
    command: arq app.workers.worker.WorkerSettings
    environment:
      <<: *backend-env
    volumes:
      - uploads_data:/data/uploads
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }
    networks: [wardrobe_net]

  image-worker:
    image: ghcr.io/anyesh/wardrowbe:backend-${WARDROWBE_VERSION}
    container_name: wardrobe_image_worker
    restart: unless-stopped
    logging: *default-logging
    command: arq app.workers.image_worker.ImageWorkerSettings
    environment:
      <<: *backend-env
      IMAGE_WORKER_CONCURRENCY: ${IMAGE_WORKER_CONCURRENCY:-1}
      BG_REMOVAL_PROVIDER: rembg
      BG_REMOVAL_MODEL: u2net
    volumes:
      - uploads_data:/data/uploads
      - rembg_models:/opt/rembg/models
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }
    networks: [wardrobe_net]

  frontend:
    image: ghcr.io/anyesh/wardrowbe:frontend-${WARDROWBE_VERSION}
    container_name: wardrobe_frontend
    restart: unless-stopped
    logging: *default-logging
    environment:
      PUID: ${PUID:-1001}
      PGID: ${PGID:-1001}
      NEXTAUTH_URL: ${APP_URL}
      NEXTAUTH_SECRET: ${NEXTAUTH_SECRET:?Set NEXTAUTH_SECRET in .env}
      BACKEND_URL: http://backend:8000
      OIDC_ISSUER_URL: ${OIDC_ISSUER_URL}
      OIDC_CLIENT_ID: ${OIDC_CLIENT_ID}
      OIDC_CLIENT_SECRET: ${OIDC_CLIENT_SECRET}
      OIDC_END_SESSION_URL: ${OIDC_END_SESSION_URL:-}
    depends_on: [backend]
    healthcheck:
      test: ["CMD", "node", "-e", "fetch('http://localhost:3000').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks: [wardrobe_net]

  nginx:
    image: nginx:alpine
    container_name: wardrobe_nginx
    restart: unless-stopped
    logging: *default-logging
    ports:
      # LAN address of this LXC, so the tunnel connector on another host can reach it
      - "192.168.1.50:8080:80"
    environment:
      NGINX_AI_TIMEOUT: ${NGINX_AI_TIMEOUT:-600}
      NGINX_CLIENT_MAX_BODY_SIZE: ${NGINX_CLIENT_MAX_BODY_SIZE:-50M}
      BACKEND_HOST: backend
      BACKEND_INTERNAL_PORT: 8000
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/templates:/etc/nginx/templates:ro
    command: >
      /bin/sh -c "envsubst '$${NGINX_AI_TIMEOUT} $${NGINX_CLIENT_MAX_BODY_SIZE} $${BACKEND_HOST} $${BACKEND_INTERNAL_PORT}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf && exec nginx -g 'daemon off;'"
    depends_on: [frontend, backend]
    networks: [wardrobe_net]

  litellm:
    image: ghcr.io/berriai/litellm:main-stable
    container_name: wardrobe_litellm
    restart: unless-stopped
    logging: *default-logging
    command: ["--config", "/app/config.yaml", "--port", "4000"]
    environment:
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY:?Set LITELLM_MASTER_KEY in .env}
      GEMINI_API_KEY: ${GEMINI_API_KEY:?Set GEMINI_API_KEY in .env}
      GROQ_API_KEY: ${GROQ_API_KEY:?Set GROQ_API_KEY in .env}
    volumes:
      - ./litellm/config.yaml:/app/config.yaml:ro
    networks: [wardrobe_net]

volumes:
  postgres_data:
  redis_data:
  uploads_data:
  rembg_models:

networks:
  wardrobe_net:
    driver: bridge
```

!!! warning "Indentation"
    YAML uses spaces only, never tabs. Each service name (`postgres:`, `litellm:`, and so on) has exactly **2** spaces in front of it, and its settings have **4**. If a service name gets 4 spaces, Compose reads it as part of the service above and fails with `mapping key "image" already defined`.

`litellm` has no `ports` entry on purpose. Only the other containers in the stack can reach it.

---

## Step 5: Create the LiteLLM config

LiteLLM gives Wardrowbe one model name, `wardrobe-ai`. Behind it, LiteLLM calls Gemini first and switches to Groq if Gemini fails.

```bash
mkdir -p /opt/wardrowbe/litellm
nano /opt/wardrowbe/litellm/config.yaml
```

```yaml title="/opt/wardrowbe/litellm/config.yaml"
model_list:
  - model_name: wardrobe-ai
    litellm_params:
      model: gemini/gemini-flash-latest
      api_key: os.environ/GEMINI_API_KEY
  - model_name: wardrobe-ai-fallback
    litellm_params:
      model: groq/qwen/qwen3.8-27b
      api_key: os.environ/GROQ_API_KEY
      additional_drop_params: ["logprobs", "top_logprobs"]

litellm_settings:
  num_retries: 1
  request_timeout: 90
  fallbacks: [{"wardrobe-ai": ["wardrobe-ai-fallback"]}]
  allowed_fails: 2
  cooldown_time: 60
  drop_params: true
```

What the settings do:

- `gemini-flash-latest` is an alias for Google's current Flash model, so the config keeps working when Google retires an older version.
- `qwen/qwen3.8-27b` was the vision-capable model on Groq in October 2026. Check [console.groq.com/docs/vision](https://console.groq.com/docs/vision) for the current one.
- `additional_drop_params` is **required** for Groq. Wardrowbe asks for `logprobs` when it tags a photo, and Groq rejects that field with `logprobs is not supported with this model`. Without this line, the fallback fails on every tagging request and items are saved as `type=unknown`.
- `fallbacks` sends a request to Groq when Gemini fails, including when Gemini is out of quota.
- `os.environ/GEMINI_API_KEY` and `os.environ/GROQ_API_KEY` tell LiteLLM to read the keys from its environment. Do not paste the keys into this file. They go into `.env` in Step 7.

---

## Step 6: Get the API keys

The `.env` file does not exist yet; you create it in Step 7. Save each key below somewhere safe as you create it, such as a password manager entry named **Wardrowbe**. You paste both keys into `.env` in Step 7.

Some providers show a key in full only once. If you lose it before Step 7, delete it and create a new one.

### Gemini

1. Go to [aistudio.google.com](https://aistudio.google.com).
2. On the welcome screen, choose **Develop with Gemini API** and click **Continue**.
3. Click **Create API key**. When asked for a project, choose **Create a new project**.
4. Copy the key and save it in your password manager as **Gemini API key**. It goes into `GEMINI_API_KEY` in Step 7. Do not paste it into chats, tickets, or screenshots.

To move from the free tier to Prepay:

1. In AI Studio, open the **Projects** page (or **Get API key**).
2. In your project's **Billing Tier** column, click **Set up billing**.
3. Choose or create a Google Cloud billing account and add a card.
4. Choose **Prepay** and buy **$5** of credit.
5. Check that the project's **Billing Tier** now shows **Tier 1**.

!!! note "Card hold"
    When the card is first added, Google may place a temporary authorization hold (for example $50) to verify it. It shows as **pending** on the card statement and drops off within about a week. Only the prepaid amount is charged.

!!! note "Welcome credit"
    New billing accounts may get Google Cloud welcome credit. It does **not** apply to the Gemini API. Gemini usage comes out of the Prepay balance.

Track spending in AI Studio under **Spend**, or in the **Monthly Spend** column of the Projects page.

### Groq

1. Go to [console.groq.com](https://console.groq.com) and sign in.
2. Open **API Keys** and click **Create API Key**.
3. Copy the key and save it in your password manager as **Groq API key**. It goes into `GROQ_API_KEY` in Step 7.
4. Check the free-tier limits for your vision model under **Settings › Limits**.

---

## Step 7: Create the `.env` file

The `.env` file holds every setting and secret for the stack. Values come from four places:

- **Already set** in the template below.
- **Generated now** with a command (items 4 and 5).
- **Saved earlier** in Step 6: the Gemini and Groq keys (item 6).
- **Added later** in Step 8: the four Authentik (OIDC) values. Authentik is not set up yet, so these lines stay empty until then.

| Variable | What it is | Where the value comes from |
|---|---|---|
| `WARDROWBE_VERSION` | Release to run | Already set (`1.11.0`) |
| `APP_URL` | Public address of the app | Already in the template. Change `wardrobe.example.com` to your hostname |
| `POSTGRES_USER`, `POSTGRES_DB` | Database user and database name | Already set (`wardrobe`) |
| `POSTGRES_PASSWORD` | Database password | **You generate it** (item 4 below) |
| `SECRET_KEY` | Backend key that signs sign-in tokens | **You generate it** (item 4) |
| `NEXTAUTH_SECRET` | Frontend key that encrypts browser sessions | **You generate it** (item 4) |
| `LITELLM_MASTER_KEY` | Password Wardrowbe uses to call LiteLLM | **You generate it** (item 5) |
| `AI_API_KEY` | The key Wardrowbe sends to LiteLLM | **Same value as** `LITELLM_MASTER_KEY` (item 5) |
| `GEMINI_API_KEY` | Google Gemini key | **Saved in Step 6.** Paste it in item 6 |
| `GROQ_API_KEY` | Groq key | **Saved in Step 6.** Paste it in item 6 |
| `OIDC_ISSUER_URL` | Authentik address for this app | **Added in Step 8.** Leave empty for now |
| `OIDC_END_SESSION_URL` | Authentik sign-out address | **Added in Step 8.** Leave empty for now |
| `OIDC_CLIENT_ID` | Authentik application ID | **Added in Step 8.** Leave empty for now |
| `OIDC_CLIENT_SECRET` | Authentik application secret | **Added in Step 8.** Leave empty for now |
| `AI_BASE_URL`, `AI_VISION_MODEL`, `AI_TEXT_MODEL`, `AI_REASONING_EFFORT` | Where Wardrowbe sends AI requests | Already set. Do not change |

The generated values are random strings that nobody types or remembers. They only have to be long, random, and different from each other. `openssl rand -hex 32` produces 64 random characters.

1. Create the file and lock its permissions, since it holds every secret for the stack:

    ```bash
    cd /opt/wardrowbe
    touch .env && chmod 600 .env
    nano .env
    ```

2. Paste this template. Change `wardrobe.example.com` in `APP_URL` to your hostname. Leave every empty value empty: items 4 to 6 fill the secrets and keys, and Step 8 fills the OIDC lines.

    ```ini title="/opt/wardrowbe/.env"
    # Release to run. Upgrade by changing this, then follow "Upgrades".
    WARDROWBE_VERSION=1.11.0

    APP_URL=https://wardrobe.example.com

    POSTGRES_USER=wardrobe
    POSTGRES_DB=wardrobe
    POSTGRES_PASSWORD=
    SECRET_KEY=
    NEXTAUTH_SECRET=

    # Authentik (OIDC). Added in Step 8. Leave empty for now.
    OIDC_ISSUER_URL=
    OIDC_END_SESSION_URL=
    OIDC_CLIENT_ID=
    OIDC_CLIENT_SECRET=

    # Wardrowbe talks only to LiteLLM. AI_API_KEY must equal LITELLM_MASTER_KEY.
    AI_BASE_URL=http://litellm:4000/v1
    AI_API_KEY=
    AI_VISION_MODEL=wardrobe-ai
    AI_TEXT_MODEL=wardrobe-ai
    AI_REASONING_EFFORT=low

    # LiteLLM and the provider keys
    LITELLM_MASTER_KEY=
    GEMINI_API_KEY=
    GROQ_API_KEY=

    # ===================== OPTIONAL =====================
    # Everything below is commented out. To use a block, remove the "# "
    # from its NAME=value lines only, fill the values, then run:
    # docker compose up -d

    # ---- Optional: email notifications -----------------
    # Port 587 with STARTTLS. Wardrowbe cannot use port 465 (implicit TLS).
    # The From address must be one the SMTP login is allowed to send as.
    # SMTP_HOST=mail.example.com
    # SMTP_PORT=587
    # SMTP_USE_TLS=true
    # SMTP_USER=notifications@example.com
    # SMTP_PASSWORD=
    # SMTP_FROM_NAME=Wardrowbe
    # SMTP_FROM_EMAIL=notifications@example.com

    # ---- Optional: ntfy push notifications -------------
    # Default server offered when a user adds an ntfy channel in the app.
    # NTFY_SERVER=https://ntfy.sh
    # NTFY_TOKEN=

    # ---- Optional: AI alternative, Groq only (free tier) ---
    # Sends AI requests straight to Groq and skips LiteLLM, so there is
    # no fallback. To use it, put "# " in front of the five AI_ lines in
    # the LiteLLM section above, then uncomment these.
    # In this block the API key is your Groq key, not the LiteLLM key.
    # AI_BASE_URL=https://api.groq.com/openai/v1
    # AI_API_KEY=
    # AI_VISION_MODEL=qwen/qwen3.8-27b
    # AI_TEXT_MODEL=qwen/qwen3.8-27b
    # AI_REASONING_EFFORT=

    # ---- Optional: tuning -------------------------------
    # Seconds to wait for one AI reply
    # AI_TIMEOUT=120
    # Photos tagged at the same time
    # AI_TAGGING_CONCURRENCY=2
    # Set to DEBUG while troubleshooting
    # LOG_LEVEL=INFO
    ```

    Lines starting with `#` are ignored. The checks and commands in this step only touch lines that are **not** commented out.

    To turn on an optional block later, remove `# ` only from the lines that look like `NAME=value`. Leave the description lines above them commented.

3. Save and close nano: press ++ctrl+o++, ++enter++, then ++ctrl+x++.

4. **Generate the database password and the two app secrets.** This writes a different random value into each of the three empty lines:

    ```bash
    cd /opt/wardrowbe
    for v in POSTGRES_PASSWORD SECRET_KEY NEXTAUTH_SECRET; do
      sed -i "s|^$v=$|$v=$(openssl rand -hex 32)|" .env
    done
    ```

    To do it by hand instead, run `openssl rand -hex 32` three times and paste each result after `POSTGRES_PASSWORD=`, `SECRET_KEY=`, and `NEXTAUTH_SECRET=` with `nano .env`.

    !!! warning "Set the database password before the first start"
        PostgreSQL saves `POSTGRES_PASSWORD` only when the database is first created. Changing it in `.env` later does not change the real password, and the backend can no longer connect. Generate it once, now, and leave it.

5. **Generate the LiteLLM key and copy it into `AI_API_KEY`.** Both lines must hold the **same** value: LiteLLM requires it on every request, and Wardrowbe sends `AI_API_KEY` as that key. LiteLLM keys start with `sk-`.

    ```bash
    cd /opt/wardrowbe
    MASTER="sk-$(openssl rand -hex 24)"
    sed -i -e "s|^LITELLM_MASTER_KEY=$|LITELLM_MASTER_KEY=$MASTER|" \
           -e "s|^AI_API_KEY=$|AI_API_KEY=$MASTER|" .env
    unset MASTER
    ```

6. **Paste the provider keys you saved in Step 6.** Open `nano .env` and paste the Gemini key after `GEMINI_API_KEY=` and the Groq key after `GROQ_API_KEY=`. No quotes and no spaces around `=`.

7. **Check the file.** This shows only the first 4 characters of each value, so no secret appears on screen:

    ```bash
    grep -E '^[A-Z_]+=' /opt/wardrowbe/.env | sed -E 's/=(.{4}).+/=\1****/'
    ```

    List any value that is still empty:

    ```bash
    grep -E '^[A-Z_]+=$' /opt/wardrowbe/.env
    ```

    At this point it should print exactly these four lines, which Step 8 fills in:

    ```
    OIDC_ISSUER_URL=
    OIDC_END_SESSION_URL=
    OIDC_CLIENT_ID=
    OIDC_CLIENT_SECRET=
    ```

    Any other line in the output is a value you still need to set.

    Confirm the two LiteLLM lines match:

    ```bash
    cd /opt/wardrowbe
    [ "$(grep '^AI_API_KEY=' .env | cut -d= -f2-)" = "$(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)" ] && echo MATCH || echo "DIFFERENT - fix before starting"
    ```

Never paste the contents of `.env` into a chat, ticket, or screenshot. If a key leaks, create a new one at the provider and replace it here.

Notes:

- `AI_REASONING_EFFORT=low`: Gemini 3 models cannot turn their reasoning off, so the upstream default of `none` does not apply. `low` keeps responses fast and cheap.
- Do not use **Settings › AI Endpoints** inside the Wardrowbe app for a fallback. Endpoints added there have no API key field and reuse the server's `AI_API_KEY`, they are stored per user, and they are tried before the server default. LiteLLM handles fallback for every user in one place.

---

## Step 8: Configure Authentik (OIDC)

This step creates the Authentik application and then fills the four empty OIDC lines in `.env` from Step 7.

Every person who uses Wardrowbe gets their own private wardrobe the first time they sign in. Joining a "family" inside the app is optional and only adds sharing between members.

### Create the access group

1. Open the Authentik **Admin interface**.
2. Go to **Directory › Groups** and click **Create**.
3. Name it `wardrobe-users` and click **Create**.
4. Open the group, go to the **Users** tab, click **Add existing user**, and add everyone who should use the app.

### Create the application and provider

1. Go to **Applications › Applications** and click **Create with provider**.
2. **Application** screen:
    - **Name:** `Wardrowbe`
    - **Slug:** `wardrowbe`
    - **Launch URL:** `https://wardrobe.example.com`
3. **Choose a Provider:** **OAuth2/OpenID Provider**.
4. **Configure Provider** screen:

    | Field | Value |
    |---|---|
    | Authorization flow | `default-provider-authorization-implicit-consent` |
    | Client type | **Confidential** |
    | Client ID / Client Secret | Copy both. They go into `.env` at the end of this step |
    | Redirect URIs | **Strict**, `https://wardrobe.example.com/api/auth/callback/oidc` |
    | Signing key | `authentik Self-signed Certificate` |
    | Encryption key | Leave empty |
    | Subject mode | **Based on the User's hashed ID** (the default) |
    | Include claims in id_token | On (the default) |
    | Issuer mode | Each provider has a different issuer (the default) |

    Why these matter:

    - **Encryption key empty:** selecting one turns on encrypted tokens (JWE), which Wardrowbe's sign-in library does not decrypt.
    - **Subject mode on hashed ID:** Wardrowbe links each account to this value. If it were based on email or username and that changed later, the person would land in a new, empty wardrobe.

5. **Configure Bindings:** **Bind existing policy/group/user** › **Group** › `wardrobe-users`.
6. Click **Submit**.

### Check the issuer from the LXC

This also proves the containers can reach Authentik:

```bash
curl -s --max-time 10 https://auth.example.com/application/o/wardrowbe/.well-known/openid-configuration \
  | grep -o '"issuer": *"[^"]*"'
```

Expected output:

```
"issuer": "https://auth.example.com/application/o/wardrowbe/"
```

### Put the Authentik values into `.env`

1. Open the file:

    ```bash
    nano /opt/wardrowbe/.env
    ```

2. Fill in the four empty OIDC lines:

    | Line | Value |
    |---|---|
    | `OIDC_ISSUER_URL=` | The exact issuer printed above, including the trailing slash: `https://auth.example.com/application/o/wardrowbe/` |
    | `OIDC_END_SESSION_URL=` | The issuer with `end-session/` added: `https://auth.example.com/application/o/wardrowbe/end-session/` |
    | `OIDC_CLIENT_ID=` | The Client ID from the provider |
    | `OIDC_CLIENT_SECRET=` | The Client Secret from the provider |

    If you did not copy the Client ID and Secret, open **Applications › Providers**, click the Wardrowbe provider, then **Edit**. Both are on that form.

3. Save, then confirm nothing is left empty:

    ```bash
    grep -E '^[A-Z_]+=$' /opt/wardrowbe/.env
    ```

    Expected: no output. Every value in `.env` is now set, and the stack is ready to start.

---

## Step 9: Start the stack

```bash
cd /opt/wardrowbe
docker compose config --quiet && echo VALID
docker compose pull
docker compose up -d
sleep 30
docker compose exec backend alembic upgrade head
docker compose restart worker image-worker
```

- `docker compose config --quiet` checks the YAML and the `.env` values before anything starts. Fix any error it prints before going on.
- `alembic upgrade head` creates the database tables. Until it runs, the workers restart in a loop because the tables do not exist yet.

Check the containers and the health endpoint:

```bash
docker compose ps
curl -s http://192.168.1.50:8080/health
```

Expected: every container `running` or `healthy`, and `{"status":"healthy"}` from curl.

### Test both AI routes through LiteLLM

The command reads the LiteLLM key from `.env` without printing it:

```bash
cd /opt/wardrowbe
K=$(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)
for m in wardrobe-ai wardrobe-ai-fallback; do
  echo "== $m"
  docker compose exec -T backend curl -s --max-time 60 -w '\nHTTP %{http_code}\n' \
    -H "Authorization: Bearer $K" -H "Content-Type: application/json" \
    http://litellm:4000/v1/chat/completions \
    -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with OK\"}]}" | cut -c1-200
done
unset K
```

Expected: `HTTP 200` and `"content":"OK"` for both models. A Gemini reply contains `thought_signatures`, and a Groq reply contains `system_fingerprint`, so you can tell which provider answered.

Then prove the Groq fallback accepts a tagging-style request, which includes `logprobs`:

```bash
K=$(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)
docker compose exec -T backend curl -s --max-time 60 -w '\nHTTP %{http_code}\n' \
  -H "Authorization: Bearer $K" -H "Content-Type: application/json" \
  http://litellm:4000/v1/chat/completions \
  -d '{"model":"wardrobe-ai-fallback","logprobs":true,"top_logprobs":3,"messages":[{"role":"user","content":"Reply with OK"}]}' | cut -c1-200
unset K
```

Expected: `HTTP 200`. An `HTTP 400` with `logprobs is not supported` means the `additional_drop_params` line is missing from `config.yaml`.

If nothing prints at all, LiteLLM is still starting. Run `docker compose logs --tail=20 litellm`, wait for `Uvicorn running on http://0.0.0.0:4000`, and test again.

---

## Step 10: Publish through the existing Cloudflare Tunnel

The tunnel connector already runs on another host, so add a route to it instead of creating a new tunnel.

1. From the host that runs the tunnel connector, confirm it can reach the LXC:

    ```bash
    curl -s --max-time 5 http://192.168.1.50:8080/health
    ```

    Expected: `{"status":"healthy"}`. A timeout means a firewall between the two hosts blocks port 8080.

2. In the Cloudflare dashboard, go to **Zero Trust › Networks › Tunnels** (some dashboards call it **Networks › Connectors**).
3. Click your tunnel › **Configure** › **Public Hostname** tab (or **Published application routes**) › **Add a public hostname**.
4. Fill in:
    - **Subdomain:** `wardrobe`
    - **Domain:** `example.com`
    - **Path:** empty
    - **Service type:** `HTTP`
    - **URL:** `192.168.1.50:8080`
5. Click **Save**. Cloudflare creates the DNS record.

!!! warning "No second login in front"
    Do not put Cloudflare Access or Pangolin resource authentication in front of this hostname. Authentik already protects the app, a second login gets in the way, and the Wardrowbe mobile app cannot pass through it.

If your LAN DNS server holds a local zone for the same domain (split-horizon), add a record for `wardrobe.example.com` there too, or the name will not resolve on the LAN.

---

## Step 11: First sign-in and a test photo

1. Open `https://wardrobe.example.com` and click **Get Started**. You land on Authentik, sign in, and return to the Wardrowbe dashboard.
2. Before uploading, watch the worker on the LXC:

    ```bash
    docker compose -f /opt/wardrowbe/docker-compose.yml logs -f worker \
      | grep -i -E 'successful via|analysis complete|429|error'
    ```

3. In the app, click **Wardrobe** and add one item with a photo.
4. Within about 30 seconds the log shows a line like:

    ```
    AI analysis complete for item ...: type=shirt, color=blue
    ```

    Press ++ctrl+c++ to stop watching.

5. On the dashboard, click **Get Outfit Suggestion** once you have a few items (a top, a bottom, and shoes). This tests the text side of the AI.

### Using it from a phone

There is an iOS app. For Android (no app yet), use the web app:

1. Open Chrome on the phone and go to `https://wardrobe.example.com`.
2. Sign in through Authentik.
3. Tap **⋮** › **Add to home screen** › **Add**.
4. To add clothes, open **Wardrobe**, add an item, and tap the photo field. Android offers **Camera** or **Files**.

---

## Step 12: Backups

Wardrowbe keeps data in two places: the PostgreSQL database (items, tags, outfits, users) and the uploads volume (the photos). Back up both, every night.

1. Create the backup script:

    ```bash
    nano /opt/wardrowbe/backup.sh
    ```

    ```bash title="/opt/wardrowbe/backup.sh"
    #!/usr/bin/env bash
    # Nightly Wardrowbe backup: database dump + uploaded photos.
    set -euo pipefail

    APP_DIR=/opt/wardrowbe
    DEST=/opt/wardrowbe/backups
    KEEP_DAYS=14
    STAMP=$(date -u +%Y%m%dT%H%M%SZ)

    mkdir -p "$DEST"
    cd "$APP_DIR"

    echo "[$STAMP] Dumping database"
    docker compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' \
      | gzip > "$DEST/db-$STAMP.sql.gz"

    echo "[$STAMP] Archiving uploads"
    docker run --rm \
      -v wardrowbe_uploads_data:/data:ro \
      -v "$DEST":/backup \
      alpine tar czf "/backup/uploads-$STAMP.tar.gz" -C /data .

    echo "[$STAMP] Pruning backups older than $KEEP_DAYS days"
    find "$DEST" -type f \( -name 'db-*.sql.gz' -o -name 'uploads-*.tar.gz' \) -mtime +"$KEEP_DAYS" -delete

    echo "[$STAMP] Done"
    ```

2. Make it executable, run it once, and schedule it for 2:15 AM:

    ```bash
    chmod 700 /opt/wardrowbe/backup.sh
    /opt/wardrowbe/backup.sh
    (crontab -l 2>/dev/null; echo "15 2 * * * /opt/wardrowbe/backup.sh >> /var/log/wardrowbe-backup.log 2>&1") | crontab -
    ```

3. Check that the backup is not empty:

    ```bash
    zcat /opt/wardrowbe/backups/db-*.sql.gz | grep -c 'CREATE TABLE'
    tar tzf /opt/wardrowbe/backups/uploads-*.tar.gz | head
    crontab -l | grep backup.sh
    ```

    Expected: a table count above 10 (21 on version 1.11.0), a list of photo files ending in `.jpg`, and the cron line.

4. Add the LXC to your Proxmox Backup Server job. `backup.sh` does not cover `.env`, `docker-compose.yml`, or `litellm/config.yaml`, and the backups it writes sit on the same container. The Proxmox backup gets all of it off the host.

Run the first backup right away, before there is real data. A backup script that has never run is not a backup.

---

## Step 13: Pin the LiteLLM image

`main-stable` moves to a new release over time. Once everything works, pin the exact image you tested, by digest:

1. Record the version and the digest:

    ```bash
    cd /opt/wardrowbe
    docker compose exec litellm python -c "import importlib.metadata as m; print('litellm', m.version('litellm'))"
    docker image inspect ghcr.io/berriai/litellm:main-stable --format '{{index .RepoDigests 0}}'
    ```

2. Write the digest into the compose file:

    ```bash
    DIGEST=$(docker image inspect ghcr.io/berriai/litellm:main-stable --format '{{index .RepoDigests 0}}')
    sed -i "s|image: ghcr.io/berriai/litellm:main-stable|image: $DIGEST|" docker-compose.yml
    grep -n 'berriai/litellm' docker-compose.yml
    unset DIGEST
    ```

    Expected: `image: ghcr.io/berriai/litellm@sha256:...`

3. Add a comment above that line with the version from step 1, for example `# litellm 1.x.y, pinned 2026-10-16`.
4. Apply it:

    ```bash
    docker compose config --quiet && docker compose up -d litellm
    ```

---

## Optional: email and push notifications

Wardrowbe can send outfit reminders and other notices by email or through [ntfy](https://ntfy.sh). Both are off until you turn them on in `.env`.

### Email

1. Check that the LXC can reach your mail server's **submission port 587** with STARTTLS:

    ```bash
    timeout 8 openssl s_client -starttls smtp -connect mail.example.com:587 -brief </dev/null 2>&1 | head -3
    ```

    Expected: `CONNECTION ESTABLISHED`. If the connection is refused or times out, the mail server does not offer port 587 to this network. Wardrowbe only sends with STARTTLS, so a server that only offers port 465 (implicit TLS) will not work. Publish or allow port 587 on the mail server first.

2. In `/opt/wardrowbe/.env`, go to the **Optional: email notifications** block. Remove the `# ` from the seven `SMTP_...=` lines (not from the two description lines above them) and fill them in:
    - `SMTP_USER` and `SMTP_PASSWORD`: the mailbox login. Use an app password if your mail server supports them.
    - `SMTP_FROM_EMAIL`: an address that `SMTP_USER` is allowed to send as. Most servers reject other senders.

3. Recreate the containers so they read the new values:

    ```bash
    cd /opt/wardrowbe && docker compose up -d
    ```

4. In Wardrowbe, open **Notifications** in the left menu and add an **Email** channel.

If nothing arrives, check the worker log:

```bash
docker compose -f /opt/wardrowbe/docker-compose.yml logs --since 10m worker | grep -i -E 'smtp|email'
```

### ntfy push

1. In `/opt/wardrowbe/.env`, uncomment `NTFY_SERVER` (and `NTFY_TOKEN` if your ntfy server needs one).
2. Run `docker compose up -d`.
3. In Wardrowbe, open **Notifications** and add an **ntfy** channel with a topic name, then subscribe to the same topic in the ntfy phone app.

---

## Upgrades

### Wardrowbe

Replace the images first, then migrate the database inside the new backend. Old code must never run against a migrated database.

```bash
cd /opt/wardrowbe
./backup.sh
nano .env            # change WARDROWBE_VERSION to the new release, e.g. 1.12.0
docker compose pull
docker compose up -d
docker compose exec backend alembic upgrade head
```

Keep the backup file. A downgrade after a migration loses data, so restoring the backup is the way back. Read the release notes at [github.com/Anyesh/wardrowbe/releases](https://github.com/Anyesh/wardrowbe/releases) before each upgrade.

If you change the release, also refresh the nginx config from the same tag (Step 3).

### LiteLLM

1. Run `./backup.sh`.
2. Put `main-stable` back on the litellm image line and run `docker compose pull litellm && docker compose up -d litellm`.
3. Run the AI route tests from Step 9.
4. Pin the new digest (Step 13).

LiteLLM stores no data in this stack, so rolling back is putting the old digest back.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `docker compose` fails with `mapping key "image" already defined` | A service name is indented with 4 spaces, so Compose merges it into the service above | Open the file at the line numbers in the error. Service names need exactly 2 spaces in front, and tabs are not allowed. See the command below the table |
| Items saved as `type=unknown, color=None` | The tagging request failed and only the description step worked | Check the worker log. Usually one of the next two rows. Then open the item and run its re-analyze option |
| LiteLLM log: `Quota exceeded for metric: generate_content_free_tier_requests, limit: 20` | Gemini free tier used up for the day | Wait for the reset (the error says how long), or move the key's project to Prepay (Step 6). Groq covers requests in the meantime |
| LiteLLM log: `Fallback to wardrobe-ai-fallback also failed ... logprobs is not supported` | Groq rejects the `logprobs` field Wardrowbe sends when tagging | Add `additional_drop_params: ["logprobs", "top_logprobs"]` under the Groq model in `config.yaml`, then `docker compose restart litellm` |
| Worker log: occasional `429 Too Many Requests` during a bulk upload, but items still finish | Provider per-minute limit, usually on the free Groq tier | Nothing to fix. Wardrowbe retries. Upload large batches in smaller groups |
| Worker log: `All connection attempts failed` for `http://litellm:4000` | LiteLLM is restarting or not running | `docker compose ps litellm` and `docker compose logs --tail=30 litellm` |
| Test calls through LiteLLM print nothing right after `up -d` | LiteLLM takes longer than 20 to 30 seconds to start the first time | Wait for `Uvicorn running on http://0.0.0.0:4000` in its log |
| Sign-in loops or shows an OIDC error | `APP_URL` does not match the hostname in the browser, or the Authentik redirect URI uses a different hostname | `APP_URL` and the redirect URI must both use the exact public hostname. After changing `.env`, run `docker compose up -d` |
| A change in `.env` has no effect | Containers read `.env` only when they are created | `docker compose up -d` recreates changed containers. A plain `restart` does not reload `.env` |
| Workers restart in a loop right after the first start | Database tables do not exist yet | `docker compose exec backend alembic upgrade head`, then `docker compose restart worker image-worker` |
| `curl http://192.168.1.50:8080/health` works on the LXC but times out from the tunnel host | A firewall between the hosts blocks 8080 | Allow TCP 8080 from the tunnel host to the LXC |

### Show indentation in the compose file

Replace `198,222` with a range around the line numbers in the error:

```bash
nl -ba /opt/wardrowbe/docker-compose.yml | sed -n '198,222p' | cat -A | cut -c1-70
```

Each line ends in `$`. The `^I` right after the line number comes from `nl`, not from the file. Any other `^I` is a tab in the file and must be replaced with spaces.

### Which provider served a request

```bash
cd /opt/wardrowbe
docker compose logs --since 10m worker | grep -i 'successful via'
docker compose logs --since 10m litellm | grep -i -E 'fallback|exception' | tail -10
```

`successful via default (model: wardrobe-ai)` means Gemini answered. A Groq model name, such as `qwen/qwen3.8-27b`, means the fallback answered.
