#!/bin/bash
# Restore a database from backup
# Usage: ./restore.sh <database_name> [backup_file]
#   ./restore.sh house_ops                              # restores latest
#   ./restore.sh house_ops house_ops-20260405.sql.gz.gpg
#   ./restore.sh house_ops house_ops-20260405.sql.gz    # legacy plaintext
#
# Encrypted (.sql.gz.gpg) backups require the operator's PRIVATE GPG key to be
# imported into the current shell's GPG agent. The private key MUST NOT live
# on the VPS — see docs/runbooks/backup-restore.md for the offline-import flow.
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
  # Prefer the newest encrypted backup; fall back to legacy plaintext if none.
  BACKUP_FILE=$(ls -t "${BACKUP_DIR}/${DB_NAME}"-*.sql.gz.gpg 2>/dev/null | head -1)
  if [ -z "${BACKUP_FILE}" ]; then
    BACKUP_FILE=$(ls -t "${BACKUP_DIR}/${DB_NAME}"-*.sql.gz 2>/dev/null | head -1)
  fi
fi

if [ ! -f "${BACKUP_FILE}" ]; then
  echo "No backup found for ${DB_NAME}"
  exit 1
fi

echo "[$(date)] Restoring ${DB_NAME} from ${BACKUP_FILE}..."

PGPASSWORD="${POSTGRES_PASSWORD}" psql \
  -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -c \
  "DROP DATABASE IF EXISTS ${DB_NAME}; CREATE DATABASE ${DB_NAME};"

case "${BACKUP_FILE}" in
  *.sql.gz.gpg)
    if ! gpg --list-secret-keys >/dev/null 2>&1 || \
       [ -z "$(gpg --list-secret-keys --with-colons 2>/dev/null | grep '^sec:')" ]; then
      echo "FATAL: no GPG secret key in operator's keyring." >&2
      echo "  Import the offline private key first; see docs/runbooks/backup-restore.md" >&2
      exit 1
    fi
    gpg --decrypt --quiet "${BACKUP_FILE}" \
      | gunzip -c \
      | PGPASSWORD="${POSTGRES_PASSWORD}" psql \
          -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" "${DB_NAME}"
    ;;
  *.sql.gz)
    gunzip -c "${BACKUP_FILE}" \
      | PGPASSWORD="${POSTGRES_PASSWORD}" psql \
          -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" "${DB_NAME}"
    ;;
  *)
    echo "FATAL: unrecognized backup extension on ${BACKUP_FILE}" >&2
    exit 1
    ;;
esac

echo "[$(date)] Restore complete."
