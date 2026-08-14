#!/usr/bin/env bash
# Shared helpers for backup / restore / verify. Source, do not execute.

# Absolute floor only catches an empty or header-only dump. Real sizes differ
# wildly per store (prod postgres ~1.8MB gzipped, mongo ~79KB), so a single
# constant is either useless or rejects a good backup — the 100KB value first
# tried here failed a perfectly valid mongo dump.
: "${MIN_BACKUP_BYTES:=8192}"
# The useful signal is a sudden collapse against the previous good backup of
# the same store, which adapts as the data grows.
: "${SHRINK_FAIL_RATIO:=50}"   # fail under this percent of the previous backup

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

# Catch a dump that succeeded technically but lost most of its content — a
# wrong --db, a half-empty database, a truncated stream.
assert_not_shrunk() {
  local file="$1" label="$2"
  local dir prefix prev prev_size size floor
  dir="$(cd "$(dirname "${file}")" && pwd)"
  prefix="$(basename "${file}" | sed -E 's/_[0-9]{8}T[0-9]{6}Z.*//')"

  # Newest same-store backup that is not the one we just wrote.
  prev="$(find "${dir}" -maxdepth 1 -name "${prefix}_*" ! -name "$(basename "${file}")" \
    | sort | tail -1)"
  if [[ -z "${prev}" ]]; then
    log "${label}: no previous backup to compare against (first run)"
    return 0
  fi

  size="$(file_size "${file}")"
  prev_size="$(file_size "${prev}")"
  (( prev_size > 0 )) || return 0
  floor=$(( prev_size * SHRINK_FAIL_RATIO / 100 ))

  if (( size < floor )); then
    die "${label}: ${size} bytes is under ${SHRINK_FAIL_RATIO}% of the previous backup (${prev_size} bytes, $(basename "${prev}")) — data appears to be missing"
  fi
  log "${label}: size sane vs previous ($(basename "${prev}"): ${prev_size} bytes)"
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
