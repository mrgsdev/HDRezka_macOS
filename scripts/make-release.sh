#!/bin/sh
# Builds REZKA in Release and packs it for a GitHub release; attach both files:
#   build/REZKA-<version>.dmg — for people: open it and drag REZKA to Applications;
#   build/REZKA-<version>.zip — for the app's own updater. macOS asks before an app may read
#   a mounted disk image, so updates come from the zip.
set -e
cd "$(dirname "$0")/.."

xcodebuild -project REZKA.xcodeproj -scheme REZKA -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build -quiet build

APP=build/Build/Products/Release/REZKA.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/REZKA-$VERSION.dmg"
ZIP="build/REZKA-$VERSION.zip"
codesign --verify --deep --strict "$APP"

# The image opens to REZKA.app next to a link to Applications: drag one onto the other to install.
# ditto keeps the code signature intact.
STAGE=build/dmg
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/REZKA.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "REZKA" -srcfolder "$STAGE" -format UDZO -ov -quiet "$DMG"
rm -rf "$STAGE"

# ditto again: plain zip can break the signature.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Готово: $DMG и $ZIP — приложите к релизу оба"
echo "Тег релиза: v$VERSION"
