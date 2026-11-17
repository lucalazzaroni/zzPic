#!/usr/bin/env bash
# Builds build/zzPic.app (universal: Apple silicon + Intel) and signs it ad hoc.
#   Scripts/build-app.sh            # universal release build
#   ARCHS=arm64 Scripts/build-app.sh  # faster, native only
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftUI's macros ship with Xcode; prefer it even if the Command Line Tools are selected.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

VERSION=$(cat VERSION)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
ARCHS=${ARCHS:-"arm64 x86_64"}
CONFIG=${CONFIG:-release}
APP=build/zzPic.app

binaries=()
for arch in $ARCHS; do
  echo "▸ Building ${arch}…"
  swift build -c "$CONFIG" --triple "$arch-apple-macosx14.0" --scratch-path ".build/$arch"
  binaries+=("$(swift build -c "$CONFIG" --triple "$arch-apple-macosx14.0" --scratch-path ".build/$arch" --show-bin-path)/zzPic")
done

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/zzPic"

# SwiftPM records the deployment target (14.0) as the "built with" SDK version, which makes
# macOS 26+ run the app in compatibility mode (old small window buttons, no Liquid Glass).
# Stamp the real SDK version so the system uses the current design.
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
MIN_VERSION=$(sed -nE 's/.*\.macOS\(\.v([0-9]+)\).*/\1.0/p' Package.swift)
for arch in $ARCHS; do
  xcrun vtool -arch "$arch" -set-build-version macos "$MIN_VERSION" "$SDK_VERSION" -replace \
    -output "$APP/Contents/MacOS/zzPic.tmp" "$APP/Contents/MacOS/zzPic" 2>/dev/null
  mv "$APP/Contents/MacOS/zzPic.tmp" "$APP/Contents/MacOS/zzPic"
done
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Signing (ad hoc)"
codesign --force --sign - --timestamp=none "$APP"

echo "✓ $APP ($(lipo -archs "$APP/Contents/MacOS/zzPic"), v$VERSION)"
