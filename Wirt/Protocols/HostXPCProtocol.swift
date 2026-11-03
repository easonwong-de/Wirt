import Foundation

public enum HostXPC {
	#if DEBUG
		public nonisolated static let serviceName = "de.easonwong.Wirt.debug.mach"
	#else
		public nonisolated static let serviceName = "de.easonwong.Wirt.mach"
	#endif
}

@objc(HostXPCProtocol)
public protocol HostXPCProtocol {
	func handleExtensionMessage(
		_ message: [String: Any], withReply reply: @escaping ([String: Any]) -> Void)
	func showSettings(withReply reply: @escaping () -> Void)
}
