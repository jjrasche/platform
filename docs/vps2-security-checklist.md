# VPS2 (family-agent) Security Checklist

Ownership: **family-agent** owns VPS2 entirely (Terraform, Ansible, DNS, Supabase). **platform** owns Cloudflare zone-level settings only (SSL, TLS, HSTS apply zone-wide).

## Platform responsibilities (this repo)

### Firewall (Hetzner Cloud — Terraform)

| Port | Protocol | Source | Status |
|------|----------|--------|--------|
| 22 | TCP | `ssh_allowed_ipv4`/`ipv6` vars (falls back to 0.0.0.0/0 if unset) | Managed |
| 80 | TCP | Cloudflare IPv4 + IPv6 ranges only | Managed |
| 443 | TCP | Cloudflare IPv4 + IPv6 ranges only | Managed |
| All others | * | **Blocked** (Hetzner default-deny) | Managed |

Action items:
- [ ] Set `ssh_allowed_ipv4` in `terraform.tfvars` to your home/office IP(s) to lock SSH
- [ ] Verify Cloudflare IP list matches https://www.cloudflare.com/ips/ (last checked 2026-04-16)

### Cloudflare (zone-wide, Terraform)

| Setting | Value | Scope |
|---------|-------|-------|
| SSL mode | Full (Strict) | Zone-wide (all subdomains) |
| Always Use HTTPS | On | Zone-wide |
| Minimum TLS | 1.2 | Zone-wide |
| TLS 1.3 | On | Zone-wide |
| HSTS | Enabled, include subdomains, max-age 1 year, preload | Zone-wide |
| Automatic HTTPS Rewrites | On | Zone-wide |

Note: Cloudflare does not support per-subdomain SSL mode or HSTS via API. These are zone-level settings that apply to familyagent.jimr.fyi along with all other subdomains.

### DNS

- `familyagent.jimr.fyi` A record proxied through Cloudflare (orange cloud)
- Origin IP never exposed to public internet

## Family-agent responsibilities (family-agent repo)

### SSH hardening

- [ ] Key-only auth (disable `PasswordAuthentication` in sshd_config)
- [ ] Disable root login (`PermitRootLogin no`)
- [ ] Use `deploy` user with sudo, not root
- [ ] Install and configure fail2ban (SSH jail, 5 attempts, 1-hour ban)
- [ ] Consider non-standard SSH port (update Hetzner firewall if changed)

### Supabase security (VPS2's own instance)

- [ ] JWT secret: unique, 40+ char, stored in Ansible Vault — NOT shared with VPS1
- [ ] Postgres port (5432) bound to `127.0.0.1` only — no public exposure
- [ ] Supabase Studio either disabled or behind auth middleware — never public
- [ ] RLS enabled on every table, no exceptions
- [ ] `anon` key scoped to read-only where applicable
- [ ] `service_role` key never exposed to frontend or Edge Functions that handle user input
- [ ] GoTrue email confirmations enabled (or autoconfirm with known-user-only policy)
- [ ] Dashboard API keys rotated on first deploy

### Agent runtime security

- [ ] Agent M2M tokens (Contract 3) use short expiry (15 min recommended)
- [ ] `mint-agent-token` Edge Function validates caller identity before issuing tokens
- [ ] Agent process runs as unprivileged user inside Docker container
- [ ] No host-network mode for agent containers

### Outbound traffic audit (mitmproxy)

- [ ] mitmproxy runs as a forward proxy for agent containers
- [ ] Agent Docker containers route outbound traffic through mitmproxy (`HTTP_PROXY`/`HTTPS_PROXY`)
- [ ] mitmproxy logs all outbound requests (destination, method, response code)
- [ ] Alerting on unexpected outbound destinations (new domains not in allowlist)
- [ ] mitmproxy management UI bound to `127.0.0.1` only

### Docker security

- [ ] All containers run with `--read-only` where feasible
- [ ] No `--privileged` containers
- [ ] Docker socket not mounted into application containers
- [ ] Container images pinned to digest or specific version tags, not `latest`
- [ ] Resource limits (`--memory`, `--cpus`) on ML pipeline containers

### Backup and recovery

- [ ] Nightly pg_dump to Hetzner Object Storage (separate credentials from VPS1)
- [ ] Backup bucket access key scoped to write-only (no delete permission)
- [ ] Backup files encrypted at rest (S3 server-side encryption or gpg before upload)
- [ ] Recovery tested: restore from backup to fresh VPS within 10 minutes
- [ ] Ansible Vault password stored securely, not in any repo

### Monitoring

- [ ] Gatus or equivalent health checks for familyagent.jimr.fyi
- [ ] Disk usage alerts (ML models + Postgres can fill 16GB quickly)
- [ ] Failed SSH attempt monitoring (fail2ban logs or journald)
- [ ] Docker container restart monitoring

## Verification schedule

| Check | Frequency | How |
|-------|-----------|-----|
| Cloudflare IP ranges current | Monthly | Compare Terraform locals with https://www.cloudflare.com/ips/ |
| SSH key rotation | Quarterly | Rotate `id_platform` keypair, update Hetzner + authorized_keys |
| Supabase JWT secret rotation | Quarterly | Rotate via Ansible Vault, redeploy |
| Backup restore test | Monthly | Restore to local Docker, verify data integrity |
| Dependency CVE scan | Weekly | Automated via GitHub Dependabot or similar |
