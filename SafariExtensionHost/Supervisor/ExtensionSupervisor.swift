import Foundation
import WebKit

@MainActor
public final class ExtensionSupervisor: NSObject, WKURLSchemeHandler, WKScriptMessageHandler {
  public static let shared = ExtensionSupervisor()

  private var backgroundWebViews: [String: WKWebView] = [:]

  public func startBackgroundRuntime(for descriptor: ExtensionDescriptor, directory: URL) {
    guard let bg = descriptor.backgroundEntry, !bg.scripts.isEmpty else { return }

    let config = WKWebViewConfiguration()
    config.setURLSchemeHandler(self, forURLScheme: "ext-bg")
    config.setURLSchemeHandler(self, forURLScheme: "ext-ui")

    let userContent = config.userContentController
    userContent.add(self, name: "hostBridge")

    let shimURL = Bundle.main.url(
      forResource: "chrome-shim", withExtension: "js", subdirectory: "Resources/shim")
    if let shimURL = shimURL, let shimCode = try? String(contentsOf: shimURL, encoding: .utf8) {
      let initScript = "window.__HOST_EXTENSION_ID__ = '\(descriptor.id)';\n" + shimCode
      let userScript = WKUserScript(
        source: initScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
      userContent.addUserScript(userScript)
    }

    let webView = WKWebView(frame: .zero, configuration: config)
    backgroundWebViews[descriptor.id] = webView

    let syntheticHtml = """
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8"></head>
      <body>
      \(bg.scripts.map { "<script src='\($0)'></script>" }.joined(separator: "\n"))
      </body>
      </html>
      """
    webView.loadHTMLString(syntheticHtml, baseURL: URL(string: "ext-bg://\(descriptor.id)/")!)
  }

  public func dispatchActionClick(extensionId: String, tabMetadata: [String: Any]) {
    guard let webView = backgroundWebViews[extensionId] else { return }
    let jsonData = (try? JSONSerialization.data(withJSONObject: tabMetadata)) ?? Data()
    let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
    let js =
      "if (window.chrome?.action?.onClicked) { for (const fn of window.chrome.action.onClicked.listeners) { fn(\(jsonString)); } }"
    webView.evaluateJavaScript(js)
  }

  public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    guard let url = urlSchemeTask.request.url, let extId = url.host else {
      urlSchemeTask.didFailWithError(URLError(.badURL))
      return
    }

    let baseDir = PackageIngestionService.shared.storageDirectory.appendingPathComponent(
      extId, isDirectory: true)
    let filePath = baseDir.appendingPathComponent(url.path)

    if let data = try? Data(contentsOf: filePath) {
      let mimeType = mimeForExtension(filePath.pathExtension)
      let response = HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: nil,
        headerFields: [
          "Content-Type": mimeType,
          "Access-Control-Allow-Origin": "*",
        ])!
      urlSchemeTask.didReceive(response)
      urlSchemeTask.didReceive(data)
      urlSchemeTask.didFinish()
    } else {
      urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
    }
  }

  public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

  public func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    // Handle bridge messages
  }

  private func mimeForExtension(_ ext: String) -> String {
    switch ext.lowercased() {
    case "html", "htm": return "text/html"
    case "js", "mjs": return "application/javascript"
    case "css": return "text/css"
    case "json": return "application/json"
    case "png": return "image/png"
    case "svg": return "image/svg+xml"
    default: return "application/octet-stream"
    }
  }
}
