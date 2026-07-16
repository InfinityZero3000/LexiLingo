#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

compose=(
  docker compose
  -p lexilingo-validation
  -f docker-compose.dev.yml
  -f docker-compose.validation.yml
)

for service in postgres redis redis-ai mongodb ai-service; do
  container=$("${compose[@]}" ps -q "$service")
  [[ -n "$container" ]] || {
    echo "missing container: $service" >&2
    exit 1
  }
  status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container")
  [[ "$status" == healthy ]] || {
    echo "not healthy: $service ($status)" >&2
    exit 1
  }
done

curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:18000/health/ready >/dev/null
curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:18001/health >/dev/null
migration=$("${compose[@]}" exec -T backend-service alembic current)
[[ "$migration" == *"(head)"* ]] || {
  echo "database migration is not at head: $migration" >&2
  exit 1
}
echo "validation stack healthy"
