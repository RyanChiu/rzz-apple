#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="RZZ"
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  VERSION="$(grep -m1 "MARKETING_VERSION = " RZZ.xcodeproj/project.pbxproj | sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/' | tr -d ' ')"
  VERSION="${VERSION:-0.1.0}"
fi

BUILD_ROOT="$ROOT_DIR/build/release"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
STAGING_DIR="$BUILD_ROOT/staging"
DIST_DIR="$ROOT_DIR/dist"

rm -rf "$BUILD_ROOT" "$DIST_DIR"
mkdir -p "$BUILD_ROOT" "$STAGING_DIR" "$DIST_DIR"

echo "Building $APP_NAME $VERSION ..."
xcodebuild \
  -project RZZ.xcodeproj \
  -scheme RZZ \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$(find "$DERIVED_DATA/Build/Products/Release" -maxdepth 1 -name "$APP_NAME.app" -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "Error: could not find built app."
  exit 1
fi

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
cat > "$STAGING_DIR/Install RZZ.txt" <<'EOF'
Install RZZ

1. Drag RZZ.app onto the Applications shortcut in this window.
2. Open RZZ from Applications or Launchpad.
3. After installation, you can eject this DMG.

Do not run RZZ directly from the DMG if you want it to appear in Applications/Launchpad.

安装 RZZ

1. 将 RZZ.app 拖到本窗口中的 Applications 替身上。
2. 从“应用程序”或 Launchpad 启动 RZZ。
3. 安装完成后，可以推出这个 DMG。

如果希望 RZZ 出现在“应用程序”或 Launchpad 中，不要直接从 DMG 里运行。
EOF

DMG_NAME="${APP_NAME}-${VERSION}-macOS.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "Creating DMG: $DMG_PATH"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Done."
ls -lh "$DMG_PATH"
shasum -a 256 "$DMG_PATH"
