#!/bin/bash
set -euo pipefail

# Ensure dist directory exists
mkdir -p dist

GITHUB_REF_NAME=${GITHUB_REF_NAME:-}
if [ -n "$GITHUB_REF_NAME" ]; then
    VERSION=${GITHUB_REF_NAME#v}
else
    VERSION="0.1.0-dev"
fi

echo "Building tunaPop $VERSION..."

# Build release binary for universal architecture
swift build -c release --arch arm64 --arch x86_64

# Bundle skeleton
APP="dist/tunaPop.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Copy binary and metadata
cp .build/apple/Products/Release/TunaPop "$APP/Contents/MacOS/tunaPop"
cp Sources/TunaPop/Resources/Info.plist "$APP/Contents/Info.plist"
cp Sources/TunaPop/Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp Sources/TunaPop/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Copy Sparkle.framework (binary's rpath includes @executable_path/../lib)
SPARKLE_FRAMEWORK="$(find .build/artifacts -type d -name 'Sparkle.framework' -path '*macos-arm64_x86_64*' 2>/dev/null | head -1)"
if [ -z "$SPARKLE_FRAMEWORK" ]; then
    SPARKLE_FRAMEWORK=".build/apple/Products/Release/Sparkle.framework"
fi
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    mkdir -p "$APP/Contents/lib"
    cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/lib/"
    echo "Embedded Sparkle.framework from $SPARKLE_FRAMEWORK"
else
    echo "WARNING: Sparkle.framework not found; app may fail to launch."
fi

# Update versions in Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%s)" "$APP/Contents/Info.plist"

# Code sign if DEVELOPER_ID is provided; otherwise ad-hoc sign (needed for
# stable TCC bundle identity on macOS 14+).
DEVELOPER_ID=${DEVELOPER_ID:-}
if [ -n "$DEVELOPER_ID" ]; then
    echo "Signing app bundle with Developer ID..."
    if [ -d "$APP/Contents/lib/Sparkle.framework" ]; then
        codesign --force --options runtime --sign "$DEVELOPER_ID" \
            "$APP/Contents/lib/Sparkle.framework"
    fi
    codesign --deep --force --options runtime \
        --sign "$DEVELOPER_ID" \
        --entitlements scripts/entitlements.plist \
        "$APP"
else
    echo "DEVELOPER_ID not set; applying ad-hoc signature."
    if [ -d "$APP/Contents/lib/Sparkle.framework" ]; then
        codesign --force --sign - "$APP/Contents/lib/Sparkle.framework"
    fi
    codesign --deep --force --sign - "$APP"
fi

# Create DMG and notarize if APPLE_ID/APP_PASSWORD are provided
APPLE_ID=${APPLE_ID:-}
APP_PASSWORD=${APP_PASSWORD:-}
APPLE_TEAM_ID=${APPLE_TEAM_ID:-}
DMG="dist/tunaPop-$VERSION.dmg"

echo "Creating DMG..."
hdiutil create -volname "tunaPop" -srcfolder "$APP" -ov -format UDZO "$DMG"

if [ -n "$APPLE_ID" ] && [ -n "$APP_PASSWORD" ]; then
    echo "Notarizing DMG..."
    xcrun notarytool submit "$DMG" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$DMG"
else
    echo "APPLE_ID or APP_PASSWORD not set, skipping notarization."
fi

echo "Packaging complete: $DMG"

# Output sha256 for Homebrew Cask formula
SHASUM=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo ""
echo "Homebrew Cask sha256:"
echo "  $SHASUM"
echo ""
echo "Update homebrew/Casks/tunapop.rb with:"
echo "  sha256 \"$SHASUM\""
