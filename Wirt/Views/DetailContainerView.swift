import SwiftUI

// MARK: - Scroll Offset Preference

struct ScrollOffsetPreferenceKey: PreferenceKey {
	static var defaultValue: CGFloat = 52
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		value = nextValue()
	}
}

// MARK: - Detail Container View

struct DetailContainerView: View {
	let extensionDescriptor: ExtensionDescriptor
	@ObservedObject private var state = AppState.shared

	@State private var isTopHovered = false
	@State private var isContentScrolled = false

	private var isHeaderVisible: Bool {
		isTopHovered || isContentScrolled
	}

	var body: some View {
		ZStack(alignment: .top) {
			tabContent
				.safeAreaPadding(.top, 52)
				.frame(maxWidth: .infinity, maxHeight: .infinity)

			translucentHeaderLayer
		}
		.ignoresSafeArea(.all, edges: .top)
		.frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
		.onChange(of: state.selectedTab) { _ in
			DispatchQueue.main.async {
				isContentScrolled = false
			}
		}
		.onChange(of: extensionDescriptor.id) { _ in
			DispatchQueue.main.async {
				isContentScrolled = false
			}
		}
		.toolbar {
			ToolbarItem(placement: .principal) {
				Picker(
					"",
					selection: Binding(
						get: { state.selectedTab },
						set: { newTab in
							DispatchQueue.main.async {
								state.selectedTab = newTab
							}
						}
					)
				) {
					ForEach(ExtensionDetailTab.allCases) { tab in
						Label(tab.rawValue, systemImage: tab.icon).tag(tab)
					}
				}
				.pickerStyle(.segmented)
			}
		}
	}

	@ViewBuilder
	private var tabContent: some View {
		switch state.selectedTab {
		case .details:
			ExtensionDetailsView(ext: extensionDescriptor, isScrolled: $isContentScrolled)
		case .preference:
			ExtensionPreferenceView(ext: extensionDescriptor)
		case .background:
			ExtensionBackgroundView(ext: extensionDescriptor)
		}
	}

	private var translucentHeaderLayer: some View {
		ZStack(alignment: .bottom) {
			Rectangle()
				.fill(.bar)

			Divider()
				.opacity(0.2)
		}
		.frame(height: 52)
		.frame(maxWidth: .infinity)
		.contentShape(Rectangle())
		.opacity(isHeaderVisible ? 1 : 0)
		.animation(.easeInOut(duration: 0.2), value: isHeaderVisible)
		.onHover { isTopHovered = $0 }
	}
}
