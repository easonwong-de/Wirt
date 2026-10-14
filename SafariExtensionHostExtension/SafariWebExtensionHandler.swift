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

    let host =
      connection.remoteObjectProxyWithErrorHandler { error in
        os_log(.error, "SafariWebExtensionHandler XPC proxy error: %@", error.localizedDescription)
        connection.invalidate()
        Self.complete(
          context,
          with: [
            "error":
              "Safari Extension Host is not set up. Open the Safari Extension Host app once to finish setup."
          ])
      } as? HostXPCProtocol

    host?.handleExtensionMessage(message) { reply in
      os_log(
        .default, "SafariWebExtensionHandler received native reply: %@", String(describing: reply))
      connection.invalidate()
      Self.complete(context, with: reply)
    }
  }

  private static func complete(_ context: NSExtensionContext, with message: [String: Any]) {
    let response = NSExtensionItem()
    response.userInfo = [SFExtensionMessageKey: message]
    context.completeRequest(returningItems: [response], completionHandler: nil)
  }
}
