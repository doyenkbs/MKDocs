# **<span style="color:#009688;">Cloudflare Overview</span>**

**Cloudflare** is a global network that provides security, performance, and reliability services to websites, APIs, and internet applications.

In the context of a **home lab**, Cloudflare offers a variety of free tools used throughout this lab:

- **DNS Management** – Host and manage your domain's DNS records with fast propagation and built-in security.
- **DDoS Protection** – Protects your services from denial-of-service attacks.
- **Cloudflare Tunnels** (formerly *Argo Tunnel*) – Securely connect your local services to the internet without exposing your public IP.
- **Zero Trust Access** – Control and secure access to applications using identity-based authentication and policy enforcement.

---

## <span style="color:#009688;">In This Section</span>

<div class="grid cards" markdown>

-   :material-information-outline: **Overview** *(this page)*

    ---

    Account setup, domain onboarding, and why Cloudflare Tunnel fits a home lab.

-   :material-tunnel: **Cloudflare Tunnel**

    ---

    Step-by-step setup: create a tunnel, install `cloudflared`, and publish a local service publicly.

    [:octicons-arrow-right-24: Start here](cloudflaretunnel.md)

-   :material-shield-lock-outline: **Cloudflare Access**

    ---

    Layer Zero Trust authentication in front of tunneled apps, integrated with Authentik SSO.

    [:octicons-arrow-right-24: Start here](cloudflareaccess.md)

</div>

---

## <span style="color:#009688;">Why Use Cloudflare Tunnel in a Home Lab?</span>

With **Cloudflare Tunnel**, you can securely expose local services — like Nextcloud, Bookstack, or Audiobookshelf — to the internet:

- No need for **port forwarding**
- Your **public IP remains hidden**
- Encrypted connections from client to Cloudflare's network
- Works behind CGNAT or restrictive ISPs

---

**Example Use Case:**
Run Bookstack in the home lab and access it remotely via `https://wiki.example.com` through Cloudflare Tunnel, without opening any ports on the firewall.

---

## <span style="color:#009688;">Pairing With Authentik</span>

Cloudflare Tunnel handles *reachability* — getting a request from the internet to a local service safely. It doesn't handle *who's allowed in*. That's where [Cloudflare Access](cloudflareaccess.md) comes in, paired with [Authentik](../application/authentik.md) as the identity provider:

- Authentik enforces SSO and MFA in front of every tunneled app
- Access policy is centralized in one place instead of configured per-service
- See the full walkthrough on the [Cloudflare Access + Authentik Integration](../application/cloudflareaccess.md) page

This is the pattern used across most of the self-hosted apps in this lab: **Tunnel for reachability, Access + Authentik for identity.**

---

## <span style="color:#009688;">Create a Cloudflare Account</span>

1. Go to <https://dash.cloudflare.com/sign-up>
2. Enter your **email address** and create a **password**.
3. Click **Create Account**.
4. Verify your email address by clicking the link sent to your inbox.

---

## <span style="color:#009688;">Add Your Domain and Transfer DNS to Cloudflare</span>

1. In the Cloudflare dashboard, click **Onboard a domain**.

2. Enter your domain name (e.g., `example.com`) and click **Continue**.

3. Select the **Free Plan** (recommended for home lab use) or another plan if you need additional features.

4. Cloudflare will automatically scan and import your existing DNS records:
   - **Review the imported DNS records** carefully.
   - Ensure they match your current DNS provider's records.
   - Click **Continue to activation**

5. Cloudflare will provide **two new nameservers** (e.g., `abby.ns.cloudflare.com` and `damon.ns.cloudflare.com`).

6. Log in to your **domain registrar** (e.g., Namecheap, GoDaddy, Google Domains).

7. Replace your registrar's existing nameservers with the **Cloudflare-provided nameservers**.

8. Save the changes and allow up to 24 hours for DNS propagation (often completes in minutes).

⏱️ Once propagation is complete, Cloudflare will manage your domain's DNS and provide security and performance benefits.

!!! note
    You can skip the step above if Cloudflare is your domain registrar.

---

## <span style="color:#009688;">Next Steps</span>

Once your domain is on Cloudflare:

1. Set up [Cloudflare Tunnel](cloudflaretunnel.md) to publish your first local service.
2. Layer [Cloudflare Access + Authentik](cloudflareaccess.md) on top for identity-based access control.

!!! tip "Running a local DNS resolver too?"
    If you're also running a local DNS server (e.g. Technitium) for internal name resolution, be careful about creating zones that shadow your public Cloudflare-managed records — an authoritative local zone with an incomplete record set (e.g. missing an MX record) can silently break external services like outbound mail even though DNS otherwise "looks fine" locally.