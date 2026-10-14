import AppKit
import os.log

public final class HostXPCListener: NSObject, NSXPCListenerDelegate, HostXPCProtocol {
  public static let shared = HostXPCListener()

  private var listener: NSXPCListener?

  public func start() {
    let listener = NSXPCListener(machServiceName: HostXPC.serviceName)
    listener.delegate = self
    listener.resume()
    self.listener = listener
    os_log(.default, "HostXPCListener resumed on Mach service: %@", HostXPC.serviceName)
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
    os_log(.default, "HostXPCListener accepting incoming connection")
    newConnection.exportedInterface = NSXPCInterface(with: HostXPCProtocol.self)
    newConnection.exportedObject = self
    newConnection.interruptionHandler = {
      os_log(.default, "HostXPCListener connection interrupted")
    }
    newConnection.invalidationHandler = {
      os_log(.default, "HostXPCListener connection invalidated")
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
        reply(["extensions": extensions])
      }
    case "DISPATCH_ACTION_CLICK":
      let extId = message["extensionId"] as? String ?? ""
      let tab = message["tab"] as? [String: Any] ?? [:]
      Task { @MainActor in
        ExtensionSupervisor.shared.dispatchActionClick(extensionId: extId, tabMetadata: tab)
        reply(["status": "success"])
      }
    case "GET_MATCHING_SCRIPTS":
      let pageUrl = message["url"] as? String ?? ""
      Task { @MainActor in
        let matching = ExtensionSupervisor.shared.getMatchingScripts(for: pageUrl)
        reply(["matchingExtensions": matching])
      }
    case "INSTALL_PACKAGE_FROM_URL":
      let downloadUrl = message["downloadUrl"] as? String ?? ""
      if let url = URL(string: downloadUrl) {
        Task {
          do {
            let descriptor = try await PackageIngestionService.shared.ingest(from: url)
            await MainActor.run {
              let dir = PackageIngestionService.shared.storageDirectory.appendingPathComponent(
                descriptor.id, isDirectory: true)
              ExtensionSupervisor.shared.startBackgroundRuntime(for: descriptor, directory: dir)
            }
            reply(["status": "success", "extensionId": descriptor.id, "name": descriptor.name])
          } catch {
            reply(["status": "error", "message": error.localizedDescription])
          }
        }
      } else {
        reply(["status": "error", "message": "Invalid URL"])
      }
    default:
      reply(["status": "unknown_message", "type": type])
    }
  }

  @MainActor
  private func getInstalledExtensionsPayload() -> [[String: Any]] {
    let storageDir = PackageIngestionService.shared.storageDirectory
    guard
      let items = try? FileManager.default.contentsOfDirectory(
        at: storageDir, includingPropertiesForKeys: nil)
    else {
      return []
    }
    var results: [[String: Any]] = []
    for item in items where item.hasDirectoryPath {
      if let desc = try? PackageIngestionService.shared.parseManifest(
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
          "version": desc.version,
          "actionType": actionType,
          "popupPath": popupPath,
          "badgeText": "",
          "badgeColor": "#0071e3",
        ])
      }
    }
    return results
  }
}
