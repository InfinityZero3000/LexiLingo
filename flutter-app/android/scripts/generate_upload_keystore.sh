#!/usr/bin/env bash
set -euo pipefail

# Generates an Android upload keystore for release signing.
# Usage:
#   ./android/scripts/generate_upload_keystore.sh <alias> <keystore-password> <key-password> [keystore-path]

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 <alias> <keystore-password> <key-password> [keystore-path]" >&2
  exit 1
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool not found. Install JDK first (Java 11+)." >&2
  exit 1
fi

ALIAS="$1"
STORE_PASSWORD="$2"
KEY_PASSWORD="$3"
KEYSTORE_PATH="${4:-android/app/upload-keystore.jks}"

mkdir -p "$(dirname "$KEYSTORE_PATH")"

keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE_PATH" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "CN=LexiLingo, OU=Mobile, O=LexiLingo, L=HCMC, ST=HCMC, C=VN"

echo "Keystore generated at: $KEYSTORE_PATH"
echo "Next: create android/key.properties (or copy android/key.properties.example)."
