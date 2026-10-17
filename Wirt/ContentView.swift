import AppKit
import Combine
import SafariServices
import SwiftUI

enum WindowMetrics {
  static let windowWidth: CGFloat = 440
}

struct ContentHeightPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    let next = nextValue()
    if next > 0 {
      value = next
    }
  }
}

@MainActor
final class AppState: ObservableObject {
  static let shared = AppState()

  @Published var isExtensionEnabled = false
  @Published var installedExtensions: [InstalledExtensionItem] = []

  private let extensionBundleId = "de.easonwong.Wirt.Extension"

  init() {
    loadInstalledExtensions()
    checkExtensionState()
  }

  func checkExtensionState() {
    SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleId) {
      state, _ in
      Task { @MainActor in
        let enabled = state?.isEnabled ?? false
        if self.isExtensionEnabled != enabled {
          self.isExtensionEnabled = enabled
        }
      }
    }
  }

  func loadInstalledExtensions() {
    let storageDir = ExtensionInstaller.shared.storageDirectory
    guard
      let items = try? FileManager.default.contentsOfDirectory(
        at: storageDir, includingPropertiesForKeys: nil)
    else {
      installedExtensions = []
      return
    }

    var loaded: [InstalledExtensionItem] = []
    for item in items where item.hasDirectoryPath {
      if let desc = try? ExtensionInstaller.shared.parseManifest(
        in: item, fallbackId: item.lastPathComponent)
      {
        loaded.append(InstalledExtensionItem(id: desc.id, name: desc.name, version: desc.version))
      }
    }
    installedExtensions = loaded
  }

  func openSafariExtensionSettings() {
    SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleId)
  }
}

struct ContentView: View {
  @ObservedObject private var state = AppState.shared
  var onHeightChange: ((CGFloat) -> Void)?

  var body: some View {
    VStack(spacing: 0) {
      if state.isExtensionEnabled {
        activeView
      } else {
        inactiveView
      }
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 20)
    .padding(.top, 38)
    .fixedSize(horizontal: false, vertical: true)
    .background(
      GeometryReader { geometry in
        Color.clear.preference(
          key: ContentHeightPreferenceKey.self,
          value: geometry.size.height
        )
      }
    )
    .frame(width: WindowMetrics.windowWidth)
    .onPreferenceChange(ContentHeightPreferenceKey.self) { newHeight in
      guard newHeight > 0 else { return }
      DispatchQueue.main.async {
        onHeightChange?(newHeight)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      state.checkExtensionState()
      state.loadInstalledExtensions()
    }
  }

  private var inactiveView: some View {
    VStack(spacing: 16) {
      VStack(spacing: 10) {
        Image(systemName: "puzzlepiece.extension")
          .font(.system(size: 40))
          .foregroundStyle(.secondary)

        HStack(spacing: 6) {
          Circle()
            .fill(Color.red)
            .frame(width: 7, height: 7)

          Text("Extension Not Enabled")
            .font(.system(size: 13, weight: .semibold))

          Button {
            state.checkExtensionState()
          } label: {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 11, weight: .medium))
          }
          .buttonStyle(.plain)
          .help("Refresh extension status")
        }
      }
      .frame(maxWidth: .infinity)

      VStack(alignment: .leading, spacing: 6) {
        instructionLine(
          number: "1.",
          text: "In Safari Settings > Advanced, tick \"Show features for web developers\".")
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
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
      .padding(.vertical, 10)
      .padding(.horizontal, 16)
      .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
      .clipShape(RoundedRectangle(cornerRadius: 8))

      Button("Open Safari Settings") {
        state.openSafariExtensionSettings()
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func instructionLine(number: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Text(number)
        .fontWeight(.medium)
      Text(text)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var activeView: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        Text("Installed Extensions")
          .font(.system(size: 13, weight: .semibold))

        Button {
          state.checkExtensionState()
          state.loadInstalledExtensions()
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.plain)
        .help("Refresh installed extensions")

        Spacer()
      }

      if state.installedExtensions.isEmpty {
        VStack(spacing: 12) {
          Image(systemName: "puzzlepiece.extension")
            .font(.system(size: 40))
            .foregroundColor(.secondary)

          VStack(spacing: 4) {
            Text("No Extensions Installed")
              .font(.system(size: 13, weight: .semibold))
            Text("Download a .crx or .xpi package in Safari to install.")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color(NSColor.separatorColor).opacity(0.7), lineWidth: 1)
        )
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(state.installedExtensions) { ext in
              HStack(spacing: 12) {
                Image(systemName: "puzzlepiece.extension.fill")
                  .font(.system(size: 18))
                  .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                  Text(ext.name)
                    .font(.system(size: 13, weight: .medium))
                  Text("v\(ext.version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                Spacer()
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 8)

              if ext.id != state.installedExtensions.last?.id {
                Divider()
                  .padding(.leading, 44)
              }
            }
          }
        }
        .frame(height: 200)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color(NSColor.separatorColor).opacity(0.7), lineWidth: 1)
        )
      }
    }
    .frame(maxWidth: .infinity)
  }
}

struct InstalledExtensionItem: Identifiable {
  let id: String
  let name: String
  let version: String
}
