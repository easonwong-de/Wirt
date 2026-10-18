import Foundation
import WebKit

final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
	private weak var delegate: WKScriptMessageHandler?

	init(delegate: WKScriptMessageHandler) {
		self.delegate = delegate
	}

	func userContentController(
		_ userContentController: WKUserContentController, didReceive message: WKScriptMessage
	) {
		delegate?.userContentController(userContentController, didReceive: message)
	}
}

public final class WebViewHostView: NSView {
	public override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		self.clipsToBounds = true
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	public override func resizeSubviews(withOldSize oldSize: NSSize) {
		guard bounds.width > 50, bounds.height > 50 else { return }
		super.resizeSubviews(withOldSize: oldSize)
		if subviews.count == 1, let wv = subviews.first {
			wv.frame = bounds
		} else if subviews.count == 2,
			let ins = subviews.first(where: {
				String(describing: type(of: $0)).contains("Inspector")
			}),
			let wv = subviews.first(where: {
				!String(describing: type(of: $0)).contains("Inspector")
			})
		{
			if ins.frame.minX == 0 && ins.frame.height < bounds.height {
				let insH = min(ins.frame.height, bounds.height - 50)
				ins.frame = NSRect(x: 0, y: 0, width: bounds.width, height: insH)
				wv.frame = NSRect(
					x: 0, y: insH, width: bounds.width, height: bounds.height - insH)
			} else if ins.frame.minX > 0 {
				let insW = min(ins.frame.width, bounds.width - 50)
				wv.frame = NSRect(
					x: 0, y: 0, width: bounds.width - insW, height: bounds.height)
				ins.frame = NSRect(
					x: bounds.width - insW, y: 0, width: insW, height: bounds.height)
			}
		}
	}
}

public final class HostContainerView: NSView {
	public weak var hostedView: NSView?

	public override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		self.clipsToBounds = true
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	public override func layout() {
		super.layout()
		if bounds.width > 50, bounds.height > 50, let hostedView = hostedView {
			hostedView.frame = bounds
		}
	}
}

@MainActor
public final class ExtensionRuntime: NSObject, WKURLSchemeHandler, WKScriptMessageHandler {
	public static let shared = ExtensionRuntime()

	private var backgroundWebViews: [String: WKWebView] = [:]
	private var backgroundHostViews: [String: WebViewHostView] = [:]
	private var pendingReplies: [String: ([String: Any]) -> Void] = [:]
	public private(set) var consoleLogs: [String: [ConsoleLogEntry]] = [:]

	public func getBackgroundWebView(for extensionId: String) -> WKWebView? {
		return backgroundWebViews[extensionId]
			?? backgroundWebViews.first(where: { $0.key.lowercased() == extensionId.lowercased() })?
			.value
	}

	public func getBackgroundHostView(for extensionId: String) -> WebViewHostView? {
		return backgroundHostViews[extensionId]
			?? backgroundHostViews.first(where: {
				$0.key.lowercased() == extensionId.lowercased()
			})?.value
	}

	public func ensureInspectorStartsAttached() {
		UserDefaults.standard.set(
			true,
			forKey: "__WebInspectorPageGroupLevel1__.WebKit2InspectorStartsAttached"
		)
		for key in UserDefaults.standard.dictionaryRepresentation().keys
		where key.hasSuffix("WebKit2InspectorStartsAttached") {
			UserDefaults.standard.set(true, forKey: key)
		}
	}

	public func showInspector(for webView: WKWebView) {
		ensureInspectorStartsAttached()
		guard let inspector = webView.value(forKey: "_inspector") as? NSObject else { return }
		if inspector.responds(to: Selector(("show"))) {
			inspector.perform(Selector(("show")))
		}
		if inspector.responds(to: Selector(("attach"))) {
			inspector.perform(Selector(("attach")))
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
			if inspector.responds(to: Selector(("attach"))) {
				inspector.perform(Selector(("attach")))
			}
		}
	}

	public func getConsoleLogs(for extensionId: String) -> [ConsoleLogEntry] {
		return consoleLogs[extensionId.lowercased()] ?? []
	}

