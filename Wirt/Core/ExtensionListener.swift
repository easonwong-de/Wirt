import AppKit
import os.log

public final class ExtensionListener: NSObject, NSXPCListenerDelegate, HostXPCProtocol {
	public static let shared = ExtensionListener()

	private var listener: NSXPCListener?

	public func start() {
		guard listener == nil else { return }
		let listener = NSXPCListener(machServiceName: HostXPC.serviceName)
		listener.delegate = self
		listener.resume()
		self.listener = listener
		os_log(.default, "ExtensionListener resumed on Mach service: %@", HostXPC.serviceName)
	}

	public func showSettings(withReply reply: @escaping () -> Void) {
		Task { @MainActor in
			(NSApp.delegate as? AppDelegate)?.showSettings()
			reply()
		}
	}

	public func listener(
		_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection
	) -> Bool {
		os_log(.default, "ExtensionListener accepting incoming connection")
		newConnection.exportedInterface = NSXPCInterface(with: HostXPCProtocol.self)
		newConnection.exportedObject = self
		newConnection.interruptionHandler = {
			os_log(.default, "ExtensionListener connection interrupted")
		}
		newConnection.invalidationHandler = {
			os_log(.default, "ExtensionListener connection invalidated")
		}
		newConnection.resume()
		return true
	}

	public func handleExtensionMessage(
		_ message: [String: Any], withReply reply: @escaping ([String: Any]) -> Void
	) {
		let type = message["type"] as? String ?? ""
		switch type {
		case "GET_INSTALLED_EXTENSIONS":
			Task { @MainActor in
				let extensions = self.getInstalledExtensionsPayload()
				reply(["status": "success", "extensions": extensions])
			}

		case "DISPATCH_ACTION_CLICK":
			let extId = message["extensionId"] as? String ?? ""
			let tab = message["tab"] as? [String: Any] ?? [:]
			Task { @MainActor in
				ExtensionRuntime.shared.dispatchActionClick(extensionId: extId, tabMetadata: tab)
				reply(["status": "success"])
			}

		case "GET_MATCHING_SCRIPTS":
			let pageUrl = message["url"] as? String ?? ""
			Task { @MainActor in
				let matching = ExtensionRuntime.shared.getMatchingScripts(for: pageUrl)
				reply(["matchingExtensions": matching])
			}

		case "RUNTIME_SEND_MESSAGE":
			let extId = message["extensionId"] as? String ?? ""
			let source = message["source"] as? [String: Any] ?? [:]
			let payload = message["payload"] ?? [:]
			Task { @MainActor in
				ExtensionRuntime.shared.dispatchRuntimeMessage(
					extensionId: extId, source: source, payload: payload
				) { result in
					reply(result)
				}
			}

		case "STORAGE_GET":
			let extId = message["extensionId"] as? String ?? ""
			let keys = message["keys"]
			let data = ExtensionStorage.shared.get(extensionId: extId, keys: keys)
			reply(["status": "success", "data": data])

		case "STORAGE_SET":
			let extId = message["extensionId"] as? String ?? ""
			let items = message["items"] as? [String: Any] ?? [:]
			ExtensionStorage.shared.set(extensionId: extId, items: items)
			reply(["status": "success"])

		case "STORAGE_REMOVE":
			let extId = message["extensionId"] as? String ?? ""
			let keys = message["keys"] as? [String] ?? []
			ExtensionStorage.shared.remove(extensionId: extId, keys: keys)
			reply(["status": "success"])

		case "STORAGE_CLEAR":
			let extId = message["extensionId"] as? String ?? ""
			ExtensionStorage.shared.clear(extensionId: extId)
			reply(["status": "success"])

		case "GET_POPUP_RESOURCES":
			let extId = message["extensionId"] as? String ?? ""
			let popupPath = message["popupPath"] as? String ?? ""
			let html = self.loadPopupHtml(extensionId: extId, popupPath: popupPath)
			reply(["status": "success", "html": html])

		case "INSTALL_PACKAGE_FROM_URL":
			let downloadUrl = message["downloadUrl"] as? String ?? ""
			if let url = URL(string: downloadUrl) {
				Task {
					do {
						let descriptor = try await ExtensionInstaller.shared.ingest(from: url)
						await MainActor.run {
							let dir = ExtensionInstaller.shared.storageDirectory
								.appendingPathComponent(
									descriptor.id, isDirectory: true)
							ExtensionRuntime.shared.startBackgroundRuntime(
								for: descriptor, directory: dir)
							AppState.shared.loadInstalledExtensions()
						}
						reply([
							"status": "success", "extensionId": descriptor.id,
							"name": descriptor.name,
						])
					} catch {
						reply(["status": "error", "message": error.localizedDescription])
					}
				}
			} else {
				reply(["status": "error", "message": "Invalid URL"])
			}

		case "OPEN_HOST_APP":
			Task { @MainActor in
				(NSApp.delegate as? AppDelegate)?.showSettings()
				reply(["status": "success"])
			}

		case "UNINSTALL_PACKAGE":
			let extId = message["extensionId"] as? String ?? ""
			guard !extId.isEmpty else {
				reply(["status": "error", "message": "Missing extensionId"])
				return
			}
			Task { @MainActor in
				ExtensionRuntime.shared.stopBackgroundRuntime(for: extId)
				do {
					try ExtensionInstaller.shared.uninstall(extensionId: extId)
					ExtensionStorage.shared.deleteStorage(for: extId)
					AppState.shared.loadInstalledExtensions()
					reply(["status": "success", "extensionId": extId])
				} catch {
					reply(["status": "error", "message": error.localizedDescription])
				}
			}

		default:
			reply(["status": "unknown_message", "type": type])
		}
	}

