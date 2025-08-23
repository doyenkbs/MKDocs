# **Nextcloud Integration with Authentik via OpenID Connect (OIDC)**

This guide describes how to integrate <span style="color:#009688;">Nextcloud</span> with <span style="color:#1976D2;">Authentik</span> for Single Sign-On (SSO) and centralized identity managemen using the OpenID Connect (OIDC) protocol. This setup enables secure authentication for users, eliminating local Nextcloud accounts and centralizing identity management with Authentik.

---

## **Prerequisites**

- A running <span style="color:#009688;">Nextcloud</span> instance: e.g. `https://nextcloud.example.com`
- A running <span style="color:#1976D2;">Authentik</span> instance: e.g. `https://authentik.example.com`
- Admin access to both <span style="color:#1976D2;">Authentik</span> and <span style="color:#009688;">Nextcloud</span>
- Nextcloud **OpenID Connect user backend** app installed and enabled

---

## **Step 1: Install Nextcloud OIDC App**

- Log into **<span style="color:#009688;">Nextcloud</span>** (`https://nextcloud.example.com`) as an admin.
- Go to **Apps** → **Your apps**.  (`top right menu`).
- Search for **OpenID Connect user backend**.
- Click **Install and Enable**.

---

## **Step 2: Configure Authentik OIDC Provider**

1. Log into <span style="color:#1976D2;">Aunthentik</span> (`https://authentik.example.com`) as an admin.
2. Navigate to **Applications** → **Providers**.
3. Click **Create** and select **OAuth2 / OpenID Connect Provider**.
4. Set the following values:

    > - **Name:** `Nextcloud OIDC`
    > - **Authorization Flow:** `default-provider-authorization-implicit-consent` `(or your choice)`
    > - **Client type:** `Confidential`
    >- **Redirect URIs:** `https://nextcloud.example.com/index.php/apps/user_oidc/code`
    > - **Signing Key:** `Select your existing key or create one.`
    > - **Scopes:** `openid, profile, email`
    > - **Subject mode:** `Based on the User's username.`

5. Save the provider.

---

## **Step 3: Create an Application in Authentik**

1. Go to **Applications → Create**
2. Set the following values:

    > - **Name:** `Nextcloud`
    > - **Slug:** `nextcloud`
    > - **Provider:** `Select the Nextcloud OIDC provider you created.`
    > - **Launch URL:** `https://nextcloud.example.com` `or leave empty`
    > - Assign appropriate **groups/users** to the application if needed.

3. Save the application.

---

## **Step 4: Get OIDC Credentials from Authentik**

1. Open your <span style="color:#009688;">Nextcloud</span> OIDC provider in <span style="color:#1976D2;">Authentik</span>.
2. Copy the following values:

    > - **Client ID**
    > - **Client Secret**
    > - **OpenID Configuration Issuer:** `https://authentik.example.com/application/o/nextcloud/`

---

## **Step 5: Configure Nextcloud OIDC Settings**

1. In <span style="color:#009688;">Nextcloud</span>, go to **Settings** → **Administration** → **OpenID Connect user backend**.
2. Fill in the fields as follows:

    > - **Identifier (max 128 characters):** `e.g: Authentik or SSO`
    > - **Discovery endpoint:** `*(Use the Provider URL (Issuer) from Authentik OIDC provider)*`  
      e.g.: `https://authentik.example.com/application/o/nextcloud/`
    > - **Client ID:** `*(from Authentik OIDC provider)*`
    > - **Client Secret:** `*(from Authentik OIDC provider)*`
    > - **Authorization endpoint:** `https://authentik.example.com/application/o/authorize/`
    > - **Scopes:** `openid profile email`

    !!! note
        Uncheck `Use Unique user ID` 
3. Save settings.

---

## **Step 6: Test SSO Login**

1. Navigate to `https://nextcloud.example.com`.
2. Try logging in; you should be redirected to <span style="color:#1976D2;">Authentik</span>.
3. After authentication, you will be sent back to <span style="color:#009688;">Nextcloud</span> and logged in automatically.

