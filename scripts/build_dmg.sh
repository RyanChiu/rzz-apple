#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="RZZ"
VERSION="${1:-}"
MIN_MACOS_VERSION="${RZZ_MIN_MACOS_VERSION:-14.0}"
RELEASE_ARCHS="${RZZ_ARCHS:-arm64 x86_64}"

if [[ -z "$VERSION" ]]; then
  VERSION="$(grep -m1 "MARKETING_VERSION = " RZZ.xcodeproj/project.pbxproj | sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/' | tr -d ' ')"
  VERSION="${VERSION:-0.1.0}"
fi

BUILD_ROOT="$ROOT_DIR/build/release"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
STAGING_DIR="$BUILD_ROOT/staging"
DIST_DIR="$ROOT_DIR/dist"
MOUNT_DIR="$BUILD_ROOT/mount"

rm -rf "$BUILD_ROOT" "$DIST_DIR"
mkdir -p "$BUILD_ROOT" "$STAGING_DIR" "$DIST_DIR" "$MOUNT_DIR"

echo "Building $APP_NAME $VERSION for macOS $MIN_MACOS_VERSION+ ($RELEASE_ARCHS) ..."
xcodebuild \
  -project RZZ.xcodeproj \
  -scheme RZZ \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS_VERSION" \
  ARCHS="$RELEASE_ARCHS" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$(find "$DERIVED_DATA/Build/Products/Release" -maxdepth 1 -name "$APP_NAME.app" -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "Error: could not find built app."
  exit 1
fi

APP_EXECUTABLE="$APP_PATH/Contents/MacOS/$APP_NAME"
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Error: could not find app executable at $APP_EXECUTABLE."
  exit 1
fi

read -r -a REQUESTED_ARCHS <<< "$RELEASE_ARCHS"
if ! lipo -verify_arch "${REQUESTED_ARCHS[@]}" "$APP_EXECUTABLE"; then
  echo "Error: built executable does not contain expected architectures: $RELEASE_ARCHS"
  lipo -info "$APP_EXECUTABLE" || true
  exit 1
fi
lipo -info "$APP_EXECUTABLE"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

DMG_NAME="${APP_NAME}-${VERSION}-macOS.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
TEMP_DMG_PATH="$BUILD_ROOT/$APP_NAME-rw.dmg"
VOLUME_NAME="$APP_NAME $VERSION"

echo "Creating DMG: $DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$TEMP_DMG_PATH"

echo "Applying DMG Finder layout ..."
hdiutil attach "$TEMP_DMG_PATH" \
  -mountpoint "$MOUNT_DIR" \
  -nobrowse \
  -noverify \
  -noautoopen

if osascript <<EOF
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 720, 430}
    set arrangement of icon view options of container window to not arranged
    set icon size of icon view options of container window to 96
    set position of item "$APP_NAME.app" of container window to {150, 150}
    set position of item "Applications" of container window to {410, 150}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
then
  echo "Finder layout applied."
else
  echo "Error: could not apply Finder layout."
  hdiutil detach -force "$MOUNT_DIR" || true
  exit 1
fi

sync
if ! hdiutil detach "$MOUNT_DIR"; then
  hdiutil detach -force "$MOUNT_DIR"
fi

hdiutil convert "$TEMP_DMG_PATH" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH"

echo "Done."
ls -lh "$DMG_PATH"
shasum -a 256 "$DMG_PATH"
