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
public final class ExtensionRuntime: NSObject, WKURLSchemeHandler, WKScriptMessageHandler {
  public static let shared = ExtensionRuntime()

  private var backgroundWebViews: [String: WKWebView] = [:]
  private var pendingReplies: [String: ([String: Any]) -> Void] = [:]

  public func bootInstalledExtensions() {
    let storageDir = ExtensionInstaller.shared.storageDirectory
    guard
      let items = try? FileManager.default.contentsOfDirectory(
        at: storageDir, includingPropertiesForKeys: nil)
    else {
      return
    }

    for item in items where item.hasDirectoryPath {
      guard
        let desc = try? ExtensionInstaller.shared.parseManifest(
          in: item, fallbackId: item.lastPathComponent)
      else {
        continue
      }
      if backgroundWebViews[desc.id] == nil {
        startBackgroundRuntime(for: desc, directory: item)
      }
    }
  }

  public func startBackgroundRuntime(for descriptor: ExtensionDescriptor, directory: URL) {
    guard let bg = descriptor.backgroundEntry, !bg.scripts.isEmpty else { return }

    let config = WKWebViewConfiguration()
    config.setURLSchemeHandler(self, forURLScheme: "ext-bg")
    config.setURLSchemeHandler(self, forURLScheme: "ext-ui")
    config.preferences.setValue(false, forKey: "webSecurityEnabled")
    config.defaultWebpagePreferences.allowsContentJavaScript = true

    let userContent = config.userContentController
    userContent.add(WeakScriptMessageHandler(delegate: self), name: "hostBridge")

    let shimURL = Bundle.main.url(
      forResource: "chrome-shim", withExtension: "js", subdirectory: "shim")
    if let shimURL = shimURL, let shimCode = try? String(contentsOf: shimURL, encoding: .utf8) {
      let initScript = "window.__HOST_EXTENSION_ID__ = '\(descriptor.id)';\n" + shimCode
      let userScript = WKUserScript(
        source: initScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
      userContent.addUserScript(userScript)
    }

    let webView = WKWebView(frame: .zero, configuration: config)
    backgroundWebViews[descriptor.id] = webView

    let scriptTags = bg.scripts.map { script in
      if bg.isModule {
        return "<script type=\"module\" src=\"\(script)\"></script>"
      }
      return "<script src=\"\(script)\"></script>"
    }.joined(separator: "\n")

    let syntheticHtml = """
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8"></head>
      <body>
      \(scriptTags)
      </body>
      </html>
      """
    webView.loadHTMLString(syntheticHtml, baseURL: URL(string: "ext-bg://\(descriptor.id)/")!)
  }

  public func dispatchRuntimeMessage(
    extensionId: String,
    source: [String: Any],
    payload: Any,
    completion: @escaping ([String: Any]) -> Void
  ) {
    guard let webView = backgroundWebViews[extensionId] else {
      completion(["error": "Extension runtime not active"])
      return
    }

    let correlationId = UUID().uuidString
    pendingReplies[correlationId] = completion

    let envelope: [String: Any] = [
      "correlationId": correlationId,
      "message": payload,
      "sender": [
        "id": extensionId,
        "tab": source["tab"] ?? [:],
        "frameId": source["frameId"] ?? 0,
        "url": source["url"] ?? "",
      ],
    ]

    guard let jsonData = try? JSONSerialization.data(withJSONObject: envelope),
      let jsonStr = String(data: jsonData, encoding: .utf8)
    else {
      pendingReplies.removeValue(forKey: correlationId)
      completion(["error": "Failed to serialize message payload"])
      return
    }

    let script =
      "if (window.__wirtDispatchRuntimeMessage) { window.__wirtDispatchRuntimeMessage(\(jsonStr)); }"
    webView.evaluateJavaScript(script) { _, error in
      if let error = error {
        if let reply = self.pendingReplies.removeValue(forKey: correlationId) {
          reply(["error": error.localizedDescription])
        }
      }
    }
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

    let baseDir = ExtensionInstaller.shared.storageDirectory.appendingPathComponent(
      extId, isDirectory: true).standardizedFileURL
    let filePath = baseDir.appendingPathComponent(url.path).standardizedFileURL

    let baseComponents = baseDir.pathComponents
    let fileComponents = filePath.pathComponents
    guard fileComponents.starts(with: baseComponents) else {
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
    guard let dict = message.body as? [String: Any],
      let api = dict["api"] as? String
    else {
      return
    }

    let extId = dict["extensionId"] as? String ?? ""
    let requestId = dict["requestId"] as? String ?? ""

    switch api {
    case "runtime.onMessage.reply":
      let callbackId = dict["callbackId"] as? String ?? ""
      let payload = dict["payload"] as? [String: Any] ?? [:]
      if let reply = pendingReplies.removeValue(forKey: callbackId) {
        reply(payload)
      }

    case "storage.get":
      let keys = dict["keys"]
      let result = ExtensionStorage.shared.get(extensionId: extId, keys: keys)
      respondToBridge(extensionId: extId, requestId: requestId, result: result, error: nil)

    case "storage.set":
      let items = dict["items"] as? [String: Any] ?? [:]
      ExtensionStorage.shared.set(extensionId: extId, items: items)
      respondToBridge(
        extensionId: extId, requestId: requestId, result: ["status": "success"], error: nil)

    case "storage.remove":
      let keys = dict["keys"] as? [String] ?? []
      ExtensionStorage.shared.remove(extensionId: extId, keys: keys)
      respondToBridge(
        extensionId: extId, requestId: requestId, result: ["status": "success"], error: nil)

    case "storage.clear":
      ExtensionStorage.shared.clear(extensionId: extId)
      respondToBridge(
        extensionId: extId, requestId: requestId, result: ["status": "success"], error: nil)

    default:
      break
    }
  }

  private func respondToBridge(
    extensionId: String, requestId: String, result: Any?, error: String?
  ) {
    guard !requestId.isEmpty, let webView = backgroundWebViews[extensionId] else { return }
    var resJson = "null"
    if let result = result, JSONSerialization.isValidJSONObject(result),
      let data = try? JSONSerialization.data(withJSONObject: result),
      let str = String(data: data, encoding: .utf8)
    {
      resJson = str
    }
    let errJson = error != nil ? "\"\(error!)\"" : "null"
    let script =
      "if (window.__wirtBridgeCallback) { window.__wirtBridgeCallback('\(requestId)', \(resJson), \(errJson)); }"
    webView.evaluateJavaScript(script, completionHandler: nil)
  }

  public func getMatchingScripts(for pageUrl: String) -> [[String: Any]] {
    guard let url = URL(string: pageUrl) else { return [] }
    let storageDir = ExtensionInstaller.shared.storageDirectory
    guard
      let items = try? FileManager.default.contentsOfDirectory(
        at: storageDir, includingPropertiesForKeys: nil)
    else {
      return []
    }

    var matchingExtensions: [[String: Any]] = []

    for item in items where item.hasDirectoryPath {
      guard
        let desc = try? ExtensionInstaller.shared.parseManifest(
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
              scripts.append([
                "code": content,
                "path": jsPath,
                "runAt": cs.runAt,
                "allFrames": cs.allFrames ? "true" : "false",
              ])
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
      if matchesPattern(url: url, pattern: pattern) {
        return true
      }
    }
    return false
  }

  private func matchesPattern(url: URL, pattern: String) -> Bool {
    if pattern == "<all_urls>" {
      if let scheme = url.scheme, scheme == "http" || scheme == "https" {
        return true
      }
      return false
    }

    guard let schemeSeparator = pattern.range(of: "://") else {
      return false
    }

    let schemePart = String(pattern[..<schemeSeparator.lowerBound])
    let remainder = String(pattern[schemeSeparator.upperBound...])

    if let urlScheme = url.scheme {
      if schemePart == "*" {
        if urlScheme != "http" && urlScheme != "https" {
          return false
        }
      } else if schemePart != urlScheme {
        return false
      }
    } else {
      return false
    }

    guard let slashIndex = remainder.firstIndex(of: "/") else {
      return false
    }

    let hostPattern = String(remainder[..<slashIndex])
    let pathPattern = String(remainder[slashIndex...])

    guard let urlHost = url.host else {
      return false
    }

    if hostPattern != "*" {
      if hostPattern.hasPrefix("*.") {
        let suffix = String(hostPattern.dropFirst(2))
        let matchesExact = urlHost.caseInsensitiveCompare(suffix) == .orderedSame
        let matchesSub = urlHost.lowercased().hasSuffix("." + suffix.lowercased())
        if !matchesExact && !matchesSub {
          return false
        }
      } else if hostPattern.caseInsensitiveCompare(urlHost) != .orderedSame {
        return false
      }
    }

    let escapedPath = NSRegularExpression.escapedPattern(for: pathPattern)
    let regexPath = "^" + escapedPath.replacingOccurrences(of: "\\*", with: ".*") + "$"
    guard let regex = try? NSRegularExpression(pattern: regexPath) else {
      return false
    }

    let urlPath = url.path.isEmpty ? "/" : url.path
    let range = NSRange(urlPath.startIndex..<urlPath.endIndex, in: urlPath)
    return regex.firstMatch(in: urlPath, options: [], range: range) != nil
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
