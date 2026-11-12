# Postfix "Not Allowed in State 1" / DNS Resolution Failure

## Symptom

- SOGo webmail shows a red/orange full-screen error: **"not allowed in state 1"** when trying to send, receive, or otherwise interact with mail.
- Sending and receiving both fail.
- `docker compose ps` shows `postfix-mailcow` with an unusually low uptime compared to other containers (e.g. "Up 28 seconds" while everything else is "Up 10 days"), or shows it repeatedly restarting.

This SOGo error is generic — it just means the webmail frontend lost its connection to the backend. It does not point directly at the cause; you have to look at the container stack.

## Diagnosis Steps

**1. Check container health/uptime**

```bash
cd /opt/mailcow-dockerized
docker compose ps
```

Look for any container with a much shorter uptime than the rest, or one stuck in a restart loop.

**2. Check the flaky container's logs**

```bash
docker compose logs --tail=100 postfix-mailcow
```

If you see repeated:

```
Waiting for DNS...
REDIS server error during connection; ... error='Temporary failure in name resolution'
```

— the container cannot resolve other containers' hostnames (e.g. `redis-mailcow`, `unbound-mailcow`) on the internal Docker network. This is a **networking** problem, not a mail config problem.

**3. Check watchdog logs**

```bash
docker compose logs --tail=100 watchdog-mailcow | grep -i postfix
```

Watchdog will report declining health levels for postfix / postfix-tlspol when the container can't be reached properly — this is a symptom of the same root cause, not a separate issue.

## Root Cause Chain (what actually happened)

1. A host-level **Postfix** (preinstalled by the VPS provider, e.g. Contabo) was bound to port 25, blocking the mailcow `postfix-mailcow` container from rebinding after a restart:
   ```
   Error response from daemon: failed to set up container networking:
   driver failed programming external connectivity on endpoint ...:
   failed to bind host port 0.0.0.0:25/tcp: address already in use
   ```
2. Next, the conflicting host Postfix was stopped and disabled. But the mailcow `postfix-mailcow` container still did not start correctly. This time, it was **fully disconnected from the mailcow Docker network**. `docker inspect` showed this: `"NetworkSettings.Networks": {}` (empty).
3. Without a network, it could not reach `unbound-mailcow` (the internal DNS resolver of mailcow, usually at a fixed IP like `172.22.1.254`). Thus, each internal hostname lookup (`redis-mailcow`, and others) failed, and postfix could not fully start.

## Fix

**Check for a conflicting host-level mail service:**

```bash
sudo ss -tulnp | grep :25
```

If it shows a process other than the mailcow postfix container (e.g. `master` — Postfix's own daemon name) holding port 25:

```bash
systemctl status postfix
sudo systemctl stop postfix
sudo systemctl disable postfix
```

**Check whether the mailcow postfix container is actually attached to the network:**

```bash
docker inspect mailcowdockerized-postfix-mailcow-1 --format '{{json .NetworkSettings.Networks}}' | python3 -m json.tool
```

- `{}` (empty) = not attached to any network — this is the bug.
- Compare against a known-good container, e.g.:
  ```bash
  docker inspect mailcowdockerized-unbound-mailcow-1 --format '{{json .NetworkSettings.Networks}}' | python3 -m json.tool
  ```

**Manually reattach it (non-disruptive, worth trying first):**

```bash
docker network connect mailcowdockerized_mailcow-network mailcowdockerized-postfix-mailcow-1
```

This can get things working temporarily, but in practice the cleanest and most reliable fix is a full stack cycle:

**Full fix — recreate the whole stack:**

```bash
cd /opt/mailcow-dockerized
docker compose down
docker compose up -d
```

This forces Docker to rebuild the mailcow network and reattach every container correctly, rather than trying to patch one container's network membership by hand.

## Verification

```bash
docker compose ps postfix-mailcow
```

- Uptime should climb steadily without resetting (check again after a few minutes).
- Ports `0.0.0.0:25`, `0.0.0.0:465`, `0.0.0.0:587` should be listed and bound.

```bash
docker compose logs --tail=30 postfix-mailcow
```

- Should show `starting the Postfix mail system` / `daemon started` with no repeated `Waiting for DNS...` lines afterward.

Then confirm actual mail flow: send a test email from SOGo to an external address (e.g. Gmail), and send one back in to confirm inbound delivery too — send and receive exercise different paths (submission vs. inbound SMTP) and can fail independently.

## Notes / Lessons Learned

- The SOGo "not allowed in state 1" screen does not help you by itself. Always go directly to `docker compose ps` and the container logs. Do not troubleshoot from the SOGo side.
- VPS providers (Contabo included) sometimes ship a host-level Postfix preinstalled for system mail (cron notices, etc.). This silently conflicts with mailcow's own postfix container on port 25 and won't show up unless you specifically check `ss -tulnp`.
- If a container shows an empty `NetworkSettings.Networks` after a `docker network connect` or restart, you must remove and create the Docker network again (`docker compose down && up -d`). Do not repair one container at a time.
- The server ran mailcow version **2026-03b** at that time (four releases behind 2026-07). Read the changelog between versions, because updates often repair network-attachment bugs like this.