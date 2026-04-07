# platform

Personal hosting platform. One Hetzner VPS running shared Supabase + per-app frontends behind Caddy with automatic HTTPS. Each tenant has its own domain (subdomain of jimr.fyi or standalone like practice.exchange).

## Stack
- Provisioning: Terraform (Hetzner Cloud) + Ansible
- Runtime: Docker Compose
- CDN/DNS: Cloudflare (proxied, Full strict TLS)
- Reverse proxy: Caddy (auto HTTPS via Let's Encrypt)
- Database: Supabase self-hosted (shared Postgres, per-tenant databases)
- Backups: pg_dump to Hetzner Object Storage
- Recovery: Terraform + Ansible recreate from backup in <10 minutes

## Commands
```bash
cd terraform/hetzner && terraform apply              # Create/update VPS + storage
cd ansible && ansible-playbook -i inventory playbook.yml  # Provision + deploy
./scripts/backup.sh                                  # Manual backup
./scripts/restore.sh <backup-file>                   # Restore from backup
```

## Architecture

See `docs/platform-architecture.drawio` (and `.png` export) for full topology.

### Key Directories
- `terraform/hetzner/` — VPS, object storage bucket, firewall rules
- `ansible/roles/common/` — Docker, Caddy, backup cron, monitoring
- `ansible/roles/supabase/` — Supabase Docker Compose, env config
- `ansible/roles/frontend/` — Generic static site deploy (build + serve)
- `ansible/inventory/` — Host vars, vault-encrypted secrets
- `scripts/` — Backup, restore, health check
- `docs/` — Architecture decisions, runbooks

### Tenants
Each tenant is an app repo with its own `frontend/Dockerfile`. This repo handles where and how they run.

| App | Repo | Domain | Database |
|---|---|---|---|
| HouseOps | house-ops | house.jimr.fyi | house_ops |
| Practice Exchange | practice-exchange | practice.exchange | practice_exchange |
| Event Planner | event-planner | hike.jimr.fyi | event_planner |

### Secrets
Ansible Vault encrypts all secrets. Never committed in plaintext.
```bash
ansible-vault edit ansible/inventory/group_vars/all/vault.yml
```

## Design Decisions
- **Shared Supabase, not per-app stacks.** One Postgres, one Auth, one Realtime. 2GB RAM vs 12GB.
- **Fast recovery over HA.** One box, nightly backups, IaC recreates in 10 min. Add LB + second box when needed.
- **Caddy over nginx.** Auto HTTPS, zero config TLS, simple reverse proxy rules.
- **No K8s.** Docker Compose is right-sized for 3 personal apps on one VPS.

## Global References
Read from `~/.claude/references/` when relevant:
- `coding-standards.md` — Standards apply to scripts and config too
- `docker-immutable-infra.md` — Container patterns, CI/CD
- `supabase-local-dev.md` — Supabase self-hosting patterns
