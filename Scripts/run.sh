#!/bin/sh
set -e
cd "$(dirname "$0")/.."
"$PWD/Scripts/build-app.sh"
open build/NowDock.app
