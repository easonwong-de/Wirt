import SafariServices
import SwiftUI

struct ContentView: View {
  @State private var isExtensionEnabled = false
  @State private var installedExtensions: [InstalledExtensionItem] = []

  private let extensionBundleId = "de.easonwong.SafariExtensionHost.Extension"

  var body: some View {
    VStack(spacing: 20) {
      headerView
      statusCard
      installedExtensionsSection
      actionButtons
    }
    .padding(24)
    .frame(width: 480, height: 420)
    .onAppear {
      checkExtensionState()
      loadInstalledExtensions()
    }
  }

  private var headerView: some View {
    VStack(spacing: 6) {
      Text("Safari Extension Host")
        .font(.title2)
        .fontWeight(.bold)
      Text("Bridge for Chrome and Firefox extensions in Safari")
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
  }

  private var statusCard: some View {
    HStack {
      Circle()
        .fill(isExtensionEnabled ? Color.green : Color.red)
        .frame(width: 10, height: 10)
      Text(isExtensionEnabled ? "Extension is active in Safari" : "Extension is disabled in Safari")
        .font(.body)
      Spacer()
      Button("Open Settings") {
        openSafariExtensionSettings()
      }
    }
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(8)
  }

  private var installedExtensionsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Installed Extensions")
        .font(.headline)

      if installedExtensions.isEmpty {
        VStack(spacing: 8) {
          Text("No third-party extensions installed.")
            .font(.subheadline)
            .foregroundColor(.secondary)
          Text("Download a .crx or .xpi in Safari to install.")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
      } else {
        List(installedExtensions) { ext in
          HStack {
            VStack(alignment: .leading) {
              Text(ext.name)
                .font(.body)
                .fontWeight(.medium)
              Text("v\(ext.version)")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
          }
        }
        .listStyle(.inset)
        .cornerRadius(8)
      }
    }
    .frame(maxHeight: .infinity)
  }

  private var actionButtons: some View {
    HStack {
      Button("Refresh") {
        checkExtensionState()
        loadInstalledExtensions()
      }
      Spacer()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
    }
  }

  private func checkExtensionState() {
    SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleId) {
      state, _ in
      DispatchQueue.main.async {
        self.isExtensionEnabled = state?.isEnabled ?? false
      }
    }
  }

  private func openSafariExtensionSettings() {
    SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleId)
  }

  private func loadInstalledExtensions() {
    let storageDir = PackageIngestionService.shared.storageDirectory
    guard
      let items = try? FileManager.default.contentsOfDirectory(
        at: storageDir, includingPropertiesForKeys: nil)
    else {
      installedExtensions = []
      return
    }

    var loaded: [InstalledExtensionItem] = []
    for item in items where item.hasDirectoryPath {
      if let desc = try? PackageIngestionService.shared.parseManifest(
        in: item, fallbackId: item.lastPathComponent)
      {
        loaded.append(InstalledExtensionItem(id: desc.id, name: desc.name, version: desc.version))
      }
    }
    installedExtensions = loaded
  }
}

struct InstalledExtensionItem: Identifiable {
  let id: String
  let name: String
  let version: String
}
