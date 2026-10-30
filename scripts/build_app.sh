#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/ModuleCache"
cd "$ROOT"
swift build -c "$CONFIGURATION" --arch arm64
BIN_DIR="$(swift build -c "$CONFIGURATION" --arch arm64 --show-bin-path)"
mkdir -p "$ROOT/tmp"
WORK="$(mktemp -d "$ROOT/tmp/launcheer-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
APP="$ROOT/dist/Launcheer.app"
STAGE="$WORK/Launcheer.app"
RESOURCES="$STAGE/Contents/Resources"
DOCK_RESOURCES="/System/Library/CoreServices/Dock.app/Contents/Resources"
mkdir -p "$STAGE/Contents/MacOS" "$RESOURCES" "$ROOT/dist"
cp "$BIN_DIR/Launcheer" "$STAGE/Contents/MacOS/Launcheer"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
cp Resources/Launcheer.icns "$RESOURCES/"
cp LICENSE "$RESOURCES/"
cp "$DOCK_RESOURCES"/ectl_search*.png "$RESOURCES/"
for localization in "$DOCK_RESOURCES"/*.lproj; do
  if [[ -f "$localization/Localizable.strings" ]]; then
    destination="$RESOURCES/$(basename "$localization")"
    mkdir -p "$destination"
    cp "$localization/Localizable.strings" "$destination/"
  fi
done
codesign --force --sign - "$STAGE"
codesign --verify --deep --strict --verbose=2 "$STAGE"
rm -rf "$APP"
mv "$STAGE" "$APP"
printf '%s\n' "$APP"
