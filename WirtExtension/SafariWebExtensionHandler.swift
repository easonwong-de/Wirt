import SafariServices
import os.log

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  func beginRequest(with context: NSExtensionContext) {
    guard let item = context.inputItems.first as? NSExtensionItem,
      let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any]
    else {
      context.completeRequest(returningItems: nil, completionHandler: nil)
      return
    }

    os_log(
      .default, "SafariWebExtensionHandler received native request: %@", String(describing: message)
    )

    let connection = NSXPCConnection(machServiceName: HostXPC.serviceName, options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: HostXPCProtocol.self)
    connection.resume()

    let lock = NSLock()
    var hasCompleted = false

    func finish(with reply: [String: Any]) {
      lock.lock()
      defer { lock.unlock() }
      guard !hasCompleted else { return }
      hasCompleted = true
      connection.invalidate()
      Self.complete(context, with: reply)
    }

    let isInstall = (message["type"] as? String) == "INSTALL_PACKAGE_FROM_URL"
    let timeout: Double = isInstall ? 60.0 : 6.0
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
      finish(with: ["error": "Host connection timed out."])
    }

    guard
      let host = connection.remoteObjectProxyWithErrorHandler({ error in
        os_log(.error, "SafariWebExtensionHandler XPC proxy error: %@", error.localizedDescription)
        finish(with: ["error": "Wirt is not running. Please open the Wirt app."])
      }) as? HostXPCProtocol
    else {
      os_log(.error, "SafariWebExtensionHandler failed to cast XPC proxy")
      finish(with: ["error": "Failed to connect to Wirt."])
      return
    }

    host.handleExtensionMessage(message) { reply in
      os_log(
        .default, "SafariWebExtensionHandler received native reply: %@", String(describing: reply))
      finish(with: reply)
    }
  }

  private static func complete(_ context: NSExtensionContext, with message: [String: Any]) {
    let response = NSExtensionItem()
    response.userInfo = [SFExtensionMessageKey: message]
    context.completeRequest(returningItems: [response], completionHandler: nil)
  }
}
