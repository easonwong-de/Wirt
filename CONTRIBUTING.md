# Contributing

Thank you for your interest in contributing to Safari Extension Host.

## Prerequisites

Ensure the following tools are installed:

- **macOS:** macOS 14.0 or later
- **Xcode:** Xcode 15.0 or later
- **Bun:** [Bun](https://bun.sh/) 1.1 or later
- **Safari:** Safari with developer settings enabled

## Project Structure

```mermaid
treeView-beta
Safari-Extension-Host/ ## repository root
├── SafariExtensionHost/ ## macOS host application
│   ├── Assets.xcassets/ ## application asset catalogue
│   ├── Core/ ## data models and persistent storage
│   ├── Ingestion/ ## package extraction and manifest parser
│   ├── IPC/ ## XPC communication with companion extension
│   ├── LaunchAgents/ ## background launch agent configuration
│   ├── Resources/ ## host bundle resources and shims
│   ├── Supervisor/ ## extension runtime supervisor and webviews
│   ├── ContentView.swift ## host application SwiftUI view
│   ├── Info.plist ## host application property list
│   ├── SafariExtensionHost.entitlements ## host application security entitlements
│   └── SafariExtensionHostApp.swift ## host application entry point
├── SafariExtensionHostExtension/ ## Safari extension companion target
│   ├── SafariWebExtensionHandler.swift ## native messaging handler
│   ├── Info.plist ## companion extension property list
│   ├── SafariExtensionHostExtension.entitlements ## companion extension security entitlements
│   └── WebExtension/ ## WXT companion extension source
└── SafariExtensionHost.xcodeproj/ ## Xcode project configuration
```

## Build Instructions

### Xcode

Xcode triggers Bun and WXT automatically before bundling the companion extension:

1. Open `SafariExtensionHost.xcodeproj` in Xcode.
2. Select the `SafariExtensionHost` scheme.
3. Build and run via **Product > Run** (`Cmd + R`).

### CLI

To build the complete macOS application and bundled extension from the terminal:

```bash
# Debug build
xcodebuild -project SafariExtensionHost.xcodeproj -scheme SafariExtensionHost -configuration Debug build

# Release build
xcodebuild -project SafariExtensionHost.xcodeproj -scheme SafariExtensionHost -configuration Release build
```

## Local Testing in Safari

1. In Safari, navigate to **Develop > Allow Unsigned Extensions** (enable develop menu in **Settings > Advanced** if hidden).
2. Open **Safari > Settings > Extensions** and tick the checkbox next to **Safari Extension Host**.
3. Install any extension package from the [Chrome Web Store](https://chromewebstore.google.com) or [Firefox Add-ons](https://addons.mozilla.org).
4. Click the **Safari Extension Host** toolbar icon to manage installed extensions or open individual extension popups.
