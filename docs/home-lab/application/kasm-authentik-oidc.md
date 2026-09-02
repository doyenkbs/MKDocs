---
tags:
  - Integration
---

# Kasm Workspaces: Authentik OIDC Integration

This sets up single sign-on so users log into Kasm with their Authentik account instead of a local Kasm password. It assumes Kasm is already installed and reachable, see [Kasm Workspaces: Install, Workspaces, and Servers](kasm-workspaces-install.md), and that [Authentik](authentik.md) is running.

The part that trips people up: OIDC scopes have to be enabled on both sides. Selecting a scope in Authentik only makes it available to the client. Kasm still has to request it by name. If either half is missing, the claim never arrives and the login fails with a missing-attribute error.

Example values used throughout:

| Component | URL |
| --- | --- |
| Kasm | https://kasm.example.com |
| Authentik | https://auth.example.com |

## Part 1: Authentik configuration

### Create the property mappings

Do this first, because the provider needs to reference them.

**Customization > Property Mappings > Create > Scope Mapping**

#### Kasm profile mapping

| Field | Value |
| --- | --- |
| Name | Kasm Profile Mapping |
| Scope name | `profile` |

```python
# Safely split the name, with a fallback to prevent crashes
name_parts = request.user.name.split(" ", 1)
given_name = name_parts[0] if len(name_parts) > 0 else request.user.username
family_name = name_parts[1] if len(name_parts) > 1 else ""

return {
    "name": request.user.name,
    "given_name": given_name,
    "family_name": family_name,
    "preferred_username": request.user.username,
    "email": request.user.email,
    "email_verified": True
}
```

The **Scope name** field is the string Kasm has to request. Set it to `profile` and it fires whenever Kasm asks for `profile`. Give it a custom name instead and Kasm has to ask for that exact name, or the mapping never runs.

The name split is worth understanding before relying on it. It splits Display Name on the first space, so "Jane Smith" gives `given_name: Jane` and `family_name: Smith`. A user with a blank Display Name falls back to their username with an empty last name.

#### Groups mapping

Authentik does not ship a default OpenID groups scope mapping, so create one:

| Field | Value |
| --- | --- |
| Name | Kasm Groups Mapping |
| Scope name | `groups` |

```python
return {
    "groups": [group.name for group in request.user.ak_groups.all()]
}
```

Skip this if you do not need group mapping.

### Create the OAuth2/OpenID provider

**Applications > Providers > Create > OAuth2/OpenID Provider**

| Field | Value |
| --- | --- |
| Name | Kasm |
| Authorization flow | explicit-consent or implicit-consent |
| Client type | Confidential |
| Redirect URIs | `strict: https://kasm.example.com/api/oidc_callback` |

The redirect URI has to match exactly what Kasm shows in its own config. Kasm displays it as a read-only field with a copy button, so copy it from there rather than typing it.

### Advanced protocol settings

This is where the scope selection lives, and it is the step most people miss. Expand **Advanced protocol settings** on the provider.

Under **Scopes**, move these from Available Scopes into Selected Scopes:

- `authentik default OAuth Mapping: OpenID 'openid'`
- `authentik default OAuth Mapping: OpenID 'email'`
- `authentik default OAuth Mapping: OpenID 'profile'`
- `Kasm Profile Mapping`
- `Kasm Groups Mapping` (only if you want group mapping)

Authentik notes this directly under the box: selecting a scope makes it available to the client, and the client still has to request it. That is the source of most failures here.

Also on this screen:

| Field | Value |
| --- | --- |
| Subject mode | Based on the User's hashed ID |
| Include claims in id_token | On |

**Subject mode must be set to "Based on the User's hashed ID."** Click **Save** after changing it. Leaving it on another mode changes what Authentik sends as the `sub` claim and breaks the identity Kasm ties the account to.

### Create the application

**Applications > Applications > Create**

| Field | Value |
| --- | --- |
| Name | Kasm |
| Slug | kasm |
| Provider | Kasm (the provider you just created) |

Collect these from the provider overview page:

- Client ID
- Client Secret
- Authorize URL
- Token URL
- Userinfo URL
- OpenID Configuration Issuer

## Part 2: Kasm configuration

**Access Management > Authentication > OpenID > Add**

### Details

| Field | Value |
| --- | --- |
| Enabled | On |
| Display Name | Continue with Authentik |
| Hostname | kasm.example.com |
| Default | On |
| Client ID | from Authentik |
| Client Secret | from Authentik |
| Authorization URL | `https://auth.example.com/application/o/authorize/` |
| Token URL | `https://auth.example.com/application/o/token/` |
| User Info URL | `https://auth.example.com/application/o/userinfo/` |
| OpenID Connect Issuer | `https://auth.example.com/application/o/kasm/` |

Fill in the issuer. It is optional in the form, but leaving it blank skips issuer validation on the token. Authentik shows the exact value on the provider page as "OpenID Configuration Issuer", including the trailing slash.

### Scope

One per line:

```
openid
email
profile
groups
```

Include `profile` even if your Username Attribute is set to `email`. The profile scope is what carries `preferred_username`, `given_name`, and `family_name`. Leave it out and Authentik never fires that mapping.

Only include `groups` if you also created and selected the groups mapping in Authentik. Requesting a scope the provider does not offer produces a missing-attribute error.

### Attributes

| Field | Value |
| --- | --- |
| Username Attribute | `email` or `preferred_username` |
| Groups Attribute | `groups` |

Either username attribute works. `email` is simpler because the email scope is nearly always present and email addresses are unique. `preferred_username` gives you shorter Kasm usernames matching your Authentik usernames.

Clear the Groups Attribute field if you are not doing group mapping.

### Redirect URL

Kasm generates this and it is read-only. Copy it into Authentik's Redirect URIs field. It follows the pattern:

