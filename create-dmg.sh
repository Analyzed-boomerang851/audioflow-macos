#!/bin/zsh
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <application-path> <volume-icon-path> <output-dmg-path>" >&2
  exit 2
fi

PROJECT_DIR="${0:A:h}"
APP_PATH="$1"
VOLUME_ICON="$2"
OUTPUT_DMG="$3"
VOLUME_NAME="AudioFlow"
BACKGROUND_SVG="$PROJECT_DIR/InstallerAssets/DMGBackground.svg"
WORK_ROOT="$(mktemp -d)"
STAGE_DIR="$WORK_ROOT/stage"
MOUNT_POINT="$WORK_ROOT/mount"
RW_DMG="$WORK_ROOT/AudioFlow-rw.dmg"
BACKGROUND_RENDER_DIR="$WORK_ROOT/background"
DEVICE_NODE=""

cleanup() {
  if [[ -n "$DEVICE_NODE" ]]; then
    hdiutil detach "$DEVICE_NODE" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

mkdir -p "$STAGE_DIR/.background" "$MOUNT_POINT" "$BACKGROUND_RENDER_DIR"
ditto "$APP_PATH" "$STAGE_DIR/AudioFlow.app"
xattr -cr "$STAGE_DIR/AudioFlow.app"
codesign --verify --deep --strict --verbose=2 "$STAGE_DIR/AudioFlow.app"
ln -s /Applications "$STAGE_DIR/Applications"
cp "$VOLUME_ICON" "$STAGE_DIR/.VolumeIcon.icns"

qlmanage -t -s 640 -o "$BACKGROUND_RENDER_DIR" "$BACKGROUND_SVG" >/dev/null 2>&1
sips -c 420 640 "$BACKGROUND_RENDER_DIR/DMGBackground.svg.png" \
  --out "$STAGE_DIR/.background/background.png" >/dev/null

hdiutil create \
  -srcfolder "$STAGE_DIR" \
  -volname "$VOLUME_NAME" \
  -fs HFS+ \
  -format UDRW \
  -ov "$RW_DMG" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$MOUNT_POINT" "$RW_DMG")"
DEVICE_NODE="$(print -r -- "$ATTACH_OUTPUT" | awk '/Apple_HFS/ {print $1; exit}')"
[[ -n "$DEVICE_NODE" ]]

SetFile -a C "$MOUNT_POINT"
open "$MOUNT_POINT"

osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Finder"
    tell disk "AudioFlow"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {180, 140, 820, 560}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 112
        set text size of theViewOptions to 13
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "AudioFlow.app" of container window to {160, 226}
        set position of item "Applications" of container window to {480, 226}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

xattr -cr "$MOUNT_POINT/AudioFlow.app"
codesign --verify --deep --strict --verbose=2 "$MOUNT_POINT/AudioFlow.app"
sync
hdiutil detach "$DEVICE_NODE" >/dev/null
DEVICE_NODE=""

rm -f "$OUTPUT_DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG" >/dev/null
codesign --force --sign - "$OUTPUT_DMG"
codesign --verify --verbose=2 "$OUTPUT_DMG"
echo "$OUTPUT_DMG"
