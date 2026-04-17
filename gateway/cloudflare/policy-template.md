# Cloudflare API Gateway Policy Template (LexiLingo)

This template mirrors the Kong policy set: authz, quota, and observability.

## 1) Edge Access Model

- Put public API behind Cloudflare proxied DNS.
- Configure origin as Kong gateway (`https://api.lexilingo.com` -> Kong).
- Block direct origin access by allowing only Cloudflare IP ranges at origin firewall.

## 2) Authentication and Authorization

### API token header enforcement (WAF custom rule)

Expression:
```
(not http.request.headers["x-api-key"][0] exists) and starts_with(http.request.uri.path, "/api/v1/")
```
Action: Block

### Admin route lock-down

Expression:
```
starts_with(http.request.uri.path, "/api/v1/admin") and ip.src ne {ALLOWED_ADMIN_IP}
```
Action: Block

Optional Zero Trust:
- Require Cloudflare Access service token for `/api/v1/admin*` and `/api/v1/ai-admin*`.

## 3) Quota and Rate Limits

Create Cloudflare Rate Limiting rules:

1. Rule `mobile-default`
- Path: `/api/v1/*`
- Match: exclude admin paths
- Threshold: 180 req/min per API key or IP
- Action: Managed Challenge (or Block)

2. Rule `ai-heavy-endpoints`
- Paths: `/api/v1/stt*`, `/api/v1/tts*`, `/api/v1/lexi*`, `/api/v1/chat*`
- Threshold: 30 req/min per API key or IP
- Action: Block for 1 minute

3. Rule `admin-strict`
- Paths: `/api/v1/admin*`, `/api/v1/ai-admin*`
- Threshold: 60 req/min per API key or IP
- Action: Block for 10 minutes

## 4) Observability

- Enable HTTP request logs to Logpush destination (S3/GCS/Azure Blob).
- Include fields:
  - `ClientRequestHost`
  - `ClientRequestPath`
  - `EdgeResponseStatus`
  - `RayID`
  - `ClientIP`
  - `WAFAction`
  - `OriginResponseTime`
- Propagate `cf-ray` and `x-request-id` headers to Kong.

## 5) Security Hardening

- Enable Bot Management or Super Bot Fight Mode for `/api/v1/*`.
- Enable WAF Managed Ruleset.
- Enforce TLS 1.2+.
- Add custom rule to block large request bodies for sensitive paths where needed.

## 6) Rollout Strategy

1. Deploy in Log-only mode first (simulate WAF/rate rules).
2. Enable Block mode for high-confidence rules.
3. Observe 7 days for false positives.
4. Tighten thresholds incrementally.
