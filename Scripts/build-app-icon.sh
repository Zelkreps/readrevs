#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
ICON_PNG="$PROJECT_DIR/Assets/AppIcon.png"
ICON_SET="$PROJECT_DIR/Assets/AppIconAssets.xcassets/AppIcon.appiconset"
ICON_OUTPUT="$PROJECT_DIR/.build/icon-assets"

swift "$SCRIPT_DIR/render-app-icon.swift" "$PROJECT_DIR/Assets/AppIcon.svg" "$ICON_PNG"

sips -z 16 16 "$ICON_PNG" --out "$ICON_SET/icon_16x16.png"
sips -z 32 32 "$ICON_PNG" --out "$ICON_SET/icon_16x16@2x.png"
sips -z 32 32 "$ICON_PNG" --out "$ICON_SET/icon_32x32.png"
sips -z 64 64 "$ICON_PNG" --out "$ICON_SET/icon_32x32@2x.png"
sips -z 128 128 "$ICON_PNG" --out "$ICON_SET/icon_128x128.png"
sips -z 256 256 "$ICON_PNG" --out "$ICON_SET/icon_128x128@2x.png"
sips -z 256 256 "$ICON_PNG" --out "$ICON_SET/icon_256x256.png"
sips -z 512 512 "$ICON_PNG" --out "$ICON_SET/icon_256x256@2x.png"
sips -z 512 512 "$ICON_PNG" --out "$ICON_SET/icon_512x512.png"
cp "$ICON_PNG" "$ICON_SET/icon_512x512@2x.png"

mkdir -p "$ICON_OUTPUT"
xcrun actool "$PROJECT_DIR/Assets/AppIconAssets.xcassets" \
    --compile "$ICON_OUTPUT" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ICON_OUTPUT/partial.plist"

cp "$ICON_OUTPUT/AppIcon.icns" "$PROJECT_DIR/Resources/AppIcon.icns"
cp "$ICON_OUTPUT/Assets.car" "$PROJECT_DIR/Resources/Assets.car"
