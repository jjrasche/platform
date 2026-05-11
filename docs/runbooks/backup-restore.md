# Runbook: Encrypted Backup & Restore

Nightly `pg_dump` on VPS1 is GPG-encrypted to a public key before it hits disk.
The matching private key lives offline (password manager + cold storage). A VPS
compromise yields ciphertext only.

Files in this repo:
- `scripts/backup.sh` — runs nightly at 03:00 UTC via cron
- `scripts/restore.sh` — manual; handles encrypted and legacy plaintext backups
- `scripts/backup-public.asc` — ASCII-armored public key (safe to commit)
- `scripts/backup-recipient.fingerprint` — 40-char fingerprint (safe to commit)

## A. Generate the backup keypair (one-time setup)

Run on Jim's local machine in WSL Ubuntu. **Never on the VPS.**

```bash
# 1. Generate the keypair. Adjust "Jim Rasche" / email if desired.
gpg --quick-generate-key "Platform Backup <jimjrasche@gmail.com>" rsa4096 encrypt 5y

# 2. Capture the full 40-char fingerprint (no spaces).
gpg --list-keys --with-colons "Platform Backup" \
  | awk -F: '/^fpr:/ {print $10; exit}'

# 3. Export the public key (ASCII-armored).
gpg --armor --export <FPR> > scripts/backup-public.asc

# 4. Paste the fingerprint into scripts/backup-recipient.fingerprint
#    (replace the placeholder; one line, hex only).

# 5. Back up the private key offline. Both lines required.
gpg --armor --export-secret-keys <FPR> > /tmp/backup-private.asc
gpg --export-secret-keys <FPR> | gpg --symmetric --cipher-algo AES256 \
  > /tmp/backup-private.asc.gpg   # passphrase-wrapped, paranoid copy

# 6. Move /tmp/backup-private.asc into 1Password (or equivalent).
#    Shred the /tmp copies.
shred -u /tmp/backup-private.asc /tmp/backup-private.asc.gpg

# 7. Commit the two repo files. Do NOT commit anything from /tmp.
git add scripts/backup-public.asc scripts/backup-recipient.fingerprint
git commit -m "backup: install platform recipient public key"

# 8. Re-run the platform Ansible playbook to push the key to VPS1.
cd ansible && ansible-playbook -i inventory playbook.yml --tags common
```

The first cron tick (03:00 UTC) after the apply produces `*.sql.gz.gpg` files.
Verify the next morning:

```bash
ssh deploy@<VPS1> "sudo ls -lh /opt/backups/ | tail"
```

## B. Restore from an encrypted backup

Two cases. **Always import the private key on a trusted workstation, not the VPS.**

### B.1 Restore a single database

```bash
# 1. On your local trusted workstation (WSL), import the offline private key.
gpg --import < /path/to/backup-private.asc      # from password manager
gpg --list-secret-keys                          # confirm

# 2. Pull the encrypted dump from the VPS.
scp deploy@<VPS1>:/opt/backups/house_ops-20260511.sql.gz.gpg .

# 3. Decrypt locally, then either restore locally or pipe back to VPS.
gpg --decrypt house_ops-20260511.sql.gz.gpg | gunzip > house_ops.sql

# 4. Apply to platform Postgres (over the SSH tunnel — see ssh-tunnels.md).
PGPASSWORD=... psql -h localhost -p 5433 -U postgres -c \
  "DROP DATABASE IF EXISTS house_ops; CREATE DATABASE house_ops;"
PGPASSWORD=... psql -h localhost -p 5433 -U postgres house_ops < house_ops.sql

# 5. Shred the local decrypted plaintext.
shred -u house_ops.sql
```

### B.2 Full disaster recovery (in-place on VPS, last resort)

Importing the private key on the VPS is a one-time emergency action. After
restore, **immediately rotate** (Section C) because the key has now touched a
potentially compromised box.

```bash
# 1. SSH to the new VPS and become root.
ssh deploy@<VPS1-new> && sudo -i

# 2. Import the private key into root's keyring (NOT /opt/backups/.gnupg).
#    Paste the armored secret key from your password manager.
gpg --import < /tmp/backup-private.asc

# 3. Run restore.sh for each database. It auto-detects .sql.gz.gpg.
/opt/apps/scripts/restore.sh house_ops
/opt/apps/scripts/restore.sh practice_exchange
/opt/apps/scripts/restore.sh event_planner
/opt/apps/scripts/restore.sh minecraft_companion
/opt/apps/scripts/restore.sh postgres

# 4. Delete the imported private key + shred the source file.
gpg --delete-secret-keys <FPR>
shred -u /tmp/backup-private.asc

# 5. Treat the key as compromised — schedule rotation (Section C) within 24h.
```

Legacy plaintext `.sql.gz` files (pre-encryption cutover) are still restorable
by `restore.sh` — it auto-detects the extension.

## C. Rotate the backup keypair

Do this annually, after any in-place-on-VPS private key import, or if you suspect
the offline key copy is exposed.

```bash
# 1. Generate a NEW keypair (Section A, steps 1-2). Pick a new email comment
#    (e.g. "Platform Backup 2027 <...>") so old + new coexist in your keyring.

# 2. Decrypt the most recent backup with the OLD key, re-encrypt to the NEW
#    recipient, and replace the file on the VPS — this guarantees you can roll
#    back even if the new key is lost on day 1.
scp deploy@<VPS1>:/opt/backups/postgres-$(date +%Y%m%d).sql.gz.gpg .
gpg --decrypt postgres-*.sql.gz.gpg \
  | gpg --batch --trust-model always --encrypt --recipient <NEW-FPR> \
        --output postgres-rotated.sql.gz.gpg
scp postgres-rotated.sql.gz.gpg deploy@<VPS1>:/opt/backups/

# 3. Update the repo:
gpg --armor --export <NEW-FPR> > scripts/backup-public.asc
echo "<NEW-FPR>" > scripts/backup-recipient.fingerprint   # preserve comment header
git commit -am "backup: rotate recipient to <NEW-FPR-SHORT>"

# 4. Re-run ansible. The common role re-imports; the VPS keyring now contains
#    both keys. backup.sh encrypts to NEW going forward; OLD-encrypted files in
#    /opt/backups remain decryptable with the OLD private key until they age out
#    (30-day prune).
cd ansible && ansible-playbook -i inventory playbook.yml --tags common

# 5. Keep the OLD private key in cold storage for at least 60 days (covers the
#    30-day on-VPS retention plus margin). Then destroy:
gpg --delete-secret-keys <OLD-FPR>
# and delete the 1Password entry.
```

## D. Smoke test (do this within a week of any change)

```bash
# On VPS1 — confirm the script can encrypt end-to-end.
ssh deploy@<VPS1> "sudo /opt/apps/scripts/backup.sh"
ssh deploy@<VPS1> "sudo ls -lh /opt/backups/ | grep $(date +%Y%m%d)"

# Locally — confirm you can decrypt with the offline key.
scp deploy@<VPS1>:/opt/backups/postgres-$(date +%Y%m%d).sql.gz.gpg .
gpg --decrypt postgres-*.sql.gz.gpg | gunzip | head -20
```

If `gpg --decrypt` succeeds and `head -20` shows `PostgreSQL database dump`,
the loop is closed.
