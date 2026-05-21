#!/bin/bash
set -euo pipefail
KEYCHAIN="build.keychain"
echo "$MAC_CERTIFICATE_BASE64" | base64 --decode > /tmp/cert.p12
security create-keychain -p actions "$KEYCHAIN"
security default-keychain -s "$KEYCHAIN"
security unlock-keychain -p actions "$KEYCHAIN"
security import /tmp/cert.p12 -k "$KEYCHAIN" -P "$MAC_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k actions "$KEYCHAIN"
rm /tmp/cert.p12
