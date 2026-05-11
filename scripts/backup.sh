#!/bin/bash
# Decision note (encrypt-at-source, 2026-05-11):
# - pg_dump is piped through gpg --encrypt (asymmetric, recipient = repo public key).
# - Private key NEVER lives on VPS1; threat model = VPS compromise must NOT yield
#   readable dumps. Verified 2026-05-11 that CLAUDE.md's "Hetzner Object Storage"
#   claim is wrong: backups never leave /opt/backups today (no rclone, no s3).
#   That mismatch is logged separately; this script's only job is encryption.
# - Output extension changes to .sql.gz.gpg. Old .sql.gz files in /opt/backups
#   continue to coexist; the 30-day prune below handles both.
# - Recipient fingerprint loaded from scripts/backup-recipient.fingerprint
#   (public, repo-checked). Public key imported into /opt/backups/.gnupg by
#   the Ansible common role. Script fails loudly if either is missing.
# - "Pin everything": gnupg pinned in common role; recipient pinned by full
#   fingerprint, not key id (short-id collision attacks).
# - Cron path on VPS1 calls /opt/apps/scripts/backup.sh — pre-existing path
#   mismatch (scripts copied to /opt/scripts manually) is OUT OF SCOPE here;
#   next ansible apply restores the playbook's intended /opt/apps/scripts path.

# Nightly backup: dump each tenant database, gpg-encrypt to /opt/backups
set -euo pipefail

BACKUP_DIR="/opt/backups"
GPG_HOME="${BACKUP_DIR}/.gnupg"
FINGERPRINT_FILE="$(dirname "$0")/backup-recipient.fingerprint"
DATE=$(date +%Y%m%d)

DATABASES=("house_ops" "practice_exchange" "event_planner" "minecraft_companion" "postgres")

if [ ! -f "${FINGERPRINT_FILE}" ]; then
  echo "[$(date)] FATAL: ${FINGERPRINT_FILE} missing — cannot encrypt backups." >&2
  exit 1
fi

RECIPIENT_FINGERPRINT=$(grep -v '^#' "${FINGERPRINT_FILE}" | tr -d '[:space:]')
if [ -z "${RECIPIENT_FINGERPRINT}" ]; then
  echo "[$(date)] FATAL: ${FINGERPRINT_FILE} contains no fingerprint." >&2
  exit 1
fi

if ! GNUPGHOME="${GPG_HOME}" gpg --list-keys "${RECIPIENT_FINGERPRINT}" >/dev/null 2>&1; then
  echo "[$(date)] FATAL: recipient ${RECIPIENT_FINGERPRINT} not in ${GPG_HOME}." >&2
  echo "  Run the ansible common role to import scripts/backup-public.asc." >&2
  exit 1
fi

for DB in "${DATABASES[@]}"; do
  DUMP_FILE="${BACKUP_DIR}/${DB}-${DATE}.sql.gz.gpg"
  echo "[$(date)] Backing up ${DB} (encrypted)..."
  docker exec supabase-db pg_dump -U supabase_admin "${DB}" \
    | gzip \
    | GNUPGHOME="${GPG_HOME}" gpg --batch --yes --trust-model always \
        --encrypt --recipient "${RECIPIENT_FINGERPRINT}" \
        --output "${DUMP_FILE}"
  echo "[$(date)] Saved ${DUMP_FILE}"
done

# Prune backups older than 30 days (both encrypted and any pre-cutover plaintext)
find "${BACKUP_DIR}" -maxdepth 1 -name '*.sql.gz' -mtime +30 -delete
find "${BACKUP_DIR}" -maxdepth 1 -name '*.sql.gz.gpg' -mtime +30 -delete
echo "[$(date)] Backup complete."
