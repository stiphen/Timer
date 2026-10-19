#!/bin/bash
# Builds a universal (arm64 + x86_64) Timer.app into ./dist.
# Pass --install to also copy it into /Applications.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Timer"
APP="dist/$APP_NAME.app"

# Per-arch builds merged with lipo: `swift build --arch a --arch b` needs full Xcode.
for arch in arm64 x86_64; do
    swift build -c release --triple "$arch-apple-macosx14.0" --scratch-path ".build/$arch"
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

lipo -create -output "$APP/Contents/MacOS/$APP_NAME" \
    ".build/arm64/release/$APP_NAME" ".build/x86_64/release/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: enough to run locally; distribution needs a Developer ID + notarization.
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    echo "Installed: /Applications/$APP_NAME.app"
fi
