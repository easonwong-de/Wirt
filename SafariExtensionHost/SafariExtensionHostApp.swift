import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var statusItem: NSStatusItem?
  private var window: NSWindow?

  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }

  private var hasInitialisedWindowSize = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    HostXPCListener.shared.start()
    setupMainMenu()
    setupStatusItem()
    setupWindow()
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
    if let window = self.window {
      if window.isMiniaturized {
        window.deminiaturize(nil)
      }
      window.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc func quitApp() {
    NSApp.terminate(nil)
  }

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem?.button {
      let image = NSImage(
        systemSymbolName: "puzzlepiece.extension",
        accessibilityDescription: "Safari Extension Host")
      image?.isTemplate = true
      button.image = image
    }

    let menu = NSMenu()
    let settingsItem = NSMenuItem(
      title: "Settings…",
      action: #selector(showSettings),
      keyEquivalent: ",")
    settingsItem.target = self
    menu.addItem(settingsItem)

    menu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(
      title: "Quit",
      action: #selector(quitApp),
      keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)

    statusItem?.menu = menu
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
    window.title = "Safari Extension Host"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.delegate = self

    if let titlebarContainer = window.standardWindowButton(.closeButton)?.superview,
      let closeButton = window.standardWindowButton(.closeButton)
    {
      let titleLabel = NSTextField(labelWithString: "Safari Extension Host")
      titleLabel.font = NSFont.titleBarFont(ofSize: 13)
      titleLabel.textColor = .labelColor
      titleLabel.alignment = .center
      titleLabel.translatesAutoresizingMaskIntoConstraints = false
      titlebarContainer.addSubview(titleLabel)
      NSLayoutConstraint.activate([
        titleLabel.centerXAnchor.constraint(equalTo: titlebarContainer.centerXAnchor),
        titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
      ])
    }

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

    NSApp.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func setupMainMenu() {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenu.addItem(
      NSMenuItem(
        title: "About Safari Extension Host",
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
        title: "Hide Safari Extension Host",
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
      title: "Quit Safari Extension Host",
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
