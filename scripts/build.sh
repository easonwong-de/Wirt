#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${1:-Debug}"

xcodebuild -project Wirt.xcodeproj -scheme Wirt -configuration "$CONFIG" -destination 'platform=macOS' build

if [ "$CONFIG" = "Debug" ]; then
	pkill -f "Wirt.app/Contents/MacOS/Wirt" 2>/dev/null || true
	APP_PATH=$(find "${HOME}/Library/Developer/Xcode/DerivedData" -maxdepth 5 -name "Wirt.app" -path "*/Build/Products/Debug/Wirt.app" 2>/dev/null | head -n 1)
	if [ -n "$APP_PATH" ]; then
		open "$APP_PATH"
	fi
fi
