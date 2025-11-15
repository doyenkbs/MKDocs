---
tags:
  - Cloudflare Access
---

# **<span style="color:#009688;">Cloudflare Access + Authentik (OIDC) Integration</span>**

This guide walks you through integrating **<span style="color:#009688;">Cloudflare Access</span>** with **<span style="color:red;">Authentik</span>** using **OpenID Connect (OIDC)** so your Cloudflare-protected apps use Authentik for SSO/MFA.

---
## **Overview**

**<span style="color:#009688;">Cloudflare Access** is Cloudflare's zero-trust access solution, sitting in front of your web apps and enforcing per-user authentication and policy.  
**Authentik** is a self-hosted identity provider that supports OIDC, SAML, LDAP, and more. By connecting Authentik and <span style="color:#009688;">Cloudflare Access</span>, you gain:

- SSO for your protected applications via Authentik accounts
- Policy-based user access management
- Easy onboarding/offboarding

!!! info "**Prerequisites**"
    - An **Authentik** instance you manage (admin access).
    - A **<span style="color:#009688;">Cloudflare Zero Trust** account with your **team domain** (example: `https://<team>.cloudflareaccess.com`). You can find your team name in **Zero Trust → Settings → Custom Pages**.
    - Optional but recommended: Your apps published behind **Cloudflare Tunnels**.

    !!! note "**Why:**" 
        <span style="color:#009688;">Cloudflare Access</span> sits in front of your apps. <span style="color:red;">Authentik</span> verifies users, while Cloudflare enforces access rules.

---

## **Step 1 — Create an OIDC Provider in Authentik**

1. In **<span style="color:red;">Authentik</span>**, go to **Applications → Providers → Create → OAuth2/OIDC**.  
2. Set a clear **Name** and a unique **Slug** (ex: `cloudflare`).  
3. Choose a **Signing Key** (recommended).  
4. Under **Redirect URIs**, add (strict): `https://<your-team-name>.cloudflareaccess.com/cdn-cgi/access/callback`
5. Select scopes: **openid**, **email**, **profile** (and optionally **groups**).  
6. Save.

!!! note "**Reference endpoints** (used in Step 2):"
    - Client ID and Client Secret
    - Authorization: `https://authentik.example.com/application/o/authorize/`  
    - Token: `https://authentik.example.com/application/o/token/`  
    - JWKS: `https://authentik.example.com/application/o/<slug>/jwks/`
    !!! note "**Why:**"
        This makes <span style="color:red;">Authentik</span> act as an **OpenID Provider (OP)**. Cloudflare will redirect users to Authentik for authentication.

---

## Step 2 — Add Authentik as a Login Method in Cloudflare

1. In Zero Trust, go to **Settings → Authentication → Login methods → Add → OpenID Connect**.  

!!! example "Paste values from <span style="color:red;">Authentik</span> provider:"
    - **App ID / Client ID** → Authentik **Client ID**  
    - **Client Secret** → Authentik **Client Secret** 
    - **Auth URL** → `.../application/o/authorize/` 
    - **Token URL** → `.../application/o/token/`  
    - **JWKS/Certificate URL** → `.../application/o/<slug>/jwks/`  
    *(You may also use the Discovery URL to populate these automatically.)*  

3. Save and click **Test** to verify claims.

!!! note "**Why:**"
    This tells Cloudflare to trust <span style="color:red;">Authentik</span> for sign-ins. The Test button validates your configuration and shows which user attributes Cloudflare will receive.

---

## **Step 3 — Protect an Application with Cloudflare Access**

1. In Zero Trust, go to **Access → Applications → Add an application → Self-hosted**.  
2. Set the **Application domain** (the URL users will visit, e.g., `https://app.example.com`).  
3. Under **Identity providers**, select your new **Authentik (OIDC)** login method.  
4. Create an **Access policy** (for example: Include → Emails ending in `@yourdomain.com`, or `Groups contains admins`).  
5. Save the application.

!!! note "**Why:**"
    This binds your app to <span style="color:red;">Authentik</span> SSO and defines **who** can access it.

---

## **Step 4 — (Optional) Publish the App with Cloudflare Tunnel**
If the app runs privately (home lab, VPC), publish it through a Tunnel:

1. Create a **Cloudflare Tunnel** and connect **cloudflared** on your host.  
2. Add a **Public Hostname** (e.g., `app.example.com`) pointing to your local service (e.g., `http://127.0.0.1:8080`).  
3. Connect this hostname to the **Access application** created earlier.

!!! note "**Why:**"
    Tunnels let you securely expose private services without opening inbound firewall ports. Access then enforces <span style="color:red;">Authentik</span> SSO before any request hits your origin

---

## **Step 5 — Enable MFA and Policies in Authentik**

- Configure MFA (TOTP or WebAuthn) in **<span style="color:red;">Authentik</span>** and bind it to the login flow used by your OIDC provider.  
- Because Cloudflare delegates auth to <span style="color:red;">Authentik</span>, MFA policy applies to **all Cloudflare-protected apps** automatically.

!!! note "**Why:**"
    Centralizing MFA ensures strong authentication everywhere.

---

## **Step 6 — Validate Claims and Headers (Optional, for Admins)**

- After authenticating to an Access-protected app, visit:
``` bash
https://app.example.com/cdn-cgi/access/get-identity
```
 This shows the identity JSON Cloudflare passes (email, groups, etc.).  
- If needed, configure your app to use these headers or validate Cloudflare’s JWT.

> **Why:** Useful for debugging and passing user data into your apps.

---

??? bug "Troubleshooting"
    - **SSL is required:** <span style="color:red;">Authentik</span> must use HTTPS with a valid cert publicly accessible.
    - **Invalid redirect URI:** Cloudflare's callback URL and <span style="color:red;">Authentik</span>’s OIDC provider Redirect URI must match exactly.
    - **Clock sync:** Ensure both servers have correct time (use NTP).
    - **Policy denies everyone:** Check your Access policy rules (emails, domains, or groups) and ensure the IdP is selected on the application.
    - **Missing claims** → Make sure scopes include `email` and `profile` (plus `groups` if needed).
    - For detailed logs, check <span style="color:red;">Authentik</span>’s and Cloudflare’s dashboards.

## **Summary**

With this integration in place, all protected applications behind Cloudflare Access will accept <span style="color:red;">Authentik</span> credentials, empowering your organization with centralized, secure, and auditable authentication.

---

## ***Reference***

- [*Authentik*](https://integrations.goauthentik.io/networking/cloudflare-access/): Cloudflare Access Integration
- [*Cloudflare Zero Trust*](https://developers.cloudflare.com/cloudflare-one/identity/idp-integration/generic-oidc/): Generic OIDC, adding login methods, Access apps & policies, locating your team domain, and Tunnels


