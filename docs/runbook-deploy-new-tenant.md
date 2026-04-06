# Runbook: Deploy a New Tenant

Adding a new app to the platform.

## Prerequisites

- App repo has a `frontend/Dockerfile` that produces a static site
- App has Supabase migrations in `supabase/migrations/`
- DNS wildcard `*.jmr.fyi` points at VPS (or add a specific A record)

## Steps

1. **Create database**
   ```sql
   CREATE DATABASE new_app_name;
   ```

2. **Apply migrations**
   ```bash
   PGPASSWORD=$PG_PASS psql -h localhost -U postgres -d new_app_name \
     -f /path/to/migrations/*.sql
   ```

3. **Add Caddy route** — append to Caddyfile:
   ```
   newapp.jmr.fyi {
       reverse_proxy frontend-newapp:3001
   }
   ```

4. **Add frontend container** — append to docker-compose.override.yml:
   ```yaml
   frontend-newapp:
     build:
       context: /opt/apps/newapp/frontend
       args:
         VITE_SUPABASE_URL: "https://api.jmr.fyi"
         VITE_SUPABASE_ANON_KEY: "${ANON_KEY}"
     restart: unless-stopped
   ```

5. **Deploy**
   ```bash
   docker compose up -d --build frontend-newapp
   docker exec caddy caddy reload --config /etc/caddy/Caddyfile
   ```

6. **Verify**
   ```bash
   curl -s https://newapp.jmr.fyi | head -5
   ```
