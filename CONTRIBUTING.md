# Contributing

Thank you for your interest in contributing to Wirt.

## Prerequisites

Ensure the following tools are installed:

- **macOS:** macOS 14.0 or later
- **Xcode:** Xcode 15.0 or later
- **Bun:** [Bun](https://bun.sh/) 1.1 or later
- **Safari:** Safari with developer settings enabled

## Project Structure

```mermaid
treeView-beta
├── Wirt/ ## macOS host application
│   ├── Assets.xcassets/ ## application asset catalogue
│   ├── Core/ ## data models and persistent storage
│   ├── Ingestion/ ## package extraction and manifest parser
│   ├── IPC/ ## XPC communication with companion extension
│   ├── LaunchAgents/ ## background launch agent configuration
│   ├── Resources/ ## host bundle resources and shims
│   ├── Supervisor/ ## extension runtime supervisor and webviews
│   ├── ContentView.swift ## host application SwiftUI view
│   ├── Info.plist ## host application property list
│   ├── Wirt.entitlements ## host application security entitlements
│   └── WirtApp.swift ## host application entry point
├── WirtExtension/ ## Safari extension companion target
│   ├── SafariWebExtensionHandler.swift ## native messaging handler
│   ├── Info.plist ## companion extension property list
│   ├── WirtExtension.entitlements ## companion extension security entitlements
│   └── WebExtension/ ## WXT companion extension source
└── Wirt.xcodeproj/ ## Xcode project configuration
```

## Build Instructions

### Xcode

Xcode triggers Bun and WXT automatically before bundling the companion extension:

1. Open `Wirt.xcodeproj` in Xcode.
2. Select the `Wirt` scheme.
3. Build and run via **Product > Run** (`Cmd + R`).

### CLI

To build the complete macOS application and bundled extension from the terminal:

```bash
# Debug build
xcodebuild -project Wirt.xcodeproj -scheme Wirt -configuration Debug build

# Release build
xcodebuild -project Wirt.xcodeproj -scheme Wirt -configuration Release build
```

## Local Testing in Safari

1. In Safari, navigate to **Develop > Allow Unsigned Extensions** (enable develop menu in **Settings > Advanced** if hidden).
2. Open **Safari > Settings > Extensions** and tick the checkbox next to **Wirt**.
3. Install any extension package from the [Chrome Web Store](https://chromewebstore.google.com) or [Firefox Add-ons](https://addons.mozilla.org).
4. Click the **Wirt** toolbar icon to manage installed extensions or open individual extension popups.
