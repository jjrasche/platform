# platform

Personal hosting platform. Two Hetzner VPS instances behind Cloudflare. VPS1 runs shared Supabase + per-app frontends behind Caddy. VPS2 (familyagent.jimr.fyi) is provisioned by platform but configured by the family-agent repo's own Ansible playbook.

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

See `docs/platform-architecture.drawio` for full topology.

### Servers

| Name | Terraform resource | Domain | Managed by |
|------|-------------------|--------|------------|
| VPS1 (platform) | `hcloud_server.platform` | house.jimr.fyi, hike.jimr.fyi, practice.exchange | This repo |
| VPS2 (family-agent) | (in family-agent repo) | familyagent.jimr.fyi | family-agent repo (its own Terraform + Ansible) |

Platform owns VPS1 only. Family-agent repo owns VPS2 entirely — its own Terraform, Ansible, DNS, Supabase.

### Key Directories
- `terraform/hetzner/` — Both VPS resources, firewall rules, Cloudflare DNS
- `ansible/roles/common/` — Docker, Caddy, backup cron, monitoring (VPS1 only)
- `ansible/roles/supabase/` — Supabase Docker Compose, env config (VPS1 only)
- `ansible/inventory/` — Host vars for both VPS instances, vault-encrypted secrets
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
Ansible Vault encrypts all secrets. Edit: `ansible-vault edit ansible/inventory/group_vars/all/vault.yml`

## Design Decisions
- **Shared Supabase, not per-app stacks.** One Postgres, one Auth, one Realtime. 2GB RAM vs 12GB.
- **Fast recovery over HA.** Nightly backups, IaC recreates in 10 min.
- **Two independent VPS, not private networking.** VPS2 is a separate box with its own Supabase. No shared state, no VPN. Communicate via public APIs.
- **Caddy over nginx.** Auto HTTPS, zero config TLS, simple reverse proxy rules.
- **No K8s.** Docker Compose is right-sized for personal apps on small VPS instances.

## Ecosystem — Family Agent Platform

This repo is part of a multi-repo system. Read `~/.claude/coordination/contracts.md` for shared interfaces.

| Repo | Role | This repo's relationship |
|------|------|--------------------------|
| **platform** (this) | Infrastructure | Hosts Supabase, deploys migrations from all repos |
| **family-agent** | Application | Runs on VPS2 (provisioned here). Own Supabase + Ansible. |
| **thalamus** | Channels | Channel apps route through Supabase hosted here |
| **unified-memory** | Knowledge | Schema deployed here via Ansible |
| **house-ops** | Legacy | Being absorbed into family-agent |

Ownership: Terraform (both VPS), Cloudflare DNS, VPS1 Ansible/Docker/Caddy, storage buckets. VPS2 provisioning only.
DO NOT modify `memory.*` schema — that's unified-memory's. Deploy only.

## Coordination & References
- Contracts: `~/.claude/coordination/contracts.md` | Proposals: `~/.claude/coordination/proposals/`
- Coordination script: `scripts/coordinate.sh` | Logs: `~/.claude/coordination/logs/`
- Standards: `~/.claude/references/coding-standards.md`, `docker-immutable-infra.md`, `supabase-local-dev.md`