	private func loadPopupHtml(extensionId: String, popupPath: String) -> String {
		let baseDir = ExtensionInstaller.shared.storageDirectory.appendingPathComponent(
			extensionId, isDirectory: true)
		let cleanedPath = popupPath.hasPrefix("/") ? String(popupPath.dropFirst()) : popupPath
		let fileUrl = baseDir.appendingPathComponent(cleanedPath)

		guard let content = try? String(contentsOf: fileUrl, encoding: .utf8) else {
			return "<html><body><p>Popup not found.</p></body></html>"
		}

		let messages = ExtensionInstaller.shared.loadLocaleMessages(in: baseDir, defaultLocale: nil)
		let messagesData =
			(try? JSONSerialization.data(withJSONObject: messages)) ?? Data("{}".utf8)
		let messagesJson = String(data: messagesData, encoding: .utf8) ?? "{}"

		let resolvedContent = ExtensionInstaller.shared.resolveI18nString(
			content, messages: messages, extensionId: extensionId)

		let shimURL = Bundle.main.url(
			forResource: "chrome-shim", withExtension: "js", subdirectory: "shim")
		let shimCode =
			(shimURL != nil ? (try? String(contentsOf: shimURL!, encoding: .utf8)) : nil) ?? ""
		let injectedHeader = """
			<script>
			window.__HOST_EXTENSION_ID__ = '\(extensionId)';
			window.__HOST_I18N_MESSAGES__ = \(messagesJson);
			\(shimCode)
			</script>
			"""

		if resolvedContent.contains("<head>") {
			return resolvedContent.replacingOccurrences(
				of: "<head>", with: "<head>\(injectedHeader)")
		}
		return injectedHeader + resolvedContent
	}

	@MainActor
	private func getInstalledExtensionsPayload() -> [[String: Any]] {
		let storageDir = ExtensionInstaller.shared.storageDirectory
		guard
			let items = try? FileManager.default.contentsOfDirectory(
				at: storageDir, includingPropertiesForKeys: nil)
		else {
			return []
		}
		var results: [[String: Any]] = []
		for item in items where item.hasDirectoryPath {
			if let desc = try? ExtensionInstaller.shared.parseManifest(
				in: item, fallbackId: item.lastPathComponent)
			{
				var actionType = "none"
				var popupPath = ""
				if let action = desc.action {
					if let pop = action.defaultPopup, !pop.isEmpty {
						actionType = "popup"
						popupPath = pop
					} else {
						actionType = "click"
					}
				}
				results.append([
					"id": desc.id,
					"name": desc.name,
					"description": desc.description,
					"version": desc.version,
					"actionType": actionType,
					"popupPath": popupPath,
					"badgeText": "",
					"badgeColor": "#0071e3",
					"iconUrl": desc.iconUrl ?? "",
				])
			}
		}
		return results
	}
}
