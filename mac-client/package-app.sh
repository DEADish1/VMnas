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

cd "$CLIENT_DIR"
set +e
swift build -c release >"$BUILD_LOG" 2>&1
BUILD_STATUS=$?
set -e

if [ -d "$APP_DIR" ]; then
  mv "$APP_DIR" "$DIST_DIR/VMnas Admin-stale-$(date +%Y%m%d%H%M%S).app"
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
if [ "$BUILD_STATUS" -eq 0 ] && [ -x "$CLIENT_DIR/.build/release/VMnasAdmin" ]; then
  BINARY="$CLIENT_DIR/.build/release/VMnasAdmin"
else
  echo "Fresh Swift build failed; see $BUILD_LOG" >&2
  echo "Looking for the newest previously built VMnasAdmin binary." >&2
  BINARY="$(
    find "$CLIENT_DIR" "/Applications/VMnas Admin.app/Contents/MacOS" \
      -path '*/VMnasAdmin' \
      -type f \
      -perm +111 \
      -print 2>/dev/null \
      | while IFS= read -r path; do
          printf '%s\t%s\n' "$(stat -f '%m' "$path")" "$path"
        done \
      | sort -nr \
      | awk -F '\t' 'NR == 1 { print $2 }'
  )"
  if [ -z "$BINARY" ]; then
    echo "No usable VMnasAdmin binary found. Install the full Xcode toolchain or restore a previous build." >&2
    exit "$BUILD_STATUS"
  fi
fi

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

echo "$APP_DIR"
