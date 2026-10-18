import AppKit
import Combine
import SafariServices
import SwiftUI
import UniformTypeIdentifiers
import WebKit

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
		if selectedExtensionId == nil
			|| !installedExtensions.contains(where: {
				$0.id.lowercased() == selectedExtensionId?.lowercased()
			})
		{
			selectedExtensionId = filteredExtensions.first?.id ?? installedExtensions.first?.id
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

		if selectedExtensionId == nil || !loaded.contains(where: { $0.id == selectedExtensionId }) {
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

// MARK: - Main ContentView

struct ContentView: View {
	@ObservedObject private var state = AppState.shared
	@State private var columnVisibility = NavigationSplitViewVisibility.all

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			SidebarView()
				.navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
		} detail: {
			if !state.isExtensionEnabled {
				disconnectedDetailView
			} else if let ext = state.selectedExtension {
				DetailContainerView(extensionDescriptor: ext)
			} else {
				emptySelectionView
			}
		}
		.frame(minWidth: 760, idealWidth: 980, minHeight: 480, idealHeight: 600)
		.onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
			_ in
			state.checkExtensionState()
			state.loadInstalledExtensions()
		}
	}

	private var disconnectedDetailView: some View {
		VStack(spacing: 18) {
			VStack(spacing: 10) {
				Image(systemName: "puzzlepiece.extension")
					.font(.system(size: 44))
					.foregroundStyle(.secondary)

				HStack(spacing: 6) {
					Circle()
						.fill(Color.red)
						.frame(width: 8, height: 8)

					Text("Extension Not Enabled")
						.font(.system(size: 14, weight: .semibold))

					Button {
						state.checkExtensionState()
					} label: {
						Image(systemName: "arrow.clockwise")
							.font(.system(size: 12, weight: .medium))
					}
					.buttonStyle(.plain)
					.help("Refresh extension status")
				}
			}

			VStack(alignment: .leading, spacing: 8) {
				instructionLine(
					number: "1.",
					text:
						"In Safari Settings > Advanced, tick \"Show features for web developers\".")
				instructionLine(
					number: "2.",
					text: "In Safari Develop menu, select \"Allow Unsigned Extensions\".")
				instructionLine(
					number: "3.",
					text: "In Safari Settings > Extensions, tick \"Wirt\".")
				instructionLine(
					number: "4.",
					text: "Select \"Always Allow on Every Website…\".")
			}
			.font(.system(size: 12))
			.foregroundStyle(.secondary)
			.padding(.vertical, 12)
			.padding(.horizontal, 18)
			.background(Color(NSColor.controlBackgroundColor).opacity(0.6))
			.clipShape(RoundedRectangle(cornerRadius: 8))
			.overlay(
				RoundedRectangle(cornerRadius: 8)
					.strokeBorder(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
			)

			Button("Open Safari Settings") {
				state.openSafariExtensionSettings()
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.regular)
		}
		.padding(32)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(Color(NSColor.windowBackgroundColor))
	}

	private func instructionLine(number: String, text: String) -> some View {
		HStack(alignment: .top, spacing: 6) {
			Text(number)
				.fontWeight(.medium)
			Text(text)
				.fixedSize(horizontal: false, vertical: true)
		}
	}

	private var emptySelectionView: some View {
		VStack(spacing: 16) {
			Image(systemName: "puzzlepiece.extension")
				.font(.system(size: 48))
				.foregroundStyle(.tertiary)

			VStack(spacing: 6) {
				Text("Select an Extension to View Details")
					.font(.system(size: 15, weight: .semibold))
				Text(
					"Select an extension from the sidebar to inspect its details, preferences, or background runtime. Click the + button above the sidebar to install a new extension."
				)
				.font(.system(size: 12))
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.frame(maxWidth: 360)
			}
		}
		.padding(32)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(Color(NSColor.windowBackgroundColor))
	}
}

// MARK: - Sidebar View (Messages.app style)

struct SidebarView: View {
	@ObservedObject private var state = AppState.shared
	@State private var extensionToUninstall: ExtensionDescriptor?