	public func clearConsoleLogs(for extensionId: String) {
		consoleLogs[extensionId.lowercased()] = []
		NotificationCenter.default.post(
			name: NSNotification.Name("WirtConsoleLogsUpdated"),
			object: nil,
			userInfo: ["extensionId": extensionId.lowercased()]
		)
	}

	public func addConsoleLog(_ entry: ConsoleLogEntry, for extensionId: String) {
		let key = extensionId.lowercased()
		var logs = consoleLogs[key] ?? []
		logs.append(entry)
		if logs.count > 1000 {
			logs.removeFirst(logs.count - 1000)
		}
		consoleLogs[key] = logs
		NotificationCenter.default.post(
			name: NSNotification.Name("WirtConsoleLogsUpdated"),
			object: nil,
			userInfo: ["extensionId": key]
		)
	}

	public func evaluateConsoleScript(_ script: String, for extensionId: String) async
		-> (result: String?, error: String?)
	{
		guard let webView = getBackgroundWebView(for: extensionId) else {
			return (nil, "Extension background runtime is not running.")
		}
		do {
			let res = try await webView.evaluateJavaScript(script)
			if let res = res {
				return (String(describing: res), nil)
			}
			return ("undefined", nil)
		} catch {
			return (nil, error.localizedDescription)
		}
	}

	public func bootInstalledExtensions() {
		let storageDir = ExtensionInstaller.shared.storageDirectory
		guard
			let items = try? FileManager.default.contentsOfDirectory(
				at: storageDir, includingPropertiesForKeys: nil)
		else {
			return
		}

		for item in items where item.hasDirectoryPath {
			guard
				let desc = try? ExtensionInstaller.shared.parseManifest(
					in: item, fallbackId: item.lastPathComponent)
			else {
				continue
			}
			if backgroundWebViews[desc.id] == nil {
				startBackgroundRuntime(for: desc, directory: item)
			}
		}
	}

	public func startBackgroundRuntime(for descriptor: ExtensionDescriptor, directory: URL) {
		guard let bg = descriptor.backgroundEntry, !bg.scripts.isEmpty || bg.page != nil else {
			return
		}

		ensureInspectorStartsAttached()

		let config = WKWebViewConfiguration()
		config.setURLSchemeHandler(self, forURLScheme: "ext-bg")
		config.setURLSchemeHandler(self, forURLScheme: "ext-ui")
		config.preferences.setValue(false, forKey: "webSecurityEnabled")
		config.preferences.setValue(true, forKey: "developerExtrasEnabled")
		config.defaultWebpagePreferences.allowsContentJavaScript = true

		let userContent = config.userContentController
		userContent.add(WeakScriptMessageHandler(delegate: self), name: "hostBridge")

		let messages = ExtensionInstaller.shared.loadLocaleMessages(
			in: directory, defaultLocale: nil)
		let messagesData =
			(try? JSONSerialization.data(withJSONObject: messages)) ?? Data("{}".utf8)
		let messagesJson = String(data: messagesData, encoding: .utf8) ?? "{}"

		let shimURL = Bundle.main.url(
			forResource: "chrome-shim", withExtension: "js", subdirectory: "shim")
		if let shimURL = shimURL, let shimCode = try? String(contentsOf: shimURL, encoding: .utf8) {
			let initScript = """
				window.__HOST_EXTENSION_ID__ = '\(descriptor.id)';
				window.__HOST_I18N_MESSAGES__ = \(messagesJson);
				\(shimCode)
				"""
			let userScript = WKUserScript(
				source: initScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
			userContent.addUserScript(userScript)
		}

		let initialRect = NSRect(x: 0, y: 0, width: 800, height: 600)
		let hostView = WebViewHostView(frame: initialRect)

		let webView = WKWebView(frame: initialRect, configuration: config)
		webView.autoresizingMask = [.width, .height]
		if #available(macOS 12.0, *) {
			webView.underPageBackgroundColor = .windowBackgroundColor
		}
		if #available(macOS 13.3, *) {
			webView.isInspectable = true
		}
		hostView.addSubview(webView)
		backgroundWebViews[descriptor.id] = webView
		backgroundHostViews[descriptor.id] = hostView

