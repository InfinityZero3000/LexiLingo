#!/usr/bin/env bash
set -euo pipefail

# One-time setup for encrypted off-site backups to Backblaze B2.
#
# Design: backups are encrypted with `age` to one or more RECIPIENT PUBLIC KEYS
# before leaving this host. Nothing that can decrypt them is ever stored here,
# so compromising this server does not expose historical backups. Generate the
# private keys on your own machine — never on production.
#
# Run on the production host:
#   sudo B2_ACCOUNT_ID=... B2_APP_KEY=... \
#        AGE_RECIPIENTS="age1xxxx age1yyyy" \
#        bash scripts/setup-offsite-backup.sh

SCRIPT_NAME="setup-offsite"
RCLONE="${RCLONE:-/usr/local/bin/rclone}"
AGE_BIN="${AGE_BIN:-/usr/local/bin/age}"
CONFIG="${RCLONE_CONFIG:-/root/.config/rclone/rclone.conf}"
B2_BUCKET="${B2_BUCKET:-lexilingo-backups}"

log() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
die() { printf '[%s] ERROR: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

[[ -x "${RCLONE}" ]] || die "rclone not found at ${RCLONE}"
[[ -x "${AGE_BIN}" ]] || die "age not found at ${AGE_BIN} — install it first"
[[ -n "${B2_ACCOUNT_ID:-}" ]] || die "set B2_ACCOUNT_ID (Backblaze applicationKeyId)"
[[ -n "${B2_APP_KEY:-}" ]] || die "set B2_APP_KEY (Backblaze applicationKey)"
[[ -n "${AGE_RECIPIENTS:-}" ]] || die "set AGE_RECIPIENTS to one or more age1... public keys"

for r in ${AGE_RECIPIENTS}; do
  [[ "${r}" == age1* ]] || die "recipient '${r}' is not an age public key (must start with age1)"
done

recipient_count="$(wc -w <<< "${AGE_RECIPIENTS}")"
if (( recipient_count < 2 )); then
  log "WARNING: only ${recipient_count} recipient. Losing that private key loses every"
  log "         off-site backup. Two keys stored separately is strongly advised."
fi

if [[ -f "${CONFIG}" ]] && grep -q '^\[lexilingo-b2\]' "${CONFIG}"; then
  die "lexilingo-b2 already configured in ${CONFIG} — refusing to overwrite"
fi

mkdir -p "$(dirname "${CONFIG}")" && chmod 700 "$(dirname "${CONFIG}")"

log "Writing rclone config -> ${CONFIG} (transport only, no encryption keys)"
cat >> "${CONFIG}" <<EOF

[lexilingo-b2]
type = b2
account = ${B2_ACCOUNT_ID}
key = ${B2_APP_KEY}
EOF
chmod 600 "${CONFIG}"

# ── Prove the whole chain works before declaring success ────────────────────
log "Verifying encrypt -> upload -> download -> byte-identical round trip"
PROBE="/tmp/lexilingo-probe.$$"
PROBE_ENC="${PROBE}.age"
PROBE_BACK="${PROBE}.back"
trap 'rm -f "${PROBE}" "${PROBE_ENC}" "${PROBE_BACK}"' EXIT

head -c 4096 /dev/urandom > "${PROBE}"
recipient_args=()
for r in ${AGE_RECIPIENTS}; do recipient_args+=(-r "${r}"); done
"${AGE_BIN}" "${recipient_args[@]}" -o "${PROBE_ENC}" "${PROBE}" || die "age encryption failed"
head -c 22 "${PROBE_ENC}" | grep -q 'age-encryption.org' || die "probe is not a valid age file"

"${RCLONE}" --config "${CONFIG}" copy "${PROBE_ENC}" "lexilingo-b2:${B2_BUCKET}/probe/" --no-traverse \
  || die "upload failed — check the B2 key and that bucket '${B2_BUCKET}' exists"
"${RCLONE}" --config "${CONFIG}" copyto \
  "lexilingo-b2:${B2_BUCKET}/probe/$(basename "${PROBE_ENC}")" "${PROBE_BACK}" \
  || die "download failed"
cmp -s "${PROBE_ENC}" "${PROBE_BACK}" || die "round trip corrupted the file"
"${RCLONE}" --config "${CONFIG}" delete "lexilingo-b2:${B2_BUCKET}/probe/$(basename "${PROBE_ENC}")" 2>/dev/null || true
log "Round trip verified"

# Deletion must fail if the key is correctly scoped write-only. Report either
# way — this is the difference between a backup and a backup that survives an
# attacker with root on this host.
if "${RCLONE}" --config "${CONFIG}" delete "lexilingo-b2:${B2_BUCKET}/probe/" 2>/dev/null; then
  log "NOTE: this key CAN delete objects. Prefer a key without deleteFiles, plus"
  log "      Object Lock on the bucket, so a compromised host cannot erase backups."
else
  log "Good: this key cannot delete — backups are protected from a compromised host"
fi

cat <<EOF

Setup complete. Enable the off-site push:

  sudo systemctl edit lexilingo-backup.service

  [Service]
  Environment=OFFSITE_RCLONE_REMOTE=lexilingo-b2:${B2_BUCKET}/lexilingo
  Environment=RCLONE_CONFIG=${CONFIG}
  Environment=AGE_RECIPIENTS=${AGE_RECIPIENTS}

  sudo systemctl start lexilingo-backup.service

To restore, on a trusted machine holding a private key:
  rclone copy lexilingo-b2:${B2_BUCKET}/lexilingo/postgres_<stamp>.sql.gz.age .
  age -d -i ~/lexilingo-backup.key postgres_<stamp>.sql.gz.age > postgres_<stamp>.sql.gz
  ./scripts/restore-prod.sh --postgres-backup postgres_<stamp>.sql.gz

No key capable of decrypting these backups exists on this server.
EOF
