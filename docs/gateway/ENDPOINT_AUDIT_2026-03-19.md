# Endpoint Audit for API Gateway (2026-03-19)

This file captures the currently configured service addresses in the repository
for wiring API Gateway policy/routes in hybrid deployment.

## Runtime topology in repo

- Flutter Web: Vercel or local web dev
- Admin Dashboard: Vercel (env in `vercel.json`)
- Backend API: Render
- AI Service: Cloudflare Tunnel (temporary URL)

## Audited endpoint values

### Backend
- Production URL: `https://lexilingo-4gu6.onrender.com/api/v1`
- Local URL: `http://localhost:8000/api/v1`
- Sources:
  - `flutter-app/lib/core/utils/constants.dart`
  - `flutter-app/.env.example`
  - `admin-service/vercel.json`

### AI Service
- Production URL (current): `https://enable-tell-memphis-wing.trycloudflare.com/api/v1`
- Local URL: `http://localhost:8001/api/v1`
- Sources:
  - `flutter-app/lib/core/utils/constants.dart`
  - `flutter-app/.env.example`
  - `admin-service/vercel.json`
  - `backend-service/render.yaml`

### Frontend origins (observed)
- Flutter web local: `http://localhost:8080`
- Admin local: `http://localhost:5173`
- Flutter prod: `https://lexilingo.vercel.app`
- Flutter alt prod: `https://flutter-app-nine-pied.vercel.app`
- Sources:
  - `ai-service/api/main.py`
  - `backend-service/app/core/config.py`

## Gateway config profiles added

- Local-internal profile (Docker internal upstreams):
  - `gateway/kong/kong.yml`
  - `gateway/docker-compose.kong.yml`

- Hybrid profile (Render + Cloudflare tunnel upstreams):
  - `gateway/kong/kong.hybrid.yml`
  - `gateway/docker-compose.kong.hybrid.yml`
  - `gateway/observability/prometheus.hybrid.yml`

## Notes

1. `trycloudflare.com` URL is temporary and changes after tunnel restart.
2. For stable production, replace AI upstream with a permanent hostname
   (for example `https://ai.yourdomain.com`) and update `gateway/kong/kong.hybrid.yml`.
3. Keep using one public API base URL from clients (gateway URL) to avoid split routing in apps.
