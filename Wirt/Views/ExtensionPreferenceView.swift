import AppKit
import SwiftUI
import WebKit

// MARK: - WebView Reference Holder

final class WebViewHolder {
	weak var webView: WKWebView?
}

// MARK: - Tab 2: Extension Preference View (Options Page)

struct ExtensionPreferenceView: View {
	let ext: ExtensionDescriptor
	@State private var reloadToken = UUID()
	@State private var webViewHolder = WebViewHolder()

	var body: some View {
		VStack(spacing: 0) {
			if let optionsPage = ext.optionsPage {
				HStack(spacing: 8) {
					Text("ext-ui://\(ext.id)/\(optionsPage)")
						.font(.system(size: 11, design: .monospaced))
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)

					Spacer()

					Button {
						if let webView = webViewHolder.webView {
							ExtensionRuntime.shared.showInspector(for: webView)
						}
					} label: {
						Label("Inspect", systemImage: "sparkles.rectangle.stack")
					}
					.buttonStyle(.bordered)
					.controlSize(.small)
					.help("Open Web Inspector")

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
					reloadToken: reloadToken,
					holder: webViewHolder
				)
				.id("\(ext.id)-\(reloadToken)")
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
	let holder: WebViewHolder

	func makeNSView(context: Context) -> WebViewHostView {
		ExtensionRuntime.shared.ensureInspectorStartsAttached()

		let config = WKWebViewConfiguration()
		config.setURLSchemeHandler(ExtensionRuntime.shared, forURLScheme: "ext-ui")
		config.setURLSchemeHandler(ExtensionRuntime.shared, forURLScheme: "ext-bg")
		config.preferences.setValue(false, forKey: "webSecurityEnabled")
		config.preferences.setValue(true, forKey: "developerExtrasEnabled")
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

		let initialRect = NSRect(x: 0, y: 0, width: 800, height: 600)
		let container = WebViewHostView(frame: initialRect)

		let webView = WKWebView(frame: initialRect, configuration: config)
		webView.autoresizingMask = [.width, .height]
		if #available(macOS 12.0, *) {
			webView.underPageBackgroundColor = .windowBackgroundColor
		}
		if #available(macOS 13.3, *) {
			webView.isInspectable = true
		}
		if let url = URL(string: "ext-ui://\(extensionId)/\(optionsPage)") {
			webView.load(URLRequest(url: url))
		}

		container.addSubview(webView)
		holder.webView = webView
		return container
	}

	func updateNSView(_ nsView: WebViewHostView, context: Context) {
		if context.coordinator.lastReloadToken != reloadToken {
			context.coordinator.lastReloadToken = reloadToken
			if let url = URL(string: "ext-ui://\(extensionId)/\(optionsPage)") {
				holder.webView?.load(URLRequest(url: url))
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
