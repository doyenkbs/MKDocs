---
tags:
  - Integration
---

# **<span style="color:#26A69A;">Integrate BookStack with Authentik via OIDC</span>**

This guide will walk you through integrating **<span style="color:#26A69A;">Bookstack</span>** with **<span style="color:red;">Authentik</span>** to enable Single Sign-On via OpenID Connect (OIDC).

---

!!! info "**Requirements**"
    Running **BookStack** and **Authentik** instances.

---

## **1. Create a BookStack Provider**

1. Open your **Authentik Admin Interface**.  
2. Navigate to:  
   **Applications → Providers → Create**.  
3. Select **OAuth2/OpenID Provider**, then click **Next**.  
!!! example "Fill in the following:"
    - **Name:** `Bookstack OIDC` (or your preferred name)
    - **Protocol settings → Client type:** `Confidential`  
    - **Redirect URIs/Origins:** `Add entry` 
    ```
    https://<your-bookstack-URL>/oidc/callback
    ```
    - **Signing Key:** `authentic Self-signed Certificate`

4. Click **Finish**.

---

## **2. Create a BookStack Application**

1. Navigate to:  
   **Applications → Applications → Create**.  
!!! example "Fill in the following:"
    - **Name:** `Bookstack` (or your preferred name)  
    - **Slug:** same as the name (`bookstack`)  
    - **Provider:** Select the provider created in the previous step (e.g., `Bookstack OIDC`) 
    - **Policy engine mode:** `Any`  
    - **UI Settings → Launch URL:** Your BookStack login URL (e.g., `https://wiki.example.com`)

2. Click **Create**.

---

## **3. Modify BookStack Environment Variables**

On your BookStack server, edit the `.env` file.
Run:

```bash
sudo nano /var/www/bookstack/.env
```

Paste/modify the following:

```bash
# Set OIDC to be the authentication method
AUTH_METHOD=oidc

# Control if BookStack automatically initiates login via your OIDC system 
# if it's the only authentication method. Prevents the need for the
# user to click the "Login with x" button on the login page.
# Setting this to true enables auto-initiation.
AUTH_AUTO_INITIATE=false

# Set the display name to be shown on the login button.
# (Login with <name>)
OIDC_NAME=SSO

# Name of the claims(s) to use for the user's display name.
# Can have multiple attributes listed, separated with a '|' in which 
# case those values will be joined with a space.
# Example: OIDC_DISPLAY_NAME_CLAIMS=given_name|family_name
OIDC_DISPLAY_NAME_CLAIMS=name

# OAuth Client ID to access the identity provider
OIDC_CLIENT_ID=abc123

# OAuth Client Secret to access the identity provider
OIDC_CLIENT_SECRET=def456

# Issuer URL
# Must start with 'https://'
OIDC_ISSUER=https://instance.authsystem.example.com

# The "end session" (RP-initiated logout) URL to call during BookStack logout.
# By default this is false which disables RP-initiated logout.
# Setting to "true" will enable logout if found as supported by auto-discovery.
# Otherwise, this can be set as a specific URL endpoint.
OIDC_END_SESSION_ENDPOINT=false

# Enable fetching of the user's avatar from the 'picture' claim on login.
# Will only be fetched if the user doesn't already have an avatar image assigned.
# By default this is false which disables avatar fetching. Set to 'true' to enable.
# WARNING: This can be a security risk due to performing server-side fetching 
# (with up to 3 redirects) of data from external URLs. Only enable if you
# trust the OIDC auth provider to provide safe URLs for user images.
OIDC_FETCH_AVATAR=false

# Enable auto-discovery of endpoints and token keys.
# As per the standard, expects the service to serve a 
# `<issuer>/.well-known/openid-configuration` endpoint.
OIDC_ISSUER_DISCOVER=true
```

!!! note
    - **Client ID and Secret:**
    In Authentik Admin, go to Admin → Applications → Providers → Edit your BookStack provider → Copy Client ID and Secret, then update `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET` in `.env`.
    - **OIDC_ISSUER:**
    In Authentik Admin → Applications → Providers → Click your BookStack provider → Copy “OpenID Configuration Issuer” and paste into `.env` as `OIDC_ISSUER`.

Save the `.env` file and restart BookStack if necessary.

## **4. Test Login**

- Go to your BookStack login page (`https://wiki.example.com/login`)
- Click **Login with SSO**

!!! tip
    - **Users:** Each user must exist in Authentik. If **Auto Register** is enabled, users are created on first login in Audiobookshelf with limited permissions.
    - **Groups:** If you wish to sync user groups, map claims accordingly in Authentik and verify `groups` claim handling in Audiobookshelf.

---

### **For more details:**
- See the [*BookStack Documentation: OpenID Connect Authentication*](https://www.bookstackapp.com/docs/admin/oidc-auth/)