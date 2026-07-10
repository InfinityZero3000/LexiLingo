# WAF/CDN Edge Rollout Runbook (Production)

This runbook closes the P0 gap for edge security in front of `api.lexilingo.me`.

## Scope

- Put Cloudflare or Azure Front Door in front of Nginx gateway
- Enable managed WAF rules (OWASP baseline)
- Keep origin (`api.lexilingo.me`) reachable only through edge layer

## Option A: Cloudflare (recommended fast path)

1. Add `api.lexilingo.me` to Cloudflare DNS as proxied (`orange cloud`).
2. SSL/TLS mode: `Full (strict)`.
3. Enable WAF managed rules:
- Cloudflare Managed Ruleset
- OWASP Core Ruleset (default sensitivity first)
4. Add custom WAF expressions:
- Block scanner paths: `/.git`, `/.env`, `/wp-config.php`, `/phpinfo.php`, `/actuator`
- Challenge bot-like bursts by country/ASN/UA as needed
5. Add rate-limit rules on sensitive paths:
- `/api/v1/auth/login`
- `/api/v1/auth/refresh`
- `/api/v1/stt/*`
- `/api/v1/tts/*`
- `/api/v1/chat/*`
6. Lock origin firewall to Cloudflare IP ranges only.

Verification:

```bash
curl -I https://api.lexilingo.me
# Expect Cloudflare headers such as cf-ray
```

## Option B: Azure Front Door + WAF

1. Create Front Door profile and endpoint for `api.lexilingo.me`.
2. Set origin to VPS gateway public IP/host.
3. Attach WAF policy in Prevention mode.
4. Enable Microsoft managed rule sets (OWASP).
5. Add custom rules for scanner paths and auth burst throttling.
6. Restrict VPS firewall to Front Door egress ranges.

Verification:

```bash
curl -I https://api.lexilingo.me
# Expect Front Door response headers and blocked probes returning 403/429
```

## Post-rollout hardening checks

1. Confirm `/.git/config`, `/.env`, `/wp-config.php` blocked at edge.
2. Confirm auth brute-force bursts are challenged/blocked before hitting origin.
3. Confirm origin logs show only edge IPs after firewall lock-down.
4. Keep runbook change log whenever rules are tuned.

## Operational notes

- Start in monitor mode for 15-30 minutes if traffic patterns are unknown.
- Move to block mode after false-positive review.
- Keep emergency bypass procedure documented for incident response.
