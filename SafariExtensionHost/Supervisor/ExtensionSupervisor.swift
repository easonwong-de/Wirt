import Foundation
import WebKit

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
  private weak var delegate: WKScriptMessageHandler?

  init(delegate: WKScriptMessageHandler) {
    self.delegate = delegate
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    delegate?.userContentController(userContentController, didReceive: message)
  }
}

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
    userContent.add(WeakScriptMessageHandler(delegate: self), name: "hostBridge")

    let shimURL = Bundle.main.url(
      forResource: "chrome-shim", withExtension: "js", subdirectory: "Resources/shim")
      ?? Bundle.main.url(forResource: "chrome-shim", withExtension: "js", subdirectory: "shim")
      ?? Bundle.main.url(forResource: "chrome-shim", withExtension: "js")
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
    let script = """
      if (window.chrome?.action?.onClicked) {
        for (const fn of window.chrome.action.onClicked.listeners) {
          fn(tab);
        }
      }
      """
    webView.callAsyncJavaScript(script, arguments: ["tab": tabMetadata], in: nil, in: .page)
  }

  public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    guard let url = urlSchemeTask.request.url, let extId = url.host else {
      urlSchemeTask.didFailWithError(URLError(.badURL))
      return
    }

    let baseDir = PackageIngestionService.shared.storageDirectory.appendingPathComponent(
      extId, isDirectory: true).standardizedFileURL
    let filePath = baseDir.appendingPathComponent(url.path).standardizedFileURL

    guard filePath.path.hasPrefix(baseDir.path) else {
      urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
      return
    }

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
  }

  public func getMatchingScripts(for pageUrl: String) -> [[String: Any]] {
    guard let url = URL(string: pageUrl) else { return [] }
    let storageDir = PackageIngestionService.shared.storageDirectory
    guard
      let items = try? FileManager.default.contentsOfDirectory(
        at: storageDir, includingPropertiesForKeys: nil)
    else {
      return []
    }

    var matchingExtensions: [[String: Any]] = []

    for item in items where item.hasDirectoryPath {
      guard
        let desc = try? PackageIngestionService.shared.parseManifest(
          in: item, fallbackId: item.lastPathComponent)
      else {
        continue
      }

      var scripts: [[String: String]] = []
      var styles: [String] = []

      for cs in desc.contentScripts {
        if matchesAnyPattern(url: url, patterns: cs.matches) {
          for jsPath in cs.js {
            let fileUrl = item.appendingPathComponent(jsPath)
            if let content = try? String(contentsOf: fileUrl, encoding: .utf8) {
              scripts.append(["code": content, "path": jsPath])
            }
          }
          for cssPath in cs.css {
            let fileUrl = item.appendingPathComponent(cssPath)
            if let content = try? String(contentsOf: fileUrl, encoding: .utf8) {
              styles.append(content)
            }
          }
        }
      }

      if !scripts.isEmpty || !styles.isEmpty {
        matchingExtensions.append([
          "id": desc.id,
          "scripts": scripts,
          "styles": styles,
        ])
      }
    }

    return matchingExtensions
  }

  private func matchesAnyPattern(url: URL, patterns: [String]) -> Bool {
    for pattern in patterns {
      if pattern == "<all_urls>" {
        if let scheme = url.scheme, scheme == "http" || scheme == "https" {
          return true
        }
      } else {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let regexPattern = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
        if let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) {
          let str = url.absoluteString
          let range = NSRange(str.startIndex..<str.endIndex, in: str)
          if regex.firstMatch(in: str, options: [], range: range) != nil {
            return true
          }
        }
      }
    }
    return false
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
