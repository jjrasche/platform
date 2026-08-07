# Zitadel as the identity provider

**Goal.** Identity, groups, and roles live in a real IdP. Pomerium enforces per-route on role
claims. Granting a person access to a site is assigning a role in an admin UI — no git, no
converge. GoTrue stops being an OIDC provider and returns to issuing Supabase sessions.

**Why not what we have.** GoTrue's OIDC server cannot carry authorization: the custom-token hook
has one call site (`GenerateAccessToken`), `IDTokenClaims` is a typed struct with no extension
field, `/oauth/userinfo` never reads `app_metadata`, and OAuth scopes are hard-coded. Verified in
`supabase/auth` v2.186.0 and `main`. No configuration reaches it.

**Why not Cloudflare Access.** It would make Cloudflare the authenticator of record — identities,
sessions, and the login surface owned off-box, with no local fallback.

## Component end-state

| Piece | Role |
|---|---|
| Zitadel (`zitadel-api` + `zitadel-login` + its own Postgres) | identity, users, orgs, projects, roles |
| Pomerium | TLS, routing, enforcement on role claims (`idp_provider: oidc`) |
| GoTrue | Supabase sessions + RLS only; federated to Zitadel for login |
| Supabase Postgres | unchanged, still the app database |

Zitadel gets its **own Postgres container**, not the Supabase instance: Zitadel is
event-sourced and recomputes all state from `eventstore.events2`, so its database is its
entire durability story and must not share a failure domain with app data.

## The wall this plan is shaped around

GoTrue has **no generic OIDC provider**. The provider switch in `internal/api/external.go`
enumerates named providers only. The community "use the keycloak slot" trick **does not work for
Zitadel**: `internal/api/provider/keycloak.go` hardcodes
`/protocol/openid-connect/{auth,token,userinfo}`, while Zitadel serves `/oauth/v2/authorize`,
`/oauth/v2/token`, `/oidc/v1/userinfo`. Zero overlap, and no env var changes it.

**Chosen path: a path-rewrite shim.** Point `GOTRUE_EXTERNAL_KEYCLOAK_URL` at a vhost that
rewrites those three Keycloak paths onto Zitadel's. Keeps stock GoTrue, keeps the redirect flow,
keeps automatic identity linking (which is what preserves user UUIDs).

Rejected: `signInWithIdToken` (deprecated upstream, app must fetch the token itself); SAML SSO
(sets `is_sso_user`, gets its own linking domain → new UUIDs → breaks RLS); forking GoTrue.

## Phase 0 — settle the unknowns before anything moves

