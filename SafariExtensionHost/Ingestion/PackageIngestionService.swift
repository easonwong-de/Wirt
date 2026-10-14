import Foundation

public final class PackageIngestionService: Sendable {
  public static let shared = PackageIngestionService()

  public var storageDirectory: URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let hostDir = appSupport.appendingPathComponent(
      "de.easonwong.SafariExtensionHost/Extensions", isDirectory: true)
    try? FileManager.default.createDirectory(at: hostDir, withIntermediateDirectories: true)
    return hostDir
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
        domain: "PackageIngestionService",
        code: httpResponse.statusCode,
        userInfo: [
          NSLocalizedDescriptionKey: "Download failed with HTTP \(httpResponse.statusCode)"
        ]
      )
    }

    let data = try Data(contentsOf: tempFile)
    let extId = deriveExtensionId(from: url)
    let targetDir = storageDirectory.appendingPathComponent(extId, isDirectory: true)
    try? FileManager.default.removeItem(at: targetDir)
    try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

    try extractPackage(data: data, to: targetDir)
    let descriptor = try parseManifest(in: targetDir, fallbackId: extId)
    return descriptor
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
    if !lastComponent.isEmpty && lastComponent != "crx" && lastComponent != "xpi" {
      return lastComponent.lowercased()
    }
    return String(UUID().uuidString.prefix(16).lowercased())
  }

  private func extractPackage(data: Data, to destination: URL) throws {
    var zipData = data
    if data.count > 16 && data.prefix(4) == Data([0x43, 0x72, 0x32, 0x34]) {
      let version = data[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) }
      if version == 3 {
        let headerSize = Int(data[8..<12].withUnsafeBytes { $0.load(as: UInt32.self) })
        let zipOffset = 12 + headerSize
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

    let name = json["name"] as? String ?? "Unnamed Extension"
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
    }

    var backgroundEntry: BackgroundEntry?
    if let bg = json["background"] as? [String: Any] {
      if let sw = bg["service_worker"] as? String {
        let isModule = (bg["type"] as? String) == "module"
        backgroundEntry = BackgroundEntry(scripts: [sw], isModule: isModule)
      } else if let scripts = bg["scripts"] as? [String] {
        backgroundEntry = BackgroundEntry(scripts: scripts, isModule: false)
      } else if let page = bg["page"] as? String {
        backgroundEntry = BackgroundEntry(scripts: [page], isModule: false)
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
          ContentScriptEntry(matches: matches, js: js, css: css, runAt: runAt, allFrames: allFrames)
        )
      }
    }

    var actionEntry: ActionEntry?
    let actionDict =
      (json["action"] as? [String: Any]) ?? (json["browser_action"] as? [String: Any])
    if let actionDict = actionDict {
      let defaultTitle = actionDict["default_title"] as? String
      let defaultPopup = actionDict["default_popup"] as? String
      let defaultIcon = actionDict["default_icon"] as? [String: String]
      actionEntry = ActionEntry(
        defaultTitle: defaultTitle, defaultPopup: defaultPopup, defaultIcon: defaultIcon)
    }

    return ExtensionDescriptor(
      id: resolvedId,
      name: name,
      version: version,
      manifestVersion: manifestVersion,
      backgroundEntry: backgroundEntry,
      contentScripts: contentScripts,
      action: actionEntry,
      permissions: permissions
    )
  }
}
