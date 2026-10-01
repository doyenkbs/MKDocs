# Stalwart and Bulwark with Authentik SSO

This page connects an existing Stalwart + Bulwark install to **Authentik**:

- Users sign in to **webmail (Bulwark)** with Authentik single sign-on.
- Administrators sign in to the **Stalwart admin console** with the same Authentik account, protected by Authentik MFA.
- **Mail apps** (Thunderbird, phones) use per-device **app passwords**.

It assumes the setup from [Stalwart Mail Server and Bulwark Webmail](stalwart-bulwark.md) is already working.

All names and addresses on this page are examples. Replace them with your own:

| Example value | Replace with |
|---|---|
| `example.com` | Your mail domain |
| `mail.example.com` | Your Stalwart hostname |
| `webmail.example.com` | Your Bulwark hostname |
| `auth.example.com` | Your Authentik hostname |
| `stalwart-mail` | The slug of your Authentik application |
| `user` | An Authentik username (becomes `user@example.com`) |

Tested with Stalwart 0.16 and Authentik 2026.8.

---

## How it works

```
  Browser                 Bulwark                  Authentik               Stalwart
     |  open webmail         |                          |                       |
     |---------------------->|                          |                       |
     |  redirect to login    |                          |                       |
     |<----------------------|                          |                       |
     |  sign in + MFA                                   |                       |
     |------------------------------------------------->|                       |
     |  back with code       |                          |                       |
     |---------------------->|  exchange code for token |                       |
     |                       |------------------------->|                       |
     |                       |  JMAP request with token                         |
     |                       |------------------------------------------------->|
     |                       |                          |  validate token       |
     |                       |                          |<----------------------|
```

- **One Authentik provider** serves both Bulwark and the Stalwart admin console. Stalwart's directory accepts tokens from one issuer and one audience, so both apps must use the same provider and the same Client ID.
- **The Client ID must be `stalwart-webui`.** Stalwart's own web interface always signs in with that Client ID, and it cannot be changed from Stalwart's settings.
- **The provider is Public, not Confidential.** The Stalwart admin console exchanges the login code from inside the browser, which cannot keep a client secret. Public clients use PKCE instead, and the redirect URIs lock down where tokens can go.
- **Stalwart's OIDC directory** becomes the source of accounts. Stalwart no longer checks mailbox passwords itself.
- **Mail apps** cannot complete an Authentik sign-in over IMAP and SMTP. They use **app passwords**, which are stored in Stalwart.

> **Availability:** webmail and admin console logins depend on Authentik. If Authentik is down, nobody can sign in to webmail. Inbound mail from other servers still arrives, because delivery does not involve a login. If Authentik runs in a home lab and the mail server runs on a VPS, a home internet outage blocks webmail logins too.

---

## Before you start

- Authentik must be reachable from the mail server over HTTPS. Test from the mail server:

    ```bash
    curl -s -o /dev/null -w '%{http_code}\n' https://auth.example.com/-/health/live/
    ```

    Expected output: `204` or `200`. A `403` usually means a Cloudflare security rule (Bot Fight Mode, WAF, or Access) is blocking server traffic.

- Decide the **username rule** now. With the settings on this page, the Authentik **username** becomes the mailbox name: Authentik user `user` signs in as `user@example.com`. The Authentik **email** field does not decide the mailbox address. Check or rename users under **Authentik Admin interface › Directory › Users**.
- Do this while Stalwart has few or no real mailboxes. Switching the account directory later is harder.

---

## Step 1: Create the Authentik application and provider

1. Open the Authentik **Admin interface**.
2. Go to **Applications › Applications**, click the arrow next to **New Application**, and choose **with New Provider...**
3. Application settings:
    - **Name:** `Stalwart Mail`
    - **Slug:** `stalwart-mail`
    - **Launch URL** (under **UI Settings**): `https://webmail.example.com`

    Set the Launch URL. Without it, Authentik builds the dashboard tile's link from the first redirect URI, which is a regex, and the tile opens a broken address.

