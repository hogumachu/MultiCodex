import AppKit
import MultiCodexCore
import Observation

@MainActor @Observable
final class ShortcutController {
  private(set) var values: [String: AccountShortcut] = [:]
  private(set) var errors: [String: String] = [:]
  private(set) var loadError: String?
  private(set) var recordingID: String?
  private(set) var recordingError: String?
  private(set) var activeIDs: Set<String> = []
  @ObservationIgnored private var store: ShortcutStore?
  @ObservationIgnored private var hotKeys: GlobalHotKeys?
  @ObservationIgnored private var monitor: Any?
  @ObservationIgnored private var resignObserver: NSObjectProtocol?
  @ObservationIgnored private var profileIDs: [String] = []
  @ObservationIgnored var onTrigger: ((String) -> Void)?

  init(root: URL) {
    do {
      store = try ShortcutStore(root: root)
      hotKeys = try GlobalHotKeys()
      hotKeys?.onTrigger = { [weak self] id in self?.onTrigger?(id) }
    } catch { loadError = error.localizedDescription }
    resignObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.cancelRecording() }
    }
  }

  func synchronize(profiles: [Profile]) {
    profileIDs = profiles.map(\.id)
    guard let store, let hotKeys, loadError == nil else { return }
    do { try store.addMissingProfiles(profileIDs) } catch {
      loadError = error.localizedDescription
      hotKeys.removeAll()
      activeIDs = []
      return
    }
    values = Dictionary(
      uniqueKeysWithValues: profileIDs.compactMap { id in store.shortcut(for: id).map { (id, $0) } }
    )
    if recordingID == nil { registerAll() }
  }

  func beginRecording(for id: String) {
    guard loadError == nil else { return }
    cancelRecording()
    recordingID = id
    recordingError = nil
    hotKeys?.removeAll()
    activeIDs = []
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let consumed = MainActor.assumeIsolated {
        guard let self, let id = self.recordingID else { return false }
        if event.keyCode == 53 {
          self.cancelRecording()
          return true
        }
        if event.isARepeat { return true }
        var modifiers: ShortcutModifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        self.change(AccountShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers), for: id)
        return true
      }
      return consumed ? nil : event
    }
  }

  func change(_ shortcut: AccountShortcut?, for id: String) {
    guard let store, let hotKeys, loadError == nil else { return }
    let previous = store.shortcut(for: id)
    do {
      try store.validate(shortcut, for: id)
      try hotKeys.replace(shortcut, for: id)
      do { try store.set(shortcut, for: id) } catch {
        try? hotKeys.replace(previous, for: id)
        throw error
      }
      values[id] = shortcut
      errors[id] = nil
      recordingError = nil
      if recordingID != nil { cancelRecording() } else { registerAll() }
    } catch {
      if recordingID != nil {
        recordingError = error.localizedDescription
      } else {
        errors[id] = error.localizedDescription
      }
    }
  }

  func restoreDefault(for id: String) {
    guard let index = profileIDs.firstIndex(of: id) else { return }
    change(AccountShortcut.defaultShortcut(at: index), for: id)
  }

  func cancelRecording() {
    guard recordingID != nil else { return }
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
    recordingID = nil
    recordingError = nil
    registerAll()
  }

  private func registerAll() {
    guard let hotKeys else { return }
    for id in hotKeys.registeredIDs.subtracting(profileIDs) { try? hotKeys.replace(nil, for: id) }
    for id in profileIDs {
      do {
        try hotKeys.replace(values[id], for: id)
        errors[id] = nil
      } catch { errors[id] = error.localizedDescription }
    }
    activeIDs = hotKeys.registeredIDs
  }

  func stop() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
    if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    hotKeys?.stop()
  }
}
