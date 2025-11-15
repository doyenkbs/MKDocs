# **<span style="color:#009688;">Paperless-ngx + authentik (OIDC) Integration</span>**

---

This page shows how to integrate **<span style="color:#009688;">Paperless-ngx** with **<span style="color:red;">authentik** using **OpenID Connect (OIDC)**. It also covers optional settings to disable local logins and auto-redirect users to SSO, plus a “Remote-User header” alternative.

**Prerequisites**

- A working Paperless-ngx instance (Docker or bare-metal).
- An authentik admin account.
- Public HTTPS URLs for both services (recommended).
- Paperless-ngx v2.5.0+ for OIDC. 

**What you’ll set up**

1. An authentik OAuth2/OIDC provider & application for Paperless-ngx.
2. Paperless-ngx configured to use the openid_connect provider from django-allauth.
3. (Optional) Disable local username/password and auto-redirect to SSO.
4. (Optional) Auto-create Paperless users on first SSO login.

---

## **Step 1 — Create the OIDC Provider in authentik**

In authentik (Admin UI):

1. Go to Applications → Applications → Create with Provider.

2. Choose OAuth2/OpenID Connect as the Provider type.

3. Note the Client ID, Client Secret, and the Application slug. You'll reference them in the next step.

4. Set Redirect URI (Strict) to:
```
https://paperless.example.com/accounts/oidc/authentik/login/callback/
```
5. Under Advanced protocol settings → Selected Scopes, confirm or add:

   > - `authentik default OAuth Mapping: OpenID 'openid'`
   > - `authentik default OAuth Mapping: OpenID 'email'`
   > - `authentik default OAuth Mapping: OpenID 'profile'`

Save. 

!!! tip
    Tip: authentik exposes a `.well-known/openid-configuration` URL per application. You’ll point Paperless-ngx at that URL in the next step.

---

## **Step 2 — Configure Paperless-ngx (OIDC / allauth)**

Paperless-ngx uses django-allauth to add social/OIDC providers. For authentik, you’ll enable the OpenID Connect provider and supply the provider configuration as JSON.

==If you have Paperless-ngx setup in Docker, add the following environment variables to your Paperless-ngx compose file:==
``` yaml
environment:
  # Enable allauth + OIDC (authentik)
  PAPERLESS_ENABLE_ALLAUTH: true
  PAPERLESS_APPS: allauth.socialaccount.providers.openid_connect
  PAPERLESS_SOCIALACCOUNT_PROVIDERS: >
    {
      "openid_connect": {
        "APPS": [
          {
            "provider_id": "authentik",
            "name": "SSO",
            "client_id": "<CLIENT_ID>",
            "secret": "<CLIENT_SECRET>",
            "settings": {
              "server_url": "https://authentik.example.com/application/o/<APPLICATION_SLUG>/.well-known/openid-configuration",
              "claims": { "username": "email" }
            }
          }
        ],
        "OAUTH_PKCE_ENABLED": "True"
      }
    }

  # Optional:
  PAPERLESS_AUTO_CREATE: true   # create Paperless user on first SSO login
  PAPERLESS_AUTO_LOGIN: true    # after signup, auto-login the user
  # Uncomment after verifying SSO works:
  #PAPERLESS_REDIRECT_LOGIN_TO_SSO: true
  #PAPERLESS_DISABLE_REGULAR_LOGIN: true
```
??? tip "(Optional) Disable local login & auto-redirect to SSO**"
    Once OIDC is working, you can remove the local username/password form and send users straight to authentik:
    ``` ini
    # In Docker env uncomment the following or add to paperless.conf 
    PAPERLESS_DISABLE_REGULAR_LOGIN: true
    PAPERLESS_REDIRECT_LOGIN_TO_SSO: true
    ```
    !!! note
        These settings hide the local login and redirect to SSO. Keep local login enabled until you’ve verified SSO works.

Restart:

``` bash
docker compose down && docker compose up -d
```
==If you run Paperless-ngx without Docker, add to `paperless.conf`:==

``` ini
PAPERLESS_ENABLE_ALLAUTH=true
PAPERLESS_APPS=allauth.socialaccount.providers.openid_connect
PAPERLESS_SOCIALACCOUNT_PROVIDERS={"openid_connect":{"OAUTH_PKCE_ENABLED":true,"APPS":[{"provider_id":"authentik","name":"authentik","client_id":"<CLIENT_ID>","secret":"<CLIENT_SECRET>","settings":{"server_url":"https://<authentik.fqdn>/application/o/<APPLICATION_SLUG>/.well-known/openid-configuration","claims":{"username":"email"}}}]}}
PAPERLESS_AUTO_CREATE=true
PAPERLESS_AUTO_LOGIN=true
```

Then restart Paperless services (example):
``` bash
sudo systemctl restart paperless-*
```

!!! note
    Why the `"claims": {"username": "email"}`? It maps the Paperless username to the user’s email claim from authentik, which is often what you want.

??? tip "Linking or creating users"
    - Auto-create (recommended for small teams/home): enable `PAPERLESS_AUTO_CREATE=true`.
    - Link existing accounts: sign in locally once, go to `My Profile → Connect new social account`, and link authentik. After that, you can disable local login

---

## **Testing checklist**

- Visit `https://paperless.example.com/accounts/login/`.
- You should see an authentik login button (and, if not yet disabled, the local form).
- Sign in with authentik; you should land back in Paperless as an authenticated user.
- Create a test user in authentik and confirm first-login behavior (auto-create vs. linking).


??? bug "**Troubleshooting**"

    1. Login page still shows username/password only.

        - Ensure `PAPERLESS_ENABLE_ALLAUTH: true` and `PAPERLESS_APPS` includes `allauth.socialaccount.providers.openid_connect`.
        - Verify the `PAPERLESS_SOCIALACCOUNT_PROVIDER`S` JSON is valid (no trailing commas, balanced braces). 
        
    2. “No such provider” or button not visible.

        - Restart Paperless after changing env/`paperless.conf`.
        - Check that your Paperless version is ≥ 2.5.0. 
        
    3. Redirect/Callback errors.

        - The authentik Redirect URI must exactly match: `https://paperless.example.com/accounts/oidc/authentik/login/callback/`
        - Confirm the authentik **server_url** you put in Paperless points to the application-scoped `.well-known/openid-configuration` URL that includes your application slug. 
    
    4. Existing users not mapped.

        - Use **My Profile → Connect new social account once**, or enable `PAPERLESS_AUTO_CREATE: true` to create on first SSO login. 

    5. Want one-click SSO.

        -Set `PAPERLESS_REDIRECT_LOGIN_TO_SSO: true`; once stable, also set `PAPERLESS_DISABLE_REGULAR_LOGIN: true`. 

---

## ***Reference***

- [Paperless-ngx docs — SSO & third-party auth (allauth OIDC, disable regular login).](https://docs.paperless-ngx.com/configuration/#PAPERLESS_DISABLE_REGULAR_LOGIN) 

- [Authentik — Integrate with Paperless-ngx (client setup, redirect URI, server_url, claims mapping).](https://integrations.goauthentik.io/documentation/paperless-ngx/)