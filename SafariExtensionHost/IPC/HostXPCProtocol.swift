import Foundation

@objc(HostXPCProtocol)
public protocol HostXPCProtocol {
  func handleExtensionMessage(
    _ message: [String: Any], withReply reply: @escaping ([String: Any]) -> Void)
}
