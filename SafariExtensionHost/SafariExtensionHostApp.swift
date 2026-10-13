import SwiftUI

@main
struct SafariExtensionHostApp: App {
  init() {
    HostXPCListener.shared.start()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .windowResizability(.contentSize)
  }
}