4. Provider type: **OAuth2/OpenID Provider**.
5. Provider settings, in the order they appear on the form:

    | Field | Value |
    |---|---|
    | Authorization flow | `default-provider-authorization-implicit-consent` |
    | Client type | **Public** |
    | Client ID | Delete the generated value and type `stalwart-webui` |
    | Client Secret | Not used by a Public client. Leave it as it is. |
    | Redirect URIs | Add the six entries in the next table |
    | Signing key | `authentik Self-signed Certificate` |
    | Scopes (under Advanced) | `openid`, `email`, `profile`, `offline_access` |
    | Subject mode | Based on the User's username |

    **Redirect URIs:** click **Add entry** for each row and set both dropdowns:

    | Matching mode | Type | URL |
    |---|---|---|
    | Regex | Authorization | `https://webmail\.example\.com/(.*/)?auth/callback` |
    | Regex | Authorization | `https://mail\.example\.com/(admin|account)/oauth/callback.*` |
    | Strict | Authorization | `https://mail.example.com/admin/oauth/callback` |
    | Strict | Authorization | `https://mail.example.com/account/oauth/callback` |
    | Strict | Post Logout | `https://webmail.example.com` |
    | Regex | Post Logout | `https://mail\.example\.com/.*` |

    What each row does:

    - **Row 1** is Bulwark's login callback, which can include a language prefix such as `/en/`.
    - **Row 2** covers the Stalwart admin console (`/admin`) and the user account page (`/account`).
    - **Rows 3 and 4 are required even though row 2 already matches them.** The Stalwart console requests its token from the browser, and Authentik decides which websites may do that (CORS) from the provider's redirect URIs. Authentik reads the hostname literally, so a regex entry (`mail\.example\.com`) never matches. Without a **Strict** entry on the mail hostname, the console login fails with "Failed to fetch".
    - **Rows 5 and 6** are where users land after signing out.

6. Click **Submit**.
7. Open **Applications › Providers** and click the provider's **name** (not **Edit**). Check that the **Redirect URIs** list shows exactly six entries. The Edit form can display duplicate rows; if the overview shows duplicates, remove them in the Edit form and save.

### Confirm the provider from the mail server

The discovery URL uses the **application slug**:

```bash
curl -s -o /tmp/oidc.json -w '%{http_code}\n' https://auth.example.com/application/o/stalwart-mail/.well-known/openid-configuration
grep -oE '"(issuer|userinfo_endpoint|jwks_uri)": *"[^"]*"' /tmp/oidc.json
```

Expected output: `200` and three lines. The `issuer` line looks like this:

```
"issuer": "https://auth.example.com/application/o/stalwart-mail/"
```

Copy that issuer value exactly, including the trailing slash. You need it in Step 3.

Check that the provider publishes a signing key:

```bash
curl -s https://auth.example.com/application/o/stalwart-mail/jwks/ | grep -o '"kid"' | wc -l
```

Expected output: `1` or more. If it prints `0`, edit the provider and set **Signing key**.

A `404` from the discovery URL means no application uses that slug, or the application has no provider assigned. The exact URL is shown on the provider's page as **OpenID Configuration URL**.

---

## Step 2: Set up a break-glass admin

Once Stalwart uses Authentik for accounts, every login goes through Authentik. Set up a recovery login **before** switching, so an Authentik problem cannot lock you out.

On the mail server (this prints the password on screen):

```bash
cd /opt/mail
echo "STALWART_RECOVERY_ADMIN=admin:$(openssl rand -hex 16)" > stalwart.env
cat stalwart.env
docker compose up -d --force-recreate stalwart
```

Save the password in a password manager. Test it: open `https://mail.example.com/admin` in a private browser window and sign in with username `admin` and that password. Do not continue until this works.

Stalwart accepts this recovery login while running normally, whatever directory is active. Step 9 turns it off once your own account has admin rights.

---

## Step 3: Create the OIDC directory in Stalwart

1. Sign in to `https://mail.example.com/admin` as the recovery `admin`.
2. Switch to **Settings** using the icons at the bottom of the left sidebar.
3. Go to **Authentication › Directories** and click **Create**.
4. Fill in the form:

    | Field | Value |
    |---|---|
    | Directory type | OpenID Connect |
    | Description | `Authentik` |
    | Issuer URL | The exact `issuer` value from Step 1, for example `https://auth.example.com/application/o/stalwart-mail/` |
    | Required Audience | `stalwart-webui` |
    | Required Scopes | `openid` |
    | Username Claim | `preferred_username` |
    | Username Domain | `example.com` |
    | Name Claim | `name` |
    | Groups Claim | Leave empty |

5. Click **Save**.

Why these values:

