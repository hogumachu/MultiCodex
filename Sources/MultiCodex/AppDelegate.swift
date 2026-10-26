import AppKit
import MultiCodexCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let controller: AppController
  private var statusItem: NSStatusItem!
  private var profileWindow: ProfileWindow!
  private var shortcuts: ShortcutController!
  private var workspaceObservers: [NSObjectProtocol] = []

  init(controller: AppController) { self.controller = controller }

  func applicationDidFinishLaunching(_ notification: Notification) {
    installMainMenu()
    shortcuts = ShortcutController(root: controller.store.root)
    shortcuts.onTrigger = { [weak self] id in self?.openProfile(id: id) }
    shortcuts.synchronize(profiles: controller.profiles)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "MultiCodex")
    statusItem.button?.image?.isTemplate = true
    statusItem.button?.toolTip = "MultiCodex"
    statusItem.button?.setAccessibilityLabel("MultiCodex")
    let menu = NSMenu()
    menu.delegate = self
    statusItem.menu = menu
    profileWindow = ProfileWindow(controller: controller, shortcuts: shortcuts)
    controller.onChange = { [weak self] in
      guard let self else { return }
      self.shortcuts.synchronize(profiles: self.controller.profiles)
      self.statusItem.button?.toolTip = "MultiCodex · \(self.controller.runningIDs.count)개 계정 실행 중"
    }
    for name in [
      NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
    ] {
      workspaceObservers.append(
        NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main)
        { [weak self] _ in
          Task { @MainActor in self?.controller.refresh() }
        })
    }
    rebuildMenu(menu)
    profileWindow.present()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    profileWindow.present()
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    shortcuts.stop()
    for observer in workspaceObservers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    controller.refresh()
    rebuildMenu(menu)
  }

  private func installMainMenu() {
    // An NSHostingView inside a manually created NSApplication needs the standard
    // responder-chain edit commands for text-field shortcuts and paste to work.
    let main = NSMenu()
    let appItem = NSMenuItem(title: "MultiCodex", action: nil, keyEquivalent: "")
    let appMenu = NSMenu(title: "MultiCodex")
    let settings = NSMenuItem(
      title: "계정 및 단축키 설정…", action: #selector(manageProfiles), keyEquivalent: ",")
    settings.target = self
    appMenu.addItem(settings)
    appMenu.addItem(.separator())
    let quit = NSMenuItem(title: "MultiCodex 종료", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    appMenu.addItem(quit)
    appItem.submenu = appMenu
    main.addItem(appItem)

    let editItem = NSMenuItem(title: "편집", action: nil, keyEquivalent: "")
    let edit = NSMenu(title: "편집")
    edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = edit.addItem(withTitle: "다시 실행", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(.separator())
    edit.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    main.addItem(editItem)
    NSApp.mainMenu = main
  }

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()
    let title = NSMenuItem(
      title: "MultiCodex · \(controller.runningIDs.count)개 실행 중", action: nil, keyEquivalent: "")
    title.isEnabled = false
    menu.addItem(title)
    menu.addItem(.separator())
    for profile in controller.profiles {
      let shortcut = shortcuts.values[profile.id]
      let hint =
        shortcuts.activeIDs.contains(profile.id) ? shortcut.map { "    " + $0.display } ?? "" : ""
      // Carbon owns the shortcuts globally. Do not also register menu key equivalents.
      let item = NSMenuItem(
        title: profile.name + hint, action: #selector(selectProfile(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = profile.id
      item.isEnabled = !controller.busy
      item.state = controller.selectedID == profile.id ? .on : .off
      if controller.runningIDs.contains(profile.id) {
        item.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "실행 중")
        item.image?.size = NSSize(width: 7, height: 7)
      }
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let manage = NSMenuItem(
      title: "계정 및 단축키 설정…", action: #selector(manageProfiles), keyEquivalent: ",")
    manage.target = self
    menu.addItem(manage)
    let quit = NSMenuItem(title: "MultiCodex 종료", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
  }

  private func openProfile(id: String) {
    guard let profile = controller.profiles.first(where: { $0.id == id }) else { return }
    Task { await controller.openProfile(profile) }
  }

  @objc private func selectProfile(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    openProfile(id: id)
  }
  @objc private func manageProfiles() { profileWindow.present() }
  @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}
