#!/bin/sh
set -e
cd "$(dirname "$0")/.."

swift build -c release

APP="build/NowDock.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

BIN="$(swift build -c release --show-bin-path)/NowDock"
cp "$BIN" "$MACOS/NowDock"
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
