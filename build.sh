#!/bin/zsh
# Builds Yap. ~/Applications/Yap.app is a fixed launcher, so macOS keeps its microphone and
# Accessibility permissions; a rebuild only replaces the library in ~/Library/Application Support/Yap.
# ./build.sh --launcher reinstalls the launcher too (macOS then asks for the permissions again).
set -euo pipefail
cd "$(dirname "$0")"

SCRATCH="$HOME/Library/Caches/Yap/build"
APP="$HOME/Applications/Yap.app"
CORE_DIR="$HOME/Library/Application Support/Yap"
ICON="Resources/Yap.icns"

swift build -c release --scratch-path "$SCRATCH"
BIN_DIR="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)"

pkill -x Yap 2>/dev/null || true
mkdir -p "$CORE_DIR"
cp "$BIN_DIR/libYapCore.dylib" "$CORE_DIR/YapCore.dylib.new"
codesign --force --sign - "$CORE_DIR/YapCore.dylib.new"
mv "$CORE_DIR/YapCore.dylib.new" "$CORE_DIR/YapCore.dylib"

if [[ ! -f "$ICON" ]]; then
    WORK="$(mktemp -d)"
    SET="$WORK/Yap.iconset"
    mkdir -p "$SET" Resources
    "$BIN_DIR/Yap" --icon "$WORK/icon-1024.png"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$WORK/icon-1024.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$WORK/icon-1024.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$SET" -o "$ICON"
fi

if [[ ! -d "$APP" || "${1:-}" == "--launcher" ]]; then
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$BIN_DIR/Yap" "$APP/Contents/MacOS/Yap"
    cp Info.plist "$APP/Contents/Info.plist"
    cp "$ICON" "$APP/Contents/Resources/Yap.icns"
    codesign --force --sign - "$APP"
fi
echo "$APP"
