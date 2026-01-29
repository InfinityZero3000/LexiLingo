#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../flutter-app" || exit 1
exec flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0
