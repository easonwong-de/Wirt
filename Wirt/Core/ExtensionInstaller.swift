import CryptoKit
import Foundation

public final class ExtensionInstaller: Sendable {
	public static let shared = ExtensionInstaller()

	public let storageDirectory: URL

	private init() {
		let appSupport =
			FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
			?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
				"Library/Application Support")
		let hostDir = appSupport.appendingPathComponent(
			"Wirt/Extensions", isDirectory: true)
		try? FileManager.default.createDirectory(at: hostDir, withIntermediateDirectories: true)
		self.storageDirectory = hostDir
	}

	public func ingest(from url: URL) async throws -> ExtensionDescriptor {
		var request = URLRequest(url: url)
		request.setValue(
			"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
			forHTTPHeaderField: "User-Agent")
		request.setValue("*/*", forHTTPHeaderField: "Accept")

		let (tempFile, response) = try await URLSession.shared.download(for: request)
		if let httpResponse = response as? HTTPURLResponse,
			!(200...299).contains(httpResponse.statusCode)
		{
			throw NSError(
				domain: "ExtensionInstaller",
				code: httpResponse.statusCode,
				userInfo: [
					NSLocalizedDescriptionKey:
						"Download failed with HTTP \(httpResponse.statusCode)"
				]
			)
		}

		let data = try Data(contentsOf: tempFile)
		let urlDerivedId = deriveExtensionId(from: url)

		let stagingDir = storageDirectory.appendingPathComponent(
			".staging_\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

		defer {
			try? FileManager.default.removeItem(at: stagingDir)
		}

		try extractPackage(data: data, to: stagingDir)
		let rawDescriptor = try parseManifest(in: stagingDir, fallbackId: urlDerivedId)

		let canonicalId = sanitizeIdentifier(rawDescriptor.id)
		let targetDir = storageDirectory.appendingPathComponent(canonicalId, isDirectory: true)

		if FileManager.default.fileExists(atPath: targetDir.path) {
			try FileManager.default.removeItem(at: targetDir)
		}

		try FileManager.default.moveItem(at: stagingDir, to: targetDir)

		return try parseManifest(in: targetDir, fallbackId: canonicalId)
	}

	public func installFromDisk(at url: URL) throws -> ExtensionDescriptor {
		var isDir: ObjCBool = false
		guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
			throw NSError(
				domain: "ExtensionInstaller",
				code: 404,
				userInfo: [NSLocalizedDescriptionKey: "Selected file or directory does not exist."]
			)
		}

		let stagingDir = storageDirectory.appendingPathComponent(
			".staging_\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: stagingDir)
		}

		if isDir.boolValue {
			var sourceDir = url
			let directManifest = sourceDir.appendingPathComponent("manifest.json")
			if !FileManager.default.fileExists(atPath: directManifest.path) {
				if let subDirs = try? FileManager.default.contentsOfDirectory(
					at: sourceDir, includingPropertiesForKeys: nil)
				{
					if let found = subDirs.first(where: {
						FileManager.default.fileExists(
							atPath: $0.appendingPathComponent("manifest.json").path)
					}) {
						sourceDir = found
					} else {
						throw NSError(
							domain: "ExtensionInstaller",
							code: 400,
							userInfo: [
								NSLocalizedDescriptionKey:
									"No manifest.json found in the selected directory."
							]
						)
					}
				}
			}

			let items = try FileManager.default.contentsOfDirectory(
				at: sourceDir, includingPropertiesForKeys: nil)
			for item in items {
				let dest = stagingDir.appendingPathComponent(item.lastPathComponent)
				try FileManager.default.copyItem(at: item, to: dest)
			}
		} else {
			let data = try Data(contentsOf: url)
			try extractPackage(data: data, to: stagingDir)
		}

		let rawDescriptor = try parseManifest(
			in: stagingDir, fallbackId: deriveExtensionId(from: url))
		let canonicalId = sanitizeIdentifier(rawDescriptor.id)
		let targetDir = storageDirectory.appendingPathComponent(canonicalId, isDirectory: true)

		if FileManager.default.fileExists(atPath: targetDir.path) {
			try FileManager.default.removeItem(at: targetDir)
		}

		try FileManager.default.moveItem(at: stagingDir, to: targetDir)

		return try parseManifest(in: targetDir, fallbackId: canonicalId)
	}

	public func uninstall(extensionId: String) throws {
		let canonicalId = sanitizeIdentifier(extensionId)
		let directDir = storageDirectory.appendingPathComponent(canonicalId, isDirectory: true)
		if FileManager.default.fileExists(atPath: directDir.path) {
			try FileManager.default.removeItem(at: directDir)
			return
		}

		guard
			let items = try? FileManager.default.contentsOfDirectory(
				at: storageDirectory, includingPropertiesForKeys: nil)
		else {
			return
		}

		for item in items where item.hasDirectoryPath {
			if let desc = try? parseManifest(in: item, fallbackId: item.lastPathComponent) {
				if desc.id.lowercased() == extensionId.lowercased()
					|| desc.name.lowercased() == extensionId.lowercased()
					|| item.lastPathComponent.lowercased() == extensionId.lowercased()
				{
					try FileManager.default.removeItem(at: item)
					return
				}
			}
		}
	}

	private func deriveExtensionId(from url: URL) -> String {
		if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
			if let xItem = components.queryItems?.first(where: { $0.name == "x" })?.value {
				if let match = xItem.range(of: "id=([a-z0-9]{32})", options: .regularExpression) {
					let idStr = String(xItem[match]).replacingOccurrences(of: "id=", with: "")
					if !idStr.isEmpty { return idStr.lowercased() }
				}
			}
			if let idItem = components.queryItems?.first(where: { $0.name == "id" })?.value,
				idItem.count == 32
			{
				return idItem.lowercased()
			}
		}
		let lastComponent = url.deletingPathExtension().lastPathComponent
		if !lastComponent.isEmpty && lastComponent != "crx" && lastComponent != "xpi"
			&& lastComponent != "latest"
		{
			return sanitizeIdentifier(lastComponent.lowercased())
		}
		return String(UUID().uuidString.prefix(16).lowercased())
	}

	private func extractPackage(data: Data, to destination: URL) throws {
		var zipData = data
		if data.count > 16 && data.prefix(4) == Data([0x43, 0x72, 0x32, 0x34]) {
			let version = data[4..<8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
			if version == 3 {
				let headerSize = Int(
					data[8..<12].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
				let zipOffset = 12 + headerSize
				if data.count > zipOffset {
					zipData = data.advanced(by: zipOffset)
				}
			} else if version == 2 {
				let pubKeyLength = Int(
					data[8..<12].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
				let sigLength = Int(
					data[12..<16].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
				let zipOffset = 16 + pubKeyLength + sigLength
				if data.count > zipOffset {
					zipData = data.advanced(by: zipOffset)
				}
			}
		}

		let zipURL = destination.appendingPathComponent("archive.zip")
		try zipData.write(to: zipURL)

		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
		process.arguments = ["-q", "-o", zipURL.path, "-d", destination.path]
		try process.run()
		process.waitUntilExit()
		try? FileManager.default.removeItem(at: zipURL)
	}

	public func parseManifest(in directory: URL, fallbackId: String) throws -> ExtensionDescriptor {
		let manifestURL = directory.appendingPathComponent("manifest.json")
		let data = try Data(contentsOf: manifestURL)
		let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

		let rawName = json["name"] as? String ?? "Unnamed Extension"
		let rawDescription = json["description"] as? String ?? ""
		let defaultLocale = json["default_locale"] as? String
		let messages = loadLocaleMessages(in: directory, defaultLocale: defaultLocale)

		let name = resolveI18nString(rawName, messages: messages, extensionId: fallbackId)
		let description = resolveI18nString(
			rawDescription, messages: messages, extensionId: fallbackId)
		let version = json["version"] as? String ?? "1.0.0"
		let manifestVersion = json["manifest_version"] as? Int ?? 3
		let permissions = json["permissions"] as? [String] ?? []

		var resolvedId = fallbackId
		if let bss = json["browser_specific_settings"] as? [String: Any],
			let gecko = bss["gecko"] as? [String: Any],
			let geckoId = gecko["id"] as? String, !geckoId.isEmpty
		{
			resolvedId = geckoId
		} else if let apps = json["applications"] as? [String: Any],
			let gecko = apps["gecko"] as? [String: Any],
			let geckoId = gecko["id"] as? String, !geckoId.isEmpty
		{
			resolvedId = geckoId
		} else if let key = json["key"] as? String,
			let keyData = Data(base64Encoded: key, options: [.ignoreUnknownCharacters]),
			fallbackId.count != 32
		{
			resolvedId = deriveIdFromPublicKey(keyData)
		}

		var backgroundEntry: BackgroundEntry?
		if let bg = json["background"] as? [String: Any] {
			if let sw = bg["service_worker"] as? String {
				let isModule = (bg["type"] as? String) == "module"
				backgroundEntry = BackgroundEntry(scripts: [sw], isModule: isModule)
			} else if let scripts = bg["scripts"] as? [String] {
				let isModule = (bg["type"] as? String) == "module"
				backgroundEntry = BackgroundEntry(scripts: scripts, isModule: isModule)
			} else if let page = bg["page"] as? String {
				backgroundEntry = BackgroundEntry(scripts: [], isModule: false, page: page)
			}
		}

		var contentScripts: [ContentScriptEntry] = []
		if let csList = json["content_scripts"] as? [[String: Any]] {
			for cs in csList {
				let matches = cs["matches"] as? [String] ?? []
				let js = cs["js"] as? [String] ?? []
				let css = cs["css"] as? [String] ?? []
				let runAt = cs["run_at"] as? String ?? "document_idle"
				let allFrames = cs["all_frames"] as? Bool ?? false
				contentScripts.append(
					ContentScriptEntry(
						matches: matches, js: js, css: css, runAt: runAt, allFrames: allFrames)
				)
			}
		}

		var actionEntry: ActionEntry?
		let actionDict =
			(json["action"] as? [String: Any]) ?? (json["browser_action"] as? [String: Any])
		if let actionDict = actionDict {
			let defaultTitle = actionDict["default_title"] as? String
			let resolvedTitle = defaultTitle.map {
				resolveI18nString($0, messages: messages, extensionId: resolvedId)
			}
			let defaultPopup = actionDict["default_popup"] as? String
			let defaultIcon = actionDict["default_icon"] as? [String: String]
			actionEntry = ActionEntry(
				defaultTitle: resolvedTitle, defaultPopup: defaultPopup, defaultIcon: defaultIcon)
		}

		let iconUrl = resolveIconDataUrl(in: directory, manifest: json)

		var optionsPage: String?
		if let optionsUi = json["options_ui"] as? [String: Any],
			let page = optionsUi["page"] as? String
		{
			optionsPage = page
		} else if let page = json["options_page"] as? String {
			optionsPage = page
		}

		let homepageUrl = json["homepage_url"] as? String
		let author =
			(json["author"] as? String)
			?? (json["developer"] as? [String: Any])?["name"] as? String

		return ExtensionDescriptor(
			id: sanitizeIdentifier(resolvedId),
			name: name,
			description: description,
			version: version,
			manifestVersion: manifestVersion,
			backgroundEntry: backgroundEntry,
			contentScripts: contentScripts,
			action: actionEntry,
			permissions: permissions,
			iconUrl: iconUrl,
			optionsPage: optionsPage,
			homepageUrl: homepageUrl,
			author: author
		)
	}

	private func resolveIconDataUrl(in directory: URL, manifest: [String: Any]) -> String? {
		var candidatePaths: [String] = []

		func extractPaths(from iconValue: Any?) {
			guard let iconValue = iconValue else { return }
			if let dict = iconValue as? [String: Any] {
				let sortedKeys = dict.keys.sorted { k1, k2 in
					let path1 = (dict[k1] as? String) ?? ""
					let path2 = (dict[k2] as? String) ?? ""
					let isSvg1 = path1.lowercased().hasSuffix(".svg")
					let isSvg2 = path2.lowercased().hasSuffix(".svg")
					if isSvg1 != isSvg2 {
						return isSvg1
					}
					let s1 = Int(k1) ?? 0
					let s2 = Int(k2) ?? 0
					if s1 != s2 {
						return s1 > s2
					}
					return k1 < k2
				}
				for key in sortedKeys {
					if let path = dict[key] as? String, !path.isEmpty,
						!candidatePaths.contains(path)
					{
						candidatePaths.append(path)
					}
				}
			} else if let str = iconValue as? String, !str.isEmpty, !candidatePaths.contains(str) {
				candidatePaths.append(str)
			}
		}

		extractPaths(from: manifest["icons"])
		if let action = (manifest["action"] as? [String: Any])
			?? (manifest["browser_action"] as? [String: Any])
			?? (manifest["page_action"] as? [String: Any])
			?? (manifest["sidebar_action"] as? [String: Any])
		{
			extractPaths(from: action["default_icon"])
		}

		if candidatePaths.isEmpty {
			let fallbackNames = [
				"icon512.png", "icon256.png", "icon128.png", "icon96.png", "icon64.png",
				"icon48.png",
				"icons/icon512.png", "icons/icon256.png", "icons/icon128.png", "icons/icon96.png",
				"icons/icon64.png", "icons/icon48.png", "images/icon512.png", "images/icon256.png",
				"images/icon128.png", "images/icon96.png", "images/icon64.png", "images/icon48.png",
				"icon.svg", "icons/icon.svg", "images/icon.svg",
				"icon.png", "icons/icon.png", "images/icon.png",
			]
			for name in fallbackNames {
				candidatePaths.append(name)
			}
		}

		for candidate in candidatePaths {
			let cleaned = candidate.hasPrefix("/") ? String(candidate.dropFirst()) : candidate
			let fileUrl = directory.appendingPathComponent(cleaned)
			if let data = try? Data(contentsOf: fileUrl), !data.isEmpty {
				let ext = fileUrl.pathExtension.lowercased()
				let mime: String
				switch ext {
				case "svg": mime = "image/svg+xml"
				case "jpg", "jpeg": mime = "image/jpeg"
				case "webp": mime = "image/webp"
				case "gif": mime = "image/gif"
				case "ico": mime = "image/x-icon"
				default: mime = "image/png"
				}
				return "data:\(mime);base64,\(data.base64EncodedString())"
			}
		}

		return nil
	}

	public func loadLocaleMessages(in directory: URL, defaultLocale: String?) -> [String: String] {
		let localesDir = directory.appendingPathComponent("_locales", isDirectory: true)
		guard FileManager.default.fileExists(atPath: localesDir.path) else {
			return [:]
		}

		var candidateCodes: [String] = []

		for lang in Locale.preferredLanguages {
			let underscore = lang.replacingOccurrences(of: "-", with: "_")
			let hyphen = lang.replacingOccurrences(of: "_", with: "-")
			candidateCodes.append(underscore)
			candidateCodes.append(hyphen)
			let base = lang.components(separatedBy: CharacterSet(charactersIn: "-_")).first ?? lang
			candidateCodes.append(base)
		}

		if let def = defaultLocale, !def.isEmpty {
			candidateCodes.append(def)
			candidateCodes.append(def.replacingOccurrences(of: "-", with: "_"))
			candidateCodes.append(def.replacingOccurrences(of: "_", with: "-"))
			let base = def.components(separatedBy: CharacterSet(charactersIn: "-_")).first ?? def
			candidateCodes.append(base)
		}

		candidateCodes.append("en")
		candidateCodes.append("en_US")
		candidateCodes.append("en-US")

		guard
			let availableDirs = try? FileManager.default.contentsOfDirectory(
				at: localesDir, includingPropertiesForKeys: nil)
		else {
			return [:]
		}
		let availableDirNames = availableDirs.filter { $0.hasDirectoryPath }.map {
			$0.lastPathComponent
		}

		var baseMessages: [String: String] = [:]
		if let fallbackDirName = availableDirNames.first(where: { name in
			if let def = defaultLocale?.lowercased() {
				return name.lowercased() == def || name.lowercased().hasPrefix(def)
			}
			return name.lowercased() == "en" || name.lowercased().hasPrefix("en")
		}) ?? availableDirNames.first {
			baseMessages = parseMessagesFile(
				at: localesDir.appendingPathComponent(fallbackDirName).appendingPathComponent(
					"messages.json"))
		}

		var userMessages: [String: String] = [:]
		for code in candidateCodes {
			if let matchedDir = availableDirNames.first(where: {
				$0.caseInsensitiveCompare(code) == .orderedSame
			}) {
				userMessages = parseMessagesFile(
					at: localesDir.appendingPathComponent(matchedDir).appendingPathComponent(
						"messages.json"))
				if !userMessages.isEmpty {
					break
				}
			}
		}

		var merged = baseMessages
		for (k, v) in userMessages {
			merged[k] = v
		}

		return merged
	}

	private func parseMessagesFile(at fileURL: URL) -> [String: String] {
		guard let data = try? Data(contentsOf: fileURL),
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else {
			return [:]
		}
		var result: [String: String] = [:]
		for (key, val) in json {
			if let dict = val as? [String: Any], var msg = dict["message"] as? String {
				if let placeholders = dict["placeholders"] as? [String: [String: Any]] {
					for (phKey, phVal) in placeholders {
						if let content = phVal["content"] as? String {
							msg = msg.replacingOccurrences(
								of: "$\(phKey)$", with: content, options: .caseInsensitive)
						}
					}
				}
				result[key.lowercased()] = msg
			}
		}
		return result
	}

	public func resolveI18nString(
		_ text: String, messages: [String: String], extensionId: String = ""
	) -> String {
		guard text.contains("__MSG_") else { return text }

		let pattern = #"__MSG_([A-Za-z0-9_@]+?)(?:__|(?<![A-Za-z0-9_@])|$)"#
		guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
			return text
		}

		let nsText = text as NSString
		let matches = regex.matches(
			in: text, options: [], range: NSRange(location: 0, length: nsText.length))
		guard !matches.isEmpty else { return text }

		var resolved = text
		for match in matches.reversed() {
			guard match.numberOfRanges > 1 else { continue }
			let keyRange = match.range(at: 1)
			let key = nsText.substring(with: keyRange).lowercased()
			let fullRange = match.range(at: 0)

			var replacement: String?
			if key == "@@extension_id" {
				replacement = extensionId
			} else if key == "@@ui_locale" {
				replacement = Locale.current.identifier
			} else if key == "@@bidi_dir" {
				replacement = "ltr"
			} else if key == "@@bidi_reversed_dir" {
				replacement = "rtl"
			} else if key == "@@bidi_start_edge" {
				replacement = "left"
			} else if key == "@@bidi_end_edge" {
				replacement = "right"
			} else if let msg = messages[key] {
				replacement = msg
			}

			if let rep = replacement {
				if let stringRange = Range(fullRange, in: resolved) {
					resolved.replaceSubrange(stringRange, with: rep)
				}
			}
		}

		return resolved
	}

	private func deriveIdFromPublicKey(_ keyData: Data) -> String {
		let digest = SHA256.hash(data: keyData)
		var chars: [Character] = []
		for byte in digest.prefix(16) {
			let high = (byte >> 4) & 0x0f
			let low = byte & 0x0f
			let scalarHigh = UnicodeScalar(UInt8(ascii: "a") + high)
			let scalarLow = UnicodeScalar(UInt8(ascii: "a") + low)
			chars.append(Character(scalarHigh))
			chars.append(Character(scalarLow))
		}
		return String(chars)
	}

	private func sanitizeIdentifier(_ id: String) -> String {
		let pattern = "[^a-zA-Z0-9._@-]"
		let cleaned = id.replacingOccurrences(of: pattern, with: "_", options: .regularExpression)
		if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
			return String(UUID().uuidString.prefix(16).lowercased())
		}
		return cleaned
	}
}
