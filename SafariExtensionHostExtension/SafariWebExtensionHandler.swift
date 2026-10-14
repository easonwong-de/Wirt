import SafariServices
import os.log

let SFExtensionMessageKey = "message"

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  private var currentConnection: NSXPCConnection?
  private let lock = NSLock()

  private func getConnection() -> NSXPCConnection {
    lock.lock()
    defer { lock.unlock() }

    if let conn = currentConnection {
      return conn
    }

    let connection = NSXPCConnection(
      machServiceName: "de.easonwong.SafariExtensionHost.mach", options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: HostXPCProtocol.self)
    connection.interruptionHandler = { [weak self] in
      os_log(.error, "SafariWebExtensionHandler: XPC connection interrupted")
      self?.lock.lock()
      self?.currentConnection = nil
      self?.lock.unlock()
    }
    connection.invalidationHandler = { [weak self] in
      os_log(.error, "SafariWebExtensionHandler: XPC connection invalidated")
      self?.lock.lock()
      self?.currentConnection = nil
      self?.lock.unlock()
    }
    connection.resume()
    currentConnection = connection
    return connection
  }

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

    let connection = getConnection()
    let host =
      connection.remoteObjectProxyWithErrorHandler { [weak self] error in
        os_log(.error, "SafariWebExtensionHandler XPC proxy error: %@", error.localizedDescription)
        self?.lock.lock()
        self?.currentConnection = nil
        self?.lock.unlock()

        let response = NSExtensionItem()
        response.userInfo = [
          SFExtensionMessageKey: [
            "error":
              "The Safari Extension Host app is not running. Please launch Safari Extension Host to proceed."
          ]
        ]
        context.completeRequest(returningItems: [response], completionHandler: nil)
      } as? HostXPCProtocol

    host?.handleExtensionMessage(message) { reply in
      os_log(
        .default, "SafariWebExtensionHandler received native reply: %@", String(describing: reply))
      let response = NSExtensionItem()
      response.userInfo = [SFExtensionMessageKey: reply]
      context.completeRequest(returningItems: [response], completionHandler: nil)
    }
  }
}
