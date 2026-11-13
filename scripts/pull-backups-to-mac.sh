#!/usr/bin/env bash
# Copies production backups onto this Mac, so losing the VPS does not lose the data with it.
# Also copies the files the database dumps do not cover: uploaded media (backend-service/data/media)
# and ai-service/data both live inside the checkout on the server, and backup-prod.sh never saw them.
#
#   scripts/pull-backups-to-mac.sh            pull now
#   scripts/pull-backups-to-mac.sh --install  install a LaunchAgent that pulls after each server backup
set -euo pipefail

DEST="${LEXILINGO_BACKUP_DEST:-${HOME}/Backups/lexilingo}"
SSH_HOST="${SSH_HOST:-ovh-vps}"
REMOTE_ROOT="${REMOTE_ROOT:-/opt/lexilingo}"
KEEP_DAYS="${KEEP_DAYS:-60}"
MIN_KEEP_SETS="${MIN_KEEP_SETS:-20}"
# Server backups run every 6h; older than this means the server side has stopped.
STALE_HOURS="${STALE_HOURS:-8}"
LABEL="me.lexilingo.backup-pull"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

notify() {
  osascript -e "display notification \"$1\" with title \"LexiLingo backup\"" >/dev/null 2>&1 || true
}

fail() {
  log "ERROR: $*"
  printf 'status=failed\ntime=%s\nreason=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" > "${DEST}/LAST_RUN"
  notify "Backup pull failed: $*"
  exit 1
}

# rsync runs inside the LXD container through lxc exec; there is no SSH into the container itself.
pull() {
  rsync -a -e "ssh -o BatchMode=yes -o ConnectTimeout=20" \
    --rsync-path="sudo lxc exec lexilingo --mode=non-interactive -- rsync" "$@"
}

# Manifest lines are "<sha256>  <server path>"; the file sits next to it here.
verify_manifest() {
  local manifest="$1" sum path name
  while read -r sum path; do
    [[ -z "${sum}" ]] && continue
    name="$(basename "${path}")"
    [[ -f "${DEST}/db/${name}" ]] || { log "missing ${name} listed in $(basename "${manifest}")"; return 1; }
    [[ "$(shasum -a 256 "${DEST}/db/${name}" | cut -d' ' -f1)" == "${sum}" ]] || { log "checksum mismatch: ${name}"; return 1; }
  done < "${manifest}"
}

# Sets are named by UTC stamp (manifest_YYYYMMDDTHHMMSSZ.txt), so string order is time order.
prune_old_sets() {
  local cutoff stamp i=0
  cutoff="$(date -u -v-"${KEEP_DAYS}"d +%Y%m%dT%H%M%SZ)"
  for manifest in $(ls -1 "${DEST}/db"/manifest_*.txt 2>/dev/null | sort -r); do
    i=$((i + 1))
    (( i <= MIN_KEEP_SETS )) && continue
    stamp="$(basename "${manifest}" .txt)"; stamp="${stamp#manifest_}"
    [[ "${stamp}" < "${cutoff}" ]] || continue
    rm -f "${DEST}/db/postgres_${stamp}.sql.gz" "${DEST}/db/mongodb_${stamp}.archive.gz" "${manifest}"
    sed -i '' "/^manifest_${stamp}.txt$/d" "${DEST}/db/.verified" 2>/dev/null || true
  done
}

run_pull() {
  mkdir -p "${DEST}/db" "${DEST}/files"
  touch "${DEST}/db/.verified"
  log "pulling into ${DEST}"

  # Never --delete: a wiped or pruned server must not be able to empty the copy.
  pull --include='manifest_*.txt' --include='postgres_*.sql.gz' --include='mongodb_*.archive.gz' --exclude='*' \
    "${SSH_HOST}:${REMOTE_ROOT}/backups/" "${DEST}/db/" || fail "could not reach ${SSH_HOST} for the database dumps"

  local manifest name newest verified=0
  for manifest in "${DEST}/db"/manifest_*.txt; do
    [[ -f "${manifest}" ]] || continue
    name="$(basename "${manifest}")"
    grep -qx "${name}" "${DEST}/db/.verified" && continue
    verify_manifest "${manifest}" || fail "backup set ${name} does not match its checksums"
    echo "${name}" >> "${DEST}/db/.verified"
    verified=$((verified + 1))
  done

  newest="$(ls -1 "${DEST}/db"/manifest_*.txt 2>/dev/null | sort | tail -n 1)"
  [[ -n "${newest}" ]] || fail "no backup sets found on the server"
  newest="$(basename "${newest}" .txt)"; newest="${newest#manifest_}"
  if [[ "${newest}" < "$(date -u -v-"${STALE_HOURS}"H +%Y%m%dT%H%M%SZ)" ]]; then
    notify "Newest server backup is ${newest}, older than ${STALE_HOURS}h — check lexilingo-backup.timer"
    log "WARNING: newest server backup ${newest} is older than ${STALE_HOURS}h"
  fi

  # Incremental; deleted-on-server files stay here on purpose.
  pull "${SSH_HOST}:${REMOTE_ROOT}/backend-service/data/media/" "${DEST}/files/media/" \
    || fail "could not copy uploaded media"
  # The kuzu runtime graph is derived and written while live; its lock and WAL files are not worth copying.
  pull --exclude='*.lock' --exclude='*.wal' "${SSH_HOST}:${REMOTE_ROOT}/ai-service/data/" "${DEST}/files/ai-service-data/" \
    || fail "could not copy ai-service/data"

  prune_old_sets
  printf 'status=ok\ntime=%s\nnewest_set=%s\nnewly_verified=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${newest}" "${verified}" > "${DEST}/LAST_RUN"
  log "done: newest set ${newest}, ${verified} newly verified, $(du -sh "${DEST}" | cut -f1) total"
}

install_agent() {
  local bin="${HOME}/.local/bin/lexilingo-backup-pull" plist="${HOME}/Library/LaunchAgents/${LABEL}.plist"
  mkdir -p "$(dirname "${bin}")" "$(dirname "${plist}")" "${HOME}/Library/Logs"
  # A copy, not a link into the repo: switching branches must not change or remove the scheduled job.
  cp "$0" "${bin}" && chmod 755 "${bin}"
  # Server backups land at 00/06/12/18:30 UTC; pull 20 minutes later. launchd runs a missed slot on wake.
  cat > "${plist}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>${bin}</string></array>
  <key>EnvironmentVariables</key><dict><key>LEXILINGO_BACKUP_DEST</key><string>${DEST}</string></dict>
  <key>StartCalendarInterval</key>
  <array>
$(for h in 0 6 12 18; do
    local_h=$(( (h + $(date +%z | sed -E 's/^([+-])0?([0-9]+)[0-9]{2}$/\1\2/') + 24) % 24 ))  # UTC slot -> local hour
    printf '    <dict><key>Hour</key><integer>%d</integer><key>Minute</key><integer>50</integer></dict>\n' "${local_h}"
  done)
  </array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>${HOME}/Library/Logs/lexilingo-backup-pull.log</string>
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/lexilingo-backup-pull.log</string>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "${plist}"
  log "installed ${LABEL}: ${bin}, schedule in ${plist}, log ~/Library/Logs/lexilingo-backup-pull.log"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    --install) install_agent ;;
    "") run_pull ;;
    *) echo "usage: $0 [--install]" >&2; exit 2 ;;
  esac
fi
