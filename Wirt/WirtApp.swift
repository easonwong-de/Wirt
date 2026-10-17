import AppKit
import ServiceManagement
import SwiftUI
import os.log

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private static let agentPlistName = "de.easonwong.Wirt.agent.plist"
  private static let backgroundArgument = "--background"

  private var window: NSWindow?

  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }

  private var hasInitialisedWindowSize = false

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if CommandLine.arguments.contains(Self.backgroundArgument) {
      NSApp.setActivationPolicy(.accessory)
      ExtensionListener.shared.start()
      ExtensionRuntime.shared.bootInstalledExtensions()
    } else if registerAgent() {
      handOffToAgent()
    } else {
      startForeground()
    }
  }

  private func startForeground() {
    NSApp.setActivationPolicy(.regular)
    ExtensionListener.shared.start()
    ExtensionRuntime.shared.bootInstalledExtensions()
    showSettings()
  }

  private func setupInterface() {
    guard window == nil else { return }
    setupMainMenu()
    setupWindow()
  }

  @discardableResult
  private func registerAgent() -> Bool {
    #if DEBUG
    let agent = SMAppService.agent(plistName: Self.agentPlistName)
    if agent.status == .enabled {
      try? agent.unregister()
    }
    return false
    #else
    let agent = SMAppService.agent(plistName: Self.agentPlistName)
    if agent.status != .enabled {
      do {
        try agent.register()
      } catch {
        os_log(.error, "Launch agent registration failed: %@", error.localizedDescription)
      }
    }
    if agent.status == .requiresApproval {
      SMAppService.openSystemSettingsLoginItems()
    }
    return agent.status == .enabled
    #endif
  }

  private func handOffToAgent() {
    let connection = NSXPCConnection(machServiceName: HostXPC.serviceName, options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: HostXPCProtocol.self)
    connection.resume()

    guard
      let agent = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
        os_log(.error, "Launch agent hand-off failed: %@", error.localizedDescription)
        connection.invalidate()
        Task { @MainActor in
          self?.startForeground()
        }
      }) as? HostXPCProtocol
    else {
      os_log(.error, "Failed to obtain remote proxy for launch agent")
      connection.invalidate()
      startForeground()
      return
    }

    agent.showSettings {
      connection.invalidate()
      Task { @MainActor in
        NSApp.terminate(nil)
      }
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showSettings()
    return true
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    NSApp.setActivationPolicy(.accessory)
    return false
  }

  @objc func showSettings() {
    NSApp.setActivationPolicy(.regular)
    setupInterface()
    if let window = self.window {
      if window.isMiniaturized {
        window.deminiaturize(nil)
      }
      window.makeKeyAndOrderFront(nil)
    }
    NSApp.activate()
  }

  @objc func quitApp() {
    NSApp.terminate(nil)
  }


  private func updateWindowSize(to contentHeight: CGFloat, animated: Bool) {
    guard let window = self.window else { return }
    let titlebarHeight = window.frame.height - window.contentLayoutRect.height
    let targetHeight = contentHeight + titlebarHeight
    let windowSize = window.frame.size
    let heightDiff = targetHeight - windowSize.height
    guard abs(heightDiff) > 0.5 else { return }

    let targetOrigin = NSPoint(x: window.frame.origin.x, y: window.frame.origin.y - heightDiff)
    let targetSize = NSSize(width: window.frame.width, height: targetHeight)
    let targetRect = NSRect(origin: targetOrigin, size: targetSize)

    if animated && hasInitialisedWindowSize {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.3
        context.allowsImplicitAnimation = true
        window.setFrame(targetRect, display: true)
      }
    } else {
      window.setFrame(targetRect, display: true)
      hasInitialisedWindowSize = true
    }
  }

  private func setupWindow() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: WindowMetrics.windowWidth, height: 200),
      styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "Wirt"
    window.titleVisibility = .visible
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.delegate = self

    let hostingView = NSHostingView(
      rootView: ContentView(onHeightChange: { [weak self] newHeight in
        self?.updateWindowSize(to: newHeight, animated: self?.hasInitialisedWindowSize ?? false)
      }))
    window.contentView = hostingView
    self.window = window

    let initialHeight = hostingView.fittingSize.height
    let titlebarHeight = window.frame.height - window.contentLayoutRect.height
    if initialHeight > titlebarHeight {
      updateWindowSize(to: initialHeight - titlebarHeight, animated: false)
    }
    hasInitialisedWindowSize = true
    window.center()
  }

  private func setupMainMenu() {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenu.addItem(
      NSMenuItem(
        title: "About Wirt",
        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
        keyEquivalent: ""))
    appMenu.addItem(NSMenuItem.separator())
    let settingsItem = NSMenuItem(
      title: "Settings…",
      action: #selector(showSettings),
      keyEquivalent: ",")
    settingsItem.target = self
    appMenu.addItem(settingsItem)
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(
      NSMenuItem(
        title: "Hide Wirt",
        action: #selector(NSApplication.hide(_:)),
        keyEquivalent: "h"))
    let hideOthersItem = NSMenuItem(
      title: "Hide Others",
      action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h")
    hideOthersItem.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(hideOthersItem)
    appMenu.addItem(
      NSMenuItem(
        title: "Show All",
        action: #selector(NSApplication.unhideAllApplications(_:)),
        keyEquivalent: ""))
    appMenu.addItem(NSMenuItem.separator())
    let quitItem = NSMenuItem(
      title: "Quit Wirt",
      action: #selector(quitApp),
      keyEquivalent: "q")
    quitItem.target = self
    appMenu.addItem(quitItem)
    appMenuItem.submenu = appMenu

    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(
      NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(
      NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(
      NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(
      NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    editMenuItem.submenu = editMenu

    let windowMenuItem = NSMenuItem()
    mainMenu.addItem(windowMenuItem)
    let windowMenu = NSMenu(title: "Window")
    let closeItem = NSMenuItem(
      title: "Close Window",
      action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w")
    windowMenu.addItem(closeItem)
    windowMenuItem.submenu = windowMenu

    NSApp.mainMenu = mainMenu
  }
}
