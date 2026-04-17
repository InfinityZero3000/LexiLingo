# LexiLingo Gateway Nginx Production Setup

## Security model

- Only `gateway` (Nginx) exposes public ports: `80` and `443`.
- `backend-service` and `ai-service` are internal-only (`expose`), not published to host/public network.
- SSL/TLS is terminated centrally at the gateway.

## Files introduced

- `docker-compose.production.yml`
- `gateway/nginx/templates/default.conf.template`
- `gateway/nginx/snippets/proxy-common.conf`
- `scripts/setup-vps-swap.sh`

## 1) Prepare environment

1. Copy `.env.production.example` to `.env.production` and fill real values.
2. Ensure DNS for `GATEWAY_SERVER_NAME` points to VPS public IP.

## 2) Configure SSL certificates on VPS

The compose mounts `/etc/letsencrypt` from host into gateway container.

You can issue certs on host with Certbot (example for Ubuntu):

```bash
sudo apt-get update
sudo apt-get install -y certbot
sudo certbot certonly --standalone -d api.lexilingo.com
```

After issuance, make sure these exist:

- `/etc/letsencrypt/live/api.lexilingo.com/fullchain.pem`
- `/etc/letsencrypt/live/api.lexilingo.com/privkey.pem`

If your domain differs, update in `.env.production`.

## 3) Set up Swap (recommended for 4GB RAM VPS)

```bash
sudo SWAP_SIZE_GB=4 VM_SWAPPINESS=10 VM_VFS_CACHE_PRESSURE=50 bash scripts/setup-vps-swap.sh
```

This config helps reduce OOM risk when AI workload spikes.

## 4) Deploy stack

```bash
docker compose -f docker-compose.production.yml --env-file .env.production up -d --build
```

## 5) Verify public edge and internal isolation

- Public check:

```bash
curl -I http://api.lexilingo.com/health
curl -I https://api.lexilingo.com/health
```

- Internal ports are not published (should show only 80/443 mapped):

```bash
docker compose -f docker-compose.production.yml ps
```

## Routing defaults

- AI routes:
  - `/api/v1/ai/`
  - `/api/v1/topics/`
  - `/api/v1/chat/`
  - `/api/v1/stt/`
  - `/api/v1/tts/`
  - `/ws/`
- Backend routes:
  - all remaining paths (`/` fallback)

Adjust routes in `gateway/nginx/templates/default.conf.template` if your API path map changes.