**Status 2026-08-07: 0.1, 0.2, 0.3 PASS. 0.4 outstanding.** Zitadel v4.16.2 runs on the box as
its own compose project (`/opt/zitadel`), fronted by Pomerium at `id.jimr.fyi` — `auth.jimr.fyi`
was already the OIDC portal page. Two plan assumptions were corrected by running it: the shim
needs no container of its own (Pomerium's `prefix_rewrite` can do the three path rewrites), and
the compose network join must be *declared*, since an imperative `docker network connect` is lost
on the next container recreate.

Nothing in this phase touches a running service. Each is pass/fail.

0.1 **PASS.** `zitadel/oidc` declares `type Bool bool` with a custom *un*marshaler only, so
encoding emits a real JSON boolean; the live discovery doc advertises `email_verified` among 24
claims (GoTrue advertises 8). GoTrue's `.(bool)` assertion will hold → verified users link →
**UUIDs preserved → this is a config change, not a data migration.**
Original question: **does Zitadel emit `email_verified` as a JSON boolean?** This single claim decides whether
existing users keep their UUIDs. `keycloak.go` does `RawClaims["email_verified"].(bool)`; a JSON
string `"true"` fails the assertion, silently becomes false, and forces new accounts. Decode a
real ID token from the instance stood up in 1.1. **Fail → stop; the migration is a data
migration, not a config change.**

0.2 **PASS.** Pomerium `h2c://zitadel-zitadel-api-1:8080` with `preserve_host_header` serves
discovery over the proxy and Zitadel derives `issuer: https://id.jimr.fyi` correctly. The
combination is documented by neither project; it works. (A wrong Host returns 404 "instance not
found" — observed directly before the header was preserved.)

0.3 **PASS.** Through the proxied hostname: discovery 200, `/ui/console` 200, and a grpc-web
`POST /zitadel.admin.v1.AdminService/Healthz` returns 200 over HTTP/1.1 — the orange cloud does
not break Connect-RPC. No grey-cloud fallback needed.

0.4 **OUTSTANDING — the remaining unknown, and now the largest piece of work.** Three
`prefix_rewrite` routes on a shim hostname mapping `/protocol/openid-connect/{auth,token,userinfo}`
onto `/oauth/v2/authorize`, `/oauth/v2/token`, `/oidc/v1/userinfo`; then a federated sign-in with
a throwaway account; then the SQL in 4.3. Prerequisite discovered while running Phase 0: creating
the OIDC application needs Zitadel management-API access, which means either a headless Console
login or re-initialising the instance with a bootstrap machine-user PAT
(`ZITADEL_DEFAULTINSTANCE_ORG_MACHINE_MACHINE_USERNAME` + `..._PAT_EXPIRATIONDATE`, verified in
`cmd/defaults.yaml`). Re-init is free while the instance holds no real identities.

## Phase 1 — Zitadel up, nothing switched

1.1 Compose service alongside the existing stack, from the official quickstart plus the
`mode-external-tls` overlay (Pomerium terminates TLS): `ZITADEL_EXTERNALSECURE=true`,
`ZITADEL_TLS_ENABLED=false`, `ZITADEL_EXTERNALDOMAIN=auth.jimr.fyi`, `ZITADEL_EXTERNALPORT=443`,
32-char `ZITADEL_MASTERKEY` into the ansible vault. Images are multi-arch (arm64 confirmed on
`ghcr.io/zitadel/zitadel` and `-login`); pin the tag by digest. Delete upstream's Traefik service.
Login v2 is a **separate container** served at `/ui/v2/login` — set the `LOGINV2` env block or the
login flow 404s.

1.2 Pomerium routes for the IdP itself, both `allow_public_unauthenticated_access: true` (gating
the IdP behind Pomerium auth is a redirect loop) and `preserve_host_header: true` (Host must
arrive as `ExternalDomain` or Zitadel answers *"Instance not found"*):
`/ui/v2/login` → `http://zitadel-login:3000`, everything else → `h2c://zitadel-api:8080`.

1.3 **Gate:** Console loads, admin user logs in, discovery doc resolves. **Rollback:** delete two
routes and the compose services; nothing else was touched.

## Phase 2 — Pomerium authenticates against Zitadel

2.1 In Zitadel: one project, one OIDC application (web, code+PKCE), redirect URI
`https://authenticate.jimr.fyi/oauth2/callback`.

2.2 Point Pomerium at it: `idp_provider: oidc`, `idp_provider_url: https://auth.jimr.fyi`,
client id/secret from the vault. **`idp_scopes` REPLACES the defaults** (`pkg/identity/oidc/oidc.go`
only uses defaults when the list is empty) — so list `openid`, `profile`, `email`,
`offline_access` explicitly, plus the role scopes in 3.2.

2.3 **Gate:** sign in to one gated route via Zitadel. **Rollback:** revert the four `idp_*` lines
to the GoTrue values and converge; GoTrue is untouched and still works throughout this phase.

## Phase 3 — roles decide access

3.1 Model access as project roles (`land-viewer`, `household`, …), assigned per user in the
Zitadel console. That assignment is the grant, and it is the whole point of this migration.

3.2 Emit them. Zitadel's native claim is a **nested object** keyed by project and org id, and
Pomerium **dot-flattens** nested claims (`pkg/identity/claims.go`), producing selectors like
`claim/urn:zitadel:iam:org:project:<PROJID>:roles.admin.<ORGID>` — brittle and it embeds two ids.
**Preferred:** an Actions v2 execution on the `preuserinfo` function returning
`{"append_claims":[{"key":"roles","value":["land-viewer"]}]}`, giving a flat array and reducing
every policy to `claim/roles: land-viewer`. Costs one small webhook service. (Actions cannot write
keys under the reserved `urn:zitadel:iam` prefix — hence a plain `roles` key.)
Enable *Assert Roles on Authentication* (project) and *User roles inside ID token* (application).

3.3 Convert the gated route from `authenticated_user: true` to `claim/roles: land-viewer`.

3.4 **Gate:** a user WITH the role gets in; the same user with the role removed gets 403 **after a
session refresh, with no converge**. That is the requirement, tested directly. Note claims refresh
on session refresh, not instantly — if revocation must be immediate, clear the Pomerium session
(there is already a `clear-pomerium-cache` skill).

## Phase 4 — GoTrue federates, UUIDs survive

4.1 Stand up the rewrite shim mapping the three Keycloak paths onto Zitadel's.

4.2 Configure GoTrue: `GOTRUE_EXTERNAL_KEYCLOAK_ENABLED=true`, `_URL` → the shim, `_CLIENT_ID`,
`_SECRET`, and `_REDIRECT_URI=${API_EXTERNAL_URL}/auth/v1/callback` (mandatory, never defaulted).
Do **not** set `GOTRUE_EXPERIMENTAL_PROVIDERS_WITH_OWN_LINKING_DOMAIN` for this provider — it
removes it from the default linking pool and forces new UUIDs. `GOTRUE_SECURITY_MANUAL_LINKING_ENABLED`
is irrelevant here (it only guards the `/user/identities` route, not automatic linking).

4.3 **The test that decides everything** — throwaway account, before and after one federated
sign-in:

```sql
select id, email, email_confirmed_at, is_sso_user, encrypted_password is not null as has_pw
from auth.users where email = 'test@example.com';

select id, user_id, provider, provider_id, identity_data->>'email_verified' as ev
from auth.identities where user_id = '<uuid>';
```

Pass = same `id`, one additional identity row. Fail = a second `auth.users` row with a new UUID
and a blanked email — at which point every RLS row keyed to the old id is orphaned.

Linking rule (`internal/models/linking.go`, identical at v2.186.0 and `main`): a **verified** email
matching an existing non-SSO user → `LinkAccount`, existing row reused, **UUID preserved**. No
verified email → `CreateAccount`, new UUID. Hence 0.1.

4.4 **Rollback:** disable the provider; existing email/password logins still work — they were never
removed. One caveat: for a user whose email was *unconfirmed*, linking deletes the email identity
and nulls the password, so that user can only log in federated afterward. Confirm emails first.

## Phase 5 — retire the old role, migrate the rest

5.1 Move remaining gated routes to role claims. 5.2 Turn off GoTrue's OAuth server
(`GOTRUE_OAUTH_SERVER_ENABLED=false`) — nothing consumes it once Pomerium is on Zitadel. 5.3 Delete
the `gated`/`allowed_emails` scaffolding from `vars.yml` and the Pomerium template; access now lives
in Zitadel. 5.4 Keep `DISABLE_SIGNUP=true` — invites become Zitadel invitations.

## Owning this

Releases ~every 2 weeks; each major supported ~6 months. Breaking changes bump the major and get a
Technical Advisory with ≥5 working days' notice — **reading advisories before upgrading is the
ritual**. DB migrations run automatically in the setup phase (idempotent and resumable);
`start-from-init` does init+setup+start in one container, which suits a single box. Whether majors
can be skipped is undocumented — treat v4→v5 as a planned exercise, not a `docker pull`.

Footprint per Zitadel's production guide: ~512MB RAM and <1 core for the app, with a warning about
CPU spikes during password hashing (they suggest 4 cores available for it); Postgres wants real
headroom. Redis optional.

**Backup = Postgres + the masterkey.** The binary is stateless and all state recomputes from the
event table, but the masterkey is not in the database and without it the dump is unreadable. It
lives in the vault; losing it means losing the instance.

## Open decisions

1. **Raw flattened role claims vs an Actions webhook** (3.2). Zero infra and ugly selectors, or one
   more container and `claim/roles: x`. Recommend the webhook.
2. **Where Zitadel's Postgres lives** — separate container (recommended, isolates the failure
   domain) or a database inside the Supabase instance (supported; Zitadel needs superuser only to
   provision).
3. **Zitadel's own admin access** — its Console is public-at-gateway by necessity; MFA on the admin
   user is the control.
