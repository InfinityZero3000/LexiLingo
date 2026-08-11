#!/usr/bin/env bash
set -euo pipefail

# Writes android/app/google-services.json from env var.
# Usage:
#   export ANDROID_GOOGLE_SERVICES_JSON='{"project_info":...}'
#   ./android/scripts/prepare_google_services_from_env.sh

if [[ -z "${ANDROID_GOOGLE_SERVICES_JSON:-}" ]]; then
  echo "ANDROID_GOOGLE_SERVICES_JSON is empty" >&2
  exit 1
fi

mkdir -p android/app
printf '%s' "$ANDROID_GOOGLE_SERVICES_JSON" > android/app/google-services.json

echo "Wrote android/app/google-services.json"
