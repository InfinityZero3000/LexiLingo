# LexiLingo API Gateway Full Policy Setup

This guide provides a production-grade gateway profile with:
- Authentication and authorization
- Quota and throttling
- Observability (metrics + traces)

Primary runtime in this repository: **Kong**.
Also included: policy templates for **Cloudflare** and **Azure API Management**.

## 1. What was added

- Kong declarative config: `gateway/kong/kong.yml`
- Kong declarative config (hybrid upstreams): `gateway/kong/kong.hybrid.yml`
- Kong + observability stack: `gateway/docker-compose.kong.yml`
- Kong + observability stack (hybrid): `gateway/docker-compose.kong.hybrid.yml`
- Prometheus config: `gateway/observability/prometheus.yml`
- Prometheus config (hybrid): `gateway/observability/prometheus.hybrid.yml`
- OpenTelemetry collector config: `gateway/observability/otel-collector.yml`
- Cloudflare policy template: `gateway/cloudflare/policy-template.md`
- Azure APIM policy template: `gateway/apim/azure-apim-policy.xml`
- Endpoint audit (current repo values): `docs/gateway/ENDPOINT_AUDIT_2026-03-19.md`

## 2. Policy model

### Authentication
- `key-auth` plugin enforces `X-Api-Key`.

### Authorization
- `acl` plugin maps consumers to groups:
  - `mobile-app`
  - `admin-web`
  - `internal`
- Admin endpoints are restricted to `admin-web` and/or `internal`.

### Quota / Rate limits
- Route-level `rate-limiting` plugin with separate thresholds for:
  - Backend public API
  - Admin routes
  - AI heavy endpoints (STT/TTS/chat)

### Observability
- `correlation-id` plugin adds `X-Request-Id`.
- `prometheus` plugin exposes `/metrics` on Kong admin endpoint.
- `opentelemetry` plugin exports traces to OTel Collector.
- OTel Collector forwards traces to Jaeger.

## 3. Run locally

Prerequisite:
- Existing network from root stack: `lexilingo-network`.
- Backend and AI services reachable as `backend-service:8000` and `ai-service:8001` in that network.

Start services:

```bash
cd gateway
docker compose -f docker-compose.kong.yml up -d
```

## 3.1 Run hybrid profile (Render + Tunnel upstreams)

Use this profile when backend is on Render and AI is exposed through Cloudflare Tunnel.

```bash
cd gateway
docker compose -f docker-compose.kong.hybrid.yml up -d
```

Hybrid upstream source of truth:
- `docs/gateway/ENDPOINT_AUDIT_2026-03-19.md`

Important:
- Update `gateway/kong/kong.hybrid.yml` when tunnel URL changes.

Gateway endpoints:
- Public gateway: `http://localhost:8008`
- Kong admin API: `http://localhost:8009`
- Prometheus UI: `http://localhost:9090`
- Grafana UI: `http://localhost:3001`
- Jaeger UI: `http://localhost:16686`

## 4. Test quick checks

### 4.1 Health checks

```bash
curl http://localhost:8008/backend-health
curl http://localhost:8008/ai-health
```

### 4.2 Auth required endpoint

```bash
curl -i http://localhost:8008/api/v1/courses
```

Expected: `401` or `403`.

### 4.3 Authenticated call

```bash
curl -i http://localhost:8008/api/v1/courses \
  -H "X-Api-Key: replace-mobile-key"
```

## 5. Integrating clients

Use one base URL for all clients:
- `http://localhost:8008` (local)
- `https://api.your-domain.com` (production)

Client policy:
- Send `X-Api-Key` for gateway auth.
- Continue sending Bearer JWT if backend still validates user identity.

## 6. Production notes

1. Rotate API keys regularly.
2. Never expose Kong admin port publicly.
3. Restrict origin firewall to Cloudflare/APIM egress ranges.
4. Tune route limits based on real traffic.
5. Add dashboards and alerts for:
- 4xx/5xx spikes
- p95 latency
- consumer-level quota saturation

## 7. Cloudflare and APIM options

- Cloudflare template: `gateway/cloudflare/policy-template.md`
- Azure APIM template: `gateway/apim/azure-apim-policy.xml`

Recommended pattern:
- Cloudflare or APIM at edge
- Kong as internal gateway/policy runtime
- Backend and AI services private behind gateway
