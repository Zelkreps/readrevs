#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")

cd "$PROJECT_DIR"
"$SCRIPT_DIR/build-app-icon.sh"
swift build
BIN_DIR=$(swift build --show-bin-path)

APP_DIR="$PROJECT_DIR/.build/app/ReadRevs.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/ReadRevs" "$MACOS_DIR/ReadRevs"
cp "$PROJECT_DIR/Config/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$PROJECT_DIR/Resources/Assets.car" "$RESOURCES_DIR/Assets.car"
plutil -lint "$CONTENTS_DIR/Info.plist"
codesign --force --deep --sign - "$APP_DIR"

printf '%s\n' "$APP_DIR"
