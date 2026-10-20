#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/.build/public-release/ProxPulse.app"
STAGING="$PWD/.build/dmg-staging"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BASENAME="ProxPulse-v${VERSION}.dmg"
DMG="$PWD/dist/$BASENAME"
[[ -d "$APP/Contents/PlugIns/ProxPulseWidget.appex" ]] || { print -u2 'Run scripts/build-release.sh first'; exit 1; }
codesign --verify --deep --strict "$APP"
rm -rf "$STAGING"
mkdir -p "$STAGING" "$PWD/dist"
ditto "$APP" "$STAGING/ProxPulse.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname ProxPulse -srcfolder "$STAGING" -ov -format UDZO -fs HFS+ "$DMG"
(cd dist && shasum -a 256 "$BASENAME" > "$BASENAME.sha256")
hdiutil verify "$DMG"
print "Installer: $DMG"
