#!/bin/zsh
# Builds the downloadable Yap: dist/Yap.app with the app's code inside the bundle, packed into dist/Yap-<version>.dmg
# with an Applications shortcut to drag it onto. Unlike build.sh it installs nothing and leaves a running Yap alone.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
SCRATCH="$HOME/Library/Caches/Yap/build"
APP="dist/Yap.app"
DMG="dist/Yap-$VERSION.dmg"

swift build -c release --scratch-path "$SCRATCH"
BIN_DIR="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)"
FLUIDAUDIO="$SCRATCH/checkouts/FluidAudio"

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources/Licenses/FluidAudio"
cp Info.plist "$APP/Contents/Info.plist"
cp "$BIN_DIR/Yap" "$APP/Contents/MacOS/Yap"
cp "$BIN_DIR/libYapCore.dylib" "$APP/Contents/Frameworks/YapCore.dylib"
cp Resources/Yap.icns "$APP/Contents/Resources/Yap.icns"
for lang in en ru; do
    mkdir -p "$APP/Contents/Resources/$lang.lproj"
    plutil -convert binary1 -o "$APP/Contents/Resources/$lang.lproj/InfoPlist.strings" "Resources/$lang.lproj/InfoPlist.strings"
done
cp LICENSE "$APP/Contents/Resources/Licenses/Yap.txt"
cp "$FLUIDAUDIO/LICENSE" "$APP/Contents/Resources/Licenses/FluidAudio/LICENSE.txt"
cp -R "$FLUIDAUDIO/ThirdPartyLicenses/." "$APP/Contents/Resources/Licenses/FluidAudio/"

# Ad-hoc signature, inner library first. Without an Apple Developer ID macOS asks the user to allow the app once.
xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/Frameworks/YapCore.dylib"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Yap -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
rm -rf "$STAGE"
shasum -a 256 "$DMG"
