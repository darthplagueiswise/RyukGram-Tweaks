#!/bin/bash
# Downloads FFmpegKit xcframeworks and extracts arm64 device frameworks.
# Output: modules/ffmpegkit/{ffmpegkit,libav*,libsw*}.framework/

set -e

DEST="$(cd "$(dirname "$0")/.." && pwd)/modules/ffmpegkit"
URL="https://github.com/luthviar/ffmpeg-kit-ios-full/releases/download/6.0/ffmpeg-kit-ios-full.zip"

mkdir -p "$DEST"

# Already set up?
if [ -f "$DEST/ffmpegkit.framework/ffmpegkit" ]; then
    echo "[ffmpegkit] Already present, skipping."
    exit 0
fi

echo "[ffmpegkit] Downloading ffmpeg-kit-ios-full..."
TMPDIR=$(mktemp -d)
curl -L -o "$TMPDIR/ffmpegkit.zip" "$URL"

echo "[ffmpegkit] Extracting arm64 device frameworks..."
unzip -q "$TMPDIR/ffmpegkit.zip" -d "$TMPDIR"

# Copy the ios-arm64 slice from each xcframework
for xcfw in "$TMPDIR"/ffmpeg-kit-ios-full/*.xcframework; do
    NAME=$(basename "$xcfw" .xcframework)
    ARM64="$xcfw/ios-arm64/$NAME.framework"
    if [ -d "$ARM64" ]; then
        cp -R "$ARM64" "$DEST/"
        echo "[ffmpegkit]   $NAME.framework"
    fi
done

rm -rf "$TMPDIR"
echo "[ffmpegkit] Done — $(ls -d "$DEST"/*.framework | wc -l | tr -d ' ') frameworks installed."
