# Reply to dungeon-master implementer — DB tunnel + dm_seeder role

Provisioned. Send your SSH pubkey and I unlock you the same day.

## Approved approach

- **Scoped role over `supabase_admin`**: `dm_seeder` with `BYPASSRLS`, narrow grants. You don't get to touch other tenants' schemas or `auth.identities`/`auth.sessions`/`auth.refresh_tokens`.
- **Port-forward-only SSH user** (`dm_tunnel`), no shell, no agent forwarding, locked to `permitopen="127.0.0.1:5432"`. Cannot run commands on VPS1, cannot tunnel anywhere except Postgres.
- **Postgres exposed on host loopback only** (`127.0.0.1:5432`). The tunnel is the only path in. No internet exposure.
- **Decline pre-writing the GRANT migration** — I keep the role grants in platform Ansible (`tenant_dev_db_access` in `vars.yml` + `dev_db_role_setup.sql.j2`). Cleaner separation: dm owns the schema, platform owns the role. If you add a new dm.* table, the role automatically gets the same grants on it (`ALTER DEFAULT PRIVILEGES`).
- **Decline the V1.4 PostgREST-RPC alternative.** asyncpg + tunnel is the right shape here. Service-role JWT seeding has worse blast radius.

## What I need from you

Generate a dedicated keypair (do NOT reuse an existing key — this one only goes to the platform tunnel user):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_platform_db -C "dm-implementer-platform-db"
```

Send me the contents of `~/.ssh/id_platform_db.pub`. Private key stays on your laptop.

## What you get back when I authorize your key

The `dm_seeder` Postgres password is already provisioned in the platform vault. After I add your pubkey and redeploy (5 min), use:

```bash
# ~/.ssh/config (add this block)
Host platform-db
  HostName 91.98.158.239
  User dm_tunnel
  IdentityFile ~/.ssh/id_platform_db
  IdentitiesOnly yes

# Open tunnel (ad-hoc, when you run the suite — kill when done)
ssh -f -N -L 5433:127.0.0.1:5432 platform-db

# Connection string
DATABASE_URL=postgresql://dm_seeder:<password-i-send-back>@localhost:5433/postgres
```

The `dm_seeder` role:
- `BYPASSRLS`
- `INSERT, SELECT, DELETE` on every table in `dm.*` (current and future — `ALTER DEFAULT PRIVILEGES` is set)
- `INSERT, SELECT, DELETE` on `auth.users` only (you can seed test users; you can't impersonate them via sessions because you don't get `auth.identities` or `auth.refresh_tokens`)
- Cannot touch other tenants' schemas

## What you commit on your end

- `~/.claude/references/ssh-tunnels.md` already has the platform-db block (I just landed it). You can read but don't need to add.
- Your repo's `.env.example` should show the expected `DATABASE_URL` shape (gitignore `.env.local`).
- Document the tunnel command + alias in your repo README under "Running the regression suite."

## Out of scope

- Always-on tunnel. We do ad-hoc only — open before suite runs, close after.
- Sharing the tunnel with another developer. Each developer gets their own keypair under the same `dm_tunnel` user (we add multiple keys to `authorized_keys`). Send a fresh pubkey for each new developer.
- Running anything other than Postgres queries through this tunnel. Agent forwarding, X11, pty — all blocked at the `authorized_keys` level.
