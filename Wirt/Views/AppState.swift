import AppKit
import Combine
import SafariServices
import UniformTypeIdentifiers

// MARK: - Enums & Models

enum ExtensionDetailTab: String, CaseIterable, Identifiable {
	case details = "Details"
	case preference = "Preference"
	case background = "Background"

	var id: String { rawValue }

	var icon: String {
		switch self {
		case .details: return "doc.text"
		case .preference: return "slider.horizontal.3"
		case .background: return "terminal"
		}
	}
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
	static let shared = AppState()

	@Published var isExtensionEnabled = false
	@Published var installedExtensions: [ExtensionDescriptor] = []
	@Published var selectedExtensionId: String? = nil
	@Published var selectedTab: ExtensionDetailTab = .details
	@Published var searchQuery: String = ""

	private let extensionBundleId = "de.easonwong.Wirt.Extension"
	private var cancellables = Set<AnyCancellable>()

	init() {
		loadInstalledExtensions()
		checkExtensionState()

		NotificationCenter.default.publisher(for: NSNotification.Name("WirtOpenOptionsPage"))
			.receive(on: RunLoop.main)
			.sink { [weak self] notification in
				guard let self = self,
					let extId = notification.userInfo?["extensionId"] as? String
				else { return }
				self.openOptionsPage(for: extId)
			}
			.store(in: &cancellables)
	}

	var selectedExtension: ExtensionDescriptor? {
		guard let id = selectedExtensionId else { return nil }
		return installedExtensions.first(where: { $0.id.lowercased() == id.lowercased() })
	}

	var filteredExtensions: [ExtensionDescriptor] {
		let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard !query.isEmpty else { return installedExtensions }
		return installedExtensions.filter {
			$0.name.lowercased().contains(query) || $0.id.lowercased().contains(query)
				|| $0.description.lowercased().contains(query)
		}
	}

	func ensureActiveSelection() {
		guard isExtensionEnabled else { return }
		if let id = selectedExtensionId,
			!installedExtensions.contains(where: {
				$0.id.lowercased() == id.lowercased()
			})
		{
			selectedExtensionId = nil
		}
	}

	func checkExtensionState() {
		SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleId) {
			state, error in
			Task { @MainActor in
				if let state = state {
					if self.isExtensionEnabled != state.isEnabled {
						self.isExtensionEnabled = state.isEnabled
						if state.isEnabled {
							self.ensureActiveSelection()
						}
					}
				} else if error != nil {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
						SFSafariExtensionManager.getStateOfSafariExtension(
							withIdentifier: self.extensionBundleId
						) { retryState, _ in
							if let retryState = retryState {
								Task { @MainActor in
									if self.isExtensionEnabled != retryState.isEnabled {
										self.isExtensionEnabled = retryState.isEnabled
										if retryState.isEnabled {
											self.ensureActiveSelection()
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}

	func loadInstalledExtensions() {
		let storageDir = ExtensionInstaller.shared.storageDirectory
		guard
			let items = try? FileManager.default.contentsOfDirectory(
				at: storageDir, includingPropertiesForKeys: nil)
		else {
			installedExtensions = []
			return
		}

		var loaded: [ExtensionDescriptor] = []
		for item in items where item.hasDirectoryPath {
			if let desc = try? ExtensionInstaller.shared.parseManifest(
				in: item, fallbackId: item.lastPathComponent)
			{
				loaded.append(desc)
			}
		}
		loaded.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
		installedExtensions = loaded

		if let id = selectedExtensionId,
			!loaded.contains(where: { $0.id.lowercased() == id.lowercased() })
		{
			selectedExtensionId = loaded.first?.id
		} else if selectedExtensionId == nil {
			selectedExtensionId = loaded.first?.id
		}
	}

	func uninstallExtension(id: String) {
		ExtensionRuntime.shared.stopBackgroundRuntime(for: id)
		try? ExtensionInstaller.shared.uninstall(extensionId: id)
		ExtensionStorage.shared.deleteStorage(for: id)
		ExtensionRuntime.shared.clearConsoleLogs(for: id)
		loadInstalledExtensions()
	}

	func reloadExtension(id: String) {
		ExtensionRuntime.shared.stopBackgroundRuntime(for: id)
		let dir = ExtensionInstaller.shared.storageDirectory.appendingPathComponent(
			id, isDirectory: true)
		if let desc = try? ExtensionInstaller.shared.parseManifest(in: dir, fallbackId: id) {
			ExtensionRuntime.shared.startBackgroundRuntime(for: desc, directory: dir)
			ExtensionRuntime.shared.addConsoleLog(
				ConsoleLogEntry(level: .info, message: "Extension background runtime reloaded."),
				for: id
			)
		}
	}

	func openOptionsPage(for id: String) {
		if let ext = installedExtensions.first(where: { $0.id.lowercased() == id.lowercased() }) {
			selectedExtensionId = ext.id
			selectedTab = .preference
		}
	}

	func openInFinder(id: String) {
		let dir = ExtensionInstaller.shared.storageDirectory.appendingPathComponent(
			id, isDirectory: true)
		NSWorkspace.shared.activateFileViewerSelecting([dir])
	}

	func openSafariExtensionSettings() {
		SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleId)
	}

	func openURLInSafari(_ url: URL) {
		if let safariURL = NSWorkspace.shared.urlForApplication(
			withBundleIdentifier: "com.apple.Safari")
		{
			let config = NSWorkspace.OpenConfiguration()
			NSWorkspace.shared.open(
				[url], withApplicationAt: safariURL, configuration: config, completionHandler: nil)
		} else {
			NSWorkspace.shared.open(url)
		}
	}

	func openChromeWebStore() {
		if let url = URL(string: "https://chromewebstore.google.com") {
			openURLInSafari(url)
		}
	}

	func openFirefoxAddons() {
		if let url = URL(string: "https://addons.mozilla.org") {
			openURLInSafari(url)
		}
	}

	func installFromDisk() {
		let panel = NSOpenPanel()
		panel.title = "Select Extension File or Folder"
		panel.prompt = "Install"
		panel.allowsMultipleSelection = false
		panel.canChooseDirectories = true
		panel.canChooseFiles = true
		panel.allowedContentTypes = [
			UTType.folder,
			UTType.zip,
			UTType(filenameExtension: "crx"),
			UTType(filenameExtension: "xpi"),
		].compactMap { $0 }

		if panel.runModal() == .OK, let url = panel.url {
			do {
				let desc = try ExtensionInstaller.shared.installFromDisk(at: url)
				let targetDir = ExtensionInstaller.shared.storageDirectory.appendingPathComponent(
					desc.id, isDirectory: true)
				ExtensionRuntime.shared.stopBackgroundRuntime(for: desc.id)
				ExtensionRuntime.shared.startBackgroundRuntime(for: desc, directory: targetDir)
				loadInstalledExtensions()
				selectedExtensionId = desc.id
			} catch {
				let alert = NSAlert()
				alert.messageText = "Failed to Install Extension"
				alert.informativeText = error.localizedDescription
				alert.alertStyle = .warning
				alert.runModal()
			}
		}
	}
}
