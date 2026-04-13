# Runbook: Deploy a New Tenant

Adding a new app to the platform.

## Prerequisites

- App repo has a `frontend/Dockerfile` that produces a static site served on port 80
- App repo calls the `build-deploy.yml` reusable workflow (see house-ops for example)
- Docker image pushed to `ghcr.io/jjrasche/<repo-name>:latest`
- DNS A record for the tenant's domain points at VPS IP (no wildcard — individual records)

## Steps

1. **Add tenant to vars.yml**
   ```yaml
   # ansible/inventory/group_vars/all/vars.yml
   tenants:
     - name: my-app
       domain: myapp.jimr.fyi
       database: my_app
       repo: my-app
   ```
   Ansible templates generate the Caddyfile route, Docker Compose service, and Gatus monitor automatically.

2. **Create Cloudflare DNS record**
   - Type: A
   - Name: subdomain (e.g., `myapp`)
   - Content: VPS IP
   - Proxy: enabled

3. **Run Ansible**
   ```bash
   cd ansible && ansible-playbook -i inventory playbook.yml
   ```
   This regenerates Caddyfile, docker-compose.override.yml, and gatus config, then restarts Caddy.

4. **Verify**
   ```bash
   curl -s https://myapp.jimr.fyi | head -5
   ```
   Check Gatus at `https://status.jimr.fyi` for the new endpoint monitor.
