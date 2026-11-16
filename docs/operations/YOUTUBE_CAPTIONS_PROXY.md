# YouTube captions proxy (Cloudflare WARP)

YouTube answers `RequestBlocked` to the VPS's datacenter IP range, so caption
lookups (`GET /api/v1/youtube/captions/{id}`) return `status: "unavailable"`
without a proxy. Prod routes only that call through a local WARP HTTP proxy.

## What runs

| Piece | Where |
|---|---|
| `lexilingo-warp-proxy.service` (systemd, inside the `lexilingo` LXD container) | runs `wireproxy`, a userspace WireGuard client; listens on `172.30.0.128:8118`, the gateway of the compose network, so only the containers (and the host) can reach it |
| `/var/lib/lexilingo/warp/` (0700) | `wireproxy` binary, `wireproxy.conf`, `wgcf-profile-v4.conf`, `wgcf-account.toml` (the anonymous WARP device; **secrets, 0600, not in git**) |
| `YOUTUBE_TRANSCRIPT_PROXY_URL=http://172.30.0.128:8118` | `.env.production` (not a secret); read by backend-service and its two celery services |

Only `youtube_transcript_api` uses it (`_get_transcript_sync` in `routes/youtube.py`).
Nothing else the backend does goes through the proxy.

## Why IPv4 only

The WARP exits over IPv6 are assigned per tunnel start and YouTube flags some
ranges: 3 restarts gave 2/3, 0/3 and 0/3 working lookups. Dropping the IPv6
`Address`/`AllowedIPs` from the profile (`wgcf-profile-v4.conf`) gave a stable
IPv4 exit and 3/3 lookups on repeated restarts. If lookups start failing again,
that exit is the first thing to check.

## Check it

```bash
sudo lxc exec lexilingo -- systemctl is-active lexilingo-warp-proxy
sudo lxc exec lexilingo -- curl -s -x http://172.30.0.128:8118 https://www.cloudflare.com/cdn-cgi/trace | grep -E '^(ip|warp)='   # warp=on
curl -s "https://api.lexilingo.me/api/v1/youtube/captions/arj7oStGLkU?lang=en"   # status: ok (first call ~20s cold, ~1.5s warm)
```

## It stops working

The app degrades, it does not break: the player shows "Subtitles could not be
loaded" with a retry button, and a failed lookup is never cached
(`CaptionsUnavailable`), so recovery is immediate once the proxy is back.

- `systemctl restart lexilingo-warp-proxy`, then re-check.
- If the compose network is recreated with another subnet, the bind address
  `172.30.0.128` no longer exists and the unit fails to start: set the new
  gateway (`docker network inspect lexilingo_lexilingo-prod`) in
  `wireproxy.conf` and in `YOUTUBE_TRANSCRIPT_PROXY_URL`, then recreate
  backend-service and the two reminder services with `up -d --no-deps --no-build`
  (not `--force-recreate`).
- Register a fresh WARP device with `wgcf` (`register --accept-tos`, `generate`),
  strip the IPv6 lines, and replace `wgcf-profile-v4.conf`.

## Roll back

```bash
sudo lxc exec lexilingo -- systemctl disable --now lexilingo-warp-proxy
# remove the YOUTUBE_TRANSCRIPT_PROXY_URL line from /opt/lexilingo/.env.production
# (a pre-change copy is in /opt/lexilingo/.deploy/env.production.pre-warp-*), then recreate
# backend-service, backend-reminder-worker and backend-reminder-beat.
```

## Notes

- Set up on 2026-11-16 by hand; compose and the systemd unit are not part of an
  image, so `auto-deploy` does not touch them.
- A full `deploy-one-shot.sh` run on this box would also create prometheus and
  grafana (they are in `docker-compose.yml` but not running on prod), so the proxy
  was applied with a targeted `up -d --no-deps --no-build` instead.
- The YouTube *Data API* (channel videos, search) is a separate matter: it needs a
  valid `YOUTUBE_API_KEY` and does not use this proxy.
