# Realm & User Configuration — Keycloak Admin Console

> Realm: `rentoption.com` | Keycloak 26.6 | Admin console: `https://sso.rentoption.com/admin`
> Source of truth for automated setup: `keycloak/realm-export.json` (auto-imported on first boot via `docker-compose.yml` `start --optimized --import-realm`).

## 1. Can this be done from the UI?

Yes. Every fix below was applied through the Keycloak Admin REST API, which is the same backend that drives the Admin Console. The API was used for reproducibility, but each step maps 1:1 to a UI action described here.

## 2. Prerequisites

- Open the Admin console: `https://sso.rentoption.com/admin`
- Log in with the admin user (`.env` `KEYCLOAK_ADMIN_PASSWORD`)
- Use the realm selector (top-left) to switch to `rentoption.com` (the realm ID is the lowercase AD domain; the Kerberos realm is the uppercase `RENTOPTION.COM`)
- Remember the realm is imported from `keycloak/realm-export.json` only on a fresh database. Live changes made in the UI live in the Keycloak DB volume and must be exported back to the JSON to be reproducible (see Section 7).

## 3. Client Scopes

Navigate to `Client scopes` in the realm.

### 3.1 Expected scope list

The realm now has 14 client scopes. The export historically had only 5 (`profile`, `email`, `roles`, `web-origins`, `offline_access`). You must add the 9 missing ones (`basic`, `acr`, `address`, `phone`, `organization`, `microprofile-jwt`, `role_list`, `service_account`, `saml_organization`) and fix `roles` and `profile`.

### 3.2 Create the 9 missing scopes

For each scope: click `Client scopes` -> `Create client scope`, enter Name / Protocol / Attributes, save, then open the scope and add its mappers under the `Mappers` tab.

| Scope | Protocol | Attributes | Mappers (Name / Mapper type / key config) |
|-------|----------|------------|------------------------------------------------|
| `basic` | openid-connect | include.in.token.scope = false, display.on.consent.screen = false | `sub` (oidc-sub-mapper, access true); `auth_time` (oidc-usersessionmodel-note-mapper, User Session Model Note = AUTH_TIME, Claim name = auth_time) |
| `acr` | openid-connect | include.in.token.scope = false, display.on.consent.screen = false | `acr loa level` (oidc-acr-mapper, Default acr.loa value = 1) |
| `address` | openid-connect | include.in.token.scope = true, display.on.consent.screen = true | `address` (oidc-address-mapper) |
| `phone` | openid-connect | include.in.token.scope = true, display.on.consent.screen = true | `phone number` (oidc-usermodel-attribute-mapper, user.attribute = phoneNumber); `phone number verified` (user.attribute = phoneNumberVerified) |
| `organization` | openid-connect | include.in.token.scope = true, display.on.consent.screen = false | `organization membership` (organization-membership-mapper) |
| `microprofile-jwt` | openid-connect | include.in.token.scope = true, display.on.consent.screen = false | `upn` (oidc-usermodel-attribute-mapper, user.attribute = username); `groups` (oidc-usermodel-realm-role-mapper with groups claim) |
| `role_list` | saml | include.in.token.scope = false, display.on.consent.screen = false | `role list` (role-list-mapper) |
| `service_account` | openid-connect | include.in.token.scope = false, display.on.consent.screen = false | `clientHost`, `clientAddress`, `client_id` (oidc-usersessionmodel-note-mapper) |
| `saml_organization` | saml | include.in.token.scope = false, display.on.consent.screen = false | `organization` (saml-organization-mapper) |

### 3.3 Fix the existing `roles` scope

Open the `roles` client scope -> `Mappers` tab. Delete any stale `client_roles` / `realm_roles` mappers, then create these three:

- `audience resolve` — mapper type `oidc-audience-resolve-mapper`
- `realm roles` — mapper type `oidc-usermodel-realm-role-mapper`, Claim name = `realm_access.roles`, access token claim = true
- `client roles` — mapper type `oidc-usermodel-client-role-mapper`, Claim name = `resource_access.${client_id}.roles`, access token claim = true

These mappers are what put `realm_access` / `resource_access` (including `resource_access.account`) into the access token.

### 3.4 Fix the `profile` scope

Open the `profile` client scope -> `Mappers` tab and add the 11 standard OIDC claim mappers that are missing: `middle name`, `birthdate`, `full name`, `gender`, `zoneinfo`, `locale`, `nickname`, `picture`, `profile`, `updated at`, `website`.

## 4. Clients

Navigate to `Clients` and edit `account` and `account-console`.

### 4.1 `account` client

- `Settings` tab: set `Client type`/`Public` = true, and toggle `Full scope allowed` to **ON**.
- `Client scopes` tab -> `Assigned default client scopes`: add `acr` and `basic`. Final default set: `web-origins`, `acr`, `profile`, `roles`, `basic`, `email`.
- `Assigned optional client scopes`: add `organization` and `microprofile-jwt`. Final optional set: `address`, `phone`, `offline_access`, `organization`, `microprofile-jwt`.
- `Advanced` tab -> `Attributes`: set `post.logout.redirect.uris=+` (global logout).

### 4.2 `account-console` client

- `Settings` tab: `Client type`/`Public` = true, `Root URL` = `${authBaseUrl}`, `Home URL`/`Base URL` = `/realms/rentoption.com/account/`, `Valid redirect URIs` = `/realms/rentoption.com/account/*`, `Web origins` = `https://sso.rentoption.com`.
- Toggle `Full scope allowed` to **ON**. This is required for the token to carry `resource_access.account` and `aud: account`, which the account console API requires.
- `Authentication flow`/`Advanced`: `Proof Key for Code Exchange (PKCE) code challenge method` = `S256` (other methods empty).
- Set the `Client scopes` (default and optional) to the same sets as `account` in Section 4.1.

