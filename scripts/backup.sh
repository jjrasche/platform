#!/bin/bash
# Nightly backup: dump each tenant database, upload to object storage
set -euo pipefail

BACKUP_DIR="/opt/backups"
DATE=$(date +%Y%m%d)

DATABASES=("house_ops" "practice_exchange" "event_planner" "minecraft_companion" "postgres")

for DB in "${DATABASES[@]}"; do
  DUMP_FILE="${BACKUP_DIR}/${DB}-${DATE}.sql.gz"
  echo "[$(date)] Backing up ${DB}..."
  docker exec supabase-db pg_dump -U supabase_admin "${DB}" \
    | gzip > "${DUMP_FILE}"
  echo "[$(date)] Saved ${DUMP_FILE}"
done

# Prune backups older than 30 days
find "${BACKUP_DIR}" -name '*.sql.gz' -mtime +30 -delete
echo "[$(date)] Backup complete."
