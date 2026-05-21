#!/bin/bash
set -euo pipefail

VERSION=${VERSION:-}
GITHUB_REF_NAME=${GITHUB_REF_NAME:-}
if [ -z "$VERSION" ] && [ -n "$GITHUB_REF_NAME" ]; then
    VERSION=${GITHUB_REF_NAME#v}
fi
VERSION=${VERSION:-0.1.0-dev}

echo "Updating appcast.xml for version $VERSION (stub)..."

# Implementation deferred to Phase 15.x.
# For now, this is a stub script to ensure build pipelines pass.
# In the future, this will parse the signature from dist/signature.txt
# and insert a new <item> tag into appcast.xml.

if [ -f dist/signature.txt ]; then
    SIGNATURE=$(cat dist/signature.txt)
    echo "Found signature: $SIGNATURE"
else
    echo "No signature found. Using placeholder."
    SIGNATURE="placeholder_signature"
fi

echo "Appcast update skipped (stub)."
