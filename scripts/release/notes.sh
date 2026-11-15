#!/usr/bin/env bash
# Release notes from the squash-merge subjects between two refs, grouped by conventional-commit type.
# Usage: notes.sh FROM TO   (FROM may be empty for the first release)
set -euo pipefail

from="${1:-}" to="${2:-HEAD}"
range="${to}"; [ -n "$from" ] && range="${from}..${to}"
subjects="$(git log --no-merges --format='%s' "$range" | grep -vE '^chore\(release\): ' || true)"

section() {  # title, type regex
  local lines
  lines="$(grep -E "^($2)(\([^)]*\))?!?: " <<<"$subjects" \
    | sed -E 's/^[a-z]+\(([^)]*)\)!?: /- **\1** /; s/^[a-z]+!?: /- /' || true)"
  if [ -n "$lines" ]; then printf '## %s\n\n%s\n\n' "$1" "$lines"; fi
}

section "Features" "feat"
section "Fixes" "fix"
section "Performance" "perf"
section "Maintenance" "refactor|docs|test|chore|ci|build|style|revert"

other="$(grep -vE '^(feat|fix|perf|refactor|docs|test|chore|ci|build|style|revert)(\([^)]*\))?!?: ' <<<"$subjects" | grep -v '^$' || true)"
if [ -n "$other" ]; then printf '## Other\n\n%s\n\n' "$(sed 's/^/- /' <<<"$other")"; fi

if [ -n "$from" ]; then printf '**Full changelog**: %s...%s\n' "$from" "$to"; fi
exit 0