	var body: some View {
		Group {
			if state.filteredExtensions.isEmpty {
				emptyListView
			} else {
				List(selection: $state.selectedExtensionId) {
					ForEach(state.filteredExtensions) { ext in
						SidebarExtensionRow(extensionDescriptor: ext)
							.tag(ext.id)
							.swipeActions(edge: .trailing, allowsFullSwipe: false) {
								Button(role: .destructive) {
									state.uninstallExtension(id: ext.id)
								} label: {
									Label("Uninstall", systemImage: "trash.fill")
								}
							}
							.contextMenu {
								Button {
									state.openInFinder(id: ext.id)
								} label: {
									Label("Show in Finder", systemImage: "folder")
								}

								Button {
									state.reloadExtension(id: ext.id)
								} label: {
									Label("Reload Runtime", systemImage: "arrow.clockwise")
								}

								Button {
									NSPasteboard.general.clearContents()
									NSPasteboard.general.setString(ext.id, forType: .string)
								} label: {
									Label("Copy Extension ID", systemImage: "doc.on.doc")
								}

								Divider()

								Button(role: .destructive) {
									extensionToUninstall = ext
								} label: {
									Label("Uninstall", systemImage: "trash")
								}
							}
					}
				}
				.listStyle(.sidebar)
			}
		}
		.searchable(text: $state.searchQuery, placement: .sidebar, prompt: "Search extensions…")
		.disabled(!state.isExtensionEnabled)
		.opacity(state.isExtensionEnabled ? 1.0 : 0.45)
		.saturation(state.isExtensionEnabled ? 1.0 : 0.0)
		.toolbar(removing: .sidebarToggle)
		.toolbar {
			ToolbarItem(placement: .navigation) {
				Menu {
					Button {
						state.openChromeWebStore()
					} label: {
						Label("From Chrome Web Store", systemImage: "globe")
					}

					Button {
						state.openFirefoxAddons()
					} label: {
						Label("From Firefox Add-on Store", systemImage: "flame")
					}

					Divider()

					Button {
						state.installFromDisk()
					} label: {
						Label("From disk...", systemImage: "internaldrive")
					}
				} label: {
					Image(systemName: "plus")
				}
				.menuIndicator(.hidden)
				.help("Add Extension")
				.disabled(!state.isExtensionEnabled)
			}
		}
		.onAppear {
			state.ensureActiveSelection()
		}
		.onChange(of: state.searchQuery) { _ in
			if let selected = state.selectedExtensionId,
				!state.filteredExtensions.contains(where: {
					$0.id.lowercased() == selected.lowercased()
				})
			{
				state.selectedExtensionId = state.filteredExtensions.first?.id
			}
		}
		.confirmationDialog(
			"Uninstall Extension",
			isPresented: Binding(
				get: { extensionToUninstall != nil },
				set: { if !$0 { extensionToUninstall = nil } }
			),
			titleVisibility: .visible,
			presenting: extensionToUninstall
		) { ext in
			Button("Uninstall \(ext.name)", role: .destructive) {
				state.uninstallExtension(id: ext.id)
			}
			Button("Cancel", role: .cancel) {}
		} message: { ext in
			Text(
				"Are you sure you want to uninstall \"\(ext.name)\"? All saved data will be removed."
			)
		}
	}

