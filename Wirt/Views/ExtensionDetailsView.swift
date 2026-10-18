import AppKit
import SwiftUI

// MARK: - Tab 1: Extension Details View

struct ExtensionDetailsView: View {
	let ext: ExtensionDescriptor
	@Binding var isScrolled: Bool
	@ObservedObject private var state = AppState.shared
	@State private var copiedLocation = false
	@State private var copiedStorage = false
	@State private var showUninstallAlert = false

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				headerBanner

				Divider()

				VStack(alignment: .leading, spacing: 14) {
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
		.scrollGeometryTracker(isScrolled: $isScrolled)
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
						.lineLimit(2)
						.layoutPriority(1)

					Text("v\(ext.version)")
						.font(.system(size: 11, weight: .semibold, design: .monospaced))
						.lineLimit(1)
						.fixedSize(horizontal: true, vertical: false)
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.background(Color(NSColor.quaternaryLabelColor))
						.clipShape(Capsule())
				}

				if let author = ext.author, !author.isEmpty {
					Text("By \(author)")
						.font(.system(size: 11))
						.foregroundStyle(.secondary)
				}

				HStack(spacing: 8) {
					badgePill(text: "Manifest V\(ext.manifestVersion)", icon: "gearshape")
					badgePill(text: "\(ext.permissions.count) Permissions", icon: "lock.shield")
				}
				.padding(.top, 4)
			}
			.frame(maxWidth: .infinity, alignment: .leading)

			Spacer(minLength: 4)

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
			.fixedSize(horizontal: true, vertical: false)
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
				.interpolation(.high)
				.antialiased(true)
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
				.lineLimit(1)
		}
		.fixedSize(horizontal: true, vertical: false)
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
								.lineLimit(1)
						}
						.fixedSize(horizontal: true, vertical: false)
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
				VStack(alignment: .leading, spacing: 0) {
					ForEach(Array(ext.contentScripts.enumerated()), id: \.offset) { idx, cs in
						VStack(alignment: .leading, spacing: 6) {
							if !cs.js.isEmpty {
								HStack(spacing: 6) {
									Text("JS:")
										.font(.system(size: 11, weight: .semibold))
										.foregroundStyle(.secondary)
									Text(cs.js.joined(separator: ", "))
										.font(.system(size: 11, design: .monospaced))
								}
							}

							HStack(alignment: .top, spacing: 6) {
								Text("Matches:")
									.font(.system(size: 11, weight: .semibold))
									.foregroundStyle(.secondary)
									.padding(.top, 2)
								FlowLayout(spacing: 6) {
									ForEach(cs.matches, id: \.self) { match in
										Text(match)
											.font(
												.system(
													size: 10, weight: .medium, design: .monospaced)
											)
											.lineLimit(1)
											.fixedSize(horizontal: true, vertical: false)
											.padding(.horizontal, 6)
											.padding(.vertical, 2)
											.background(Color.accentColor.opacity(0.1))
											.clipShape(RoundedRectangle(cornerRadius: 4))
									}
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
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.top, idx > 0 ? nil : 0)
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
						Text(
							bg.page != nil
								? "Background Page"
								: (bg.isModule ? "Module Service Worker" : "Standard Script")
						)
						.font(.system(size: 11))
					}

					HStack(spacing: 6) {
						Text(bg.page != nil ? "Page:" : "Scripts:")
							.font(.system(size: 11, weight: .semibold))
							.foregroundStyle(.secondary)
						Text(bg.page ?? bg.scripts.joined(separator: ", "))
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
			VStack(alignment: .leading, spacing: 8) {
				let installPath = ExtensionInstaller.shared.storageDirectory.appendingPathComponent(
					ext.id
				).path
				let storePath = ExtensionStorage.shared.baseDirectory.appendingPathComponent(
					"\(ext.id).json"
				).path

				HStack(spacing: 6) {
					Text("Location:")
						.font(.system(size: 11, weight: .semibold))
						.foregroundStyle(.secondary)
					Text(installPath)
						.font(.system(size: 10, design: .monospaced))
						.lineLimit(1)
						.truncationMode(.middle)

					Button {
						NSPasteboard.general.clearContents()
						NSPasteboard.general.setString(installPath, forType: .string)
						copiedLocation = true
						DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
							copiedLocation = false
						}
					} label: {
						ZStack {
							Image(systemName: "checkmark")
								.opacity(copiedLocation ? 1 : 0)
							Image(systemName: "doc.on.doc")
								.opacity(copiedLocation ? 0 : 1)
						}
						.font(.system(size: 10))
						.frame(width: 14, height: 14)
					}
					.buttonStyle(.plain)
					.foregroundStyle(copiedLocation ? Color.green : Color.secondary)
					.help("Copy Location Path")
				}

				HStack(spacing: 6) {
					Text("Storage:")
						.font(.system(size: 11, weight: .semibold))
						.foregroundStyle(.secondary)
					Text(storePath)
						.font(.system(size: 10, design: .monospaced))
						.lineLimit(1)
						.truncationMode(.middle)

					Button {
						NSPasteboard.general.clearContents()
						NSPasteboard.general.setString(storePath, forType: .string)
						copiedStorage = true
						DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
							copiedStorage = false
						}
					} label: {
						ZStack {
							Image(systemName: "checkmark")
								.opacity(copiedStorage ? 1 : 0)
							Image(systemName: "doc.on.doc")
								.opacity(copiedStorage ? 0 : 1)
						}
						.font(.system(size: 10))
						.frame(width: 14, height: 14)
					}
					.buttonStyle(.plain)
					.foregroundStyle(copiedStorage ? Color.green : Color.secondary)
					.help("Copy Storage Path")
				}
			}
		}
	}

	private func cardContainer<Content: View>(
		title: String, icon: String, @ViewBuilder content: () -> Content
	) -> some View {
		VStack(alignment: .leading, spacing: 12) {
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
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.padding(14)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(NSColor.quaternaryLabelColor))
		.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
	}

	private func iconForPermission(_ perm: String) -> String {
		let p = perm.lowercased()
		if p.contains("alarm") { return "alarm" }
		if p.contains("contextmenu") { return "contextualmenu.and.pointer.arrow" }
		if p.contains("theme") { return "paintpalette" }
		if p.contains("url") || p.contains("*://") || p.contains("http") { return "globe" }
		if p.contains("storage") { return "cylinder.split.1x2" }
		if p.contains("tab") { return "rectangle.stack" }
		if p.contains("web") { return "globe" }
		if p.contains("cookie") { return "circle.grid.2x2" }
		if p.contains("download") { return "arrow.down.circle" }
		if p.contains("notification") { return "bell" }
		if p.contains("setting") { return "gearshape" }
		if p.contains("management") { return "wrench.and.screwdriver" }
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

// MARK: - Scroll Geometry Tracker

extension View {
	@ViewBuilder
	func scrollGeometryTracker(isScrolled: Binding<Bool>) -> some View {
		if #available(macOS 15.0, *) {
			self.onScrollGeometryChange(for: Bool.self) { geo in
				geo.contentOffset.y + geo.contentInsets.top > 0
			} action: { _, scrolled in
				if isScrolled.wrappedValue != scrolled {
					DispatchQueue.main.async {
						isScrolled.wrappedValue = scrolled
					}
				}
			}
		} else {
			self.coordinateSpace(name: "detailScroll")
				.background(
					GeometryReader { proxy in
						Color.clear.preference(
							key: ScrollOffsetPreferenceKey.self,
							value: proxy.frame(in: .named("detailScroll")).minY
						)
					}
				)
				.onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
					let scrolled = offset < -1
					if isScrolled.wrappedValue != scrolled {
						DispatchQueue.main.async {
							isScrolled.wrappedValue = scrolled
						}
					}
				}
		}
	}
}
