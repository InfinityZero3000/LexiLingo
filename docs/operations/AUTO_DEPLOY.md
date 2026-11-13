# Auto-deploy (VPS pulls when CI is green)

Backend and ai-service reach production without anyone running a deploy by hand.
A systemd timer inside the `lexilingo` LXD container asks GitHub whether the newest
`dev` commit passed CI, and if so rebuilds only what changed.

```
timer (every 2 min after the last run ends)
  └─ scripts/auto-deploy.sh
       CI for newest dev push: green?  ── no / running ──► exit, try again later
       already deployed, or failed before? ───────────────► exit
       diff last_deployed..sha  ──► backend-service/ → backend + worker + beat
                                    ai-service/      → ai-service
                                    anything else    → checkout updated, nothing rebuilt
       preflight: >= 5 GB free, no exited container
       tag :rollback → compose build → compose up -d --no-deps <services>
       verify: all 8 containers healthy and networked, backend reaches
               postgres/mongodb/redis, scripts/smoke-prod.sh
       verify fails ──► retag :rollback → :latest, recreate, verify again, alert
```

Flutter web and the admin dashboard are not handled here: `cd.yml` ships them to Vercel.

## Why it looks like this

- **Pull, not push.** The repo is public, so the CI status is readable without a token and the box needs no
  inbound SSH from GitHub and no new secret. A 304 reply to the ETag request does not count against the
  unauthenticated rate limit.
- **Only the newest CI run counts.** An older green commit never ships while a newer one is running or red.
- **`--no-deps`, never `--force-recreate`.** Only the rebuilt services restart. On 2026-11-13 a swap left
  postgres without a network and mongodb dead after a full disk; every core container is verified, not just the rebuilt ones.
  See `docs/operations/MULTI_PROJECT_VPS.md` for the shared-host context.
- **No timeout on builds.** A cancelled `llama-cpp-python` build once destroyed the rollback image.
- **A failed SHA is not retried** until a newer green commit arrives (`failed_sha`). A broken commit would otherwise
  rebuild every two minutes.
- **Free space is checked before building.** The LXD pool is btrfs: at ~97% even `docker rmi` fails with ENOSPC.

## What it does not do

- `docker-compose.yml`, `gateway/` and `.env.production*` changes are noted in the log but not applied beyond the
  rebuilt services. Roll those out with `scripts/deploy-one-shot.sh`.
- It never restarts the docker daemon. If rollback also fails, the alert says so and a human takes over
  (`systemctl restart docker`, then `docker rm -f <svc>` and `compose up -d --no-deps <svc>` for any container left without a network).
- After a rolled-back deploy the checkout stays on the new commit. Do not run `deploy-one-shot.sh` until a newer
  green commit has been deployed.

## Install (once, inside the container, as root)

```bash
cd /opt/lexilingo && git pull --ff-only origin dev
cp deploy/systemd/lexilingo-auto-deploy.{service,timer} /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now lexilingo-auto-deploy.timer
```

Optional alert webhook: `systemctl edit lexilingo-auto-deploy` and add `Environment=ALERT_WEBHOOK_URL=...`.
Without it, failures go to `journalctl -p crit -t lexilingo-auto-deploy` and `/var/lib/lexilingo/auto-deploy/LAST_ALERT`.

## Operate

```bash
systemctl list-timers lexilingo-auto-deploy.timer      # next run
journalctl -u lexilingo-auto-deploy -n 50 --no-pager    # what it decided
DRY_RUN=true STATE_DIR=/tmp/ad-state bash scripts/auto-deploy.sh   # print the plan, change nothing
systemctl disable --now lexilingo-auto-deploy.timer     # pause auto-deploy (manual deploys still work)
```

State lives in `/var/lib/lexilingo/auto-deploy/`: `last_deployed` (SHA), `failed_sha`, `LAST_ALERT`.
To force a retry of a failed SHA, delete `failed_sha`.

Test the decision logic with `bash scripts/tests/test_auto_deploy.sh`.