	private var emptyListView: some View {
		VStack(spacing: 12) {
			Spacer()
			Image(systemName: "puzzlepiece.extension")
				.font(.system(size: 32))
				.foregroundStyle(.tertiary)
			Text(state.searchQuery.isEmpty ? "No Extensions Installed" : "No Matching Extensions")
				.font(.system(size: 13, weight: .semibold))
			Text(
				state.searchQuery.isEmpty
					? "Click the + button to install an extension."
					: "Try a different search term."
			)
			.font(.system(size: 11))
			.foregroundStyle(.secondary)
			.multilineTextAlignment(.center)
			.padding(.horizontal, 20)
			Spacer()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

// MARK: - Sidebar Row View

struct SidebarExtensionRow: View {
	let extensionDescriptor: ExtensionDescriptor

	var body: some View {
		HStack(spacing: 10) {
			extensionIconView
				.frame(width: 38, height: 38)
				.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
				.overlay(
					RoundedRectangle(cornerRadius: 8, style: .continuous)
						.strokeBorder(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
				)

			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 4) {
					Text(extensionDescriptor.name)
						.font(.system(size: 13, weight: .medium))
						.lineLimit(1)

					Spacer(minLength: 4)

					Text("v\(extensionDescriptor.version)")
						.font(.system(size: 10, weight: .medium, design: .monospaced))
						.foregroundStyle(.tertiary)
				}

				Text(
					extensionDescriptor.description.isEmpty
						? "No description declared."
						: extensionDescriptor.description
				)
				.font(.system(size: 11))
				.foregroundStyle(.secondary)
				.lineLimit(2)
				.lineSpacing(1.5)
			}
		}
		.padding(.vertical, 4)
	}

	@ViewBuilder
	private var extensionIconView: some View {
		if let iconUrl = extensionDescriptor.iconUrl,
			let commaIndex = iconUrl.firstIndex(of: ","),
			let data = Data(base64Encoded: String(iconUrl[iconUrl.index(after: commaIndex)...])),
			let nsImage = NSImage(data: data)
		{
			Image(nsImage: nsImage)
				.resizable()
				.aspectRatio(contentMode: .fit)
		} else {
			ZStack {
				Color.accentColor.opacity(0.12)
				Image(systemName: "puzzlepiece.extension.fill")
					.font(.system(size: 18))
					.foregroundStyle(Color.accentColor)
			}
		}
	}
}

// MARK: - Detail Container View

struct DetailContainerView: View {
	let extensionDescriptor: ExtensionDescriptor
	@ObservedObject private var state = AppState.shared

	var body: some View {
		VStack(spacing: 0) {
			topTabBar
			Divider()

			Group {
				switch state.selectedTab {
				case .details:
					ExtensionDetailsView(ext: extensionDescriptor)
				case .preference:
					ExtensionPreferenceView(ext: extensionDescriptor)
				case .background:
					ExtensionBackgroundView(ext: extensionDescriptor)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.background(Color(NSColor.windowBackgroundColor))
	}

	private var topTabBar: some View {
		HStack(spacing: 12) {
			Picker("", selection: $state.selectedTab) {
				ForEach(ExtensionDetailTab.allCases) { tab in
					Label(tab.rawValue, systemImage: tab.icon).tag(tab)
				}
			}
			.pickerStyle(.segmented)
			.frame(width: 320)

			Spacer()

			HStack(spacing: 8) {
				Button {
					state.reloadExtension(id: extensionDescriptor.id)
				} label: {
					Image(systemName: "arrow.clockwise")
				}
				.help("Reload background runtime")

				Button {
					state.openInFinder(id: extensionDescriptor.id)
				} label: {
					Image(systemName: "folder")
				}
				.help("Show extension in Finder")
			}
			.buttonStyle(.bordered)
			.controlSize(.small)
		}
		.padding(.horizontal, 18)
		.padding(.vertical, 10)
		.background(Color(NSColor.controlBackgroundColor).opacity(0.5))
	}
}

// MARK: - Tab 1: Extension Details View (VS Code style)

struct ExtensionDetailsView: View {
	let ext: ExtensionDescriptor
	@ObservedObject private var state = AppState.shared
	@State private var showCopiedAlert = false
	@State private var showUninstallAlert = false

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				headerBanner

				Divider()

				VStack(alignment: .leading, spacing: 16) {
					descriptionSection
					permissionsSection
					contentScriptsSection
					backgroundSection
					actionSection
					fileInfoSection
				}
			}
			.padding(24)
		}
		.confirmationDialog(
			"Uninstall Extension",
			isPresented: $showUninstallAlert,
			titleVisibility: .visible
		) {
			Button("Uninstall \(ext.name)", role: .destructive) {
				state.uninstallExtension(id: ext.id)
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text(
				"Are you sure you want to uninstall \"\(ext.name)\"? All saved data will be deleted."
			)
		}
	}

	private var headerBanner: some View {
		HStack(alignment: .top, spacing: 16) {
			extensionLargeIcon
				.frame(width: 58, height: 58)
				.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
				.overlay(
					RoundedRectangle(cornerRadius: 12, style: .continuous)
						.strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
				)

			VStack(alignment: .leading, spacing: 4) {
				HStack(spacing: 8) {
					Text(ext.name)
						.font(.system(size: 18, weight: .bold))

					Text("v\(ext.version)")
						.font(.system(size: 11, weight: .semibold, design: .monospaced))
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.background(Color(NSColor.quaternaryLabelColor))
						.clipShape(Capsule())
				}

				HStack(spacing: 6) {
					Text(ext.id)
						.font(.system(size: 11, design: .monospaced))
						.foregroundStyle(.secondary)

					Button {
						NSPasteboard.general.clearContents()
						NSPasteboard.general.setString(ext.id, forType: .string)
						showCopiedAlert = true
						DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
							showCopiedAlert = false
						}
					} label: {
						Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
							.font(.system(size: 10))
					}
					.buttonStyle(.plain)
					.foregroundStyle(showCopiedAlert ? Color.green : Color.secondary)
					.help("Copy Extension ID")
				}

				if let author = ext.author, !author.isEmpty {
					Text("By \(author)")
						.font(.system(size: 11))
						.foregroundStyle(.secondary)
				}

				HStack(spacing: 8) {
					badgePill(text: "Manifest V\(ext.manifestVersion)", icon: "gearshape")
					badgePill(text: "\(ext.permissions.count) Permissions", icon: "lock.shield")
					badgePill(text: "\(ext.contentScripts.count) Scripts", icon: "doc.plaintext")
				}
				.padding(.top, 4)
			}

			Spacer()

			VStack(alignment: .trailing, spacing: 8) {
				Button(role: .destructive) {
					showUninstallAlert = true
				} label: {
					Label("Uninstall", systemImage: "trash")
				}
				.buttonStyle(.bordered)
				.controlSize(.regular)

				if ext.optionsPage != nil {
					Button {
						state.selectedTab = .preference
					} label: {
						Label("Preferences…", systemImage: "slider.horizontal.3")
					}
					.buttonStyle(.borderedProminent)
					.controlSize(.regular)
				}
			}
		}
	}

	@ViewBuilder
	private var extensionLargeIcon: some View {
		if let iconUrl = ext.iconUrl,
			let commaIndex = iconUrl.firstIndex(of: ","),
			let data = Data(base64Encoded: String(iconUrl[iconUrl.index(after: commaIndex)...])),
			let nsImage = NSImage(data: data)
		{
			Image(nsImage: nsImage)
				.resizable()
				.aspectRatio(contentMode: .fit)
		} else {
			ZStack {
				Color.accentColor.opacity(0.12)
				Image(systemName: "puzzlepiece.extension.fill")
					.font(.system(size: 28))
					.foregroundStyle(Color.accentColor)
			}
		}
	}

	private func badgePill(text: String, icon: String) -> some View {
		HStack(spacing: 4) {
			Image(systemName: icon)
				.font(.system(size: 9))
			Text(text)
				.font(.system(size: 10, weight: .medium))
		}
		.foregroundStyle(.secondary)
		.padding(.horizontal, 8)
		.padding(.vertical, 3)
		.background(Color(NSColor.controlBackgroundColor).opacity(0.6))
		.clipShape(Capsule())
		.overlay(
			Capsule()
				.strokeBorder(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
		)
	}

	private var descriptionSection: some View {
		cardContainer(title: "Overview", icon: "text.alignleft") {
			Text(
				ext.description.isEmpty
					? "No description provided by the extension manifest." : ext.description
			)
			.font(.system(size: 13))
			.foregroundStyle(ext.description.isEmpty ? .secondary : .primary)
			.lineSpacing(3)
		}
	}

	private var permissionsSection: some View {
		cardContainer(title: "Permissions", icon: "lock.shield") {
			if ext.permissions.isEmpty {
				Text("No permissions requested.")
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
			} else {
				FlowLayout(spacing: 6) {
					ForEach(ext.permissions, id: \.self) { perm in
						HStack(spacing: 4) {
							Image(systemName: iconForPermission(perm))
								.font(.system(size: 9))
							Text(perm)
								.font(.system(size: 11, design: .monospaced))
						}
						.padding(.horizontal, 8)
						.padding(.vertical, 4)
						.background(Color(NSColor.controlBackgroundColor))
						.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
						.overlay(
							RoundedRectangle(cornerRadius: 6, style: .continuous)
								.strokeBorder(
									Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
						)
					}
				}
			}
		}
	}

	private var contentScriptsSection: some View {
		cardContainer(title: "Content Scripts", icon: "doc.plaintext") {
			if ext.contentScripts.isEmpty {
				Text("No content scripts declared.")
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
			} else {
				VStack(alignment: .leading, spacing: 10) {
					ForEach(Array(ext.contentScripts.enumerated()), id: \.offset) { idx, cs in
						VStack(alignment: .leading, spacing: 6) {
							HStack(spacing: 6) {
								Text("Matches:")
									.font(.system(size: 11, weight: .semibold))
									.foregroundStyle(.secondary)
								ForEach(cs.matches, id: \.self) { match in
									Text(match)
										.font(
											.system(size: 10, weight: .medium, design: .monospaced)
										)
										.padding(.horizontal, 6)
										.padding(.vertical, 2)
										.background(Color.accentColor.opacity(0.1))
										.clipShape(RoundedRectangle(cornerRadius: 4))
								}
							}

							if !cs.js.isEmpty {
								HStack(spacing: 6) {
									Text("JS:")
										.font(.system(size: 11, weight: .semibold))
										.foregroundStyle(.secondary)
									Text(cs.js.joined(separator: ", "))
										.font(.system(size: 11, design: .monospaced))
								}
							}

							if !cs.css.isEmpty {
								HStack(spacing: 6) {
									Text("CSS:")
										.font(.system(size: 11, weight: .semibold))
										.foregroundStyle(.secondary)
									Text(cs.css.joined(separator: ", "))
										.font(.system(size: 11, design: .monospaced))
								}
							}

							HStack(spacing: 12) {
								Text("Run At: \(cs.runAt)")
									.font(.system(size: 10))
									.foregroundStyle(.tertiary)
								Text("All Frames: \(cs.allFrames ? "Yes" : "No")")
									.font(.system(size: 10))
									.foregroundStyle(.tertiary)
							}
						}
						.padding(10)
						.frame(maxWidth: .infinity, alignment: .leading)
						.background(Color(NSColor.controlBackgroundColor).opacity(0.4))
						.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
					}
				}
			}
		}
	}

	private var backgroundSection: some View {
		cardContainer(title: "Background Runtime", icon: "cpu") {
			if let bg = ext.backgroundEntry {
				VStack(alignment: .leading, spacing: 6) {
					HStack(spacing: 6) {
						Text("Type:")
							.font(.system(size: 11, weight: .semibold))
							.foregroundStyle(.secondary)
						Text(bg.isModule ? "Module Service Worker" : "Standard Script")
							.font(.system(size: 11))
					}

					HStack(spacing: 6) {
						Text("Scripts:")
							.font(.system(size: 11, weight: .semibold))
							.foregroundStyle(.secondary)
						Text(bg.scripts.joined(separator: ", "))
							.font(.system(size: 11, design: .monospaced))
					}

					HStack(spacing: 6) {
						Text("Origin:")
							.font(.system(size: 11, weight: .semibold))
							.foregroundStyle(.secondary)
						Text("ext-bg://\(ext.id)/")
							.font(.system(size: 11, design: .monospaced))
					}
				}
			} else {
				Text("No background entry declared.")
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
			}
		}
	}

	private var actionSection: some View {
		cardContainer(title: "Toolbar Action", icon: "menubar.rectangle") {
			if let act = ext.action {
				VStack(alignment: .leading, spacing: 6) {
					if let title = act.defaultTitle {
						HStack(spacing: 6) {
							Text("Title:")
								.font(.system(size: 11, weight: .semibold))
								.foregroundStyle(.secondary)
							Text(title)
								.font(.system(size: 11))
						}
					}
					if let popup = act.defaultPopup {
						HStack(spacing: 6) {
							Text("Popup:")
								.font(.system(size: 11, weight: .semibold))
								.foregroundStyle(.secondary)
							Text(popup)
								.font(.system(size: 11, design: .monospaced))
						}
					}
				}
			} else {
				Text("No toolbar action declared.")
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
			}
		}
	}

	private var fileInfoSection: some View {
		cardContainer(title: "Disk & Storage", icon: "internaldrive") {
			VStack(alignment: .leading, spacing: 6) {
				let installPath = ExtensionInstaller.shared.storageDirectory.appendingPathComponent(
					ext.id
				).path
				let storePath = ExtensionStorage.shared.baseDirectory.appendingPathComponent(
					"\(ext.id).json"
				).path

				HStack(alignment: .top, spacing: 6) {
					Text("Location:")
						.font(.system(size: 11, weight: .semibold))
						.foregroundStyle(.secondary)
					Text(installPath)
						.font(.system(size: 10, design: .monospaced))
						.lineLimit(1)
						.truncationMode(.middle)
				}

				HStack(alignment: .top, spacing: 6) {
					Text("Storage:")
						.font(.system(size: 11, weight: .semibold))
						.foregroundStyle(.secondary)
					Text(storePath)
						.font(.system(size: 10, design: .monospaced))
						.lineLimit(1)
						.truncationMode(.middle)
				}
			}
		}
	}

	private func cardContainer<Content: View>(
		title: String, icon: String, @ViewBuilder content: () -> Content
	) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 6) {
				Image(systemName: icon)
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
				Text(title)
					.font(.system(size: 13, weight: .semibold))
			}

			VStack(alignment: .leading, spacing: 6) {
				content()
			}
			.padding(14)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(Color(NSColor.controlBackgroundColor).opacity(0.5))
			.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 10, style: .continuous)
					.strokeBorder(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
			)
		}
	}

