# AI Service Production E2E Runbook

## Server secrets

Create `.env.production.secrets` with mode `0600`. Never commit or paste its values into logs.

Root production requires `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `SECRET_KEY`, `AI_ADMIN_API_KEY`, and exactly seven unique comma-separated values in `GROQ_API_KEYS`. `SECRET_KEY` must match the backend and contain at least 32 random characters. Set `ALLOWED_ORIGINS` in `.env.production` to the deployed frontend origins. Add `SENTRY_DSN`, Gemini, Firebase, or content-agent secrets only when those features are enabled.

The isolated E2E stack uses `ai-service/.env` and requires `REDIS_PASSWORD`, `SECRET_KEY`, `AI_ADMIN_API_KEY`, and exactly seven unique `GROQ_API_KEYS`. `MONGO_EXPRESS_USER` and `MONGO_EXPRESS_PASSWORD` are needed only for its optional `admin` profile; Mongo Express is not part of root production.

Generate secrets on the server without echoing them into shell history, then restrict files:

```sh
umask 077
chmod 600 .env.production .env.production.secrets ai-service/.env
```

## Deploy a pinned commit

```sh
git fetch origin
git checkout <reviewed-commit>
docker compose --env-file .env.production --env-file .env.production.secrets -f docker-compose.yml config --quiet
docker compose --env-file .env.production --env-file .env.production.secrets -f docker-compose.yml up -d --build mongodb redis ai-service gateway
docker compose --env-file .env.production --env-file .env.production.secrets -f docker-compose.yml ps
curl --fail --show-error https://<server-host>/health
docker compose --env-file .env.production --env-file .env.production.secrets -f docker-compose.yml logs --since 10m --tail 300 ai-service gateway
```

Mongo indexes are created idempotently by the AI-service lifespan. Do not reset MongoDB or delete volumes during deployment.

## Real-provider E2E and latency report

The isolated project uses project-scoped container names and loopback-only ports, so it can be validated independently. Do not start the `admin` profile for routine checks.

```bash
docker compose -p lexilingo-ai-e2e --env-file ai-service/.env -f ai-service/docker-compose.yml config --quiet
docker compose -p lexilingo-ai-e2e --env-file ai-service/.env -f ai-service/docker-compose.yml up -d --build mongodb redis ai-service
cd ai-service
python3 scripts/e2e_ai_service.py preflight --env-file .env
smoke_output=$(python3 scripts/e2e_ai_service.py smoke --base-url http://127.0.0.1:18001 --env-file .env)
echo "$smoke_output"
smoke_report=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["report"])' <<<"$smoke_output")
python3 scripts/e2e_ai_service.py benchmark --base-url http://127.0.0.1:18001 --env-file .env
ls -lt reports/e2e
cd ..
docker compose -p lexilingo-ai-e2e --env-file ai-service/.env -f ai-service/docker-compose.yml up -d --no-deps --force-recreate ai-service
curl --fail --show-error http://127.0.0.1:18001/live
cd ai-service
python3 scripts/e2e_ai_service.py verify-persistence --base-url http://127.0.0.1:18001 --env-file .env --source-report "$smoke_report"
cd ..
docker compose -p lexilingo-ai-e2e --env-file ai-service/.env -f ai-service/docker-compose.yml logs --since 20m --tail 500 ai-service
docker compose -p lexilingo-ai-e2e --env-file ai-service/.env -f ai-service/docker-compose.yml down
```

Do not pass `--volumes`: the restart/persistence check depends on retained data. Reports are host files under `ai-service/reports/e2e/`, are ignored by Git, redact secrets, and expire after 30 days.

## Optional Mongo Express

Bind it to loopback and reach it through an SSH tunnel. Startup intentionally fails if its password is empty.

```sh
docker compose -p lexilingo-ai-e2e --profile admin --env-file ai-service/.env -f ai-service/docker-compose.yml up -d mongo-express
ssh -L 8081:127.0.0.1:8081 <server>
```

## Rollback

Record the current and previous reviewed commits before deployment. Root rollback recreates only AI service and keeps database/cache volumes:

```sh
git checkout <previous-reviewed-commit>
docker compose --env-file .env.production --env-file .env.production.secrets -f docker-compose.yml up -d --build --force-recreate ai-service
curl --fail --show-error https://<server-host>/health
docker compose --env-file .env.production --env-file .env.production.secrets -f docker-compose.yml logs --since 10m --tail 300 ai-service gateway
```

Use the isolated E2E stack to verify that a session created before `--force-recreate ai-service` remains readable afterward. Never use `down --volumes`, database reset scripts, or destructive Git commands for rollback.