- **Required Audience** makes Stalwart reject tokens that Authentik issued to any of your other applications.
- **Required Scopes** is only `openid`, because the Stalwart console may request fewer scopes than Bulwark.
- **Username Domain** turns the Authentik username `user` into `user@example.com`.
- **Groups Claim is left empty on purpose.** If it is set to `groups`, Stalwart creates a group account for every Authentik group the user belongs to (for example `admins@example.com`). Those group addresses can receive mail from outside, and they show up as shared mailboxes in webmail.

---

## Step 4: Make Authentik the active directory

Creating the directory is not enough. Stalwart only uses it once it is set as the default.

1. In **Settings**, go to **Authentication › General**.
2. Set **Directory** to `Authentik`.
3. Click **Save**.
4. Restart Stalwart:

    ```bash
    cd /opt/mail
    docker compose restart stalwart
    ```

5. In a new private window, confirm the recovery login from Step 2 still works.

---

## Step 5: Configure Bulwark

1. Open `https://webmail.example.com/admin` and sign in with the Bulwark admin password.
2. Go to **Configuration › Authentication**.
3. Fill in **OAuth / OpenID Connect**:

    | Field | Value |
    |---|---|
    | OAuth Enabled | On |
    | OAuth Only | Off (for now) |
    | OAuth Client ID | `stalwart-webui` |
    | OAuth Client Secret | Leave empty (the provider is Public) |
    | OAuth Issuer URL | `https://auth.example.com/application/o/stalwart-mail` with **no trailing slash** |
    | Allow private OAuth endpoints | Off |
    | OAuth Scopes | `openid email profile offline_access` |
    | OAuth Extra Scopes | Leave empty |

4. Under **Single Sign-On**, set **Post-logout redirect URI** to `https://webmail.example.com/en/login`.
5. Click **Save changes**.

> **Do not click "Set up automagically".** That button registers Bulwark with Stalwart's own built-in OAuth server, not with Authentik.

Bulwark adds `/.well-known/openid-configuration` to the issuer URL itself. A trailing slash produces a double slash that Authentik rejects, which is why this issuer URL has no trailing slash while Stalwart's does.

---

## Step 6: Test webmail

1. Open `https://webmail.example.com` in a private browser window.
2. Click the single sign-on button.
3. Sign in on the Authentik page.
4. You land back in Bulwark with the mailbox loaded.

Accounts from an external directory are created in Stalwart the **first time** the user signs in. Mail sent to an address before that first login bounces, so have each user sign in once before moving real mail to their address.

If the login fails, check the Stalwart log:

```bash
cd /opt/mail
docker compose logs --since 5m stalwart | grep -iE 'oidc|token|audience|directory' | tail -15
```

Successful token logins are not logged at the default level. An empty result after a working login is normal.

---

## Step 7: Give your account admin rights and test the console

Your Authentik account starts as a normal user. Promote it using the recovery admin:

1. Sign in once through webmail (Step 6) so your account exists.
2. Open `https://mail.example.com/admin` in a private window and sign in as the recovery `admin`.
3. Switch to the management view (first icon at the bottom of the left sidebar) and go to **Directory › Accounts**.
4. Open your account (`user@example.com`), add the `admin` role, and save.
5. In a new private window, open `https://mail.example.com/admin`, enter `user@example.com`, and sign in on the Authentik page. You should get the full admin console.

What to expect on the console sign-in:

