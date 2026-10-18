import Foundation
import os.log

public final class ExtensionStorage: Sendable {
	public static let shared = ExtensionStorage()

	public let baseDirectory: URL

	private let queue = DispatchQueue(
		label: "de.easonwong.Wirt.ExtensionStorage", attributes: .concurrent)

	private init() {
		let appSupport =
			FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
			?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
				"Library/Application Support")
		let storageDir = appSupport.appendingPathComponent(
			"Wirt/Storage", isDirectory: true)
		try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
		self.baseDirectory = storageDir
	}

	public func get(extensionId: String, keys: Any?) -> [String: Any] {
		queue.sync {
			let store = loadStore(for: extensionId)
			guard let keys = keys else {
				return store
			}

			if let singleKey = keys as? String {
				if singleKey.isEmpty {
					return store
				}
				if let val = store[singleKey] {
					return [singleKey: val]
				}
				return [:]
			}

			if let keyList = keys as? [String] {
				var result: [String: Any] = [:]
				for k in keyList {
					if let val = store[k] {
						result[k] = val
					}
				}
				return result
			}

			if let keyDict = keys as? [String: Any] {
				var result = keyDict
				for (k, val) in store where keyDict[k] != nil {
					result[k] = val
				}
				return result
			}

			return store
		}
	}

	public func set(extensionId: String, items: [String: Any]) {
		queue.async(flags: .barrier) {
			var store = self.loadStore(for: extensionId)
			for (k, v) in items {
				store[k] = v
			}
			self.persistStore(store, for: extensionId)
		}
	}

	public func remove(extensionId: String, keys: [String]) {
		queue.async(flags: .barrier) {
			var store = self.loadStore(for: extensionId)
			for k in keys {
				store.removeValue(forKey: k)
			}
			self.persistStore(store, for: extensionId)
		}
	}

	public func clear(extensionId: String) {
		queue.async(flags: .barrier) {
			self.persistStore([:], for: extensionId)
		}
	}

	public func deleteStorage(for extensionId: String) {
		queue.async(flags: .barrier) {
			let url = self.fileURL(for: extensionId)
			try? FileManager.default.removeItem(at: url)
		}
	}

	private func fileURL(for extensionId: String) -> URL {
		let safeName = sanitizeIdentifier(extensionId)
		return baseDirectory.appendingPathComponent("\(safeName).json")
	}

	private func loadStore(for extensionId: String) -> [String: Any] {
		let url = fileURL(for: extensionId)
		guard let data = try? Data(contentsOf: url),
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else {
			return [:]
		}
		return json
	}

	private func persistStore(_ store: [String: Any], for extensionId: String) {
		let url = fileURL(for: extensionId)
		guard JSONSerialization.isValidJSONObject(store),
			let data = try? JSONSerialization.data(withJSONObject: store, options: [.prettyPrinted])
		else {
			return
		}
		try? data.write(to: url, options: .atomic)
	}

	private func sanitizeIdentifier(_ id: String) -> String {
		let pattern = "[^a-zA-Z0-9._@-]"
		return id.replacingOccurrences(of: pattern, with: "_", options: .regularExpression)
	}
}
