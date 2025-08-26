---
tags:
    - Integration
---

# **<span style="color:coral;">Audiobookshelf ↔ Authentik: OIDC Integration Guide</span>**

This guide will walk you through integrating **<span style="color:coral;">Audiobookshelf</span>** with **<span style="color:red;">Authentik</span>** to enable Single Sign-On via OpenID Connect (OIDC).


!!! info "**Requirements**"
    - A running instance of **Audiobookshelf** (latest recommended)
    - A running instance of **Authentik** with admin access

---

## **Overview**

- Create an OAuth2/OpenID *provider + application* in Authentik.  
- Register Audiobookshelf redirect URIs in Authentik.  
- Copy the Client ID / Client Secret (from Authentik) into Audiobookshelf.  
- Configure OIDC in Audiobookshelf (auto-populate using discovery endpoint).  
- Test login and troubleshoot as needed.

---

## **Step 1: Create an Application & Provider in Authentik**

1. **Log into your Authentik admin interface.**
2. Go to **Applications > Providers** and click **Create**.
3. Select **OAuth2/OpenID Provider** and click **Next**.
!!! example "Fill in:"
    - **Name:** `Audiobookshelf OIDC` (or anything you prefer)
    - **Authorization flow:** `default-provider-authorization-implicit-consent`
    - **Client Type:** Confidential
    - **Redirect URIs:**
    ```
    https://<your-audiobookshelf-URL>/auth/openid/callback
    https://<your-audiobookshelf-URL>/auth/openid/mobile-redirect
    ```
    - **Signing Key:** Self-signed or your chosen key.

4. Click **Finish**.

5. Navigate to **Applications > Applications** and click **Create**.
!!! example "Fill in:"
    - **Name:** Audiobookshelf (or anything you prefer)
    - **Slug:** audiobookshelf (keeps things simple)
    - **Provider:** Select the provider created above (`Audiobookshelf OIDC`)
    - **Policy Engine Mode:** Any
    - **Launch URL:** Your <span style="color:coral;">Audiobookshelf</span> login page (e.g., `https://abs.yoursite.com`)

6. **Save** the application.

---

## **Step 2: Copy client credentials & discovery info from Authentik**

- In Authentik, go to the **Provider** you created for Audiobookshelf.
!!! tip "Locate and copy the following values:"
    - **Client ID**
    - **Client Secret**
    - **OpenID Configuration Issuer URL** (or the discovery URL)  
    ```
    https://auth.example.com/application/o/audiobookshelf/
    ```
    or the `.well-known` endpoint:
    ```
    https://auth.example.com/.well-known/openid-configuration
    ```
    
Copy these; you’ll paste them into Audiobookshelf.

---

## **Step 3: Configure Audiobookshelf for OIDC**

1. **Access Audiobookshelf** as an admin.
2. Navigate to **Settings > Authentication**.
3. Enable **OpenID Connect Authentication**.

4. **Use Auto-populate (optional):**

   - In **Issuer URL** paste your Authentik issuer/discovery URL (see step 2) and click **Auto-populate** — Audiobookshelf will fill Authorization, Token, UserInfo and JWKS URLs automatically.

!!! example "**Fill any remaining fields:**"
    - **Client ID:** (from Authentik)
    - **Client Secret:** (from Authentik)
    - **Signing Algorithm:** `RS256`
    - **Button Text:** (e.g., "Login with SSO" or "Sign in with Authentik")
    - **Allowed Mobile Redirect URIs:**
     ```
     audiobookshelf://oauth
     ```
     - **Auto Launch:** Enable for auto-redirect, disable to show button.
     - **Auto Register:** Enable if you want new users created on login.

5. Save settings.

---

## **Step 4: Test Your SSO Login**

1. Visit your Audiobookshelf login page.
2. If auto-launch is enabled, you will be redirected to Authentik to log in.
3. Otherwise, click the **Login with SSO** (or your chosen button text).
4. Authenticate via Authentik and confirm access to Audiobookshelf.

!!! info 
    If you misconfigure SSO and are locked out, visit  
    ```
    https://<your-audiobookshelf-url>/login/?autoLaunch=0
    ``` to force show the local login form.


!!! note
    - **Users:** Each user must exist in <span style="color:red;">Authentik</span>. If **Auto Register** is enabled, users are created on first login in <span style="color:coral;">Audiobookshelf</span> with limited permissions.
    - **Groups:** If you wish to sync user groups, map claims accordingly in <span style="color:red;">Authentik</span> and verify `groups` claim handling in <span style="color:coral;">Audiobookshelf</span>.
    - **Mobile App:** Ensure the extra mobile redirect URI is also added in the provider's allowed redirect URIs.

---
### **For more details:**
- See the [*Audiobookshelf OIDC guide*](https://www.audiobookshelf.org/guides/oidc_authentication/)
- For advanced Authentik configuration, consult the [*Authentik documentation*](https://docs.goauthentik.io/docs).

