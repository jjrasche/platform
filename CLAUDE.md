# platform

Personal hosting platform. Two Hetzner VPS instances behind Cloudflare. VPS1 runs shared Supabase + per-app frontends behind Pomerium (IAP + TLS terminator). VPS2 (familyagent.jimr.fyi) is provisioned by platform but configured by the family-agent repo's own Ansible playbook.

## Stack
- Provisioning: Terraform (Hetzner Cloud) + Ansible
- Runtime: Docker Compose
- CDN/DNS: Cloudflare (proxied, Full strict TLS)
- Edge gateway: Pomerium (identity-aware proxy + TLS terminator, Cloudflare Origin Cert)
- Internal API gateway: Kong (path-routes Supabase microservices behind Pomerium)
- Identity: GoTrue / supabase-auth (OAuth 2.1 Server, ES256 JWTs)
- Static file serving: nginx sidecar (`static-jimr`) for portal/dm/apps + corrected OIDC discovery
- Database: Supabase self-hosted (shared Postgres, per-tenant databases)
- Backups: GPG-encrypted nightly pg_dump to `/opt/backups` on VPS1. **Local-only; no off-site replication wired yet** (TODO: rclone to Hetzner Object Storage). Private key offline in password manager; public key in `scripts/backup-public.asc`.
- Recovery: Terraform + Ansible recreate VPS, then restore from the most recent encrypted backup. <10 min assumes the backup disk survived; full-VPS-loss recovery needs off-site replication wired (above).

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
- `ansible/roles/common/` — Docker, deploy user, swap, fail2ban (sshd + pomerium-auth jails), unattended-upgrades, backup cron, GPG keyring import (VPS1 only)
- `ansible/roles/pomerium/` — Pomerium config + cert files + static-jimr sidecar template
- `ansible/roles/supabase/` — Supabase Docker Compose, env config (VPS1 only)
- `ansible/inventory/` — Host vars for both VPS instances, vault-encrypted secrets
- `scripts/` — Backup, restore, health check, plus `backup-public.asc` + `backup-recipient.fingerprint`
- `docs/runbooks/` — backup-restore, cutover procedures

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
- **Fast recovery over HA.** Nightly backups, IaC recreates in 10 min (within VPS-disk-survives scope).
- **Two independent VPS, not private networking.** VPS2 is a separate box with its own Supabase. No shared state, no VPN. Communicate via public APIs.
- **Pomerium over Caddy (cutover 2026-05-10/11).** Caddy was simpler; Pomerium gives identity-aware gating on Gitea/Studio/status/apps. CF Origin Cert (not Let's Encrypt; LE TLS-ALPN-01 doesn't traverse CF proxy).
- **Encrypt-at-source backups, key offline.** GPG asymmetric. VPS compromise yields ciphertext only.
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

Ownership: Terraform (both VPS), Cloudflare DNS, VPS1 Ansible/Docker/Pomerium/Kong/Supabase, storage buckets. VPS2 provisioning only.
DO NOT modify `memory.*` schema — that's unified-memory's. Deploy only.

## Coordination & References
- Contracts: `~/.claude/coordination/contracts.md` | Proposals: `~/.claude/coordination/proposals/`
- Coordination script: `scripts/coordinate.sh` | Logs: `~/.claude/coordination/logs/`
- Standards: `~/.claude/references/coding-standards.md`, `docker-immutable-infra.md`, `supabase-local-dev.md`