	private func iconForPermission(_ perm: String) -> String {
		let p = perm.lowercased()
		if p.contains("storage") { return "cylinder.split.1x2" }
		if p.contains("tab") { return "rectangle.stack" }
		if p.contains("web") { return "globe" }
		if p.contains("cookie") { return "circle.grid.2x2" }
		if p.contains("download") { return "arrow.down.circle" }
		if p.contains("notification") { return "bell" }
		return "lock.shield"
	}
}

// MARK: - Flow Layout for chips

struct FlowLayout: Layout {
	var spacing: CGFloat = 6

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let width = proposal.width ?? .infinity
		var currentX: CGFloat = 0
		var currentY: CGFloat = 0
		var lineHeight: CGFloat = 0

		for subview in subviews {
			let size = subview.sizeThatFits(.unspecified)
			if currentX + size.width > width && currentX > 0 {
				currentX = 0
				currentY += lineHeight + spacing
				lineHeight = 0
			}
			currentX += size.width + spacing
			lineHeight = max(lineHeight, size.height)
		}

		return CGSize(width: width, height: currentY + lineHeight)
	}

	func placeSubviews(
		in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
	) {
		var currentX: CGFloat = bounds.minX
		var currentY: CGFloat = bounds.minY
		var lineHeight: CGFloat = 0

		for subview in subviews {
			let size = subview.sizeThatFits(.unspecified)
			if currentX + size.width > bounds.maxX && currentX > bounds.minX {
				currentX = bounds.minX
				currentY += lineHeight + spacing
				lineHeight = 0
			}
			subview.place(
				at: CGPoint(x: currentX, y: currentY),
				proposal: ProposedViewSize(size)
			)
			currentX += size.width + spacing
			lineHeight = max(lineHeight, size.height)
		}
	}
}

