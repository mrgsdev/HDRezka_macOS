#!/bin/sh
# Builds REZKA in Release and packs it for a GitHub release: build/REZKA-<version>.zip.
# The app updates itself from the zip attached to the latest release, so attach exactly this file.
set -e
cd "$(dirname "$0")/.."

xcodebuild -project REZKA.xcodeproj -scheme REZKA -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build -quiet build

APP=build/Build/Products/Release/REZKA.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="build/REZKA-$VERSION.zip"

# ditto keeps the code signature intact; plain zip can break it.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
codesign --verify --deep --strict "$APP"

echo "Готово: $ZIP"
echo "Тег релиза: v$VERSION"
