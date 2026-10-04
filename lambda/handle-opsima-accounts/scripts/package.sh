#!/usr/bin/env bash
# Builds a reproducible deployment package: same source, same zip, same SHA-256, on any machine.
set -euo pipefail
cd "$(dirname "$0")/.."

npm ci --silent
rm -rf dist
npx tsc

# Fixed timestamp so the archive does not depend on the build date.
find dist -type f -name '*.js' -exec touch -t 202001010000.00 {} +

ARCHIVE="dist/handle-opsima-accounts.zip"
rm -f "$ARCHIVE"
( cd dist && TZ=UTC zip -X -D -q handle-opsima-accounts.zip handleOpsimaAccounts.js )

echo "package: $ARCHIVE"
echo "sha256 (hex, for verification):   $(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
echo "sha256 (base64, for Terraform):   $(openssl dgst -sha256 -binary "$ARCHIVE" | base64)"
