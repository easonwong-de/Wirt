import SwiftUI

// MARK: - View Extension for Liquid Glass Button Style

extension View {
	@ViewBuilder
	func liquidGlassButtonStyle() -> some View {
		if #available(macOS 26.0, *) {
			self.buttonStyle(.glass)
				.buttonBorderShape(.circle)
		} else {
			self.buttonStyle(.borderless)
		}
	}
}
