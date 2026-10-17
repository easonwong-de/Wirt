import AppKit
import ServiceManagement
import SwiftUI
import os.log

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
	private static let agentPlistName = "de.easonwong.Wirt.agent.plist"
	private static let backgroundArgument = "--background"

	private var window: NSWindow?

	static func main() {
		let app = NSApplication.shared
		let delegate = AppDelegate()
		app.delegate = delegate
		app.run()
	}

	private var hasInitialisedWindowSize = false

	func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
		return true
	}

	private static let agentLabel = "de.easonwong.Wirt.agent"

	func applicationDidFinishLaunching(_ notification: Notification) {
		cleanStaleExtensions()
		registerLaunchAgent()

		if CommandLine.arguments.contains(Self.backgroundArgument) {
			NSApp.setActivationPolicy(.accessory)
			ExtensionListener.shared.start()
			ExtensionRuntime.shared.bootInstalledExtensions()
			return
		}

		ensureAgentRunningAndHandOff()
	}

	private func ensureAgentRunningAndHandOff() {
		let uid = String(getuid())
		let kickstartProcess = Process()
		kickstartProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
		kickstartProcess.arguments = ["kickstart", "-k", "gui/\(uid)/\(Self.agentLabel)"]
		try? kickstartProcess.run()
		kickstartProcess.waitUntilExit()

		handOffToAgent()
	}

	private func registerLaunchAgent() {
		let agent = SMAppService.agent(plistName: Self.agentPlistName)
		if agent.status == .enabled || agent.status == .requiresApproval {
			try? agent.unregister()
		}

		guard let executablePath = Bundle.main.executablePath else { return }

		let fileManager = FileManager.default
		let launchAgentsDir = fileManager.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
		let plistURL = launchAgentsDir.appendingPathComponent(Self.agentPlistName)

		let plistDict: [String: Any] = [
			"Label": Self.agentLabel,
			"ProgramArguments": [executablePath, Self.backgroundArgument],
			"MachServices": [HostXPC.serviceName: true],
			"ProcessType": "Interactive",
		]

		var shouldUpdate = true
		if fileManager.fileExists(atPath: plistURL.path),
			let existingData = try? Data(contentsOf: plistURL),
			let existingPlist = try? PropertyListSerialization.propertyList(
				from: existingData, format: nil) as? [String: Any],
			let existingArgs = existingPlist["ProgramArguments"] as? [String],
			existingArgs == [executablePath, Self.backgroundArgument]
		{
			shouldUpdate = false
		}

		if shouldUpdate {
			try? fileManager.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
			if let data = try? PropertyListSerialization.data(
				fromPropertyList: plistDict, format: .xml, options: 0)
			{
				try? data.write(to: plistURL)
			}

			let uid = String(getuid())
			let bootoutProcess = Process()
			bootoutProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
			bootoutProcess.arguments = ["bootout", "gui/\(uid)/\(Self.agentLabel)"]
			try? bootoutProcess.run()
			bootoutProcess.waitUntilExit()

			let bootstrapProcess = Process()
			bootstrapProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
			bootstrapProcess.arguments = ["bootstrap", "gui/\(uid)", plistURL.path]
			try? bootstrapProcess.run()
			bootstrapProcess.waitUntilExit()
		}
	}

	private func cleanStaleExtensions() {
		DispatchQueue.global(qos: .utility).async {
			guard
				let currentExtensionURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent(
					"WirtExtension.appex", isDirectory: true)
			else { return }

			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
			process.arguments = ["-m", "-A", "-v", "-i", "de.easonwong.Wirt.Extension"]
			let pipe = Pipe()
			process.standardOutput = pipe
			do {
				try process.run()
				let data = pipe.fileHandleForReading.readDataToEndOfFile()
				process.waitUntilExit()

				guard let output = String(data: data, encoding: .utf8) else { return }

				for line in output.components(separatedBy: .newlines) {
					let trimmed = line.trimmingCharacters(in: .whitespaces)
					if trimmed.contains("/WirtExtension.appex") {
						let parts = trimmed.components(separatedBy: "\t")
						if let path = parts.last?.trimmingCharacters(in: .whitespaces),
							path != currentExtensionURL.path
						{
							let rmProc = Process()
							rmProc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
							rmProc.arguments = ["-r", path]
							try? rmProc.run()
							rmProc.waitUntilExit()

							let appURL = URL(fileURLWithPath: path)
								.deletingLastPathComponent()
								.deletingLastPathComponent()
								.deletingLastPathComponent()
							if appURL.pathExtension == "app" {
								let lsProc = Process()
								lsProc.executableURL = URL(
									fileURLWithPath:
										"/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
								)
								lsProc.arguments = ["-u", appURL.path]
								try? lsProc.run()
								lsProc.waitUntilExit()
							}
						}
					}
				}
			} catch {
				os_log(.error, "cleanStaleExtensions failed: %@", error.localizedDescription)
			}
		}
	}

	private func handOffToAgent() {
		let connection = NSXPCConnection(machServiceName: HostXPC.serviceName, options: [])
		connection.remoteObjectInterface = NSXPCInterface(with: HostXPCProtocol.self)
		connection.resume()

		let lock = NSLock()
		var hasCompleted = false

		func finish(shouldTerminate: Bool) {
			lock.lock()
			defer { lock.unlock() }
			guard !hasCompleted else { return }
			hasCompleted = true
			connection.invalidate()
			Task { @MainActor in
				if shouldTerminate {
					NSApp.terminate(nil)
				} else {
					self.startForeground()
				}
			}
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
			finish(shouldTerminate: false)
		}

		guard
			let agent = connection.remoteObjectProxyWithErrorHandler({ error in
				os_log(.error, "Launch agent hand-off failed: %@", error.localizedDescription)
				finish(shouldTerminate: false)
			}) as? HostXPCProtocol
		else {
			os_log(.error, "Failed to obtain remote proxy for launch agent")
			finish(shouldTerminate: false)
			return
		}

		agent.showSettings {
			finish(shouldTerminate: true)
		}
	}

	private func startForeground() {
		NSApp.setActivationPolicy(.regular)
		ExtensionListener.shared.start()
		ExtensionRuntime.shared.bootInstalledExtensions()
		showSettings()
	}

	private func setupInterface() {
		guard window == nil else { return }
		setupMainMenu()
		setupWindow()
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
		-> Bool
	{
		showSettings()
		return true
	}

	func windowShouldClose(_ sender: NSWindow) -> Bool {
		sender.orderOut(nil)
		NSApp.setActivationPolicy(.accessory)
		return false
	}

	@objc func showSettings() {
		NSApp.setActivationPolicy(.regular)
		setupInterface()
		if let window = self.window {
			if window.isMiniaturized {
				window.deminiaturize(nil)
			}
			window.makeKeyAndOrderFront(nil)
			window.orderFrontRegardless()
		}
		NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
		NSApp.activate(ignoringOtherApps: true)
	}

	@objc func quitApp() {
		window?.orderOut(nil)
		NSApp.setActivationPolicy(.accessory)
	}

	@objc func terminateEntireApp() {
		NSApp.terminate(nil)
	}

	private func updateWindowSize(to contentHeight: CGFloat, animated: Bool) {
		guard let window = self.window else { return }
		let titlebarHeight = window.frame.height - window.contentLayoutRect.height
		let targetHeight = contentHeight + titlebarHeight
		let windowSize = window.frame.size
		let heightDiff = targetHeight - windowSize.height
		guard abs(heightDiff) > 0.5 else { return }

		let targetOrigin = NSPoint(x: window.frame.origin.x, y: window.frame.origin.y - heightDiff)
		let targetSize = NSSize(width: window.frame.width, height: targetHeight)
		let targetRect = NSRect(origin: targetOrigin, size: targetSize)

		if animated && hasInitialisedWindowSize {
			NSAnimationContext.runAnimationGroup { context in
				context.duration = 0.3
				context.allowsImplicitAnimation = true
				window.setFrame(targetRect, display: true)
			}
		} else {
			window.setFrame(targetRect, display: true)
			hasInitialisedWindowSize = true
		}
	}

	private func setupWindow() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: WindowMetrics.windowWidth, height: 200),
			styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		window.title = "Wirt"
		window.titleVisibility = .visible
		window.titlebarAppearsTransparent = true
		window.titlebarSeparatorStyle = .none
		window.isMovableByWindowBackground = true
		window.isReleasedWhenClosed = false
		window.delegate = self

		let hostingView = NSHostingView(
			rootView: ContentView(onHeightChange: { [weak self] newHeight in
				self?.updateWindowSize(
					to: newHeight, animated: self?.hasInitialisedWindowSize ?? false)
			}))
		window.contentView = hostingView
		self.window = window

		let initialHeight = hostingView.fittingSize.height
		let titlebarHeight = window.frame.height - window.contentLayoutRect.height
		if initialHeight > titlebarHeight {
			updateWindowSize(to: initialHeight - titlebarHeight, animated: false)
		}
		hasInitialisedWindowSize = true
		window.center()
	}

	private func setupMainMenu() {
		let mainMenu = NSMenu()

		let appMenuItem = NSMenuItem()
		mainMenu.addItem(appMenuItem)
		let appMenu = NSMenu()
		appMenu.addItem(
			NSMenuItem(
				title: "About Wirt",
				action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
				keyEquivalent: ""))
		appMenu.addItem(NSMenuItem.separator())
		let settingsItem = NSMenuItem(
			title: "Settings…",
			action: #selector(showSettings),
			keyEquivalent: ",")
		settingsItem.target = self
		appMenu.addItem(settingsItem)
		appMenu.addItem(NSMenuItem.separator())
		appMenu.addItem(
			NSMenuItem(
				title: "Hide Wirt",
				action: #selector(NSApplication.hide(_:)),
				keyEquivalent: "h"))
		let hideOthersItem = NSMenuItem(
			title: "Hide Others",
			action: #selector(NSApplication.hideOtherApplications(_:)),
			keyEquivalent: "h")
		hideOthersItem.keyEquivalentModifierMask = [.command, .option]
		appMenu.addItem(hideOthersItem)
		appMenu.addItem(
			NSMenuItem(
				title: "Show All",
				action: #selector(NSApplication.unhideAllApplications(_:)),
				keyEquivalent: ""))
		appMenu.addItem(NSMenuItem.separator())
		let closeWirtItem = NSMenuItem(
			title: "Close Wirt",
			action: #selector(quitApp),
			keyEquivalent: "q")
		closeWirtItem.target = self
		appMenu.addItem(closeWirtItem)

		let terminateItem = NSMenuItem(
			title: "Quit Wirt & Stop Background Service",
			action: #selector(terminateEntireApp),
			keyEquivalent: "q")
		terminateItem.keyEquivalentModifierMask = [.command, .option]
		terminateItem.target = self
		appMenu.addItem(terminateItem)
		appMenuItem.submenu = appMenu

		let editMenuItem = NSMenuItem()
		mainMenu.addItem(editMenuItem)
		let editMenu = NSMenu(title: "Edit")
		editMenu.addItem(
			NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
		editMenu.addItem(
			NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
		editMenu.addItem(
			NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
		editMenu.addItem(
			NSMenuItem(
				title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
		editMenuItem.submenu = editMenu

		let windowMenuItem = NSMenuItem()
		mainMenu.addItem(windowMenuItem)
		let windowMenu = NSMenu(title: "Window")
		let closeItem = NSMenuItem(
			title: "Close Window",
			action: #selector(NSWindow.performClose(_:)),
			keyEquivalent: "w")
		windowMenu.addItem(closeItem)
		windowMenuItem.submenu = windowMenu

		NSApp.mainMenu = mainMenu
	}
}
