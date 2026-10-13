import SafariServices
import os.log

let SFExtensionMessageKey = "message"

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  private lazy var xpcConnection: NSXPCConnection = {
    let connection = NSXPCConnection(
      machServiceName: "com.eason.SafariExtensionHost.mach", options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: HostXPCProtocol.self)
    connection.resume()
    return connection
  }()

  func beginRequest(with context: NSExtensionContext) {
    guard let item = context.inputItems.first as? NSExtensionItem,
      let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any]
    else {
      context.completeRequest(returningItems: nil, completionHandler: nil)
      return
    }

    let host =
      xpcConnection.remoteObjectProxyWithErrorHandler { error in
        os_log(.error, "XPC Error: %@", error.localizedDescription)
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["error": error.localizedDescription]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
      } as? HostXPCProtocol

    host?.handleExtensionMessage(message) { reply in
      let response = NSExtensionItem()
      response.userInfo = [SFExtensionMessageKey: reply]
      context.completeRequest(returningItems: [response], completionHandler: nil)
    }
  }
}
