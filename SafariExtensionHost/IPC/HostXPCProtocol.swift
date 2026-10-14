import Foundation

public enum HostXPC {
  public nonisolated static let serviceName = "de.easonwong.SafariExtensionHost.mach"
}

@objc(HostXPCProtocol)
public protocol HostXPCProtocol {
  func handleExtensionMessage(
    _ message: [String: Any], withReply reply: @escaping ([String: Any]) -> Void)
  func showSettings(withReply reply: @escaping () -> Void)
}
