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
    jimr.fyi     Kong         Hetzner
    practice.    Postgres     Object
    exchange     GoTrue       Storage
                 Realtime
                 Studio
```

## Request Flow

1. User hits `https://house.jimr.fyi`
2. Caddy terminates TLS (Let's Encrypt auto-provisioned)
3. Request routes to `frontend-house-ops` container (static files)
4. Frontend JS calls `https://api.jimr.fyi/rest/v1/*`
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

Two domains, one VPS IP:

| Record | Type | Value | Notes |
|---|---|---|---|
| `jimr.fyi` | A | VPS IP | Supabase Studio |
| `*.jimr.fyi` | A | VPS IP | Covers house, mrt, api subdomains |
| `practice.exchange` | A | VPS IP | Standalone domain |

Wildcard `*.jimr.fyi` covers `house.jimr.fyi`, `mrt.jimr.fyi`, and `api.jimr.fyi`. `practice.exchange` requires its own A record at its registrar.

## Security

- Caddy handles TLS. No self-signed certs.
- Supabase RLS enforces per-tenant row isolation.
- Ansible Vault encrypts all secrets (DB passwords, JWT secrets, API keys).
- VPS firewall: only 80, 443, 22 open. SSH key-only auth.
- No root SSH. Dedicated deploy user.
