#!/bin/zsh
# Builds with stock Xcode; isolates compatibility fixes for this machine's mixed CLT installation.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-environment.sh
swift build "${package_flags[@]}"
BINARY_DIR="$(swift build --show-bin-path)"
swiftc -swift-version 6 -parse-as-library "${compiler_flags[@]}" -I "$BINARY_DIR/Modules" scripts/check-core.swift scripts/APIFixtureChecks.swift scripts/Sprint3Checks.swift scripts/Sprint4Checks.swift scripts/Sprint5Checks.swift scripts/Sprint51Checks.swift scripts/Sprint6Checks.swift scripts/Sprint7Checks.swift scripts/Sprint8Checks.swift scripts/Sprint9Checks.swift "$BINARY_DIR"/ProxPulseCore.build/*.swift.o -o .build/check-core
.build/check-core
"$BINARY_DIR/ProxPulse" --verify-demo
"$BINARY_DIR/ProxPulse" --verify-ui
"$BINARY_DIR/ProxPulse" --verify-sprint5
"$BINARY_DIR/ProxPulse" --verify-sprint52
"$BINARY_DIR/ProxPulse" --verify-sprint6
"$BINARY_DIR/ProxPulse" --verify-sprint622
"$BINARY_DIR/ProxPulse" --verify-sprint61
"$BINARY_DIR/ProxPulse" --verify-sprint8
"$BINARY_DIR/ProxPulse" --verify-sprint9
swiftc -swift-version 6 -parse-as-library -application-extension -Xlinker -e -Xlinker _NSExtensionMain "${compiler_flags[@]}" -I "$BINARY_DIR/Modules" WidgetExtension/ProxPulseWidget.swift "$BINARY_DIR"/ProxPulseCore.build/*.swift.o "$BINARY_DIR"/ProxPulseWidgetUI.build/*.swift.o -o .build/ProxPulseWidget
python3 scripts/verify-widget-entry.py .build/ProxPulseWidget
plutil -lint AppInfo.plist ProxPulse.entitlements WidgetExtension/Info.plist ProxPulse.xcodeproj/project.pbxproj
"$BINARY_DIR/ProxPulse" --render-preview
print 'PASS: build, core checks, demo state checks, WidgetKit executable link, project/plists, dark/light renders'
