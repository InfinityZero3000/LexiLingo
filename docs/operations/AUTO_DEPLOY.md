# Auto-deploy: CI builds images, the VPS pulls them

Nothing is compiled on the VPS any more. Backend and ai-service images are built once, by CI, after
every test job has passed; the VPS only pulls those exact images.

```
MacBook ── git push ──► GitHub (dev)
                          └─ ci.yml: 7 test jobs ──► images job (only if all 7 are green)
                                                       ├─ ghcr.io/infinityzero3000/lexilingo/backend:sha-<sha>
                                                       └─ ghcr.io/infinityzero3000/lexilingo/ai-service:sha-<sha>
VPS (container lexilingo)
  lexilingo-auto-deploy.timer, every 2 min after the previous run ends
    └─ scripts/auto-deploy.sh
         newest CI run on dev green?  no / running ─► wait
         diff last_deployed..sha ─► backend-service/ → backend, worker, beat (one image)
                                    ai-service/      → ai-service
                                    anything else    → checkout updated, nothing restarted
         preflight: free disk (3 GB, 8 GB if ai-service), no exited container
         git merge --ff-only  (config + data mounts only, see below)
         compose pull  ─► fails? nothing was touched, retry next tick
         compose up -d --no-deps --no-build <services>
         verify: 8 containers healthy and networked, backend reaches postgres/mongodb/redis, smoke test
           ok   ─► image-tags.env updated, older images pruned (current + previous kept)
           fail ─► previous tags (or, on the first switch, the images built on the box) back up, alert
```

Flutter web and the admin dashboard keep deploying to Vercel from `cd.yml`.

## Where the data is, and why this cannot touch it

| Data | Where | Touched by a deploy? |
|---|---|---|
| Postgres, MongoDB, Redis | named volumes `lexilingo_*_data` | No. Database services are never restarted (`--no-deps`) |
| Uploaded media (~300 MB) | bind mount `backend-service/data/media` in the checkout | No. Same mount, new image |
| ai-service data, runtime graph | bind mount `ai-service/data` in the checkout | Tracked files follow the commit, runtime files are untouched |

`docker-compose.images.yml` changes **only the `image:` of the four application services**; volumes,
networks and mounts come from `docker-compose.yml` unchanged. `scripts/tests/test_auto_deploy.sh` fails
if the deploy script ever contains `down`, `-v`, `volume rm`, `system prune`, `--force-recreate`,
`--remove-orphans` or `rm -rf`.

**Why the checkout stays on the VPS.** It no longer provides code, but it still holds the gateway
templates, the compose files, the scripts and — through the two bind mounts above — real user data.
Deleting it would delete uploads. Making the VPS truly source-free means first moving those mounts
out of the checkout (a data move, done separately with a fresh backup), then a sparse checkout of
`docker-compose*.yml gateway/ scripts/ deploy/ monitoring/`.

## Rules and why each exists

- **Images only after green tests.** The old `cd.yml` job pushed `backend:dev` on every push, tests or not.
  It is gone; `images` in `ci.yml` needs all seven test jobs (incl. the deploy-script tests), so a green CI run for a SHA means its images exist.
- **Only the newest CI run counts.** An older green commit never ships while a newer one is running or red.
- **Per-service tags.** A backend-only commit keeps ai-service on its old tag, so ai-service is not
  restarted (its cold start rebuilds the embedding index).
- **Pull before swap.** A failed download leaves the running containers as they were.
- **Free disk is checked first.** The LXD pool is btrfs; at ~97% even `docker rmi` failed (2026-11-13).
- **A failed SHA is not retried** (`failed_sha`) until a newer green commit arrives.
- **Never restarts the docker daemon.** If rollback is not healthy either, the alert says so and a human takes over
  (`systemctl restart docker`, then `docker rm -f <svc>` + `compose up -d --no-deps <svc>` for any container left without a network).
- `docker-compose*.yml`, `gateway/` and `.env.production*` changes are not carried by images; the log notes them,
  roll them out with `scripts/deploy-one-shot.sh`.

## First switch (once)

With no `image-tags.env` yet, the script moves all four services to the registry in one go. If that
fails verification it brings back the images that were built on the box (`lexilingo-*:latest`), which
is why those local images are kept until a few registry deploys have succeeded.

```bash
# inside the container, as root
cd /opt/lexilingo && git pull --ff-only origin dev
cp deploy/systemd/lexilingo-auto-deploy.{service,timer} /etc/systemd/system/
systemctl daemon-reload
DRY_RUN=true bash scripts/auto-deploy.sh            # prints the plan, changes nothing
systemctl start lexilingo-auto-deploy.service        # first switch, watched
journalctl -u lexilingo-auto-deploy -f
systemctl enable --now lexilingo-auto-deploy.timer   # from now on, automatic
```

## Operate

```bash
systemctl list-timers lexilingo-auto-deploy.timer
journalctl -u lexilingo-auto-deploy -n 50 --no-pager
cat /var/lib/lexilingo/auto-deploy/image-tags.env    # what is running
systemctl disable --now lexilingo-auto-deploy.timer  # pause
```

Roll back by hand to the previous images:

```bash
cd /opt/lexilingo
docker compose -f docker-compose.yml -f docker-compose.images.yml --env-file .env.production \
  --env-file .env.production.secrets --env-file /var/lib/lexilingo/auto-deploy/image-tags.env.prev \
  up -d --no-deps --no-build backend-service backend-reminder-worker backend-reminder-beat ai-service
```

State in `/var/lib/lexilingo/auto-deploy/`: `image-tags.env` (+ `.prev`), `last_deployed`, `failed_sha`,
`LAST_ALERT`. Delete `failed_sha` to retry a SHA. Optional webhook: `systemctl edit lexilingo-auto-deploy`,
`Environment=ALERT_WEBHOOK_URL=...`.

## Backups on the Mac

`scripts/pull-backups-to-mac.sh --install` sets up a LaunchAgent that copies every server backup set
(checksum-verified against its manifest), plus uploaded media and `ai-service/data`, to `~/Backups/lexilingo`
20 minutes after each server backup. See `BACKUP_RESTORE_POLICY.md`.
