import Foundation
import Network

public final class ExtensionServer: @unchecked Sendable {
	public static let shared = ExtensionServer()

	public let sessionToken = UUID().uuidString
	private let lock = NSLock()
	private var activePort: UInt16 = 0
	private var listener: NWListener?
	private let queue = DispatchQueue(label: "de.easonwong.Wirt.ExtensionServer", qos: .userInitiated)

	public var port: UInt16 {
		lock.lock()
		defer { lock.unlock() }
		return activePort
	}

	public func start() {
		guard listener == nil else { return }
		do {
			let params = NWParameters.tcp
			params.requiredInterfaceType = .loopback
			let newListener = try NWListener(using: params, on: .any)
			let semaphore = DispatchSemaphore(value: 0)

			newListener.stateUpdateHandler = { [weak self] state in
				if case .ready = state {
					self?.setPort(newListener.port?.rawValue ?? 0)
					semaphore.signal()
				} else if case .failed = state {
					semaphore.signal()
				}
			}
			newListener.newConnectionHandler = { [weak self] connection in
				self?.handleConnection(connection)
			}
			newListener.start(queue: queue)
			self.listener = newListener
			_ = semaphore.wait(timeout: .now() + 1.0)
		} catch {
			self.listener = nil
		}
	}

	public func stop() {
		listener?.cancel()
		listener = nil
		setPort(0)
	}

	private func setPort(_ value: UInt16) {
		lock.lock()
		activePort = value
		lock.unlock()
	}

	private func handleConnection(_ connection: NWConnection) {
		connection.start(queue: queue)
		readRequest(connection: connection, accumulatedData: Data())
	}

