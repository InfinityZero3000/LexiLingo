# Cloudflare WAF Rules — LexiLingo

Generated from 30-day log analysis (May 2026).
Deploy these in **Cloudflare Dashboard → Security → WAF → Custom Rules**.

---

## 0. ⚠️ CRITICAL: Allow CORS Preflight (OPTIONS) — Must be Rule #1

**Why**: Cloudflare Bot Fight Mode blocks OPTIONS preflight requests before they reach
the backend, returning `cf-mitigated: challenge`. This breaks CORS for ALL authenticated
API calls from `www.lexilingo.me` to `api.lexilingo.me`.

**Fix**: Create a WAF "Skip" rule that bypasses bot protection for OPTIONS requests.

**Dashboard → Security → WAF → Custom Rules → Create rule**

**Rule name:** `Allow CORS preflight OPTIONS`
**Expression:**
```
(http.request.method eq "OPTIONS") and (http.host eq "api.lexilingo.me")
```
**Action:** Skip → Bot Fight Mode

> ⚡ This rule MUST be placed first (highest priority) before any Block/Challenge rules.

**Also in Dashboard → Security → Bots:**
- "Likely automated" → change from **Managed Challenge** to **Allow** (or create a
  more targeted rule with `http.request.method ne "OPTIONS"` for Bot Fight Mode)

---

## 1. Enable Bot Fight Mode (Free plan)

Dashboard → Security → Bots → **Super Bot Fight Mode**
- Definitely automated → **Block**
- Likely automated → **Managed Challenge**

This alone will stop the majority of scanner traffic (libredtail-http, zgrab, etc.).

---

## 2. Block Scanner User-Agents (Custom Rule)

**Rule name:** `Block known scanner UAs`
**Expression:**
```
(http.user_agent contains "libredtail") or
(http.user_agent contains "zgrab") or
(http.user_agent contains "masscan") or
(http.user_agent contains "nikto") or
(http.user_agent contains "sqlmap") or
(http.user_agent contains "nuclei") or
(http.user_agent contains "gobuster") or
(http.user_agent contains "dirbuster") or
(http.user_agent contains "python-httpx") or
(http.user_agent eq "") or
(http.user_agent eq "-")
```
**Action:** Block

---

## 3. Block Direct Origin Access (Most Important)

The top offender `185.177.72.52` (2770 hits) bypasses Cloudflare and hits the origin server directly.
To prevent this, restrict the VPS firewall to only accept port 80/443 from Cloudflare IP ranges.

### Option A — UFW on VPS (recommended)
```bash
# Run on the VPS as root. Replaces direct port 80/443 rules with CF-only.
sudo ufw delete allow 80/tcp
sudo ufw delete allow 443/tcp

# Cloudflare IPv4 ranges (update from https://www.cloudflare.com/ips-v4 periodically)
for ip in \
  173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 \
  141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 \
  197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 \
  104.24.0.0/14 172.64.0.0/13 131.0.72.0/22; do
  sudo ufw allow from "$ip" to any port 80 proto tcp
  sudo ufw allow from "$ip" to any port 443 proto tcp
done
sudo ufw reload
```

⚠️ **WARNING**: Run this only after confirming your domain's DNS is 100% proxied through Cloudflare (orange cloud). If not, direct HTTPS access will break.

---

## 4. Rate Limit — API Default

**Rule name:** `Rate limit API`
- **Path:** `/api/v1/*`
- **Threshold:** 180 requests per minute per IP
- **Action:** Managed Challenge for 1 minute

---

## 5. Rate Limit — Heavy AI Endpoints

**Rule name:** `Rate limit AI endpoints`
- **Paths:** `/api/v1/stt*`, `/api/v1/tts*`, `/api/v1/lexi*`, `/api/v1/chat*`
- **Threshold:** 30 requests per minute per IP
- **Action:** Block for 1 minute

---

## 6. Block Scanner Paths at Edge (WAF Custom Rule)

**Rule name:** `Block scanner/exploit paths`
**Expression:**
```
(http.request.uri.path contains "/.env") or
(http.request.uri.path contains "/.git") or
(http.request.uri.path contains "/vendor/") or
(http.request.uri.path contains "eval-stdin") or
(http.request.uri.path contains "wp-config") or
(http.request.uri.path contains "phpinfo") or
(http.request.uri.path matches ".*\.php$") or
(http.request.uri.path contains "allow_url_include") or
(http.request.uri.path contains "/etc/passwd") or
(http.request.uri.path contains "/cgi-bin/")
```
**Action:** Block

---

## 7. Managed Challenge for High-Risk Countries (Optional)

Based on log data, most scanner traffic originates from hosting/datacenter ASNs.
If false-positive risk is low, add a Managed Challenge for ASNs known for abuse:

**Expression:**
```
(ip.geoip.asnum in {9009 62041 30823 202425}) and
not (http.request.uri.path contains "/api/v1/auth")
```
(ASNs: Voxility NL, M247, etc. — verify against your log data before blocking)
**Action:** Managed Challenge

---

## 8. IP Block List — Confirmed Abusers

**Rule name:** `Block confirmed abuser IPs`
**Expression:**
```
(ip.src in {185.177.72.52 179.43.146.226 176.142.69.236 212.102.40.218 79.124.40.174 195.170.172.108 195.178.110.104})
```
**Action:** Block

---

## 9. Enable WAF Managed Ruleset

Dashboard → Security → WAF → Managed Rules
- Enable **Cloudflare Managed Ruleset**
- Enable **Cloudflare OWASP Core Ruleset** (sensitivity: Medium)

---

## Monitoring

After deploying, watch:
- **Security → Events** for false positives (legitimate traffic blocked)
- **Analytics → Traffic** for drop in 4xx error rate (target: < 5%)
- Review and update IP blocklist monthly from `gateway/nginx/logs/security.log`
