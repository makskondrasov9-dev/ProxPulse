#!/bin/zsh
# Source from the repository root. Workarounds are isolated inside .build.
mkdir -p .build/compat
compiler_flags=()
package_flags=()
CLT="$(xcode-select -p)"
MANIFEST="$CLT/usr/lib/swift/pm/ManifestAPI"
if [[ -f "$MANIFEST/PackageDescription.swiftmodule/x86_64-apple-macos.private.swiftinterface" ]] && \
   ! rg -q 'SwiftLanguageMode' "$MANIFEST/PackageDescription.swiftmodule/x86_64-apple-macos.private.swiftinterface" && \
   rg -q 'SwiftLanguageMode' "$MANIFEST/PackageDescription.swiftmodule/x86_64-apple-macos.swiftinterface"; then
    mkdir -p .build/compat/libs
    cp -R "$MANIFEST" .build/compat/libs/
    cp .build/compat/libs/ManifestAPI/PackageDescription.swiftmodule/x86_64-apple-macos.swiftinterface .build/compat/libs/ManifestAPI/PackageDescription.swiftmodule/x86_64-apple-macos.private.swiftinterface
    export SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/compat/libs"
fi
if [[ -f "$CLT/usr/include/swift/module.modulemap" && -f "$CLT/usr/include/swift/bridging.modulemap" ]] && \
   rg -q 'module SwiftBridging' "$CLT/usr/include/swift/module.modulemap" && \
   rg -q 'module SwiftBridging' "$CLT/usr/include/swift/bridging.modulemap"; then
    touch .build/compat/empty.modulemap
    python3 - "$CLT" "$PWD" <<'PY'
import json,sys
root,work=sys.argv[1:]
json.dump({'version':0,'roots':[{'type':'file','name':root+'/usr/include/swift/bridging.modulemap','external-contents':work+'/.build/compat/empty.modulemap'}]},open('.build/compat/overlay.json','w'))
PY
    compiler_flags=(-vfsoverlay "$PWD/.build/compat/overlay.json")
    package_flags=(-Xswiftc -vfsoverlay -Xswiftc "$PWD/.build/compat/overlay.json")
fi
