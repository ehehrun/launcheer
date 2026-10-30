#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 2 ]]; then
  printf 'Usage: %s [Launcheer.app] [output directory]\n' "$0" >&2
  exit 64
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/Launcheer.app}"
OUTPUT_DIR="${2:-$ROOT/dist}"

identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
if [[ "$identifier" != launcheer.kodify.vip ]]; then
  printf '%s\n' 'The source app is not Launcheer.' >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")

mkdir -p "$ROOT/tmp" "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
WORK="$(mktemp -d "$ROOT/tmp/launcheer-package.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root/Applications" "$WORK/packages" "$WORK/dmg"
ditto "$APP" "$WORK/root/Applications/Launcheer.app"
/usr/bin/xattr -dr com.apple.quarantine "$WORK/root/Applications/Launcheer.app"

pkgbuild --root "$WORK/root" \
  --component-plist "$ROOT/Resources/InstallerComponents.plist" \
  --identifier launcheer.kodify.vip.installer \
  --version "$BUILD" \
  --install-location / \
  "$WORK/packages/Launcheer.component.pkg"
productbuild --distribution "$ROOT/Resources/InstallerDistribution.xml" \
  --package-path "$WORK/packages" \
  "$WORK/dmg/Install Launcheer.pkg"

package="Launcheer-$VERSION-$BUILD-arm64"
hdiutil create -volname Launcheer -srcfolder "$WORK/dmg" -format UDZO "$WORK/$package.dmg"
hdiutil verify "$WORK/$package.dmg"
mv "$WORK/$package.dmg" "$OUTPUT_DIR/$package.dmg"
cd "$OUTPUT_DIR"
shasum -a 256 "$package.dmg" > "$package.dmg.sha256"
shasum -a 256 -c "$package.dmg.sha256"
printf '%s\n' "$OUTPUT_DIR/$package.dmg"
