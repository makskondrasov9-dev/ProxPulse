#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="${PROXPULSE_INSTALL_SOURCE:-$PWD/.build/ProxPulse.app}"
DESTINATION="/Applications/ProxPulse.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
EXTENSION="Contents/PlugIns/ProxPulseWidget.appex"
[[ -f "$SOURCE/$EXTENSION/Contents/MacOS/ProxPulseWidget" ]] || { print -u2 'Build the WidgetKit extension and app first.'; exit 1; }
python3 scripts/verify-widget-entry.py "$SOURCE/$EXTENSION/Contents/MacOS/ProxPulseWidget"
codesign --verify --deep --strict "$SOURCE"
if [[ -e "$DESTINATION" ]]; then
    [[ ! -L "$DESTINATION" ]] || { print -u2 'Destination is a symbolic link; refusing to replace it.'; exit 1; }
    INSTALLED_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")
    [[ "$INSTALLED_ID" == "dev.proxpulse.app" ]] || { print -u2 'A different application occupies the destination.'; exit 1; }
fi
# macOS process names may contain a full path, so pkill -x ProxPulse can miss them.
python3 - "$SOURCE/Contents/MacOS/ProxPulse" "$DESTINATION/Contents/MacOS/ProxPulse" <<'PYSTOP'
import os,signal,subprocess,sys,time
paths=set(sys.argv[1:])
processes=subprocess.check_output(['/bin/ps','-U',str(os.getuid()),'-ww','-o','pid=,comm='],text=True)
pids=[]
for line in processes.splitlines():
    parts=line.strip().split(None,1)
    if len(parts)==2 and parts[1] in paths:
        try: os.kill(int(parts[0]),signal.SIGTERM); pids.append(int(parts[0]))
        except ProcessLookupError: pass
for _ in range(20):
    alive=[]
    for pid in pids:
        try: os.kill(pid,0); alive.append(pid)
        except ProcessLookupError: pass
    if not alive: break
    time.sleep(0.1)
PYSTOP
if [[ -d "$DESTINATION" ]]; then
    BACKUP="$PWD/.build/install-backups/$(date +%Y%m%d-%H%M%S)/ProxPulse.app"
    mkdir -p "$(dirname "$BACKUP")"
    /usr/bin/ditto "$DESTINATION" "$BACKUP"
fi
/usr/bin/ditto "$SOURCE" "$DESTINATION"
codesign --verify --deep --strict --verbose=2 "$DESTINATION"
# Keep the installed location canonical in both registries.
pluginkit -r "$SOURCE/$EXTENSION" 2>/dev/null || true
"$LSREGISTER" -u "$SOURCE" 2>/dev/null || true
"$LSREGISTER" -f -R -trusted "$DESTINATION"
pluginkit -a "$DESTINATION/$EXTENSION"
pluginkit -e use -i dev.proxpulse.app.widget
killall -9 chronod NotificationCenter 2>/dev/null || true
open "$DESTINATION"
print "Installed and launched $DESTINATION"
pluginkit -m -A -D -v -i dev.proxpulse.app.widget
