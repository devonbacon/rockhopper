#!/usr/bin/env bash
# Exports a Windows build and zips it up to share: build/rockhopper-<build>.zip,
# where <build> is the hash the server checks, so you can tell at a glance
# whether a zip matches what the server runs.
#
#   tools/export_windows.sh [path to Godot]
set -euo pipefail
GODOT=${1:-${GODOT:-C:/Users/dcole/src/godot/4.7.2/Godot_v4.7.2-stable_win64.exe}}
cd "$(dirname "$0")/.."
rm -rf build/windows
mkdir -p build/windows
"$GODOT" --headless --path . --export-release windows build/windows/Rockhopper.exe
BUILD=$("$GODOT" --headless --path . res://tools/print_build.tscn 2>/dev/null | grep -o 'build [0-9a-f]*' | cut -d' ' -f2)
rm -f "build/rockhopper-$BUILD.zip"
(cd build/windows && powershell -NoProfile -Command "Compress-Archive -Path * -DestinationPath ../rockhopper-$BUILD.zip")
echo "build/rockhopper-$BUILD.zip"
