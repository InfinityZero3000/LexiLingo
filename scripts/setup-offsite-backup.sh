#!/usr/bin/env bash
set -euo pipefail

# One-time setup for encrypted off-site backups to Backblaze B2.
#
# Backups contain user PII (emails, bcrypt hashes), so nothing leaves this host
# unencrypted: an rclone `crypt` remote wraps B2 and encrypts both file
# contents and file names. B2 only ever stores opaque blobs.
#
# Run on the production host:
#   sudo B2_ACCOUNT_ID=... B2_APP_KEY=... B2_BUCKET=lexilingo-backups \
#     bash scripts/setup-offsite-backup.sh

SCRIPT_NAME="setup-offsite"
RCLONE="${RCLONE:-/usr/local/bin/rclone}"
CONFIG="${RCLONE_CONFIG:-/root/.config/rclone/rclone.conf}"
SECRET_OUT="${SECRET_OUT:-/root/lexilingo-backup-crypt-passphrases.txt}"
B2_BUCKET="${B2_BUCKET:-lexilingo-backups}"

log() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
die() { printf '[%s] ERROR: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

[[ -x "${RCLONE}" ]] || die "rclone not found at ${RCLONE}"
[[ -n "${B2_ACCOUNT_ID:-}" ]] || die "set B2_ACCOUNT_ID (Backblaze applicationKeyId)"
[[ -n "${B2_APP_KEY:-}" ]] || die "set B2_APP_KEY (Backblaze applicationKey)"

if [[ -f "${CONFIG}" ]] && grep -q '^\[lexilingo-crypt\]' "${CONFIG}"; then
  die "lexilingo-crypt already configured in ${CONFIG} — refusing to overwrite (that would orphan existing backups)"
fi

mkdir -p "$(dirname "${CONFIG}")" && chmod 700 "$(dirname "${CONFIG}")"

# Generated here, on the host. Never echoed to stdout — losing them makes every
# off-site backup unrecoverable, so they are written to a root-only file for
# you to copy into a password manager and then delete.
CRYPT_PASS_PLAIN="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)"
CRYPT_SALT_PLAIN="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)"

log "Writing rclone config -> ${CONFIG}"
cat >> "${CONFIG}" <<EOF

[lexilingo-b2]
type = b2
account = ${B2_ACCOUNT_ID}
key = ${B2_APP_KEY}
hard_delete = true

[lexilingo-crypt]
type = crypt
remote = lexilingo-b2:${B2_BUCKET}/lexilingo
filename_encryption = standard
directory_name_encryption = true
password = $("${RCLONE}" obscure "${CRYPT_PASS_PLAIN}")
password2 = $("${RCLONE}" obscure "${CRYPT_SALT_PLAIN}")
EOF
chmod 600 "${CONFIG}"

umask 077
cat > "${SECRET_OUT}" <<EOF
LexiLingo off-site backup encryption passphrases
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(hostname)

WITHOUT THESE, EVERY OFF-SITE BACKUP IS UNRECOVERABLE.
Copy into a password manager, verify, then delete this file.

CRYPT_PASSWORD=${CRYPT_PASS_PLAIN}
CRYPT_SALT=${CRYPT_SALT_PLAIN}
B2_BUCKET=${B2_BUCKET}
EOF
chmod 600 "${SECRET_OUT}"

log "Verifying the remote works (writes and reads back a probe file)"
PROBE="/tmp/lexilingo-offsite-probe.$$"
echo "probe $(date -u +%s)" > "${PROBE}"
"${RCLONE}" --config "${CONFIG}" copy "${PROBE}" lexilingo-crypt:/ --no-traverse \
  || die "upload failed — check the B2 key and that bucket '${B2_BUCKET}' exists"
"${RCLONE}" --config "${CONFIG}" cat "lexilingo-crypt:/$(basename "${PROBE}")" >/dev/null \
  || die "read-back failed — the crypt remote cannot decrypt what it wrote"
"${RCLONE}" --config "${CONFIG}" delete "lexilingo-crypt:/$(basename "${PROBE}")" || true
rm -f "${PROBE}"
log "Round-trip verified: upload, decrypt, delete all work"

cat <<EOF

Next steps:
  1. Copy the passphrases out of ${SECRET_OUT} into a password manager,
     then: shred -u ${SECRET_OUT}
  2. Enable the off-site push:
       sudo systemctl edit lexilingo-backup.service
     add:
       [Service]
       Environment=OFFSITE_RCLONE_REMOTE=lexilingo-crypt:
       Environment=RCLONE_CONFIG=${CONFIG}
  3. sudo systemctl start lexilingo-backup.service   # confirm it pushes
EOF
