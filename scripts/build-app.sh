#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--use-debug-build" ]]; then
    EXECUTABLE=.build/debug/ProxPulse
else
    swift build -c release
    EXECUTABLE=.build/release/ProxPulse
fi
APP="$PWD/.build/ProxPulse.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi
cp "$EXECUTABLE" "$APP/Contents/MacOS/ProxPulse"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ProxPulse</string>
<key>CFBundleIdentifier</key><string>dev.proxpulse.app</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleName</key><string>ProxPulse</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.3</string>
<key>CFBundleVersion</key><string>17</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>dev.proxpulse.dashboard</string><key>CFBundleURLSchemes</key><array><string>proxpulse</string></array></dict></array>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ -f .build/ProxPulseWidget ]]; then
    python3 scripts/verify-widget-entry.py .build/ProxPulseWidget
    EXTENSION="$APP/Contents/PlugIns/ProxPulseWidget.appex"
    mkdir -p "$EXTENSION/Contents/MacOS" "$EXTENSION/Contents/Resources"
    if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$EXTENSION/Contents/Resources/AppIcon.icns"; fi
    cp .build/ProxPulseWidget "$EXTENSION/Contents/MacOS/ProxPulseWidget"
    python3 - "$EXTENSION/Contents/Info.plist" <<'PYINFO'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
 plistlib.dump({'CFBundleIconFile':'AppIcon.icns','CFBundleExecutable':'ProxPulseWidget','CFBundleIdentifier':'dev.proxpulse.app.widget','CFBundleName':'ProxPulse','CFBundleDisplayName':'ProxPulse','CFBundlePackageType':'XPC!','CFBundleShortVersionString':'0.2.3','CFBundleVersion':'17','LSMinimumSystemVersion':'14.0','CFBundleInfoDictionaryVersion':'6.0','CFBundleSupportedPlatforms':['MacOSX'],'NSExtension':{'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}},f)
PYINFO
    codesign --force --sign - --entitlements ProxPulse.entitlements "$EXTENSION"
fi
cp scripts/install.sh "$APP/Contents/Resources/install.sh"
codesign --force --sign - --entitlements ProxPulse.local.entitlements "$APP"
print "Built $APP (native app; local WidgetKit extension included when prebuilt)"
