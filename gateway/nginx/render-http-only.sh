#!/bin/sh
# Rewrites a rendered gateway config for use behind a TLS-terminating proxy
# (GATEWAY_TLS=off, see docs/operations/MULTI_PROJECT_VPS.md):
#   - drops the port-80 redirect server block,
#   - makes the main server listen on plain port 80 with no ssl_* directives,
#   - trusts the edge proxy's address for real_ip so per-IP rate limits still
#     see the visitor (CF-Connecting-IP) instead of the proxy.
set -eu
file="$1"
trusted="${GATEWAY_TRUSTED_PROXY:-10.77.0.1}"
awk -v trusted="$trusted" '
/^server \{/ { servers++; if (servers == 1) skip = 1 }
skip { if ($0 ~ /^\}/) skip = 0; next }
/^[ \t]*listen 443 ssl;/        { print "    listen 80;"; next }
/^[ \t]*listen \[::\]:443 ssl;/ { print "    listen [::]:80;"; next }
/^[ \t]*http2 on;/              { next }
/^[ \t]*ssl_/                   { next }
/^[ \t]*real_ip_header/         { print; print "    set_real_ip_from " trusted ";"; next }
{ print }
' "$file" > "$file.tmp"
mv "$file.tmp" "$file"
