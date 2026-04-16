#!/bin/bash
# Downloads pre-built FFmpegKit frameworks for iOS arm64.
# Called by build.sh before compilation if modules/ffmpegkit/ is empty.

set -e

DEST="$(dirname "$0")/../modules/ffmpegkit"
MARKER="$DEST/.fetched"

# Skip if already fetched
if [ -f "$MARKER" ]; then
    echo "[ffmpegkit] Already fetched, skipping."
    exit 0
fi

# FFmpegKit 6.0 LTS — min-gpl variant (smallest, has x264)
VERSION="6.0"
VARIANT="min-gpl"
URL="https://github.com/arthenica/ffmpeg-kit/releases/download/v${VERSION}/ffmpeg-kit-${VARIANT}-${VERSION}-ios-xcframework.zip"

echo "[ffmpegkit] Downloading FFmpegKit ${VERSION} (${VARIANT})..."
TMPZIP=$(mktemp /tmp/ffmpegkit-XXXXXX.zip)
curl -L -o "$TMPZIP" "$URL"

echo "[ffmpegkit] Extracting..."
TMPDIR=$(mktemp -d /tmp/ffmpegkit-extract-XXXXXX)
unzip -q "$TMPZIP" -d "$TMPDIR"

# XCFrameworks contain ios-arm64 slices — extract the .framework from each
echo "[ffmpegkit] Installing frameworks..."
for xcfw in "$TMPDIR"/*.xcframework; do
    NAME=$(basename "$xcfw" .xcframework)
    # Find the ios-arm64 framework slice
    ARM64_DIR=$(find "$xcfw" -type d -name "ios-arm64" -o -name "ios-arm64_armv7" 2>/dev/null | head -1)
    if [ -z "$ARM64_DIR" ]; then
        # Try the plain ios directory
        ARM64_DIR=$(find "$xcfw" -type d -name "*.framework" | head -1)
        ARM64_DIR=$(dirname "$ARM64_DIR")
    fi

    if [ -d "$ARM64_DIR/${NAME}.framework" ]; then
        cp -R "$ARM64_DIR/${NAME}.framework" "$DEST/"
        echo "  + ${NAME}.framework"
    else
        echo "  ! ${NAME}.framework not found in xcframework"
    fi
done

# Cleanup
rm -rf "$TMPZIP" "$TMPDIR"

touch "$MARKER"
echo "[ffmpegkit] Done. Frameworks installed to modules/ffmpegkit/"
