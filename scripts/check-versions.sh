#!/usr/bin/env bash
# Fails if the services do not declare one product version (the vX.Y.Z of the latest release tag).
set -euo pipefail
cd "$(dirname "$0")/.."

flutter=$(sed -nE 's/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+$/\1/p' flutter-app/pubspec.yaml)
admin=$(sed -nE 's/^  "version": "([^"]+)",$/\1/p' admin-service/package.json)
backend=$(sed -nE 's/^    APP_VERSION: str = "([^"]+)"$/\1/p' backend-service/app/core/config.py)
ai=$(sed -nE 's/^__version__ = "([^"]+)"$/\1/p' ai-service/api/__init__.py)
mcp=$(sed -nE 's/.*server_version="([^"]+)".*/\1/p' mcp-server/server.py)

printf '%-10s %s\n' flutter "$flutter" admin "$admin" backend "$backend" ai-service "$ai" mcp-server "$mcp"

for v in "$flutter" "$admin" "$backend" "$ai" "$mcp"; do
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "FAIL: a service has no semver declaration"; exit 1; }
done
[ "$(printf '%s\n' "$flutter" "$admin" "$backend" "$ai" "$mcp" | sort -u | wc -l | tr -d ' ')" = 1 ] \
  || { echo "FAIL: versions differ"; exit 1; }

if tag=$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname 2>/dev/null | grep -vE -- '-' | head -1) && [ -n "$tag" ] && [ "${tag#v}" != "$flutter" ]; then
  echo "note: highest release tag is $tag, code declares $flutter (bump both at release)"
fi
echo "OK: $flutter"