	private func readRequest(connection: NWConnection, accumulatedData: Data) {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
			guard let self = self else { return }
			if error != nil {
				connection.cancel()
				return
			}
			guard let data = data, !data.isEmpty else {
				connection.cancel()
				return
			}

			var current = accumulatedData
			current.append(data)

			let separator = "\r\n\r\n".data(using: .utf8)!
			if let range = current.range(of: separator) {
				let headerData = current.subdata(in: 0..<range.lowerBound)
				guard let headerString = String(data: headerData, encoding: .utf8) else {
					self.sendResponse(
						connection: connection, status: "400 Bad Request",
						headers: [:], body: Data(), isHead: false)
					return
				}
				self.processRequest(connection: connection, headerString: headerString)
			} else if current.count > 131072 {
				self.sendResponse(
					connection: connection, status: "413 Payload Too Large",
					headers: [:], body: Data(), isHead: false)
			} else {
				self.readRequest(connection: connection, accumulatedData: current)
			}
		}
	}

	private func processRequest(connection: NWConnection, headerString: String) {
		let lines = headerString.components(separatedBy: "\r\n")
		guard let requestLine = lines.first else {
			sendResponse(
				connection: connection, status: "400 Bad Request",
				headers: [:], body: Data(), isHead: false)
			return
		}

		let parts = requestLine.components(separatedBy: " ")
		guard parts.count >= 2 else {
			sendResponse(
				connection: connection, status: "400 Bad Request",
				headers: [:], body: Data(), isHead: false)
			return
		}

		let method = parts[0].uppercased()
		guard method == "GET" || method == "HEAD" else {
			sendResponse(
				connection: connection, status: "405 Method Not Allowed",
				headers: [:], body: Data(), isHead: false)
			return
		}

		let isHead = method == "HEAD"
		let rawUri = parts[1]

		var headers: [String: String] = [:]
		for line in lines.dropFirst() {
			let headerParts = line.components(separatedBy: ":")
			if headerParts.count >= 2 {
				let key = headerParts[0].trimmingCharacters(in: .whitespaces).lowercased()
				let val = headerParts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
				headers[key] = val
			}
		}

		guard let host = headers["host"],
			host.starts(with: "127.0.0.1:") || host.starts(with: "localhost:")
		else {
			sendResponse(
				connection: connection, status: "403 Forbidden",
				headers: [:], body: Data(), isHead: isHead)
			return
		}

		handleFileGet(connection: connection, uri: rawUri, headers: headers, isHead: isHead)
	}

	private func handleFileGet(
		connection: NWConnection, uri: String,
		headers: [String: String], isHead: Bool
	) {
		let pathWithoutQuery = uri.components(separatedBy: "?").first ?? uri
		let cleanPath = (pathWithoutQuery.components(separatedBy: "#").first ?? pathWithoutQuery)
			.removingPercentEncoding ?? pathWithoutQuery

		let segments = cleanPath.components(separatedBy: "/").filter { !$0.isEmpty }

		var extId = ""
		var filePath = ""

		if segments.count >= 3, segments[0] == sessionToken, segments[1] == "__wirt__",
			segments[2] == "chrome-shim.js"
		{
			let shimURL = Bundle.main.url(
				forResource: "chrome-shim", withExtension: "js", subdirectory: "shim")
			if let shimURL = shimURL, let data = try? Data(contentsOf: shimURL) {
				sendResponse(
					connection: connection, status: "200 OK",
					headers: ["Content-Type": "application/javascript; charset=utf-8"],
					body: data, isHead: isHead)
			} else {
				sendResponse(
					connection: connection, status: "404 Not Found",
					headers: [:], body: Data(), isHead: isHead)
			}
			return
		}

		if segments.count >= 2, segments[0] == sessionToken {
			extId = segments[1]
			filePath = segments.dropFirst(2).joined(separator: "/")
		} else if let referer = headers["referer"], let refUrl = URL(string: referer) {
			let refSegments = refUrl.path.components(separatedBy: "/").filter { !$0.isEmpty }
			if refSegments.count >= 2, refSegments[0] == sessionToken {
				extId = refSegments[1]
				filePath = cleanPath.hasPrefix("/") ? String(cleanPath.dropFirst()) : cleanPath
			}
		}

		guard !extId.isEmpty else {
			sendResponse(
				connection: connection, status: "403 Forbidden",
				headers: [:], body: Data(), isHead: isHead)
			return
		}

		let storageDir = ExtensionInstaller.shared.storageDirectory
		let baseDir = storageDir.appendingPathComponent(extId, isDirectory: true).standardizedFileURL
		let targetFile = baseDir.appendingPathComponent(filePath).standardizedFileURL

		guard targetFile.path.hasPrefix(baseDir.path),
			FileManager.default.fileExists(atPath: targetFile.path)
		else {
			sendResponse(
				connection: connection, status: "404 Not Found",
				headers: [:], body: Data(), isHead: isHead)
			return
		}

		let ext = targetFile.pathExtension.lowercased()
		if ext == "html" || ext == "htm" {
			guard var content = try? String(contentsOf: targetFile, encoding: .utf8) else {
				sendResponse(
					connection: connection, status: "500 Internal Server Error",
					headers: [:], body: Data(), isHead: isHead)
				return
			}

			let messages = ExtensionInstaller.shared.loadLocaleMessages(in: baseDir, defaultLocale: nil)
			let messagesData = (try? JSONSerialization.data(withJSONObject: messages)) ?? Data("{}".utf8)
			let messagesJson = String(data: messagesData, encoding: .utf8) ?? "{}"

			content = ExtensionInstaller.shared.resolveI18nString(
				content, messages: messages, extensionId: extId)

			content = content
				.replacingOccurrences(of: "src=\"/", with: "src=\"/\(sessionToken)/\(extId)/")
				.replacingOccurrences(of: "href=\"/", with: "href=\"/\(sessionToken)/\(extId)/")

			let injectedHeader = """
				<script>
				window.__HOST_EXTENSION_ID__ = '\(extId)';
				window.__HOST_I18N_MESSAGES__ = \(messagesJson);
				</script>
				<script src="/\(sessionToken)/__wirt__/chrome-shim.js"></script>
				"""

			if content.contains("<head>") {
				content = content.replacingOccurrences(of: "<head>", with: "<head>\n\(injectedHeader)")
			} else {
				content = injectedHeader + content
			}

			let bodyData = content.data(using: .utf8) ?? Data()
			sendResponse(
				connection: connection, status: "200 OK",
				headers: ["Content-Type": "text/html; charset=utf-8"],
				body: bodyData, isHead: isHead)
			return
		}

		guard let data = try? Data(contentsOf: targetFile) else {
			sendResponse(
				connection: connection, status: "500 Internal Server Error",
				headers: [:], body: Data(), isHead: isHead)
			return
		}

		let mime = mimeType(for: ext)
		sendResponse(
			connection: connection, status: "200 OK",
			headers: ["Content-Type": mime], body: data, isHead: isHead)
	}

	private func mimeType(for ext: String) -> String {
		switch ext.lowercased() {
		case "html", "htm": return "text/html; charset=utf-8"
		case "js", "mjs": return "application/javascript; charset=utf-8"
		case "css": return "text/css; charset=utf-8"
		case "json": return "application/json; charset=utf-8"
		case "png": return "image/png"
		case "jpg", "jpeg": return "image/jpeg"
		case "gif": return "image/gif"
		case "svg": return "image/svg+xml"
		case "webp": return "image/webp"
		case "ico": return "image/x-icon"
		case "woff": return "font/woff"
		case "woff2": return "font/woff2"
		case "ttf": return "font/ttf"
		case "otf": return "font/otf"
		default: return "application/octet-stream"
		}
	}

	private func sendResponse(
		connection: NWConnection, status: String,
		headers: [String: String], body: Data, isHead: Bool
	) {
		var headerString = "HTTP/1.1 \(status)\r\n"
		var allHeaders = headers
		allHeaders["Content-Length"] = "\(body.count)"
		allHeaders["Connection"] = "close"
		allHeaders["X-Content-Type-Options"] = "nosniff"
		for (k, v) in allHeaders {
			headerString += "\(k): \(v)\r\n"
		}
		headerString += "\r\n"
		var responseData = headerString.data(using: .utf8) ?? Data()
		if !isHead {
			responseData.append(body)
		}
		connection.send(content: responseData, completion: .contentProcessed { _ in
			connection.cancel()
		})
	}
}
