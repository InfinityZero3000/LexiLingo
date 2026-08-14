#!/usr/bin/env bash
# Shared helpers for backup / restore / verify. Source, do not execute.

# A dump this small is a failed pg_dump or mongodump, not a real backup.
# Prod postgres is ~1.8MB gzipped and mongo ~2MB; 100KB is far below any
# legitimate value and catches "container was down, dump is just headers".
: "${MIN_BACKUP_BYTES:=102400}"

log() { printf '[%s] %s\n' "${SCRIPT_NAME:-backup}" "$*"; }
die() { printf '[%s] ERROR: %s\n' "${SCRIPT_NAME:-backup}" "$*" >&2; exit 1; }

file_size() {
  # macOS and GNU stat disagree on flags; wc -c works on both.
  wc -c < "$1" | tr -d '[:space:]'
}

# Fail loudly rather than let a truncated or empty dump masquerade as a backup.
assert_gzip_intact() {
  local file="$1" label="$2" size
  [[ -f "${file}" ]] || die "${label}: file missing (${file})"
  size="$(file_size "${file}")"
  if (( size < MIN_BACKUP_BYTES )); then
    die "${label}: only ${size} bytes (< ${MIN_BACKUP_BYTES}) — dump almost certainly failed"
  fi
  gzip -t "${file}" 2>/dev/null || die "${label}: gzip integrity check failed — file is corrupt"
  log "${label}: OK (${size} bytes, gzip intact)"
}

# Verify against the manifest written at backup time, when one exists.
verify_against_manifest() {
  local file="$1"
  local dir stamp manifest expected actual
  dir="$(cd "$(dirname "${file}")" && pwd)"
  stamp="$(basename "${file}" | sed -E 's/^[a-z]+_([0-9TZ]+)\..*/\1/')"
  manifest="${dir}/manifest_${stamp}.txt"

  if [[ ! -f "${manifest}" ]]; then
    log "WARNING: no manifest for $(basename "${file}") — checksum not verified"
    return 0
  fi

  expected="$(grep -F "$(basename "${file}")" "${manifest}" | awk '{print $1}' | head -1)"
  if [[ -z "${expected}" ]]; then
    log "WARNING: $(basename "${file}") absent from manifest — checksum not verified"
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "${file}" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "${file}" | awk '{print $1}')"
  fi

  [[ "${expected}" == "${actual}" ]] \
    || die "$(basename "${file}"): checksum mismatch — backup is corrupt or was tampered with"
  log "$(basename "${file}"): checksum matches manifest"
}
