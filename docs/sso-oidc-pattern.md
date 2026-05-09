# SSO via OIDC — Pattern for Self-Hosted Apps

How any PKCE-compliant OIDC client (Grafana, Vaultwarden, Outline, Jenkins,
etc.) signs users in through `auth.jimr.fyi` instead of carrying its own user
database.

## Architecture (V1.3)

GoTrue runs an OAuth 2.1 / OIDC authorization server. Apps redirect users to
GoTrue's `/oauth/authorize` (PKCE required), GoTrue delegates user
authentication to the auth portal at `auth.jimr.fyi/authorize`, the portal
posts the user's JWT back to `/oauth/authorizations/<id>/consent`, and GoTrue
returns the auth code to the client's callback URL.

The infrastructure wiring (already deployed):

- **ES256 keypair** in vault (`vault_gotrue_jwt_keys` private, `vault_jwt_jwks`
  public + legacy HS256 fallback for in-flight tokens / anon / service_role /
  agent JWTs)
- **GoTrue** signs new user JWTs ES256, validates both ES256 + HS256
- **PostgREST + storage** validate via JWKS (`PGRST_JWT_SECRET=${JWT_JWKS}`
  override in `docker-compose.override.yml.j2`)
- **Edge runtime** uses a custom JWKS-aware `main/index.ts` gateway in
  `ansible/roles/supabase/files/functions/main/`. `mint-agent-token` reads its
  HMAC key from `LEGACY_HS256_SECRET` (since runtime `JWT_SECRET` now holds the
  JWKS JSON, not a plain secret).
- **Realtime** stays HS256-only (Joken doesn't parse JWKS — known limitation,
  ES256 user tokens won't authenticate to realtime channels).
- **Caddy** serves the OIDC discovery doc with absolute URLs at
  `https://api.jimr.fyi/auth/v1/.well-known/openid-configuration` (working
  around supabase-auth v2.186 returning empty issuer + relative URLs).
- **Kong** has open routes for `/auth/v1/oauth/{authorize,token,userinfo}` and
  `/auth/v1/.well-known/jwks.json` (no apikey required — OIDC clients can't
  send one).
- **Auth portal** has a `/authorize` handler in `portal/app.js` that completes
  the OIDC consent flow by POSTing the user's JWT to
  `/oauth/authorizations/<id>/consent` and following the returned `redirect_to`.

## Adding a new OIDC client

Prereqs: client must implement OAuth 2.1 / RFC 7636 (PKCE with S256). Most
modern apps do — see the limitation note at the bottom for what doesn't.

1. **Pick a stable client_id (UUIDv4) and generate a client_secret**
   ```bash
   uuidgen
   openssl rand -hex 32
   ```

2. **Add both to vault**
   ```bash
   ansible-vault edit ansible/inventory/group_vars/all/vault.yml \
     --vault-password-file ~/.ansible-vault/platform
   ```
   ```yaml
   vault_<app>_oauth_client_id: "<uuid>"
   vault_<app>_oauth_client_secret: "<hex>"
   ```

3. **Add an Ansible task that upserts the OAuth client** in
   `ansible/roles/supabase/tasks/main.yml`. Direct DB insert is required
   because GoTrue's admin API rejects HS256 service_role_key with
   `"signing method HS256 is invalid"`.

   ```yaml
   - name: Generate bcrypt hash of <app> OIDC client secret
     shell: |
       docker run --rm caddy:2-alpine caddy hash-password \
         --plaintext "{{ vault_<app>_oauth_client_secret }}"
     register: <app>_secret_hash
     changed_when: false
     when: oauth_server_enabled

   - name: Upsert <app> OAuth client in auth.oauth_clients
     shell: |
       docker exec -i supabase-db psql -U supabase_admin -d postgres \
         -v ON_ERROR_STOP=1 <<'SQL'
       INSERT INTO auth.oauth_clients (
         id, client_secret_hash, registration_type, redirect_uris,
         grant_types, client_name, token_endpoint_auth_method, client_type
       ) VALUES (
         '{{ vault_<app>_oauth_client_id }}'::uuid,
         '{{ <app>_secret_hash.stdout }}',
         'manual',
         'https://<app>.jimr.fyi/<callback-path>',
         'authorization_code refresh_token',
         '<app>',
         'client_secret_post',
         'confidential'
       ) ON CONFLICT (id) DO NOTHING;
       SQL
     register: <app>_client_upsert
     changed_when: "'INSERT 0 1' in <app>_client_upsert.stdout"
     when: oauth_server_enabled
   ```

4. **Configure the client app** with these endpoints (almost always identical
   for any OIDC consumer — the auto-discovery URL is the only one most
   apps need):

   ```
   issuer:                     https://api.jimr.fyi/auth/v1
   discovery URL:              https://api.jimr.fyi/auth/v1/.well-known/openid-configuration
   client_id:                  <uuid from step 1>
   client_secret:              <hex from step 1>
   scopes:                     openid email
   redirect_uri:               https://<app>.jimr.fyi/<callback-path>
   token_endpoint_auth_method: client_secret_post
   ```

5. **Apply**
   ```bash
   cd ansible && ansible-playbook -i inventory playbook.yml \
     --vault-password-file ~/.ansible-vault/platform --tags supabase
   ```

6. **Test** — open an incognito window, visit the app, click its SSO button.
   If a user with the same email already exists at `auth.jimr.fyi`, the app
   creates a linked account; otherwise sign up at the portal first.

## Known limitation: Gitea

Gitea's OIDC consumer (verified through 1.25.2) does **not** send PKCE
parameters. supabase-auth implements OAuth 2.1 strictly — PKCE is required for
all clients, public and confidential. There is no env var to relax this
requirement.

This is **a Gitea bug**, not a platform gap. Confirmed by capturing the
`/oauth/authorize` URL Gitea generates: `client_id`, `redirect_uri`,
`response_type=code`, `scope`, `state` — but no `code_challenge` or
`code_challenge_method`. The `failed PKCE code challenge` strings in the
Gitea binary are for Gitea's *server* role (when third-party apps OAuth into
Gitea), not its *client* role.

For Gitea specifically: stay on local auth (registration disabled, HTTPS,
behind Cloudflare proxy — secure for one-user personal git). When upstream
Gitea ships PKCE for OIDC consumers, follow the recipe above.

For any other non-PKCE-capable OIDC consumer that comes up, the architectural
answer is **oauth2-proxy in front of the app**: oauth2-proxy speaks PKCE
correctly, validates the user via this platform's OIDC server, and injects
the verified identity into the upstream app via `X-WEBAUTH-USER` headers
(most apps support reverse-proxy auth natively).