---
With this setup, <span style="color:#009688;">Nextcloud</span> is fully integrated into your centralized **Authentik SSO & Zero Trust environment**. 

---

## **Troubleshooting**

- Ensure domains and URLs are correct and reachable from both servers.
- If login fails, review <span style="color:#009688;">Nextcloud</span>'s admin logs and <span style="color:#1976D2;">Authentik</span>'s provider logs.
- Check for trailing slashes and matching Redirect URIs.
- Make sure clocks are synced (for token validation).

---

## **OpenID Connect Provider Setup via Command Line**
---

## Disable Other Login Methods and Manage OpenID Connect Providers in Nextcloud

This guide explains how to make OpenID Connect (OIDC) the default and only login method in your Nextcloud instance, as well as how to manage OIDC provider entries via the command line.

---

## **Disable Other Login Methods**

If you only have one OpenID Connect provider configured in <span style="color:#009688;">Nextcloud</span>, you can **force it to be the default login method**. This means users will be **immediately redirected to your OIDC provider's login page**, bypassing the default <span style="color:#009688;">nextcloud</span> login form.

- **Admins can still log in using the native login page** by appending `?direct=1` to the login URL.
  > - e.g.: `https://nextcloud.example.com/login?direct=1`

### **Disable Multiple User Backends**

To make the OIDC provider the sole login method, run:

``` bash
sudo -u www-data php /var/www/nextcloud/occ config:app:set --value=0 user_oidc allow_multiple_user_backends
```
!!! note
    > - *`--value=0`: Disables multiple user backends (OIDC becomes default and exclusive)*
    > - *`--value=1`: Enables multiple user backends (users can choose between available login methods)*
    > - *`/var/www/nextcloud`: Replace this with the actual path to your Nextcloud installation directory*

---
## **Provider Entries Management**

OIDC providers are managed by their **provider identifier** in Nextcloud. You can list, create, show, or delete providers directly from the command line.

### **List All Configured Providers**
``` bash
sudo -u www-data php /var/www/nextcloud/occ user_oidc:provider
```
### **Show Detailed Provider Configuration**
``` bash
sudo -u www-data php /var/www/nextcloud/occ user_oidc:provider PROVIDER_IDENTIFIER
```
*Replace `PROVIDER_IDENTIFIER` with your actual provider's name.*

### **Create a New Provider**

If a provider with the given identifier does not exist, you can create it (replace values as needed):
``` bash
sudo -u www-data php /var/www/nextcloud/occ user_oidc:provider PROVIDER_IDENTIFIER --clientid="WBXCa003871" \ --clientsecret="lbXy***********" --discoveryuri="https://authentik.example.com/openid-configuration"
```
!!! info
    *- You can set other options (attribute mappings, group provisioning, etc.) by adding more flags.*  
    ***- For all available parameters, use:***
    ``` bash
    sudo -u www-data php /var/www/nextcloud/occ user_oidc:provider --help
    ```

### **Delete a Provider**
To delete a configured provider:
``` bash
sudo -u www-data php /var/www/nextcloud/occ user_oidc:provider:delete PROVIDER_IDENTIFIER
```
> *Replace `/var/www/nextcloud` with the actual path to your Nextcloud installation directory.*

You will be asked for confirmation.
!!! warning
    Deleting a provider may invalidate all Nextcloud user accounts provisioned by that provider.
  
To skip the confirmation, add `--force`:
``` bash
sudo -u www-data php /var/www/nextcloud/occ user_oidc:provider:delete PROVIDER_IDENTIFIER --force
```

---

## ***References***

> - [*Nextcloud OIDC Documentation*](https://github.com/nextcloud/user_oidc)
> - [*Authentik Integration - Nextcloud*](https://integrations.goauthentik.io/chat-communication-collaboration/nextcloud/)


