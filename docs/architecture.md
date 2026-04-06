# Platform Architecture

## Overview

Single Hetzner VPS running all personal projects. Shared Supabase backend, independent frontend containers, Caddy for HTTPS routing.

## Infrastructure

```
                 Internet
                    │
            ┌───────┴───────┐
            │  Hetzner VPS  │  CX22: 2 vCPU, 4GB RAM, 40GB SSD (~$5/mo)
            │   (Docker)    │
            └───────┬───────┘
                    │
         ┌──────────┼──────────┐
         │          │          │
    ┌────┴────┐ ┌───┴───┐ ┌───┴────┐
    │  Caddy  │ │Supabase│ │Backups │
    │ :80/443 │ │ Stack  │ │ Cron   │
    └────┬────┘ └───┬───┘ └───┬────┘
         │          │          │
    Routes to:   Contains:   Dumps to:
    *.jmr.fyi    Kong         Hetzner
                 Postgres     Object
    house.*      GoTrue       Storage
    practice.*   Realtime
    mrt.*        Studio
```

## Request Flow

1. User hits `https://house.jmr.fyi`
2. Caddy terminates TLS (Let's Encrypt auto-provisioned)
3. Request routes to `frontend-houseops` container (static files)
4. Frontend JS calls `https://api.jmr.fyi/rest/v1/*`
5. Caddy routes API calls to Kong (Supabase gateway)
6. Kong validates JWT, forwards to Postgres

## Database Layout

One Postgres instance, one database per tenant.

```
postgres (instance)
├── house_ops        # HouseOps tables, RLS policies
├── practice_exchange # Practice Exchange tables
└── mrt              # MRT tables
```

Supabase schemas (auth, storage, realtime) are shared.

## Backup Strategy

- **Frequency:** Nightly at 3am UTC
- **Method:** pg_dump per database, gzip compressed
- **Destination:** Hetzner Object Storage bucket
- **Retention:** 30 days
- **Restore:** Download backup, psql restore, <5 minutes

## Recovery Procedure

If the VPS dies:
1. Terraform creates new VPS (2 min)
2. Ansible provisions Docker + Supabase (5 min)
3. Restore latest backup from object storage (2 min)
4. DNS already points at new IP (or update A record, 1 min)

Total: ~10 minutes. No manual steps if automated recovery is wired.

## Automated Recovery (future)

```
Health check (every 5 min)
    │ fails 3x
    ▼
Webhook → GitHub Action
    │
    ├── terraform apply (new VPS)
    ├── ansible-playbook (provision)
    ├── restore backup
    └── update DNS A record (Hetzner DNS API)
```

## DNS Layout

All under `jmr.fyi` domain:

| Record | Type | Value |
|---|---|---|
| `house.jmr.fyi` | A | VPS IP |
| `practice.jmr.fyi` | A | VPS IP |
| `mrt.jmr.fyi` | A | VPS IP |
| `api.jmr.fyi` | A | VPS IP |

Or use a wildcard: `*.jmr.fyi` → VPS IP (one record covers everything).

## Security

- Caddy handles TLS. No self-signed certs.
- Supabase RLS enforces per-tenant row isolation.
- Ansible Vault encrypts all secrets (DB passwords, JWT secrets, API keys).
- VPS firewall: only 80, 443, 22 open. SSH key-only auth.
- No root SSH. Dedicated deploy user.
