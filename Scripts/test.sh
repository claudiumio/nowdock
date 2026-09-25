#!/bin/sh
# Command Line Tools ship Swift Testing outside the default search paths.
set -e
cd "$(dirname "$0")/.."
D="$(xcode-select -p)/Library/Developer"
exec swift test \
  -Xswiftc -F -Xswiftc "$D/Frameworks" \
  -Xlinker -F -Xlinker "$D/Frameworks" \
  -Xlinker -rpath -Xlinker "$D/Frameworks" \
  -Xlinker -rpath -Xlinker "$D/usr/lib" "$@"
