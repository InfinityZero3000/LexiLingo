#!/bin/bash
# LexiLingo MCP Server — portable startup script
DIR="$(cd "$(dirname "$0")" && pwd)"

# Load .env if present
if [ -f "$DIR/.env" ]; then
  set -a
  source "$DIR/.env"
  set +a
fi

exec "$DIR/venv/bin/python3.12" "$DIR/server.py"
