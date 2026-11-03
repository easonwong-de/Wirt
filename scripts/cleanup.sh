#!/usr/bin/env bash
set -eo pipefail

echo "==> Terminating running Wirt processes..."
pkill -f "Contents/MacOS/Wirt" 2>/dev/null || true
pkill -f "WirtExtension" 2>/dev/null || true

echo "==> Unloading launch agents..."
UID_VAL=$(id -u)
launchctl bootout "gui/${UID_VAL}/de.easonwong.Wirt.agent" 2>/dev/null || true
launchctl bootout "gui/${UID_VAL}/de.easonwong.Wirt.debug.agent" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/de.easonwong.Wirt.agent.plist"
rm -f "$HOME/Library/LaunchAgents/de.easonwong.Wirt.debug.agent.plist"

echo "==> Unregistering Safari extensions..."
PLUGINS=$(pluginkit -m -A -v 2>/dev/null | grep -E "de\.easonwong\.Wirt(\.debug)?\.Extension" | grep -o '/.*WirtExtension\.appex' || true)
if [ -n "$PLUGINS" ]; then
	while IFS= read -r plugin; do
		if [ -n "$plugin" ]; then
			pluginkit -r "$plugin" 2>/dev/null || true
			app_path="${plugin%/Contents/PlugIns/WirtExtension.appex}"
			if [ -d "$app_path" ]; then
				/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app_path" 2>/dev/null || true
			fi
		fi
	done <<< "$PLUGINS"
fi

echo "==> Cleaning application and extension storage..."
rm -rf "$HOME/Library/Application Support/Wirt"
rm -rf "$HOME/Library/Application Support/WirtDebug"
rm -rf "$HOME/Library/Containers/de.easonwong.Wirt.Extension"
rm -rf "$HOME/Library/Containers/de.easonwong.Wirt.debug.Extension"

echo "==> Cleaning WebExtension build artifacts..."
rm -rf WirtExtension/WebExtension/.output WirtExtension/WebExtension/.wxt

echo "==> Cleaning Xcode build artifacts..."
xcodebuild -project Wirt.xcodeproj -scheme Wirt -destination 'platform=macOS' clean -quiet

echo "==> Clean slate prepared successfully."
