# LexiLingo Production Security and Gateway Report

## Scope

This report summarizes all production hardening and deployment features implemented for the VPS setup:

- Docker internal network isolation for AI/Backend
- Public edge Gateway (Nginx) only
- Centralized SSL/TLS termination
- UFW firewall baseline (open only 22/80/443)
- Fail2ban protections (SSH + Nginx abuse)
- Certbot auto-renew via systemd timer + deploy hook reload
- Endpoint-specific rate limiting for heavy AI routes
- Swap configuration support for 4GB RAM VPS

---

## 1) Docker and network isolation

File: `docker-compose.production.yml`

### Implemented

- Added `gateway` service as the only public ingress.
- `gateway` publishes `80:80` and `443:443`.
- `backend-service` and `ai-service` changed from host-published ports to Docker-internal `expose` only.
- Internal services communicate over `lexilingo-prod` bridge network.

### Security outcome

- Internet clients cannot directly reach AI/Backend ports.
- Requests must pass through Gateway policy/rate-limit/TLS layer.

---

## 2) Gateway architecture and routing

Files:

- `gateway/nginx/templates/default.conf.template`
- `gateway/nginx/snippets/proxy-common.conf`

### Implemented

- HTTP (80) redirects to HTTPS.
- TLS termination at Gateway with cert/key from mounted `/etc/letsencrypt`.
- Security headers enabled:
  - HSTS
  - X-Content-Type-Options
  - X-Frame-Options
  - Referrer-Policy
- Reverse proxy forwarding headers standardized in shared snippet.
- Route split:
  - AI-heavy paths to `ai-service:8001`
  - Remaining routes to `backend-service:8000`

### Route map

- AI: `/api/v1/ai/`, `/api/v1/topics/`, `/api/v1/chat/`, `/api/v1/stt/`, `/api/v1/tts/`, `/ws/`
- Backend: fallback `/`

---

## 3) Rate limit hardening for heavy AI endpoints

File: `gateway/nginx/templates/default.conf.template`

### Implemented

Dedicated rate-limit zones per traffic class:

- `ai_chat_per_ip`: stricter than general API
- `ai_stt_per_ip`: strict (expensive endpoint)
- `ai_tts_per_ip`: strict (expensive endpoint)
- `ai_general_per_ip`: medium
- `ws_per_ip`: websocket-specific
- `api_default_per_ip`: backend default

Also added:

- `limit_conn_zone` + `limit_conn` to cap concurrent connections per IP.

### Security outcome

- Better abuse resistance on cost-heavy endpoints.
- Reduces DoS amplification risks from STT/TTS/chat floods.

---

## 4) Nginx log export for host-side security tooling

File: `docker-compose.production.yml`

### Implemented

- Mounted gateway logs to host path:
  - `./gateway/nginx/logs:/var/log/nginx`
- Nginx configured to write:
  - `/var/log/nginx/access.log`
  - `/var/log/nginx/error.log`

### Security outcome

- Enables host-based Fail2ban to parse containerized Nginx logs.

---

## 5) UFW firewall baseline

File: `scripts/security/setup-ufw-fail2ban.sh`

### Implemented

- Resets and applies UFW baseline:
  - default deny incoming
  - default allow outgoing
  - allow only `22/tcp`, `80/tcp`, `443/tcp`

### Security outcome

- VPS only exposes SSH and web ingress.
- Internal service ports remain inaccessible externally.

---

## 6) Fail2ban protections

Files:

- `deploy/fail2ban/filter.d/nginx-429-abuse.conf`
- `deploy/fail2ban/jail.d/lexilingo-nginx.local`
- `scripts/security/setup-ufw-fail2ban.sh`

### Implemented

- Enabled `sshd` jail.
- Enabled `nginx-http-auth` jail.
- Added custom `nginx-429-abuse` jail that bans IPs repeatedly triggering 429 rate-limit responses.
- Bans are applied via UFW (`banaction = ufw`).

### Security outcome

- Automated blocking of brute-force and API abuse patterns.

---

## 7) SSL auto-renew with systemd timer + gateway reload hook

Files:

- `deploy/systemd/lexilingo-certbot-renew.service`
- `deploy/systemd/lexilingo-certbot-renew.timer`
- `scripts/ssl/reload-gateway-after-renew.sh`
- `scripts/ssl/install-certbot-timer.sh`

### Implemented

- Created dedicated systemd service to run `certbot renew`.
- Added timer to run renew twice daily.
- Added deploy hook to validate Nginx config and reload Gateway container after successful cert renewal.

### Security outcome

- SSL certificate lifecycle is automated.
- No manual restart required after renewal.

---

## 8) Swap memory support for 4GB VPS

Files:

- `scripts/setup-vps-swap.sh`
- `.env.production.example`

### Implemented

- Script provisions `/swapfile`, enables persistence in `/etc/fstab`, and sets kernel tunables:
  - `vm.swappiness`
  - `vm.vfs_cache_pressure`

### Ops outcome

- Better resilience under memory pressure for AI workloads.
- Lower risk of OOM kills on low-memory VPS.

---

## 9) Environment variables added

File: `.env.production.example`

### Implemented

Added gateway and swap related variables:

- `GATEWAY_SERVER_NAME`
- `GATEWAY_SSL_CERT_PATH`
- `GATEWAY_SSL_KEY_PATH`
- `SWAP_SIZE_GB`
- `VM_SWAPPINESS`
- `VM_VFS_CACHE_PRESSURE`

---

## 10) Deployment execution order (recommended)

1. Fill `.env.production` from `.env.production.example`.
2. Configure DNS to VPS for gateway domain.
3. Issue first SSL cert via certbot.
4. Run swap setup script.
5. Deploy compose stack.
6. Run UFW + Fail2ban setup script.
7. Install certbot systemd timer.
8. Verify external exposure only has 22/80/443.

---

## 11) Validation checklist

- `docker compose ps` shows only gateway publishes ports.
- `ufw status verbose` shows only 22/80/443 allowed.
- `fail2ban-client status` lists active jails.
- `systemctl list-timers` includes `lexilingo-certbot-renew.timer`.
- HTTPS endpoint returns valid certificate chain.
- AI/backend direct public access is not reachable.

---

## 12) Files changed/added summary

- `docker-compose.production.yml`
- `gateway/nginx/templates/default.conf.template`
- `gateway/nginx/snippets/proxy-common.conf`
- `gateway/nginx/logs/`
- `deploy/fail2ban/filter.d/nginx-429-abuse.conf`
- `deploy/fail2ban/jail.d/lexilingo-nginx.local`
- `scripts/security/setup-ufw-fail2ban.sh`
- `deploy/systemd/lexilingo-certbot-renew.service`
- `deploy/systemd/lexilingo-certbot-renew.timer`
- `scripts/ssl/reload-gateway-after-renew.sh`
- `scripts/ssl/install-certbot-timer.sh`
- `scripts/setup-vps-swap.sh`
- `.env.production.example`
- `docs/deploy/GATEWAY_NGINX_PRODUCTION.md`

