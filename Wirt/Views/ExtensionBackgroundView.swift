import AppKit
import SwiftUI
import WebKit

// MARK: - Tab 3: Extension Background View with Inspectable WebView

struct ExtensionBackgroundView: View {
	let ext: ExtensionDescriptor
	@ObservedObject private var state = AppState.shared
	@State private var reloadToken = UUID()

	private var hasBackground: Bool {
		guard let bg = ext.backgroundEntry else { return false }
		return !bg.scripts.isEmpty || bg.page != nil
	}

	var body: some View {
		VStack(spacing: 0) {
			if hasBackground {
				headerControlBar

				Divider()

				BackgroundWebViewRepresentable(
					extensionId: ext.id,
					reloadToken: reloadToken
				)
				.id("\(ext.id)-\(reloadToken)")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				noBackgroundPlaceholder
			}
		}
	}

	private var headerControlBar: some View {
		HStack(spacing: 8) {
			let target = ext.backgroundEntry?.page ?? (ext.backgroundEntry?.scripts.first ?? "")
			Text("ext-bg://\(ext.id)/\(target)")
				.font(.system(size: 11, design: .monospaced))
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.truncationMode(.middle)

			Spacer()

			Button {
				if let webView = ExtensionRuntime.shared.getBackgroundWebView(for: ext.id) {
					ExtensionRuntime.shared.showInspector(for: webView)
				}
			} label: {
				Label("Inspect", systemImage: "sparkles.rectangle.stack")
			}
			.buttonStyle(.bordered)
			.controlSize(.small)
			.help("Open Web Inspector")

			Button {
				state.reloadExtension(id: ext.id)
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
	}

	private var noBackgroundPlaceholder: some View {
		VStack(spacing: 14) {
			Image(systemName: "gearshape.2")
				.font(.system(size: 40))
				.foregroundStyle(.tertiary)

			VStack(spacing: 4) {
				Text("No Background Script Declared")
					.font(.system(size: 14, weight: .semibold))

				Text("This extension does not specify a background page or script in its manifest.")
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.frame(maxWidth: 340)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

// MARK: - Background WebView Representable

struct BackgroundWebViewRepresentable: NSViewRepresentable {
	let extensionId: String
	let reloadToken: UUID

	func makeNSView(context: Context) -> HostContainerView {
		let container = HostContainerView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
		attachWebView(to: container)
		return container
	}

	func updateNSView(_ nsView: HostContainerView, context: Context) {
		if context.coordinator.lastExtensionId != extensionId
			|| context.coordinator.lastReloadToken != reloadToken
		{
			context.coordinator.lastExtensionId = extensionId
			context.coordinator.lastReloadToken = reloadToken
			attachWebView(to: nsView)
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(extensionId: extensionId, reloadToken: reloadToken)
	}

	final class Coordinator {
		var lastExtensionId: String
		var lastReloadToken: UUID
		init(extensionId: String, reloadToken: UUID) {
			self.lastExtensionId = extensionId
			self.lastReloadToken = reloadToken
		}
	}

	private func attachWebView(to container: HostContainerView) {
		container.subviews.forEach { $0.removeFromSuperview() }

		if ExtensionRuntime.shared.getBackgroundHostView(for: extensionId) == nil {
			let dir = ExtensionInstaller.shared.storageDirectory.appendingPathComponent(
				extensionId, isDirectory: true)
			if let desc = try? ExtensionInstaller.shared.parseManifest(
				in: dir, fallbackId: extensionId)
			{
				ExtensionRuntime.shared.startBackgroundRuntime(for: desc, directory: dir)
			}
		}

		guard let hostView = ExtensionRuntime.shared.getBackgroundHostView(for: extensionId) else {
			return
		}

		container.hostedView = hostView
		if container.bounds.width > 50, container.bounds.height > 50 {
			hostView.frame = container.bounds
		}
		container.addSubview(hostView)
	}
}
