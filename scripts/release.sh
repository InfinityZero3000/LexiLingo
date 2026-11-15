#!/usr/bin/env bash
# Opens the release PR: bumps the product version on a branch cut from origin/dev and files the PR.
# Merging it (CI green) is what releases: .github/workflows/tag-release.yml tags, publishes and versions the images.
#
#   scripts/release.sh patch|minor|major|X.Y.Z [--dry-run]
#
# Works in a throwaway worktree, so the checkout you run it from is never touched.
set -euo pipefail

arg="${1:-}"; dry=false; [ "${2:-}" = "--dry-run" ] && dry=true
[ -n "$arg" ] || { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
cd "$(git rev-parse --show-toplevel)"

git fetch -q origin dev --tags
sha="$(git rev-parse origin/dev)"

# The latest stable tag is the current version; no tag yet means start from the declared one.
last="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | grep -v -- - | head -1 || true)"
cur="${last#v}"
IFS=. read -r maj min pat <<<"${cur:-0.0.0}"
case "$arg" in
  major) next="$((maj + 1)).0.0" ;;
  minor) next="${maj}.$((min + 1)).0" ;;
  patch) next="${maj}.${min}.$((pat + 1))" ;;
  [0-9]*.[0-9]*.[0-9]*) next="$arg" ;;
  *) echo "give patch, minor, major or X.Y.Z" >&2; exit 2 ;;
esac
git rev-parse -q --verify "refs/tags/v${next}" >/dev/null && { echo "v${next} already exists" >&2; exit 1; }

# A release is the exact commit that was green and deployed, so refuse to cut one from a red or running CI.
state="$(gh run list --workflow CI --branch dev --commit "$sha" --limit 1 --json status,conclusion \
  --jq '.[0] | "\(.status)/\(.conclusion)"' 2>/dev/null || true)"
[ "$state" = "completed/success" ] || { echo "CI on dev ${sha:0:8} is '${state:-unknown}', not completed/success; wait for it" >&2; exit 1; }

echo "current ${last:-none} -> next v${next}  (dev ${sha:0:8})"
notes="$(bash scripts/release/notes.sh "$last" "$sha")"
if $dry; then printf '\n%s\n' "$notes"; exit 0; fi

work="$(mktemp -d)"; trap 'git worktree remove --force "$work" 2>/dev/null; rm -rf "$work"' EXIT
branch="release/v${next}"
git worktree add -q -B "$branch" "$work" "$sha"
(cd "$work" && bash scripts/release/bump-version.sh "$next" \
  && git add flutter-app/pubspec.yaml admin-service/package.json backend-service/app/core/config.py ai-service/api/__init__.py mcp-server/server.py \
  && git commit -q -m "chore(release): v${next}" && git push -q -u origin "$branch")

body="$(printf '## Release v%s\n\nMerging this PR releases it: the tag, the GitHub Release and the vX.Y.Z image tags are created automatically once CI is green on the merge commit.\n\nThe release commit changes `backend-service` and `ai-service`, so auto-deploy restarts both services once (ai-service rebuilds its embedding index). Merge when a short pause in chat is acceptable.\n\n%s\n' "$next" "$notes")"
gh pr create --base dev --head "$branch" --title "chore(release): v${next}" --body "$body"
