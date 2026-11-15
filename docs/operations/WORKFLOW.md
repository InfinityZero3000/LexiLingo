# Working agreement: branches, PRs, releases

`dev` is the trunk. A merge into `dev` is a deploy, so every change arrives by pull request and CI decides.

## What a merge into dev does

| Changed | Goes live how | Needs a human |
|---|---|---|
| `backend-service`, `ai-service` | CI builds `sha-<sha>` images; the VPS pulls them once CI is green (`docs/operations/AUTO_DEPLOY.md`). Only the changed service restarts. | no |
| `flutter-app` (web), `admin-service` | CD deploys both to Vercel production on every push to `dev` | no |
| `docker-compose*.yml`, `gateway/`, `.env.production*` | not carried by images | yes: `scripts/deploy-one-shot.sh` |
| mobile app binaries | not deployed by CI | yes: store release |

`main` only trails the latest release (the release workflow merges into it). Do not branch from it or open PRs against it.

## Day to day

1. Branch from the newest `dev` in your own worktree, not in a shared checkout:
   `git fetch origin && git worktree add ../lexi-<name> -b fix/<short-name> origin/dev`
2. Branch names: `feat/`, `fix/`, `perf/`, `refactor/`, `docs/`, `test/`, `chore/`, `ci/`.
3. Open a PR into `dev` and fill the template, including **Deploy impact**. Keep it small: one reason to merge.
4. The PR title is what counts, because squash-merge turns it into the commit subject:
   `type(scope): subject`, for example `fix(auth): stop the login spinner`. Types: `feat fix perf refactor docs test chore ci build style revert`; add `!` after the type for a breaking change. The `PR title` check enforces it.
5. Merge when the required checks are green. Squash only; the branch is deleted for you.

No hotfix branches and no cherry-picks: `dev` is production, so a hotfix is a small PR into `dev`. If something bad is live, revert it (`revert: ...`) and let the deploy roll forward, or roll back by hand (below).

## Versions and releases

One product version, declared in five places (`scripts/check-versions.sh` fails CI if they differ): `flutter-app/pubspec.yaml`, `admin-service/package.json`, `backend-service/app/core/config.py`, `ai-service/api/__init__.py`, `mcp-server/server.py`.

- **patch** (`1.14.0` → `1.14.1`): fixes only. **minor**: new features. **major**: a breaking change or a coordinated migration.
- Cut a release when something worth naming has shipped, at a quiet time: the release commit changes `backend-service` and `ai-service`, so both restart once (ai-service rebuilds its embedding index).

```bash
scripts/release.sh minor --dry-run    # the next version and the notes, nothing changed
scripts/release.sh minor              # opens the PR "chore(release): v1.14.0"
```

Merge that PR. When CI is green on the merge commit, `.github/workflows/tag-release.yml`:

1. tags the commit `vX.Y.Z` and publishes the GitHub Release with notes grouped by type;
2. gives the already-built images the tag too: `ghcr.io/infinityzero3000/lexilingo/{backend,ai-service}:vX.Y.Z`;
3. merges the release into `main`.

If it did not run or failed halfway: Actions → Release → Run workflow with the `sha` of the release commit (leave `dry_run` on first). It is safe to repeat; an existing tag stops it.

## Rolling back

- To the previous deploy: `docs/operations/AUTO_DEPLOY.md` (`image-tags.env.prev`).
- To a release: stop `lexilingo-auto-deploy.timer` (the next green commit would roll forward again), set `BACKEND_TAG=v1.13.0` and `AI_TAG=v1.13.0` in an env file, and run the same `docker compose … up -d --no-deps --no-build` as in `AUTO_DEPLOY.md`, passing that file as the last `--env-file`. Tags are free-form, so a release tag works like a `sha-…` one.
- The web app and admin: redeploy the older commit from the Vercel dashboard.

## Branch rules on GitHub

Kept here so they can be recreated.

- `dev`: PR required (no approvals needed, a single maintainer), the CI jobs and `PR title` must pass, no force-push, no deletion, linear history. Admins can bypass in an emergency.
- `main`: no force-push, no deletion. Pushes are allowed because the release workflow merges into it.
- Dependabot PRs auto-merge once checks pass (`dependabot-auto-merge.yml` needs the protection above).