> **UI caveat:** Keycloak ignores the `defaultClientScopes` field if you edit a client's general settings. To change assigned scopes you must use the `Client scopes` tab on the client (which calls the dedicated per-scope admin endpoint), not the JSON / general settings.

## 5. Roles and Default Roles

### 5.1 `account` client roles

`Clients` -> `account` -> `Roles` tab -> `Create role`. Create these 7 roles:

`view-profile`, `manage-account`, `manage-account-links`, `view-applications`, `view-consent`, `manage-consent`, `delete-account`

### 5.2 Realm role `default-roles-rentoption.com`

`Realm roles` -> `Create role`, name = `default-roles-rentoption.com`, enable `Composite`.

Then in this role's `Associated roles` (composites) tab add:
- Realm roles: `uma_authorization`, `offline_access`
- Client roles (client `account`): `view-profile`, `manage-account`, `manage-account-links`, `view-applications`, `view-consent`, `manage-consent`, `delete-account`

### 5.3 Verify the default role

`Realm settings` -> `General` -> `Default role` should show `default-roles-rentoption.com`. Every new user inherits this composite, which grants account-console access so the token contains `resource_access.account` and `aud: account`.

## 6. Verification (Account Console)

1. Open a private/incognito window: `https://sso.rentoption.com/realms/rentoption.com/account/`
2. Log in with an AD-synced user, e.g. `testuser` (password `Admin1234`, set via `samba-tool setpassword`)
3. The Profile page should load without a "Something went wrong" error.
4. Open browser DevTools -> Network and confirm:
   - `GET .../account/supportedLocales` returns `200` with `["en","es"]`
   - `GET .../account/?userProfileMetadata=true` returns `200`
5. Decode the access token (e.g. at jwt.io) and confirm it contains:
   - `sub` (from the `basic` scope's sub mapper)
   - `acr: 1` (from the `acr` scope)
   - `resource_access.account.roles` (from the `roles` scope client-roles mapper + `audience resolve`)
   - `aud: account`

> Note: If you test the API against `http://localhost:8080` directly you may get `401` / Host-mismatch errors; always test through the public URL `https://sso.rentoption.com` exactly as the browser does.

## 7. Persistence and Reproducibility

UI changes are stored in the Keycloak database volume (`keycloak_data` volume in `docker-compose.yml`) and do **not** survive a fresh deploy unless exported back into `keycloak/realm-export.json`.

To persist changes:
- `Realm settings` -> `Partial export` (or query the realm via `GET http://localhost:8080/admin/realms/rentoption.com` with an admin token), then overwrite `keycloak/realm-export.json` and commit.

`scripts/deploy.sh` and `docker-compose.yml` run Keycloak with `--import-realm`, which imports `realm-export.json` only on a fresh database.

## 8. Future SSO Goal (Services Portal)

The longer-term goal is a portal where AD users see the services they are granted and are provisioned (JIT) on first login, with service-to-service token exchange. This builds on the pieces above:

- For each service: `Clients` -> create client (confidential or public, Valid redirect URIs, Web origins), then add dedicated mappers (roles/groups) under the client's `Client scopes`.
- Use `Realm roles` composites to express service access (as done for the `account` roles in Section 5).
- Token exchange is available via the `token-exchange` feature (set in `docker-compose.yml` `KC_FEATURES`).

## 9. Appendix — CLI / API equivalents

For automation, the same operations via the Admin REST API (all against `http://localhost:8080` with an admin bearer token from `realms/master/protocol/openid-connect/token`):

- Add default scope to a client:
  `PUT /admin/realms/<realm>/clients/<client-uuid>/default-client-scopes/<clientScopeId>` (returns 204)
- Add optional scope to a client:
  `PUT /admin/realms/<realm>/clients/<client-uuid>/optional-client-scopes/<clientScopeId>`
- Create a client role:
  `POST /admin/realms/<realm>/clients/<client-uuid>/roles`
- Add realm or client composites to a role:
  `POST /admin/realms/<realm>/roles-by-id/<role-id>/composites`
- Add a mapper to a client scope:
  `POST /admin/realms/<realm>/client-scopes/<scope-id>/protocol-mappers/models`

Quirks observed on Keycloak 26.6:
- Client `PUT` ignores the `defaultClientScopes` / `optionalClientScopes` fields; only the dedicated per-scope endpoints above work.
- Scope mappers are not updated by a scope `PUT`; use the `POST .../protocol-mappers/models` and `DELETE .../models/<mapper-id>` endpoints.

## 10. Troubleshooting

- **Scopes missing from the token** `scope` claim is normal when `include.in.token.scope=false` (e.g. `roles`, `basic`, `acr`); their mappers still add claims to the token.
- **Account API 401 when testing on `localhost:8080`** is expected (Host mismatch). Test via `https://sso.rentoption.com`.
- **Token has no `resource_access.account` / `aud: account`** — confirm `Full scope allowed` is ON for `account` and `account-console`, the `roles` scope has the `audience resolve` + client-roles mappers, and users inherit `default-roles-rentoption.com` via the default role.
- **`reset-password` via Keycloak API does not write to AD** for LDAP-federated users. Change AD passwords with `samba-tool setpassword` (see `samba/scripts/create-user.sh`).
