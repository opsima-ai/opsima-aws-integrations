#!/usr/bin/env bash
# Builds a reproducible deployment package: same source, same zip, same SHA-256, on any machine.
set -euo pipefail
cd "$(dirname "$0")/.."

# The version reported by the HEALTHCHECK action must be the one of package.json.
PKG_VERSION="$(node -p "require('./package.json').version")"
SRC_VERSION="$(sed -nE 's/^const LAMBDA_VERSION = "([^"]+)";$/\1/p' src/handleOpsimaAccounts.ts)"
if [ "$PKG_VERSION" != "$SRC_VERSION" ]; then
  echo "LAMBDA_VERSION in src/handleOpsimaAccounts.ts ($SRC_VERSION) differs from package.json ($PKG_VERSION)" >&2
  exit 1
fi

npm ci --silent
rm -rf dist
npx tsc

# Fixed timestamp, set in UTC, so the archive depends neither on the build date nor on the time
# zone of the machine.
TZ=UTC find dist -type f -name '*.js' -exec touch -t 202001010000.00 {} +

ARCHIVE="dist/handle-opsima-accounts.zip"
rm -f "$ARCHIVE"
( cd dist && TZ=UTC zip -X -D -q handle-opsima-accounts.zip handleOpsimaAccounts.js )

echo "version: $PKG_VERSION"
echo "package: $ARCHIVE"
echo "sha256 (hex, for verification):   $(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
echo "sha256 (base64, for Terraform):   $(openssl dgst -sha256 -binary "$ARCHIVE" | base64)"
