#!/bin/bash
# Nightly backup: dump each tenant database, upload to object storage
set -euo pipefail

BACKUP_DIR="/opt/backups"
DATE=$(date +%Y%m%d)
PG_HOST="localhost"
PG_PORT="5432"
PG_USER="postgres"

# Source credentials
source /opt/supabase/docker/.env

DATABASES=("house_ops" "practice_exchange" "mrt")

for DB in "${DATABASES[@]}"; do
  DUMP_FILE="${BACKUP_DIR}/${DB}-${DATE}.sql.gz"
  echo "[$(date)] Backing up ${DB}..."
  PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
    -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" "${DB}" \
    | gzip > "${DUMP_FILE}"
  echo "[$(date)] Saved ${DUMP_FILE}"
done

# Prune backups older than 30 days
find "${BACKUP_DIR}" -name '*.sql.gz' -mtime +30 -delete
echo "[$(date)] Backup complete."
