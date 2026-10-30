#!/usr/bin/env bash
set -euo pipefail
if [[ "${LAUNCHEER_UI_TESTS:-}" != "1" ]]; then
  printf '%s\n' 'This probe opens a window. Set LAUNCHEER_UI_TESTS=1 only when UI verification is explicitly wanted.' >&2
  exit 1
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p tmp/native-swipe-validation
MODE="swipe"
if [[ "${1:-}" == "--interactions" ]]; then MODE="interactions"; shift; fi
LOG="$ROOT/tmp/native-swipe-validation/$MODE.log"
MARKER='PASS: swipe probe, 720 display callbacks'
if [[ "$MODE" == "interactions" ]]; then MARKER='PASS: real native root reorder'; fi
if [[ ! -f dist/Launcheer.app/Contents/Resources/NativeDockBuild.h ]]; then
  printf '%s\n' 'Build the native app first: ./scripts/build_app.sh' >&2
  exit 1
fi
WORK="$(mktemp -d "$ROOT/tmp/native-swipe-probe.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
/usr/bin/python3 - "$WORK" "$MODE" <<'PY'
from pathlib import Path
import sys
work = Path(sys.argv[1])
source = Path('Sources/NativeLaunchpad/Host.m').read_text()
assert source.count('@selector(verifyFirstPage)') == 1
if sys.argv[2] == 'interactions':
    source = source.replace('@selector(verifyFirstPage)', '@selector(verifyNativeInteractions)')
    source += '\n' + Path('Tests/Fixtures/NativeSnapshot.m').read_text()
    source += '\n' + Path('Tests/Fixtures/NativeInteractionProbe.m').read_text()
else:
    source = source.replace('@selector(verifyFirstPage)', '@selector(verifySwipePerformance)')
    assert source.count('    [super layout];') == 1
    source = source.replace('    [super layout];', '    probeLayouts++;\n    [super layout];')
    assert source.count('        NSImage *image = self.icons[url];') == 1
    source = source.replace('        NSImage *image = self.icons[url];', '        probeIcons++;\n        NSImage *image = self.icons[url];')
    fixture = Path('Tests/Fixtures/NativeSwipeProbe.m').read_text()
    counters, fixture = fixture.split('@interface NSObject', 1)
    source = counters + source + '\n@interface NSObject' + fixture
(work / 'Host.m').write_text(source)
header = Path('Sources/NativeLaunchpad/include/Host.h').resolve()
(work / 'module.modulemap').write_text('module NativeLaunchpad { header "' + str(header) + '" export * }\n')
PY
OBJECTS=()
for source in "$WORK/Host.m" Sources/NativeLaunchpad/*.m; do
  if [[ "$source" == Sources/NativeLaunchpad/Host.m ]]; then continue; fi
  object="$WORK/$(basename "${source%.m}").o"
  xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter \
    -arch arm64 -mmacosx-version-min=26.2 -I Sources/NativeLaunchpad -I Sources/NativeLaunchpad/include \
    -c "$source" -o "$object"
  OBJECTS+=("$object")
done
APP="$WORK/NativeLaunchpadSwipeProbe.app"
mkdir -p "$APP/Contents/MacOS"
cp -R dist/Launcheer.app/Contents/Resources "$APP/Contents/"
cp dist/Launcheer.app/Contents/Info.plist "$APP/Contents/"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier launcheer.kodify.vip.native-swipe-probe' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName NativeLaunchpadSwipeProbe' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable NativeLaunchpadSwipeProbe' "$APP/Contents/Info.plist"
xcrun swiftc -O -parse-as-library -swift-version 6 -target arm64-apple-macosx26.2 \
  -module-cache-path "$ROOT/.build/ModuleCache" -I "$WORK" \
  Sources/Launcheer/*.swift "${OBJECTS[@]}" \
  -framework AppKit -framework QuartzCore -framework ImageIO -framework Carbon -framework ScreenCaptureKit \
  -o "$APP/Contents/MacOS/NativeLaunchpadSwipeProbe"
codesign --force --sign - "$APP"
if [[ "${1:-}" == "--record" ]]; then
  shift
  LOG="$ROOT/tmp/native-swipe-validation/trace-stdout.log"
  : > "$LOG"
  xcrun xctrace record --template 'Animation Hitches' --time-limit 45s \
    --output "$ROOT/tmp/native-swipe-validation/" \
    --target-stdout "$LOG" \
    --launch -- "$APP" --verify-all "$@"
else
  "$APP/Contents/MacOS/NativeLaunchpadSwipeProbe" --verify-all "$@" 2>&1 | tee "$LOG"
fi
if [[ "$(<"$LOG")" != *"$MARKER"* ]]; then
  printf '%s\n' 'The probe exited without completing its verification.' >&2
  exit 1
fi
