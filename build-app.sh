#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
DIST_DIR="$PROJECT_DIR/dist"
DIST_APP="$DIST_DIR/AudioFlow.app"
INSTALL_APP="/Applications/AudioFlow.app"
ICON_SOURCE="$PROJECT_DIR/Sources/Shenglan/Resources/ShenglanIcon.png"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
CREATE_DMG="${CREATE_DMG:-1}"
INSTALL_AFTER_BUILD="${INSTALL_AFTER_BUILD:-0}"
OPEN_AFTER_INSTALL="${OPEN_AFTER_INSTALL:-0}"
STAGE_ROOT="$(mktemp -d)"
ICON_ROOT="$(mktemp -d)"
VERIFY_ROOT="$(mktemp -d)"
STAGE_APP="$STAGE_ROOT/AudioFlow.app"
ICON_WORK="$ICON_ROOT/Shenglan.iconset"

cleanup() {
  rm -rf "$STAGE_ROOT" "$ICON_ROOT" "$VERIFY_ROOT"
}
trap cleanup EXIT

cd "$PROJECT_DIR"
swift build -c release
RELEASE_DIR="$(swift build -c release --show-bin-path)"

mkdir -p "$DIST_DIR" "$ICON_WORK"
sips -z 16 16 "$ICON_SOURCE" --out "$ICON_WORK/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICON_WORK/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICON_WORK/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICON_WORK/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICON_WORK/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICON_WORK/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICON_WORK/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICON_WORK/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICON_WORK/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICON_WORK/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICON_WORK" -o "$DIST_DIR/AudioFlow.icns"

mkdir -p "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources"
cp "$RELEASE_DIR/Shenglan" "$STAGE_APP/Contents/MacOS/AudioFlow"
cp "$PROJECT_DIR/Info.plist" "$STAGE_APP/Contents/Info.plist"
cp "$DIST_DIR/AudioFlow.icns" "$STAGE_APP/Contents/Resources/AudioFlow.icns"
cp "$ICON_SOURCE" "$STAGE_APP/Contents/Resources/ShenglanIcon.png"
cp -R "$PROJECT_DIR/PackagingLocalizations/." "$STAGE_APP/Contents/Resources/"
cp -R "$RELEASE_DIR/ShenglanNative_Shenglan.bundle" "$STAGE_APP/Contents/Resources/"
chmod +x "$STAGE_APP/Contents/MacOS/AudioFlow"
xattr -cr "$STAGE_APP"

# Public builds are ad-hoc signed by default and never mutate the user's
# keychain. Release maintainers can supply a Developer ID explicitly:
# CODE_SIGN_IDENTITY="Developer ID Application: Example" ./build-app.sh
codesign \
  --force \
  --deep \
  --sign "$SIGN_IDENTITY" \
  --identifier com.starry.shenglan \
  --entitlements "$PROJECT_DIR/Entitlements.plist" \
  "$STAGE_APP"
codesign --verify --deep --strict --verbose=2 "$STAGE_APP"

rm -rf "$DIST_APP"
ditto "$STAGE_APP" "$DIST_APP"
xattr -cr "$DIST_APP"
codesign --verify --deep --strict --verbose=2 "$DIST_APP"

rm -f "$DIST_DIR/AudioFlow-macOS.zip" "$DIST_DIR/AudioFlow.dmg"
ditto -c -k --keepParent --norsrc "$DIST_APP" "$DIST_DIR/AudioFlow-macOS.zip"
ditto -x -k "$DIST_DIR/AudioFlow-macOS.zip" "$VERIFY_ROOT"
codesign --verify --deep --strict --verbose=2 "$VERIFY_ROOT/AudioFlow.app"

if [[ "$CREATE_DMG" == "1" ]]; then
  "$PROJECT_DIR/create-dmg.sh" "$STAGE_APP" "$DIST_DIR/AudioFlow.icns" "$DIST_DIR/AudioFlow.dmg"
fi

# Finder can attach metadata while styling the DMG. Remove it so the standalone
# application remains independently verifiable.
xattr -cr "$DIST_APP"
codesign --verify --deep --strict --verbose=2 "$DIST_APP"

if [[ "$INSTALL_AFTER_BUILD" == "1" ]]; then
  rm -rf "$INSTALL_APP"
  ditto "$STAGE_APP" "$INSTALL_APP"
  codesign --verify --deep --strict --verbose=2 "$INSTALL_APP"
  if [[ "$OPEN_AFTER_INSTALL" == "1" ]]; then
    open "$INSTALL_APP"
  fi
fi

echo "Application: $DIST_APP"
echo "ZIP archive: $DIST_DIR/AudioFlow-macOS.zip"
if [[ "$CREATE_DMG" == "1" ]]; then
  echo "DMG installer: $DIST_DIR/AudioFlow.dmg"
fi
