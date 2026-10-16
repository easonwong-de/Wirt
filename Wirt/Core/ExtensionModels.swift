import Foundation

public struct ExtensionDescriptor: Codable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let version: String
  public let manifestVersion: Int
  public let backgroundEntry: BackgroundEntry?
  public let contentScripts: [ContentScriptEntry]
  public let action: ActionEntry?
  public let permissions: [String]

  public init(
    id: String,
    name: String,
    version: String,
    manifestVersion: Int,
    backgroundEntry: BackgroundEntry?,
    contentScripts: [ContentScriptEntry],
    action: ActionEntry?,
    permissions: [String]
  ) {
    self.id = id
    self.name = name
    self.version = version
    self.manifestVersion = manifestVersion
    self.backgroundEntry = backgroundEntry
    self.contentScripts = contentScripts
    self.action = action
    self.permissions = permissions
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
