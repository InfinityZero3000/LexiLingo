<!-- Title: type(scope): subject, e.g. fix(auth): stop the login spinner. It becomes the commit subject and a release-notes line. -->

## Why
<!-- The problem or need. Link the issue if there is one. -->

## What
<!-- The change, in a few lines. -->

## Checked
<!-- Tests run and their result. For UI: screenshots at 390, 768 and 1440 px. -->

## Deploy impact
<!-- Merging into dev deploys. Tick what applies. -->
- [ ] `backend-service` / `ai-service`: auto-deploy restarts the service (ai-service rebuilds its embedding index)
- [ ] `docker-compose*.yml`, `gateway/` or `.env.production`: images do not carry these; roll out with `scripts/deploy-one-shot.sh`
- [ ] Database migration (expand first, contract in a later PR)
- [ ] None: docs, tests, or app UI only (Vercel redeploys the web app and admin)
