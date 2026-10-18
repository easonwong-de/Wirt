import Foundation

public struct ExtensionDescriptor: Codable, Identifiable, Sendable {
	public let id: String
	public let name: String
	public let description: String
	public let version: String
	public let manifestVersion: Int
	public let backgroundEntry: BackgroundEntry?
	public let contentScripts: [ContentScriptEntry]
	public let action: ActionEntry?
	public let permissions: [String]
	public let iconUrl: String?
	public let optionsPage: String?
	public let homepageUrl: String?
	public let author: String?

	public init(
		id: String,
		name: String,
		description: String = "",
		version: String,
		manifestVersion: Int,
		backgroundEntry: BackgroundEntry?,
		contentScripts: [ContentScriptEntry],
		action: ActionEntry?,
		permissions: [String],
		iconUrl: String? = nil,
		optionsPage: String? = nil,
		homepageUrl: String? = nil,
		author: String? = nil
	) {
		self.id = id
		self.name = name
		self.description = description
		self.version = version
		self.manifestVersion = manifestVersion
		self.backgroundEntry = backgroundEntry
		self.contentScripts = contentScripts
		self.action = action
		self.permissions = permissions
		self.iconUrl = iconUrl
		self.optionsPage = optionsPage
		self.homepageUrl = homepageUrl
		self.author = author
	}
}

public struct ConsoleLogEntry: Identifiable, Sendable {
	public let id: UUID
	public let timestamp: Date
	public let level: LogLevel
	public let message: String

	public init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel, message: String) {
		self.id = id
		self.timestamp = timestamp
		self.level = level
		self.message = message
	}

	public enum LogLevel: String, Codable, CaseIterable, Sendable {
		case log
		case info
		case warn
		case error

		public var icon: String {
			switch self {
			case .log: return "bubble.left"
			case .info: return "info.circle"
			case .warn: return "exclamationmark.triangle.fill"
			case .error: return "xmark.circle.fill"
			}
		}
	}
}

public struct BackgroundEntry: Codable, Sendable {
	public let scripts: [String]
	public let isModule: Bool

	public init(scripts: [String], isModule: Bool) {
		self.scripts = scripts
		self.isModule = isModule
	}
}

public struct ContentScriptEntry: Codable, Sendable {
	public let matches: [String]
	public let js: [String]
	public let css: [String]
	public let runAt: String
	public let allFrames: Bool

	public init(matches: [String], js: [String], css: [String], runAt: String, allFrames: Bool) {
		self.matches = matches
		self.js = js
		self.css = css
		self.runAt = runAt
		self.allFrames = allFrames
	}
}

public struct ActionEntry: Codable, Sendable {
	public let defaultTitle: String?
	public let defaultPopup: String?
	public let defaultIcon: [String: String]?

	public init(defaultTitle: String?, defaultPopup: String?, defaultIcon: [String: String]?) {
		self.defaultTitle = defaultTitle
		self.defaultPopup = defaultPopup
		self.defaultIcon = defaultIcon
	}
}
