#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build >/dev/null
BIN="$(swift build --show-bin-path)"
CHECK_DIR="$(mktemp -d "${TMPDIR:?}/nowdock-layout.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -swift-version 5 -I "$BIN/Modules" \
    "$BIN"/NowDockCore.build/*.swift.o \
    Sources/NowDock/UI/CompanionView.swift \
    Sources/NowDock/Window/CompanionPanel.swift \
    Sources/NowDock/App/LaunchAtLogin.swift \
    Scripts/LayoutCheck/main.swift \
    -o "$CHECK_DIR/check-layout"
OUTPUT="${1:-${TMPDIR%/}/nowdock-layouts.png}"
if [ "$#" -gt 0 ]; then shift; fi
"$CHECK_DIR/check-layout" "$OUTPUT" "$@"
