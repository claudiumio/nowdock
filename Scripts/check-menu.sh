#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build >/dev/null
BIN="$(swift build --show-bin-path)"
CHECK_DIR="$(mktemp -d "${TMPDIR:?}/nowdock-menu.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -swift-version 5 -parse-as-library -I "$BIN/Modules" \
    "$BIN"/NowDockCore.build/*.swift.o \
    Sources/NowDock/UI/CompanionView.swift \
    Sources/NowDock/Window/CompanionPanel.swift \
    Sources/NowDock/App/LaunchAtLogin.swift \
    Scripts/MenuCheck/main.swift \
    -o "$CHECK_DIR/check-menu"
OUTPUT="$("$CHECK_DIR/check-menu")"
printf '%s\n' "$OUTPUT"
case "$OUTPUT" in
    *"PASS complete native menu dispatch check"*) ;;
    *) printf '%s\n' "Native menu check exited before completing assertions" >&2; exit 1 ;;
esac
