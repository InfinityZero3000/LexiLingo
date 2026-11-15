#!/usr/bin/env bash
# bump-version.sh moves every declared version together; notes.sh groups squash subjects by type.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fail=0
expect() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: want [$2] got [$3]"; fail=1; fi; }

# ---- bump-version.sh on a copy of the files that declare the version
mkdir -p "$work/tree/scripts/release" "$work/tree/flutter-app" "$work/tree/admin-service" \
  "$work/tree/backend-service/app/core" "$work/tree/ai-service/api" "$work/tree/mcp-server"
cp "$ROOT/scripts/release/bump-version.sh" "$work/tree/scripts/release/"
cp "$ROOT/scripts/check-versions.sh" "$work/tree/scripts/"
cp "$ROOT/flutter-app/pubspec.yaml" "$work/tree/flutter-app/"
cp "$ROOT/admin-service/package.json" "$work/tree/admin-service/"
cp "$ROOT/backend-service/app/core/config.py" "$work/tree/backend-service/app/core/"
cp "$ROOT/ai-service/api/__init__.py" "$work/tree/ai-service/api/"
cp "$ROOT/mcp-server/server.py" "$work/tree/mcp-server/"
cd "$work/tree"
git init -q && git add -A

build_before=$(sed -nE 's/^version: [0-9.]+\+([0-9]+)$/\1/p' flutter-app/pubspec.yaml)
bash scripts/release/bump-version.sh 99.8.7 >/dev/null
expect "pubspec version and build number" "99.8.7+$((build_before + 1))" "$(sed -nE 's/^version: (.*)$/\1/p' flutter-app/pubspec.yaml)"
expect "all five declarations agree" "OK: 99.8.7" "$(bash scripts/check-versions.sh | tail -1)"
expect "admin package.json" '  "version": "99.8.7",' "$(grep -E '^  "version"' admin-service/package.json)"
expect "mcp server_version" "1" "$(grep -c 'server_version="99.8.7"' mcp-server/server.py)"

if bash scripts/release/bump-version.sh 99.8.7 >/dev/null 2>&1; then expect "same version is refused" refused accepted; else expect "same version is refused" refused refused; fi
if bash scripts/release/bump-version.sh 1.0.0 >/dev/null 2>&1; then expect "downgrade is refused" refused accepted; else expect "downgrade is refused" refused refused; fi
cd "$ROOT"

# ---- notes.sh on a throwaway history
repo="$work/notes"; git init -q "$repo"; cd "$repo"
c() { git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$1"; }
c "chore: base"; git tag v0.1.0
c "feat(auth): sign in with a passkey (#1)"; c "fix: the spinner stops (#2)"; c "perf(db): index users"
c "docs(readme): update"; c "chore(release): v0.2.0 (#3)"; c "update stuff"
out="$("$ROOT/scripts/release/notes.sh" v0.1.0 HEAD)"
expect "feature line"      "1" "$(grep -c '^- \*\*auth\*\* sign in with a passkey (#1)$' <<<"$out")"
expect "unscoped fix"      "1" "$(grep -c '^- the spinner stops (#2)$' <<<"$out")"
expect "perf section"      "1" "$(grep -c '^## Performance$' <<<"$out")"
expect "docs under Maintenance" "1" "$(grep -c '^- \*\*readme\*\* update$' <<<"$out")"
expect "non-conventional goes to Other" "1" "$(grep -c '^- update stuff$' <<<"$out")"
expect "release commit is left out" "0" "$(grep -c 'release' <<<"$out")"
expect "base commit is outside the range" "0" "$(grep -c 'base' <<<"$out")"
expect "changelog link" "1" "$(grep -c 'Full changelog.*v0.1.0...HEAD' <<<"$out")"

exit "$fail"
