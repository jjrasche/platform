#!/bin/bash
# Restore a database from backup
# Usage: ./restore.sh <database_name> [backup_file]
#   ./restore.sh house_ops                    # restores latest
#   ./restore.sh house_ops house_ops-20260405.sql.gz  # restores specific
set -euo pipefail

DB_NAME="${1:?Usage: restore.sh <database_name> [backup_file]}"
BACKUP_DIR="/opt/backups"
PG_HOST="localhost"
PG_PORT="5432"
PG_USER="postgres"

source /opt/supabase/docker/.env

if [ -n "${2:-}" ]; then
  BACKUP_FILE="${BACKUP_DIR}/${2}"
else
  BACKUP_FILE=$(ls -t "${BACKUP_DIR}/${DB_NAME}"-*.sql.gz 2>/dev/null | head -1)
fi

if [ ! -f "${BACKUP_FILE}" ]; then
  echo "No backup found for ${DB_NAME}"
  exit 1
fi

echo "[$(date)] Restoring ${DB_NAME} from ${BACKUP_FILE}..."

PGPASSWORD="${POSTGRES_PASSWORD}" psql \
  -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -c \
  "DROP DATABASE IF EXISTS ${DB_NAME}; CREATE DATABASE ${DB_NAME};"

gunzip -c "${BACKUP_FILE}" | PGPASSWORD="${POSTGRES_PASSWORD}" psql \
  -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" "${DB_NAME}"

echo "[$(date)] Restore complete."
