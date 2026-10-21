#!/bin/bash
# ProxPulse direct-distribution installer. No Homebrew or Python dependency.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
REPO=makskondrasov9-dev/ProxPulse
DEST=/Applications/ProxPulse.app
DMG=""; WAIT_PID=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dmg) DMG="$2"; shift 2 ;;
    --wait-pid) WAIT_PID="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[ "$(uname -s)" = Darwin ] || { echo 'macOS is required.' >&2; exit 1; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ProxPulse-install.XXXXXX")
MOUNT="$TMP/mount"; MOUNTED=0; BACKUP=""; STAGE=""; INSTALLED=0; APP_STOPPED=0
cleanup() {
  result=$?
  if [ "$result" -ne 0 ] && [ "$INSTALLED" -eq 1 ] && [ -n "$BACKUP" ]; then
    echo 'Installation failed; restoring previous version.' >&2
    if [ -d "$BACKUP" ]; then
      if [ -d "$DEST" ]; then privileged /bin/rm -rf "$DEST" || true; fi
      privileged /bin/mv "$BACKUP" "$DEST" || true
    fi
    open "$DEST" || true
  fi
  if [ "$result" -ne 0 ] && { [ "$APP_STOPPED" -eq 1 ] || [ -n "$WAIT_PID" ]; } && [ -d "$DEST" ]; then open "$DEST" || true; fi
  if [ -n "$STAGE" ] && [ -d "$STAGE" ]; then privileged /bin/rm -rf "$STAGE" || true; fi
  if [ "$result" -eq 0 ] && [ -n "$BACKUP" ] && [ -d "$BACKUP" ]; then privileged /bin/rm -rf "$BACKUP" || true; fi
  if [ "$MOUNTED" -eq 1 ]; then hdiutil detach "$MOUNT" -quiet || true; fi
  rm -rf "$TMP"
  exit "$result"
}
trap cleanup EXIT
privileged() {
  if [ -w /Applications ] && { [ ! -e "$DEST" ] || [ -w "$DEST" ]; }; then "$@"; else
    local command
    printf -v command '%q ' "$@"
    /usr/bin/osascript -e 'on run argv' -e 'do shell script (item 1 of argv) with administrator privileges' -e 'end run' "$command"
  fi
}
if [ -z "$DMG" ]; then
  echo 'Checking the latest ProxPulse release…'
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 "https://api.github.com/repos/$REPO/releases/latest" -o "$TMP/release.json"
  TAG=$(plutil -extract tag_name raw -o - "$TMP/release.json")
  [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release tag' >&2; exit 1; }
  NAME="ProxPulse-$TAG.dmg"; FOUND=0
  for ((i=0;i<100;i++)); do
    asset=$(plutil -extract "assets.$i.name" raw -o - "$TMP/release.json" 2>/dev/null) || break
    if [ "$asset" = "$NAME" ]; then
      URL=$(plutil -extract "assets.$i.browser_download_url" raw -o - "$TMP/release.json")
      [ "$URL" = "https://github.com/$REPO/releases/download/$TAG/$NAME" ] || exit 1
      FOUND=1; break
    fi
  done
  [ "$FOUND" -eq 1 ] || { echo 'No supported DMG in latest release' >&2; exit 1; }
  DMG="$TMP/$NAME"
  curl -fLsS --proto '=https' --proto-redir '=https' --tlsv1.2 "$URL" -o "$DMG"
  curl -fLsS --proto '=https' --proto-redir '=https' --tlsv1.2 "$URL.sha256" -o "$DMG.sha256"
  EXPECTED=$(awk 'NR == 1 { print $1 }' "$DMG.sha256")
  CHECK_NAME=$(awk 'NR == 1 { print $2 }' "$DMG.sha256")
  [[ "$EXPECTED" =~ ^[0-9a-fA-F]{64}$ ]] && [ "$CHECK_NAME" = "$NAME" ]
  ACTUAL=$(shasum -a 256 "$DMG" | awk '{print $1}')
  [ "$EXPECTED" = "$ACTUAL" ] || { echo 'SHA-256 mismatch' >&2; exit 1; }
else
  # In-app updates verify the official checksum before invoking this path.
  [ -f "$DMG" ] || { echo 'Missing DMG' >&2; exit 1; }
fi
hdiutil verify "$DMG" >/dev/null
mkdir "$MOUNT"
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT" -quiet
MOUNTED=1
SOURCE="$MOUNT/ProxPulse.app"
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$SOURCE/Contents/Info.plist")" = dev.proxpulse.app ]
EXTENSION="$SOURCE/Contents/PlugIns/ProxPulseWidget.appex"
[ -d "$EXTENSION" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$EXTENSION/Contents/Info.plist")" = dev.proxpulse.app.widget ]
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$EXTENSION/Contents/Info.plist")" = "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$SOURCE/Contents/Info.plist")" ]
codesign --verify --deep --strict "$SOURCE"
if [ -L "$DEST" ]; then echo 'Refusing a symbolic-link destination' >&2; exit 1; fi
if [ -e "$DEST" ]; then
  [ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST/Contents/Info.plist")" = dev.proxpulse.app ]
fi
if [ -n "$WAIT_PID" ]; then
  [[ "$WAIT_PID" =~ ^[0-9]+$ ]] || exit 1
  for ((i=0;i<150;i++)); do kill -0 "$WAIT_PID" 2>/dev/null || break; sleep 0.2; done
  if kill -0 "$WAIT_PID" 2>/dev/null; then echo 'ProxPulse is still running; update cancelled.' >&2; exit 1; fi
else
  while read -r pid; do
    [ -n "$pid" ] || continue
    kill -TERM "$pid" 2>/dev/null || true
    for ((i=0;i<100;i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    if kill -0 "$pid" 2>/dev/null; then echo 'Please quit ProxPulse before updating.' >&2; exit 1; fi
  done < <(pgrep -f '^/Applications/ProxPulse[.]app/Contents/MacOS/ProxPulse([[:space:]]|$)' || true)
fi
APP_STOPPED=1
STAGE="/Applications/.ProxPulse-new-$(basename "$TMP").app"
BACKUP="/Applications/.ProxPulse-old-$(basename "$TMP").app"
[ ! -e "$STAGE" ] && [ ! -e "$BACKUP" ]
privileged /usr/bin/ditto "$SOURCE" "$STAGE"
codesign --verify --deep --strict "$STAGE"
INSTALLED=1
if [ -e "$DEST" ]; then privileged /bin/mv "$DEST" "$BACKUP"; fi
privileged /bin/mv "$STAGE" "$DEST"
# Explicitly requested for the ad-hoc distribution; affects this app only.
privileged /usr/bin/xattr -cr "$DEST"
codesign --verify --deep --strict "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/ProxPulseWidget.appex"
pluginkit -e use -i dev.proxpulse.app.widget
killall chronod NotificationCenter 2>/dev/null || true
open "$DEST"
INSTALLED=0
echo 'ProxPulse installed and launched.'
