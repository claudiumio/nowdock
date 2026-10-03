#!/bin/sh
set -e
cd "$(dirname "$0")/.."

swift build -c release --triple arm64-apple-macosx
swift build -c release --triple x86_64-apple-macosx

APP="build/NowDock.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

ARM_BIN="$(swift build -c release --triple arm64-apple-macosx --show-bin-path)/NowDock"
INTEL_BIN="$(swift build -c release --triple x86_64-apple-macosx --show-bin-path)/NowDock"
lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$MACOS/NowDock"
chmod +x "$MACOS/NowDock"
cp Resources/Info.plist "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

if [ -d Resources ]; then
  for f in Resources/*; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
      Info.plist|*.entitlements) ;;
      *) cp "$f" "$RES/" ;;
    esac
  done
fi

codesign --force --options runtime \
  --entitlements Resources/NowDock.entitlements \
  --sign "${NOWDOCK_SIGN_IDENTITY:--}" \
  "$APP"

codesign -dv "$APP"
