# Gateway Hardening Checklist

Use this checklist for production hardening of Nginx gateway in LexiLingo.

## 1) Edge Security Baseline

- [x] Enforce HTTPS only (HTTP 301 to HTTPS).
- [ ] Keep TLS to `TLSv1.2+` only and rotate certificates automatically.
- [ ] Set security headers globally:
  - [x] `Strict-Transport-Security`
  - [x] `X-Frame-Options`
  - [x] `X-Content-Type-Options`
  - [x] `Referrer-Policy`
- [x] Hide Nginx version in responses (`server_tokens off`).
- [ ] Limit request body size by endpoint type.

## 2) WAF / Attack Surface Reduction

- [x] Put Cloudflare/Azure Front Door/WAF in front of gateway.
- [ ] Enable managed rule sets (OWASP Top 10 baseline).
- [ ] Add custom rules for:
  - [ ] SQLi patterns (`union select`, `sleep(`, `information_schema`)
  - [x] RCE/LFI probes (`/cgi-bin/`, `/etc/passwd`, `/proc/self/environ`)
  - [x] Secret scans (`/.env`, `/wp-config.php`, `/.git/config`)
- [ ] Block methods not used by API (`TRACE`, `TRACK`, optionally `PROPFIND`).
- [ ] Add bot mitigation/challenge for abnormal user-agent bursts.

## 3) Rate Limiting by Sensitive Path

- [x] Keep global rate limiting for all API routes.
- [ ] Add stricter limits for sensitive paths:
  - [x] `/api/v1/auth/login`
  - [x] `/api/v1/auth/refresh`
  - [x] `/api/v1/stt/`
  - [x] `/api/v1/tts/`
  - [x] `/api/v1/chat/`
- [x] Add per-IP connection caps with lower values for auth routes.
- [x] Return consistent status and retry guidance on rate limit (`429`).

## 4) Deny Bot Scan Patterns (Nginx-level)

- [x] Deny known probe targets early with static `location` blocks:
  - [x] `~* /(\.git|\.svn|\.hg|\.env|wp-config\.php)`
  - [x] `~* /(actuator|phpinfo\.php|config\.ya?ml|docker-compose\.yml)`
- [x] Add deny-list for noisy abusive IPs from logs.
- [x] Auto-feed deny-list from Fail2Ban based on gateway logs.

## 5) Access Log Filtering & Observability

- [x] Separate normal access logs and security logs.
- [x] Add structured JSON access logs for SIEM ingestion.
- [x] Reduce noise by filtering health checks from access logs.
- [x] Keep error logs at `warn` or `error` in production.
- [ ] Add dashboard metrics:
  - [x] `4xx/5xx` rate
  - [ ] top blocked paths
  - [ ] top source IPs
  - [x] auth failure burst alerts
- [ ] Set retention and rotation (`max-size`, `max-file`).

## 6) Upstream Resilience / Load Balancing

- [x] Use upstream blocks with `least_conn` and keepalive.
- [ ] Configure upstream retry for transient failures (`502/503/504`).
- [x] Use Docker DNS resolver in Nginx for service discovery.
- [x] Recycle/reload gateway after major upstream container recreation.

## 7) Deployment Guardrails

- [x] Run one-shot deploy script with smoke test gate.
- [x] Fail deployment when smoke test fails.
- [x] Emit rollback-required signal file on failure.
- [x] Keep last successful deployment metadata (branch + commit + timestamp).

## 8) Secret & Config Hygiene

- [x] Remove plaintext secrets from committed env files.
- [ ] Use external secret store (Vault, Doppler, SOPS, cloud secret manager).
- [x] Rotate exposed keys immediately after migration.
- [ ] Restrict admin dashboards (`pgadmin`, `redisinsight`) to private network or VPN.

## Recommended Immediate Next Actions

- [x] Add deny rules for `.env/.git/wp-config` probes in gateway template.
- [x] Add auth-specific rate limit zones in Nginx.
- [x] Put WAF in front of `api.lexilingo.me` and enable managed rules.
- [x] Execute edge rollout runbook: `docs/gateway/WAF_EDGE_ROLLOUT_RUNBOOK.md`.
- [ ] Ship gateway logs to central monitoring and set alerts.

## Current Edge Notes

- Cloudflare edge is active for `api.lexilingo.me`.
- `Cloudflare Managed Free Ruleset` is enabled, along with custom WAF and rate-limit rules.
- Full OWASP Top 10 managed baseline remains plan-dependent on Cloudflare and is still pending.
