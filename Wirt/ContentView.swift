import AppKit
import SwiftUI

// MARK: - Main ContentView

struct ContentView: View {
	@ObservedObject private var state = AppState.shared
	@State private var columnVisibility: NavigationSplitViewVisibility = .all

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			SidebarView(columnVisibility: $columnVisibility)
				.navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
		} detail: {
			detailContentView
				.navigationSplitViewColumnWidth(min: 480, ideal: 560)
		}
		.navigationSplitViewStyle(.balanced)
		.frame(minWidth: 760, minHeight: 480)
		.onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
			_ in
			state.checkExtensionState()
			state.loadInstalledExtensions()
		}
	}

	@ViewBuilder
	private var detailContentView: some View {
		Group {
			if !state.isExtensionEnabled {
				disconnectedDetailView
			} else if let ext = state.selectedExtension {
				DetailContainerView(extensionDescriptor: ext)
			} else {
				Color.clear
			}
		}
		.frame(minWidth: 480)
	}

	private var disconnectedDetailView: some View {
		VStack(spacing: 18) {
			VStack(spacing: 10) {
				Image(systemName: "puzzlepiece.extension")
					.font(.system(size: 44))
					.foregroundStyle(.secondary)

				HStack(spacing: 6) {
					Circle()
						.fill(Color.red)
						.frame(width: 8, height: 8)

					Text("Extension Not Enabled")
						.font(.system(size: 14, weight: .semibold))

					Button {
						state.checkExtensionState()
					} label: {
						Image(systemName: "arrow.clockwise")
							.font(.system(size: 12, weight: .medium))
					}
					.buttonStyle(.plain)
					.help("Refresh extension status")
				}
			}

			VStack(alignment: .leading, spacing: 8) {
				instructionLine(
					number: "1.",
					text:
						"In Safari Settings > Advanced, tick \"Show features for web developers\".")
				instructionLine(
					number: "2.",
					text: "In Safari Develop menu, select \"Allow Unsigned Extensions\".")
				instructionLine(
					number: "3.",
					text: "In Safari Settings > Extensions, tick \"Wirt\".")
				instructionLine(
					number: "4.",
					text: "Select \"Always Allow on Every Website…\".")
			}
			.font(.system(size: 12))
			.foregroundStyle(.secondary)
			.padding(.vertical, 12)
			.padding(.horizontal, 18)
			.background(Color(NSColor.controlBackgroundColor).opacity(0.6))
			.clipShape(RoundedRectangle(cornerRadius: 8))
			.overlay(
				RoundedRectangle(cornerRadius: 8)
					.strokeBorder(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
			)

			Button("Open Safari Settings") {
				state.openSafariExtensionSettings()
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.regular)
		}
		.padding(32)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(Color(NSColor.windowBackgroundColor))
	}

	private func instructionLine(number: String, text: String) -> some View {
		HStack(alignment: .top, spacing: 6) {
			Text(number)
				.fontWeight(.medium)
			Text(text)
				.fixedSize(horizontal: false, vertical: true)
		}
	}
}