- **The Authentik login field is prefilled with `user@example.com`.** Stalwart passes the address you typed to Authentik. If that address is not the Authentik user's username or email, delete it and type the username. Setting the Authentik user's **Email** to the mailbox address (Directory › Users › user › **Edit**) avoids the edit.
- **Chrome asks "Access other devices on your local network".** This happens when your local DNS resolves `auth.example.com` to a private IP (split DNS). Click **Allow**. In a normal window Chrome remembers the choice; in a private window it asks every time.
- **Authentik may ask you to sign in twice.** See [Known limitations](#known-limitations).

---

## Step 8: Mail apps on phones and desktops

Mail apps cannot complete an Authentik sign-in over IMAP and SMTP. Give each device its own **app password**.

Each user creates their own app passwords. An administrator editing someone else's account under **Directory › Accounts** gets the error "Secondary credentials cannot be set directly".

1. Sign in to `https://mail.example.com/admin` with your Authentik account.
2. Switch to the account view (the person icon, third icon at the bottom of the left sidebar).
3. Go to **Credentials › App Passwords** and click **Create App password**.
4. Enter a **Description** that names the device (for example `Thunderbird laptop`). Leave **Allowed IPs** empty, or the app will fail from other networks such as a phone on mobile data.
5. Save, and copy the generated password into a password manager. It is shown only once.

In the mail app:

| Setting | Value |
|---|---|
| Username | Your full address, `user@example.com` (not just `user`) |
| Password | The app password |
| Incoming | IMAP, `mail.example.com`, port 993, SSL/TLS |
| Outgoing | SMTP, `mail.example.com`, port 465, SSL/TLS |
| Authentication | Normal password |

Test an app password without a mail app, from PowerShell on Windows. curl asks for the password and does not display it:

```powershell
curl.exe --user "user@example.com" "imaps://mail.example.com/"
```

Lines starting with `* LIST` mean the app password works. Do not add `-v` to this command: verbose mode prints the login command, including the password in base64.

---

## Step 9: Turn off the recovery admin

Once your Authentik account has the full admin console, turn the recovery login off. The line stays in the file, commented out, so you can turn it back on in an emergency.

```bash
cd /opt/mail
sed -i 's/^STALWART_RECOVERY_ADMIN=/#STALWART_RECOVERY_ADMIN=/' stalwart.env
chmod 600 stalwart.env
docker compose up -d --force-recreate stalwart
grep -c '^STALWART_RECOVERY_ADMIN=' stalwart.env
```

Expected output: `0`. In a private window, signing in to `https://mail.example.com/admin` as `admin` should now fail.

To turn it back on (for example while Authentik is down):

```bash
cd /opt/mail
sed -i 's/^#STALWART_RECOVERY_ADMIN=/STALWART_RECOVERY_ADMIN=/' stalwart.env
docker compose up -d --force-recreate stalwart
```

---

## Optional: Add an admin console tile to the Authentik dashboard

Opening the Stalwart console from the Authentik dashboard means you already have an Authentik session, so you sign in once instead of twice (see [Known limitations](#known-limitations)).

1. Authentik Admin interface › **Applications › Applications**, click the arrow next to **New Application**, and choose **with Existing Provider...**
2. Set:
    - **Name:** `Stalwart Admin`
    - **Slug:** `stalwart-admin`
    - **Launch URL** (under **UI Settings**): `https://mail.example.com/admin`
3. Click **Create**.
4. To show the tile only to administrators: **Applications › Applications** › `Stalwart Admin` › **Policy / Group / User Bindings** › **Bind existing policy/group/user**, and bind your admin group.

---

## Optional: Make Authentik the only way to sign in to webmail

Use this once SSO has worked for a while and every device has an app password.

### Bulwark: hide the password form

In `https://webmail.example.com/admin` › **Configuration › Authentication**:

| Setting | Value | Effect |
|---|---|---|
| **OAuth Only** | On | Hides the username and password form. Only the SSO button remains. |
| **Auto SSO** | On | Skips the Bulwark login page and sends users straight to Authentik. |
| **End provider session on sign-out** | On | Signing out of webmail also signs out of Authentik. |

Click **Save changes**, then test in a private window. The Bulwark admin password still works at `https://webmail.example.com/admin`.

### Authentik: control who can sign in

Authentik Admin interface › **Applications › Applications** › `Stalwart Mail` › **Policy / Group / User Bindings** › **Bind existing policy/group/user**. Bind a group such as `mail-users`. Only members can sign in to webmail and the Stalwart console.

### What stays outside SSO

| Item | Why it stays |
|---|---|
| App passwords | Mail apps need them for IMAP and SMTP. Revoke any that are no longer used. |
| Stalwart recovery admin | Your way in if Authentik is down. Keep it commented out in `stalwart.env` and stored in a password manager. |
| Bulwark admin password | Protects Bulwark's own settings page. |

---

## Known limitations

These affect only the **Stalwart admin console**. Webmail signs in and out normally.

| Behavior | Cause | Workaround |
|---|---|---|
| Authentik asks you to sign in **twice** when you have no Authentik session yet. | The Stalwart console always sends `prompt=login`, which tells Authentik to force a fresh login. After the first login, Authentik applies it again on the way back. | Sign in to Authentik first (for example through webmail or the dashboard tile above). Then the console asks only once. |
| Signing out of the console ends on an Authentik **Bad Request** page: "The request is otherwise malformed". | The Stalwart console's logout request does not include the ID token (`id_token_hint`), and Authentik refuses a logout redirect without it. | None needed. The Stalwart session is already ended; close the tab. Your Authentik session stays active. |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Authentik shows **Client ID Error** for `client_id=stalwart-webui` | The provider's Client ID is not `stalwart-webui`. | Step 1: edit the provider and set Client ID to `stalwart-webui`. |
| Stalwart log: `Failed to decode token. If you are using an external OIDC provider, make sure it is configured as the default directory` | The OIDC directory was created but is not the active directory. | Step 4: set **Authentication › General › Directory** to `Authentik`, save, and restart Stalwart. |
| Stalwart log: `InvalidAudience` | **Required Audience** does not match the Client ID. | Set Required Audience to `stalwart-webui` (Step 3) and Bulwark's Client ID to `stalwart-webui` (Step 5). |
| Stalwart console login stops at **Failed to fetch**; the browser Network tab (F12) shows a **CORS error** on `token/` | No **Strict** redirect URI on the mail hostname. Authentik ignores regex entries when deciding which websites may request tokens. | Add rows 3 and 4 from Step 1. |
| Authentik dashboard tile opens an address like `webmail/.example/.com?auth/callback` | The application has no Launch URL. | Step 1: set **Launch URL** to `https://webmail.example.com`. |
| Webmail shows shared mailboxes named after Authentik groups | **Groups Claim** is set in the Stalwart directory. | Clear **Groups Claim** (Step 3), delete the group accounts under **Directory › Groups**, and restart Stalwart. |
| Discovery URL returns `404` | Wrong slug, or the application has no provider. | Use the application slug. Copy the **OpenID Configuration URL** from the provider page. |
| Discovery URL returns `403` from the mail server | A Cloudflare rule blocks server traffic to Authentik. | Allow the mail server's IP, or relax Bot Fight Mode or WAF rules for the Authentik hostname. |
| Signed in, but the mailbox is the wrong address (for example `akadmin@example.com`) | The Authentik username is used as the mailbox name. | Rename the Authentik user, or change **Username Claim** to `email` if Authentik emails match mailbox addresses. |
| Mail app hangs on "Creating account..." or reports an authentication error | Wrong app password for that account (for example another user's), a username without the domain, or a revoked app password. Stalwart's IMAP reply to a bad app password makes clients wait about a minute before failing. | Use the full address as the username and that account's own app password. Test with the `curl.exe` command from Step 8. Stop retrying after a few failures: repeated failures get your IP banned. |
| IMAP log: `Unsupported credentials type for OIDC backend` | The mail app is sending the Authentik password instead of an app password. | Create an app password (Step 8). |
| "Secondary credentials cannot be set directly" | An admin tried to add an app password to another user's account. | The user creates it from their own account view (Step 8). |
| Nobody can sign in, but mail still arrives | Authentik is unreachable from the mail server. | Fix Authentik, or turn the recovery admin back on (Step 9) for urgent admin work. |

---

## Note on MFA

This page assumes MFA is already enforced in Authentik. Because every webmail and admin console login now goes through Authentik, that MFA protects all mail accounts, including administrators.

??? note "Set up MFA in Authentik (if it is not enabled yet)"

    This setting applies to every application that uses Authentik's default login flow. Keep an Authentik admin session open in a second window before you save, so a mistake cannot lock you out.

    1. Authentik Admin interface › **Flows and Stages › Stages** › `default-authentication-mfa-validation` › **Edit**.
    2. Set:
        - **Device classes:** TOTP, WebAuthn, Static
        - **Not configured action:** Force the user to configure an authenticator
        - **Configuration stages:** `default-authenticator-totp-setup`
    3. Click **Update**.
    4. Test in a private window: sign in to webmail. Authentik should ask you to set up an authenticator, then ask for a code on later logins.

---

## References

- [Stalwart: OpenID Connect directory](https://stalw.art/docs/auth/backend/oidc/)
- [Stalwart: Directory object reference](https://stalw.art/docs/ref/object/directory/)
- [Stalwart: App passwords](https://stalw.art/docs/auth/authentication/app-password/)
- [Stalwart: Docker install (recovery admin)](https://stalw.art/docs/install/platform/docker/)
- [Bulwark Webmail on GitHub](https://github.com/bulwarkmail/webmail)
- [Authentik: OAuth2 provider](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/)
