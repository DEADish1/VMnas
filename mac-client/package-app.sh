#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT_DIR="$ROOT/mac-client"
APP_NAME="VMnas Admin.app"
DIST_DIR="$ROOT/dist/mac-client"
APP_DIR="$DIST_DIR/$APP_NAME"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
MACOS_DIR="$APP_DIR/Contents/MacOS"
BUILD_LOG="$DIST_DIR/build.log"

mkdir -p "$DIST_DIR"

if ! xcodebuild -version >/dev/null 2>&1; then
  for developer_dir in \
    "$HOME/Downloads/Xcode-beta.app/Contents/Developer" \
    "/Applications/Xcode-beta.app/Contents/Developer" \
    "/Applications/Xcode.app/Contents/Developer"
  do
    if [ -x "$developer_dir/usr/bin/xcodebuild" ]; then
      export DEVELOPER_DIR="$developer_dir"
      break
    fi
  done
fi

cd "$CLIENT_DIR"
set +e
swift build -c release >"$BUILD_LOG" 2>&1
BUILD_STATUS=$?
set -e

if [ "$BUILD_STATUS" -ne 0 ] || [ ! -x "$CLIENT_DIR/.build/release/VMnasAdmin" ]; then
  echo "Fresh Swift build failed; see $BUILD_LOG" >&2
  echo "Install the full Xcode toolchain, then rerun this script." >&2
  exit "${BUILD_STATUS:-1}"
fi

BINARY="$CLIENT_DIR/.build/release/VMnasAdmin"
if [ -d "$APP_DIR" ]; then
  rm -rf "$APP_DIR"
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
echo "Packaging binary: $BINARY"
ditto --norsrc "$BINARY" "$MACOS_DIR/VMnasAdmin"
ditto --norsrc "$CLIENT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$MACOS_DIR/VMnasAdmin"

if [ -f "$ROOT/dist/vmnas-server-trixie-amd64.iso" ]; then
  ditto --norsrc "$ROOT/dist/vmnas-server-trixie-amd64.iso" "$RESOURCES_DIR/vmnas-server-trixie-amd64.iso"
fi

if [ -f "$ROOT/dist/vmnas-server-trixie-amd64.iso.sha256" ]; then
  ditto --norsrc "$ROOT/dist/vmnas-server-trixie-amd64.iso.sha256" "$RESOURCES_DIR/vmnas-server-trixie-amd64.iso.sha256"
fi

xattr -cr "$APP_DIR" 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.fileprovider.fpfs#P {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.macl {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true
codesign --force --deep --no-strict --sign - "$APP_DIR"
xattr -cr "$APP_DIR" 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.fileprovider.fpfs#P {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.macl {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true

echo "$APP_DIR"