		if let page = bg.page {
			if let url = URL(string: "ext-bg://\(descriptor.id)/\(page)") {
				webView.load(URLRequest(url: url))
			}
		} else {
			let scriptTags = bg.scripts.map { script in
				if bg.isModule {
					return "<script type=\"module\" src=\"\(script)\"></script>"
				}
				return "<script src=\"\(script)\"></script>"
			}.joined(separator: "\n")

			let syntheticHtml = """
				<!DOCTYPE html>
				<html>
				<head>
				<meta charset="utf-8">
				<meta name="color-scheme" content="light dark">
				<style>
					html, body {
						width: 100%;
						height: 100%;
						margin: 0;
						padding: 0;
						background-color: transparent;
					}
				</style>
				</head>
				<body>
				\(scriptTags)
				</body>
				</html>
				"""
			webView.loadHTMLString(
				syntheticHtml, baseURL: URL(string: "ext-bg://\(descriptor.id)/")!)
		}
	}

	public func stopBackgroundRuntime(for extensionId: String) {
		let target = extensionId.lowercased()
		let matchingKeys = backgroundWebViews.keys.filter { $0.lowercased() == target }
		for key in matchingKeys {
			if let webView = backgroundWebViews.removeValue(forKey: key) {
				webView.stopLoading()
				webView.configuration.userContentController.removeAllScriptMessageHandlers()
			}
			if let hostView = backgroundHostViews.removeValue(forKey: key) {
				hostView.removeFromSuperview()
			}
		}
	}

	public func dispatchRuntimeMessage(
		extensionId: String,
		source: [String: Any],
		payload: Any,
		completion: @escaping ([String: Any]) -> Void
	) {
		guard let webView = backgroundWebViews[extensionId] else {
			completion(["error": "Extension runtime not active"])
			return
		}

		let correlationId = UUID().uuidString
		pendingReplies[correlationId] = completion

		let envelope: [String: Any] = [
			"correlationId": correlationId,
			"message": payload,
			"sender": [
				"id": extensionId,
				"tab": source["tab"] ?? [:],
				"frameId": source["frameId"] ?? 0,
				"url": source["url"] ?? "",
			],
		]

		guard let jsonData = try? JSONSerialization.data(withJSONObject: envelope),
			let jsonStr = String(data: jsonData, encoding: .utf8)
		else {
			pendingReplies.removeValue(forKey: correlationId)
			completion(["error": "Failed to serialize message payload"])
			return
		}

		let script =
			"if (window.__wirtDispatchRuntimeMessage) { window.__wirtDispatchRuntimeMessage(\(jsonStr)); }"
		webView.evaluateJavaScript(script) { _, error in
			if let error = error {
				if let reply = self.pendingReplies.removeValue(forKey: correlationId) {
					reply(["error": error.localizedDescription])
				}
			}
		}
	}

	public func dispatchActionClick(extensionId: String, tabMetadata: [String: Any]) {
		guard let webView = backgroundWebViews[extensionId] else { return }
		let script = """
			if (window.chrome?.action?.onClicked) {
			  for (const fn of window.chrome.action.onClicked.listeners) {
			    fn(tab);
			  }
			}
			"""
		webView.callAsyncJavaScript(script, arguments: ["tab": tabMetadata], in: nil, in: .page)
	}

	public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
		guard let url = urlSchemeTask.request.url else {
			urlSchemeTask.didFailWithError(URLError(.badURL))
			return
		}

		let extId: String
		if let user = url.user, !user.isEmpty, let host = url.host {
			extId = "\(user)@\(host)"
		} else if let host = url.host, !host.isEmpty {
			extId = host
		} else {
			urlSchemeTask.didFailWithError(URLError(.badURL))
			return
		}

		var baseDir = ExtensionInstaller.shared.storageDirectory.appendingPathComponent(
			extId, isDirectory: true
		).standardizedFileURL

		if !FileManager.default.fileExists(atPath: baseDir.path) {
			if let items = try? FileManager.default.contentsOfDirectory(
				at: ExtensionInstaller.shared.storageDirectory, includingPropertiesForKeys: nil)
			{
				if let matched = items.first(where: {
					$0.lastPathComponent.caseInsensitiveCompare(extId) == .orderedSame
				}) {
					baseDir = matched.standardizedFileURL
				}
			}
		}

		let relativePath = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
		let filePath = baseDir.appendingPathComponent(relativePath).standardizedFileURL

		let baseComponents = baseDir.pathComponents
		let fileComponents = filePath.pathComponents
		guard fileComponents.starts(with: baseComponents) else {
			urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
			return
		}

		if let data = try? Data(contentsOf: filePath) {
			let mimeType = mimeForExtension(filePath.pathExtension)
			let response = HTTPURLResponse(
				url: url, statusCode: 200, httpVersion: nil,
				headerFields: [
					"Content-Type": mimeType,
					"Access-Control-Allow-Origin": "*",
				])!
			urlSchemeTask.didReceive(response)
			urlSchemeTask.didReceive(data)
			urlSchemeTask.didFinish()
		} else {
			urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
		}
	}

	public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

	public func userContentController(
		_ userContentController: WKUserContentController, didReceive message: WKScriptMessage
	) {
		guard let dict = message.body as? [String: Any],
			let api = dict["api"] as? String
		else {
			return
		}

		let extId = dict["extensionId"] as? String ?? ""
		let requestId = dict["requestId"] as? String ?? ""

		switch api {
		case "runtime.onMessage.reply":
			let callbackId = dict["callbackId"] as? String ?? ""
			let payload = dict["payload"] as? [String: Any] ?? [:]
			if let reply = pendingReplies.removeValue(forKey: callbackId) {
				reply(payload)
			}

		case "storage.get":
			let keys = dict["keys"]
			let result = ExtensionStorage.shared.get(extensionId: extId, keys: keys)
			respondToBridge(extensionId: extId, requestId: requestId, result: result, error: nil)

		case "storage.set":
			let items = dict["items"] as? [String: Any] ?? [:]
			ExtensionStorage.shared.set(extensionId: extId, items: items)
			respondToBridge(
				extensionId: extId, requestId: requestId, result: ["status": "success"], error: nil)

		case "storage.remove":
			let keys = dict["keys"] as? [String] ?? []
			ExtensionStorage.shared.remove(extensionId: extId, keys: keys)
			respondToBridge(
				extensionId: extId, requestId: requestId, result: ["status": "success"], error: nil)

		case "storage.clear":
			ExtensionStorage.shared.clear(extensionId: extId)
			respondToBridge(
				extensionId: extId, requestId: requestId, result: ["status": "success"], error: nil)

		case "console.log":
			let levelStr = dict["level"] as? String ?? "log"
			let level = ConsoleLogEntry.LogLevel(rawValue: levelStr) ?? .log
			let messageText = dict["message"] as? String ?? ""
			let entry = ConsoleLogEntry(level: level, message: messageText)
			addConsoleLog(entry, for: extId)

		case "runtime.openOptionsPage":
			NotificationCenter.default.post(
				name: NSNotification.Name("WirtOpenOptionsPage"),
				object: nil,
				userInfo: ["extensionId": extId]
			)
			respondToBridge(
				extensionId: extId, requestId: requestId, result: ["status": "success"], error: nil)

		default:
			break
		}
	}

	private func respondToBridge(
		extensionId: String, requestId: String, result: Any?, error: String?
	) {
		guard !requestId.isEmpty, let webView = backgroundWebViews[extensionId] else { return }
		var resJson = "null"
		if let result = result, JSONSerialization.isValidJSONObject(result),
			let data = try? JSONSerialization.data(withJSONObject: result),
			let str = String(data: data, encoding: .utf8)
		{
			resJson = str
		}
		let errJson = error != nil ? "\"\(error!)\"" : "null"
		let script =
			"if (window.__wirtBridgeCallback) { window.__wirtBridgeCallback('\(requestId)', \(resJson), \(errJson)); }"
		webView.evaluateJavaScript(script, completionHandler: nil)
	}

	public func getMatchingScripts(for pageUrl: String) -> [[String: Any]] {
		guard let url = URL(string: pageUrl) else { return [] }
		let storageDir = ExtensionInstaller.shared.storageDirectory
		guard
			let items = try? FileManager.default.contentsOfDirectory(
				at: storageDir, includingPropertiesForKeys: nil)
		else {
			return []
		}

		var matchingExtensions: [[String: Any]] = []

		for item in items where item.hasDirectoryPath {
			guard
				let desc = try? ExtensionInstaller.shared.parseManifest(
					in: item, fallbackId: item.lastPathComponent)
			else {
				continue
			}

			let messages = ExtensionInstaller.shared.loadLocaleMessages(
				in: item, defaultLocale: nil)
			var scripts: [[String: String]] = []
			var styles: [String] = []

			for cs in desc.contentScripts {
				if matchesAnyPattern(url: url, patterns: cs.matches) {
					for jsPath in cs.js {
						let fileUrl = item.appendingPathComponent(jsPath)
						if let content = try? String(contentsOf: fileUrl, encoding: .utf8) {
							scripts.append([
								"code": content,
								"path": jsPath,
								"runAt": cs.runAt,
								"allFrames": cs.allFrames ? "true" : "false",
							])
						}
					}
					for cssPath in cs.css {
						let fileUrl = item.appendingPathComponent(cssPath)
						if let content = try? String(contentsOf: fileUrl, encoding: .utf8) {
							let resolvedCss = ExtensionInstaller.shared.resolveI18nString(
								content, messages: messages, extensionId: desc.id)
							styles.append(resolvedCss)
						}
					}
				}
			}

			if !scripts.isEmpty || !styles.isEmpty {
				matchingExtensions.append([
					"id": desc.id,
					"scripts": scripts,
					"styles": styles,
				])
			}
		}

		return matchingExtensions
	}

	private func matchesAnyPattern(url: URL, patterns: [String]) -> Bool {
		for pattern in patterns {
			if matchesPattern(url: url, pattern: pattern) {
				return true
			}
		}
		return false
	}

	private func matchesPattern(url: URL, pattern: String) -> Bool {
		if pattern == "<all_urls>" {
			if let scheme = url.scheme, scheme == "http" || scheme == "https" {
				return true
			}
			return false
		}

		guard let schemeSeparator = pattern.range(of: "://") else {
			return false
		}

		let schemePart = String(pattern[..<schemeSeparator.lowerBound])
		let remainder = String(pattern[schemeSeparator.upperBound...])

		if let urlScheme = url.scheme {
			if schemePart == "*" {
				if urlScheme != "http" && urlScheme != "https" {
					return false
				}
			} else if schemePart != urlScheme {
				return false
			}
		} else {
			return false
		}

		guard let slashIndex = remainder.firstIndex(of: "/") else {
			return false
		}

		let hostPattern = String(remainder[..<slashIndex])
		let pathPattern = String(remainder[slashIndex...])

		guard let urlHost = url.host else {
			return false
		}

		if hostPattern != "*" {
			if hostPattern.hasPrefix("*.") {
				let suffix = String(hostPattern.dropFirst(2))
				let matchesExact = urlHost.caseInsensitiveCompare(suffix) == .orderedSame
				let matchesSub = urlHost.lowercased().hasSuffix("." + suffix.lowercased())
				if !matchesExact && !matchesSub {
					return false
				}
			} else if hostPattern.caseInsensitiveCompare(urlHost) != .orderedSame {
				return false
			}
		}

		let escapedPath = NSRegularExpression.escapedPattern(for: pathPattern)
		let regexPath = "^" + escapedPath.replacingOccurrences(of: "\\*", with: ".*") + "$"
		guard let regex = try? NSRegularExpression(pattern: regexPath) else {
			return false
		}

		let urlPath = url.path.isEmpty ? "/" : url.path
		let range = NSRange(urlPath.startIndex..<urlPath.endIndex, in: urlPath)
		return regex.firstMatch(in: urlPath, options: [], range: range) != nil
	}

	private func mimeForExtension(_ ext: String) -> String {
		switch ext.lowercased() {
		case "html", "htm": return "text/html"
		case "js", "mjs": return "application/javascript"
		case "css": return "text/css"
		case "json": return "application/json"
		case "png": return "image/png"
		case "svg": return "image/svg+xml"
		default: return "application/octet-stream"
		}
	}
}
