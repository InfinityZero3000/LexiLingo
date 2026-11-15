#!/usr/bin/env bash
# Sets the one product version in every place that declares it. Usage: bump-version.sh X.Y.Z
# scripts/check-versions.sh is the check that they all agree.
set -euo pipefail
cd "$(dirname "$0")/../.."

new="${1:-}"
[[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 X.Y.Z" >&2; exit 2; }

current=$(sed -nE 's/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+$/\1/p' flutter-app/pubspec.yaml)
build=$(sed -nE 's/^version: [0-9.]+\+([0-9]+)$/\1/p' flutter-app/pubspec.yaml)
[[ -n "$current" && -n "$build" ]] || { echo "pubspec.yaml has no X.Y.Z+N version" >&2; exit 1; }
[ "$(printf '%s\n%s\n' "$current" "$new" | sort -V | tail -1)" = "$new" ] && [ "$current" != "$new" ] \
  || { echo "$new is not newer than $current" >&2; exit 1; }

# sed -i differs between GNU and BSD, so write to a temp file and move it back.
edit() { local file="$1" expr="$2" tmp; tmp="$(mktemp)"; sed -E "$expr" "$file" > "$tmp" && cat "$tmp" > "$file"; rm -f "$tmp"; }

# The store build number only ever goes up.
edit flutter-app/pubspec.yaml "s/^version: .*/version: ${new}+$((build + 1))/"
edit admin-service/package.json "s/^  \"version\": \"[^\"]+\",\$/  \"version\": \"${new}\",/"
edit backend-service/app/core/config.py "s/^    APP_VERSION: str = \"[^\"]+\"\$/    APP_VERSION: str = \"${new}\"/"
edit ai-service/api/__init__.py "s/^__version__ = \"[^\"]+\"\$/__version__ = \"${new}\"/"
edit mcp-server/server.py "s/server_version=\"[^\"]+\"/server_version=\"${new}\"/"

bash scripts/check-versions.sh >/dev/null
echo "bumped ${current} -> ${new} (build $((build + 1)))"