```
https://<kasm-hostname>/api/oidc_callback
```

It uses the Hostname field from this config, so if that is wrong the redirect URI will be wrong too.

## Part 3: Attribute mapping (optional)

The **Attribute Mapping** tab populates Kasm profile fields from OIDC claims. It has nothing to do with login or group membership. Skip it unless you want names showing in the Kasm user list.

| User Field | OIDC Attribute |
| --- | --- |
| First Name | `given_name` |
| Last Name | `family_name` |

The other available fields (Phone, Organization, Notes, City, State, Country) have no matching claim in a standard OIDC token, so leave them unmapped unless your provider emits custom claims for them.

## Part 4: Group mapping (optional)

Group mapping lets Authentik groups control Kasm permissions. It needs all four of these, and missing any one means it silently does nothing:

1. A groups scope mapping created in Authentik (there is no default one)
2. That mapping in the provider's Selected Scopes under Advanced protocol settings
3. `groups` in Kasm's Scope field
4. `groups` as the Groups Attribute in Kasm

Then in Kasm, under **Access Management > Groups**, edit a group and add an **SSO Group Mapping** matching the Authentik group name.

Without group mapping, every OIDC user lands in whatever default group Kasm assigns. For a small lab that is usually fine.

## Troubleshooting

### Failed to find username attribute (preferred_username)

```
File "api_server/authentication/oidc/__init__.py", line 61, in process_callback
Exception: Failed to find username attribute (preferred_username)
```

Kasm is looking for a claim that is not in the token. Two causes:

**Kasm is not requesting `profile`.** This is the common one. `preferred_username` comes from the profile scope. If the Scope field only has `openid` and `email`, that claim never arrives.

**Your mapping is attached to a scope Kasm is not requesting.** Check the mapping's Scope name in Authentik and make sure Kasm asks for it by that exact string.

Quick workaround: change Username Attribute to `email`, which is available whenever the email scope is requested.

### Failed to find groups attribute (groups)

Same mechanism. Either the groups mapping is missing from Authentik's Selected Scopes, or `groups` is not in Kasm's Scope field. Remember Authentik has no default groups scope, so if you never created one it does not exist. If you do not need group mapping, clear the Groups Attribute field in Kasm and the error stops.

### Unhandled exception in the callback

A long CherryPy traceback ending in a claim exception is that exception bubbling up, not a separate problem. Read the last line:

```
Exception: Failed to find username attribute (preferred_username)
```

Everything above it is framework noise.

### Seeing what claims actually arrive

Stop guessing at the token contents. Turn on **Debug** in the Kasm OpenID config, log in once, then read the log:

```bash
sudo docker exec kasm_db psql -U kasmapp -d kasm -c \
  "SELECT ingest_date, left(data->>'message',400) FROM logs ORDER BY ingest_date DESC LIMIT 20;"
```

Map only what you actually see. Turn Debug back off afterward, since it logs token contents.

Errors only:

```bash
sudo docker exec kasm_db psql -U kasmapp -d kasm -c \
  "SELECT ingest_date, left(data->>'message',200) FROM logs WHERE levelname='ERROR' ORDER BY ingest_date DESC LIMIT 10;"
```

### Redirect URI mismatch

If the browser gets an Authentik error before ever reaching Kasm, the redirect URI does not match. Authentik in `strict` mode requires an exact string match, including scheme, host, path, and trailing characters. Copy from Kasm's read-only Redirect URL field rather than typing it.

### How far did it get?

If the traceback shows `oidc_callback` in the stack, authentication succeeded and only claim mapping failed. That means the client ID, secret, redirect URI, and endpoint URLs are all correct. It is a good place to be stuck, because it narrows the problem to scopes and attribute names.

### Locked out

Keep a local Kasm admin account working. Do not delete `admin@kasm.local` after enabling SSO. If the OIDC provider goes down or the config breaks, that account is your way back in, and there is no CLI password reset.

## Verification checklist

- [ ] Property mappings created, with Scope name set to what Kasm will request
- [ ] Scopes selected under **Advanced protocol settings**, including Kasm Profile Mapping
- [ ] Subject mode set to "Based on the User's hashed ID", and saved
- [ ] Redirect URI matches exactly between Kasm and Authentik
- [ ] OpenID Connect Issuer filled in, with trailing slash
- [ ] Kasm Scope includes `openid`, `email`, and `profile` at minimum
- [ ] Every scope Kasm requests exists in Authentik's Selected Scopes
- [ ] Username Attribute matches a claim the token actually contains
- [ ] Groups Attribute cleared if you are not doing group mapping
- [ ] Local admin account still works as a fallback

---

## *References*

- [*Kasm OpenID Connect*](https://kasmweb.com/docs/latest/guide/oidc.html): Kasm's OIDC configuration fields, including Scope and attribute mapping
- [*Kasm Groups*](https://kasmweb.com/docs/latest/guide/groups.html): Group membership and SSO group mapping
- [*Authentik OAuth2 Provider*](https://docs.goauthentik.io/docs/add-secure-apps/providers/oauth2/): Provider settings, subject mode, and the endpoint URLs Kasm needs
- [*Create an OAuth2 Provider*](https://docs.goauthentik.io/docs/add-secure-apps/providers/oauth2/create-oauth2-provider): Step-by-step provider creation
- [*Authentik Property Mappings*](https://docs.goauthentik.io/docs/add-secure-apps/providers/property-mappings/): Scope mapping syntax and the expression context used on this page
- [*Authentik Integrations*](https://integrations.goauthentik.io/): Community integration guides for other applications
- [*OpenID Connect Core 1.0*](https://openid.net/specs/openid-connect-core-1_0.html): The specification behind the standard claims and scopes referenced here