// MARK: - Tab 2: Extension Preference View (Options Page)

struct ExtensionPreferenceView: View {
	let ext: ExtensionDescriptor
	@State private var reloadToken = UUID()

	var body: some View {
		VStack(spacing: 0) {
			if let optionsPage = ext.optionsPage {
				HStack(spacing: 8) {
					Text("ext-ui://\(ext.id)/\(optionsPage)")
						.font(.system(size: 11, design: .monospaced))
						.foregroundStyle(.secondary)

					Spacer()

					Button {
						reloadToken = UUID()
					} label: {
						Label("Reload", systemImage: "arrow.clockwise")
					}
					.buttonStyle(.bordered)
					.controlSize(.small)
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 8)
				.background(Color(NSColor.controlBackgroundColor).opacity(0.3))

				Divider()

				OptionsWebViewRepresentable(
					extensionId: ext.id,
					optionsPage: optionsPage,
					reloadToken: reloadToken
				)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				noOptionsPageView
			}
		}
	}

	private var noOptionsPageView: some View {
		VStack(spacing: 14) {
			Image(systemName: "slider.horizontal.3")
				.font(.system(size: 40))
				.foregroundStyle(.tertiary)

			VStack(spacing: 4) {
				Text("No Preferences Page Declared")
					.font(.system(size: 14, weight: .semibold))

				Text(
					"This extension does not declare an \"options_ui\" or \"options_page\" in its manifest."
				)
				.font(.system(size: 12))
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.frame(maxWidth: 340)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

// MARK: - Options WebView Representable

struct OptionsWebViewRepresentable: NSViewRepresentable {
	let extensionId: String
	let optionsPage: String
	let reloadToken: UUID

	func makeNSView(context: Context) -> WKWebView {
		let config = WKWebViewConfiguration()
		config.setURLSchemeHandler(ExtensionRuntime.shared, forURLScheme: "ext-ui")
		config.setURLSchemeHandler(ExtensionRuntime.shared, forURLScheme: "ext-bg")
		config.preferences.setValue(false, forKey: "webSecurityEnabled")
		config.defaultWebpagePreferences.allowsContentJavaScript = true

		let userContent = config.userContentController
		userContent.add(
			WeakScriptMessageHandler(delegate: ExtensionRuntime.shared), name: "hostBridge")

		let dir = ExtensionInstaller.shared.storageDirectory.appendingPathComponent(
			extensionId, isDirectory: true)
		let messages = ExtensionInstaller.shared.loadLocaleMessages(in: dir, defaultLocale: nil)
		let messagesData =
			(try? JSONSerialization.data(withJSONObject: messages)) ?? Data("{}".utf8)
		let messagesJson = String(data: messagesData, encoding: .utf8) ?? "{}"

		let shimURL = Bundle.main.url(
			forResource: "chrome-shim", withExtension: "js", subdirectory: "shim")
		if let shimURL = shimURL, let shimCode = try? String(contentsOf: shimURL, encoding: .utf8) {
			let initScript = """
				window.__HOST_EXTENSION_ID__ = '\(extensionId)';
				window.__HOST_I18N_MESSAGES__ = \(messagesJson);
				\(shimCode)
				"""
			let userScript = WKUserScript(
				source: initScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
			userContent.addUserScript(userScript)
		}

		let webView = WKWebView(frame: .zero, configuration: config)
		if #available(macOS 13.3, *) {
			webView.isInspectable = true
		}
		if let url = URL(string: "ext-ui://\(extensionId)/\(optionsPage)") {
			webView.load(URLRequest(url: url))
		}
		return webView
	}

	func updateNSView(_ nsView: WKWebView, context: Context) {
		if context.coordinator.lastReloadToken != reloadToken {
			context.coordinator.lastReloadToken = reloadToken
			if let url = URL(string: "ext-ui://\(extensionId)/\(optionsPage)") {
				nsView.load(URLRequest(url: url))
			}
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(reloadToken: reloadToken)
	}

	final class Coordinator {
		var lastReloadToken: UUID
		init(reloadToken: UUID) {
			self.lastReloadToken = reloadToken
		}
	}
}

// MARK: - Tab 3: Extension Background View with Console Utilities

struct ExtensionBackgroundView: View {
	let ext: ExtensionDescriptor
	@State private var consoleLogs: [ConsoleLogEntry] = []
	@State private var replCommand: String = ""
	@State private var isEvaluating = false
	@State private var filterLevel: ConsoleLogFilter = .all
	@State private var logSearch: String = ""
	@State private var viewMode: BackgroundViewMode = .console

	enum BackgroundViewMode: String, CaseIterable, Identifiable {
		case console = "Console"
		case split = "Split"
		case webView = "Page View"
		var id: String { rawValue }
	}

	enum ConsoleLogFilter: String, CaseIterable, Identifiable {
		case all = "All"
		case logs = "Logs"
		case warnings = "Warnings"
		case errors = "Errors"
		var id: String { rawValue }
	}

	var filteredLogs: [ConsoleLogEntry] {
		var logs = consoleLogs
		switch filterLevel {
		case .all: break
		case .logs: logs = logs.filter { $0.level == .log || $0.level == .info }
		case .warnings: logs = logs.filter { $0.level == .warn }
		case .errors: logs = logs.filter { $0.level == .error }
		}
		let query = logSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard !query.isEmpty else { return logs }
		return logs.filter { $0.message.lowercased().contains(query) }
	}

	var body: some View {
		VStack(spacing: 0) {
			headerControlBar

			Divider()

			switch viewMode {
			case .console:
				consoleArea
			case .split:
				VSplitView {
					BackgroundWebViewRepresentable(extensionId: ext.id)
						.frame(minHeight: 140)
					consoleArea
						.frame(minHeight: 180)
				}
			case .webView:
				BackgroundWebViewRepresentable(extensionId: ext.id)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
		.onAppear {
			loadLogs()
		}
		.onReceive(
			NotificationCenter.default.publisher(for: NSNotification.Name("WirtConsoleLogsUpdated"))
		) {
			notif in
			guard let id = notif.userInfo?["extensionId"] as? String,
				id == ext.id.lowercased()
			else { return }
			loadLogs()
		}
	}

	private func loadLogs() {
		consoleLogs = ExtensionRuntime.shared.getConsoleLogs(for: ext.id)
	}

	private var headerControlBar: some View {
		HStack(spacing: 12) {
			HStack(spacing: 6) {
				Circle()
					.fill(Color.green)
					.frame(width: 7, height: 7)
				Text("Runtime Active")
					.font(.system(size: 11, weight: .semibold))
				Text("ext-bg://\(ext.id)/")
					.font(.system(size: 11, design: .monospaced))
					.foregroundStyle(.secondary)
			}

			Spacer()

			Picker("", selection: $viewMode) {
				ForEach(BackgroundViewMode.allCases) { mode in
					Text(mode.rawValue).tag(mode)
				}
			}
			.pickerStyle(.segmented)
			.frame(width: 220)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
		.background(Color(NSColor.controlBackgroundColor).opacity(0.3))
	}

	private var consoleArea: some View {
		VStack(spacing: 0) {
			consoleFilterBar

			Divider()

			consoleLogList

			Divider()

			replInputBar
		}
	}

	private var consoleFilterBar: some View {
		HStack(spacing: 8) {
			Picker("", selection: $filterLevel) {
				ForEach(ConsoleLogFilter.allCases) { filter in
					Text(filter.rawValue).tag(filter)
				}
			}
			.pickerStyle(.segmented)
			.frame(width: 240)

			HStack(spacing: 4) {
				Image(systemName: "magnifyingglass")
					.font(.system(size: 10))
					.foregroundStyle(.tertiary)
				TextField("Filter logs…", text: $logSearch)
					.textFieldStyle(.plain)
					.font(.system(size: 11))
			}
			.padding(.horizontal, 6)
			.padding(.vertical, 3)
			.background(Color(NSColor.controlBackgroundColor).opacity(0.8))
			.clipShape(RoundedRectangle(cornerRadius: 6))
			.frame(maxWidth: 180)

			Spacer()

			Text("\(filteredLogs.count) logs")
				.font(.system(size: 10, design: .monospaced))
				.foregroundStyle(.tertiary)

			Button {
				let text = filteredLogs.map { "[\($0.level.rawValue.uppercased())] \($0.message)" }
					.joined(separator: "\n")
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(text, forType: .string)
			} label: {
				Image(systemName: "doc.on.doc")
					.font(.system(size: 11))
			}
			.buttonStyle(.plain)
			.foregroundStyle(.secondary)
			.help("Copy all logs")

			Button {
				ExtensionRuntime.shared.clearConsoleLogs(for: ext.id)
				consoleLogs = []
			} label: {
				Image(systemName: "trash")
					.font(.system(size: 11))
			}
			.buttonStyle(.plain)
			.foregroundStyle(.secondary)
			.help("Clear logs")
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 6)
		.background(Color(NSColor.controlBackgroundColor).opacity(0.2))
	}

	private var consoleLogList: some View {
		ScrollViewReader { proxy in
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 2) {
					if filteredLogs.isEmpty {
						HStack {
							Spacer()
							Text("Console output will appear here.")
								.font(.system(size: 11, design: .monospaced))
								.foregroundStyle(.tertiary)
								.padding(.top, 40)
							Spacer()
						}
					} else {
						ForEach(filteredLogs) { log in
							consoleLogRow(log)
								.id(log.id)
						}
					}
				}
				.padding(8)
			}
			.background(Color(NSColor.textBackgroundColor))
			.onChange(of: filteredLogs.count) { _ in
				if let last = filteredLogs.last {
					withAnimation {
						proxy.scrollTo(last.id, anchor: .bottom)
					}
				}
			}
		}
	}

	private func consoleLogRow(_ log: ConsoleLogEntry) -> some View {
		HStack(alignment: .top, spacing: 6) {
			Text(logTimeFormatter.string(from: log.timestamp))
				.font(.system(size: 10, design: .monospaced))
				.foregroundStyle(.tertiary)

			Image(systemName: log.level.icon)
				.font(.system(size: 10))
				.foregroundStyle(colorForLogLevel(log.level))
				.frame(width: 12)

			Text(log.message)
				.font(.system(size: 11, design: .monospaced))
				.foregroundStyle(colorForLogLevel(log.level))
				.textSelection(.enabled)

			Spacer(minLength: 0)
		}
		.padding(.vertical, 2)
		.padding(.horizontal, 4)
		.background(
			log.level == .error
				? Color.red.opacity(0.08)
				: (log.level == .warn ? Color.orange.opacity(0.08) : Color.clear)
		)
		.clipShape(RoundedRectangle(cornerRadius: 4))
	}

	private var replInputBar: some View {
		HStack(spacing: 8) {
			Text(">")
				.font(.system(size: 12, weight: .bold, design: .monospaced))
				.foregroundStyle(Color.accentColor)

			TextField("Evaluate JavaScript in background runtime…", text: $replCommand)
				.textFieldStyle(.plain)
				.font(.system(size: 12, design: .monospaced))
				.onSubmit {
					executeRepl()
				}

			if isEvaluating {
				ProgressView()
					.controlSize(.small)
			} else {
				Button {
					executeRepl()
				} label: {
					Image(systemName: "arrow.up.circle.fill")
						.font(.system(size: 14))
				}
				.buttonStyle(.plain)
				.foregroundStyle(
					replCommand.trimmingCharacters(in: .whitespaces).isEmpty
						? Color.secondary : Color.accentColor
				)
				.disabled(replCommand.trimmingCharacters(in: .whitespaces).isEmpty)
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.background(Color(NSColor.controlBackgroundColor).opacity(0.4))
	}

	private func executeRepl() {
		let cmd = replCommand.trimmingCharacters(in: .whitespaces)
		guard !cmd.isEmpty, !isEvaluating else { return }
		isEvaluating = true
		replCommand = ""

		ExtensionRuntime.shared.addConsoleLog(
			ConsoleLogEntry(level: .log, message: "> \(cmd)"),
			for: ext.id
		)

		Task {
			let (res, err) = await ExtensionRuntime.shared.evaluateConsoleScript(cmd, for: ext.id)
			await MainActor.run {
				isEvaluating = false
				if let err = err {
					ExtensionRuntime.shared.addConsoleLog(
						ConsoleLogEntry(level: .error, message: "< \(err)"),
						for: ext.id
					)
				} else if let res = res {
					ExtensionRuntime.shared.addConsoleLog(
						ConsoleLogEntry(level: .info, message: "< \(res)"),
						for: ext.id
					)
				}
			}
		}
	}

	private func colorForLogLevel(_ level: ConsoleLogEntry.LogLevel) -> Color {
		switch level {
		case .log: return .primary
		case .info: return .blue
		case .warn: return .orange
		case .error: return .red
		}
	}

	private var logTimeFormatter: DateFormatter {
		let df = DateFormatter()
		df.dateFormat = "HH:mm:ss.SSS"
		return df
	}
}

// MARK: - Background WKWebView Representable

struct BackgroundWebViewRepresentable: NSViewRepresentable {
	let extensionId: String

	func makeNSView(context: Context) -> NSView {
		let container = NSView()
		if let webView = ExtensionRuntime.shared.getBackgroundWebView(for: extensionId) {
			webView.autoresizingMask = [.width, .height]
			webView.frame = container.bounds
			container.addSubview(webView)
		}
		return container
	}

	func updateNSView(_ nsView: NSView, context: Context) {
		guard let webView = ExtensionRuntime.shared.getBackgroundWebView(for: extensionId) else {
			return
		}
		if webView.superview != nsView {
			nsView.subviews.forEach { $0.removeFromSuperview() }
			webView.autoresizingMask = [.width, .height]
			webView.frame = nsView.bounds
			nsView.addSubview(webView)
		}
	}
}
