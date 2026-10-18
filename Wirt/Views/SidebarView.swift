import AppKit
import SwiftUI

// MARK: - Sidebar View

struct SidebarView: View {
	@ObservedObject private var state = AppState.shared
	@Binding var columnVisibility: NavigationSplitViewVisibility
	@Environment(\.controlActiveState) private var controlActiveState
	@State private var extensionToUninstall: ExtensionDescriptor?

	private var isWindowFocused: Bool {
		controlActiveState != .inactive
	}

	var body: some View {
		List(selection: $state.selectedExtensionId) {
			ForEach(state.filteredExtensions) { ext in
				let isSelected = ext.id.lowercased() == state.selectedExtensionId?.lowercased()
				SidebarExtensionRow(
					extensionDescriptor: ext,
					isSelected: isSelected,
					isWindowFocused: isWindowFocused
				)
				.tag(ext.id)
				.listRowBackground(
					RoundedRectangle(cornerRadius: 8, style: .continuous)
						.fill(
							isSelected
								? (isWindowFocused
									? Color.accentColor
									: Color(NSColor.unemphasizedSelectedContentBackgroundColor))
								: Color.clear
						)
						.padding(.horizontal, 4)
				)
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
		.overlay {
			if state.filteredExtensions.isEmpty {
				emptyListView
			}
		}
		.searchable(text: $state.searchQuery, placement: .sidebar, prompt: "Search extensions…")
		.toolbar(removing: columnVisibility != .detailOnly ? .sidebarToggle : nil)
		.toolbar {
			if columnVisibility != .detailOnly {
				Spacer()

				Menu {
					Group {
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
					}
					.labelStyle(.titleAndIcon)
				} label: {
					Image(systemName: "plus")
				}
				.menuIndicator(.hidden)
				.liquidGlassButtonStyle()
				.help("Add Extension")
				.disabled(!state.isExtensionEnabled)
			}
		}
		.disabled(!state.isExtensionEnabled)
		.opacity(state.isExtensionEnabled ? 1.0 : 0.45)
		.saturation(state.isExtensionEnabled ? 1.0 : 0.0)
		.onChange(of: state.searchQuery) { _ in
			if let selected = state.selectedExtensionId,
				!state.filteredExtensions.contains(where: {
					$0.id.lowercased() == selected.lowercased()
				})
			{
				state.selectedExtensionId = nil
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
	let isSelected: Bool
	let isWindowFocused: Bool

	var body: some View {
		HStack(spacing: 10) {
			extensionIconView
				.frame(width: 38, height: 38)
				.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
				.overlay(
					RoundedRectangle(cornerRadius: 8, style: .continuous)
						.strokeBorder(
							isSelected && isWindowFocused
								? Color.white.opacity(0.2)
								: Color(NSColor.separatorColor).opacity(0.4),
							lineWidth: 1
						)
				)

			VStack(alignment: .leading, spacing: 2) {
				Text(extensionDescriptor.name)
					.font(.system(size: 13, weight: .medium))
					.foregroundStyle(
						isSelected && isWindowFocused ? Color.white : Color.primary
					)
					.lineLimit(1)

				Text(
					extensionDescriptor.description.isEmpty
						? "No description declared."
						: extensionDescriptor.description
				)
				.font(.system(size: 11))
				.foregroundStyle(
					isSelected && isWindowFocused ? Color.white.opacity(0.8) : Color.secondary
				)
				.lineLimit(3, reservesSpace: true)
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
				.interpolation(.high)
				.antialiased(true)
				.aspectRatio(contentMode: .fit)
		} else {
			ZStack {
				(isSelected && isWindowFocused
					? Color.white.opacity(0.2)
					: Color.accentColor.opacity(0.12))
				Image(systemName: "puzzlepiece.extension.fill")
					.font(.system(size: 18))
					.foregroundStyle(
						isSelected && isWindowFocused ? Color.white : Color.accentColor)
			}
		}
	}
}
