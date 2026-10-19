#!/bin/zsh
# Reproducible universal release using the macOS SDK; no Xcode GUI dependency.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-environment.sh
VERSION=0.1.0
BUILD=7
RELEASE="$PWD/.build/public-release"
APP="$RELEASE/ProxPulse.app"
mkdir -p "$RELEASE"
swift "${compiler_flags[@]}" scripts/make-icon.swift
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
for architecture in x86_64 arm64; do
    triple="$architecture-apple-macosx14.0"
    scratch="$PWD/.build/production-$architecture"
    swift build -c release --triple "$triple" --scratch-path "$scratch" "${package_flags[@]}"
    binary_dir="$(swift build -c release --triple "$triple" --scratch-path "$scratch" --show-bin-path)"
    cp "$binary_dir/ProxPulse" "$RELEASE/ProxPulse-$architecture"
    strip -S "$RELEASE/ProxPulse-$architecture"
    swiftc -O -swift-version 6 -target "$triple" -parse-as-library -application-extension \
        -Xlinker -e -Xlinker _NSExtensionMain "${compiler_flags[@]}" \
        -I "$binary_dir/Modules" WidgetExtension/ProxPulseWidget.swift \
        "$binary_dir"/ProxPulseCore.build/*.o "$binary_dir"/ProxPulseWidgetUI.build/*.o \
        -o "$RELEASE/ProxPulseWidget-$architecture"
    strip -S "$RELEASE/ProxPulseWidget-$architecture"
    python3 scripts/verify-widget-entry.py "$RELEASE/ProxPulseWidget-$architecture"
done
# Assemble in an isolated directory, never from the developer's installed app or shared data.
rm -rf "$APP"
EXTENSION="$APP/Contents/PlugIns/ProxPulseWidget.appex"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXTENSION/Contents/MacOS" "$EXTENSION/Contents/Resources"
lipo -create "$RELEASE/ProxPulse-x86_64" "$RELEASE/ProxPulse-arm64" -output "$APP/Contents/MacOS/ProxPulse"
lipo -create "$RELEASE/ProxPulseWidget-x86_64" "$RELEASE/ProxPulseWidget-arm64" -output "$EXTENSION/Contents/MacOS/ProxPulseWidget"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/AppIcon.icns "$EXTENSION/Contents/Resources/AppIcon.icns"
python3 - "$APP" "$VERSION" "$BUILD" <<'PY'
import pathlib,plistlib,sys
app,version,build=pathlib.Path(sys.argv[1]),sys.argv[2],sys.argv[3]
common={'CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'ProxPulse','CFBundleDisplayName':'ProxPulse','CFBundleIconFile':'AppIcon.icns','CFBundleShortVersionString':version,'CFBundleVersion':build,'CFBundleSupportedPlatforms':['MacOSX'],'LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True}
host={**common,'CFBundleExecutable':'ProxPulse','CFBundleIdentifier':'dev.proxpulse.app','CFBundlePackageType':'APPL','LSApplicationCategoryType':'public.app-category.utilities','CFBundleURLTypes':[{'CFBundleURLName':'dev.proxpulse.dashboard','CFBundleURLSchemes':['proxpulse']}]}
ext={**common,'CFBundleExecutable':'ProxPulseWidget','CFBundleIdentifier':'dev.proxpulse.app.widget','CFBundlePackageType':'XPC!','NSExtension':{'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}}
for path,info in [(app/'Contents/Info.plist',host),(app/'Contents/PlugIns/ProxPulseWidget.appex/Contents/Info.plist',ext)]:
 with path.open('wb') as stream: plistlib.dump(info,stream)
PY
# Preserve the proper entitlements explicitly, signing nested code before its host.
codesign --force --sign - --entitlements ProxPulse.entitlements "$EXTENSION"
codesign --force --sign - --entitlements ProxPulse.local.entitlements "$APP"
# Deep re-sign must preserve each nested component's own sandbox/group entitlements.
codesign --force --deep --sign - --preserve-metadata=entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
python3 - "$APP" <<'PYSIGN'
import pathlib,plistlib,subprocess,sys
app=pathlib.Path(sys.argv[1])
for component in [app,app/'Contents/PlugIns/ProxPulseWidget.appex']:
 value=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(component)],stderr=subprocess.DEVNULL))
 assert value['com.apple.security.application-groups']==['group.proxpulsedata']
 if component.suffix=='.appex': assert value.get('com.apple.security.app-sandbox') is True
print('PASS: final host/extension App Group and widget sandbox entitlements')
PYSIGN
lipo -archs "$APP/Contents/MacOS/ProxPulse"
lipo -archs "$EXTENSION/Contents/MacOS/ProxPulseWidget"
print "Release app: $APP"
