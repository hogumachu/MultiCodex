import CustomDump
import Foundation
import Testing

@testable import MultiCodexCore

@Suite struct ShortcutTests {
  private func directory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "MultiCodexShortcuts-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  @Test func defaultsAvoidCommandNumberAndPersistCustomizationAndDisabledState() throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ShortcutStore(root: root)
    try store.addMissingProfiles(["a", "b"])
    expectNoDifference(store.shortcut(for: "a")?.display, "⌃⌥⌘1")
    expectNoDifference(store.shortcut(for: "b")?.display, "⌃⌥⌘2")
    let custom = AccountShortcut(keyCode: 40, modifiers: [.control, .shift, .command])
    try store.set(custom, for: "a")
    try store.set(nil, for: "b")
    let reopened = try ShortcutStore(root: root)
    try reopened.addMissingProfiles(["b", "a", "c"])
    expectNoDifference(reopened.shortcut(for: "a"), custom)
    expectNoDifference(reopened.shortcut(for: "b"), nil)
    expectNoDifference(reopened.shortcut(for: "c")?.display, "⌃⌥⌘3")
    let mode = try FileManager.default.attributesOfItem(
      atPath: root.appendingPathComponent("shortcuts.json").path)
    expectNoDifference((mode[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  @Test func invalidAndDuplicateEditsDoNotDiscardSavedShortcuts() throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ShortcutStore(root: root)
    try store.addMissingProfiles(["a", "b"])
    let before = try Data(contentsOf: root.appendingPathComponent("shortcuts.json"))
    #expect(throws: (any Error).self) { try store.set(store.shortcut(for: "a"), for: "b") }
    #expect(throws: (any Error).self) {
      try store.set(.init(keyCode: 999, modifiers: [.command, .option]), for: "a")
    }
    #expect(throws: (any Error).self) {
      try store.set(.init(keyCode: 18, modifiers: .init(rawValue: 0xFF)), for: "a")
    }
    expectNoDifference(try Data(contentsOf: root.appendingPathComponent("shortcuts.json")), before)
  }

  @Test(arguments: [ShortcutModifiers(), .command, .option, .shift, .control, [.option, .shift]])
  func customShortcutsAllowAnyModifierCountAndPersist(modifiers: ShortcutModifiers) throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ShortcutStore(root: root)
    try store.addMissingProfiles(["a"])
    let shortcut = AccountShortcut(keyCode: 18, modifiers: modifiers)
    try store.set(shortcut, for: "a")
    let reopened = try ShortcutStore(root: root)
    expectNoDifference(reopened.shortcut(for: "a"), shortcut)
  }

  @Test func newProfilesNeverStealACustomShortcut() throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ShortcutStore(root: root)
    try store.addMissingProfiles(["a"])
    try store.set(AccountShortcut.defaultShortcut(at: 1), for: "a")
    try store.addMissingProfiles(["a", "b"])
    expectNoDifference(store.shortcut(for: "a")?.display, "⌃⌥⌘2")
    expectNoDifference(store.shortcut(for: "b"), nil)
    expectNoDifference(AccountShortcut.defaultShortcut(at: 9), nil)
  }

  @Test func corruptShortcutsFileIsNeverReplaced() throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("shortcuts.json")
    let data = Data("broken preferences".utf8)
    try data.write(to: url)
    #expect(throws: (any Error).self) { try ShortcutStore(root: root) }
    expectNoDifference(try Data(contentsOf: url), data)
  }

  @Test func defaultStorageIsMultiCodexAndReloadsExistingProfiles() throws {
    let home = try directory()
    defer { try? FileManager.default.removeItem(at: home) }
    let root = home.appendingPathComponent("Library/Application Support/MultiCodex")
    expectNoDifference(ProfileStore.defaultRoot(home: home), root)
    let original = Profile.original(home: home)
    let store = try ProfileStore(root: root, original: original)
    let b = try store.add(name: "B")
    let before = try Data(contentsOf: root.appendingPathComponent("profiles.json"))
    let reopened = try ProfileStore(root: ProfileStore.defaultRoot(home: home), original: original)
    expectNoDifference(reopened.profiles, [original, b])
    expectNoDifference(try Data(contentsOf: root.appendingPathComponent("profiles.json")), before)
  }

}

@Suite(.serialized) @MainActor struct NativeHotKeyTests {
  @Test func conflictingReplacementRetainsOldRegistrationAndUnregisterReleasesKeys() throws {
    let first = try GlobalHotKeys()
    let second = try GlobalHotKeys()
    defer {
      first.stop()
      second.stop()
    }
    let a = AccountShortcut(keyCode: 103, modifiers: [.control, .option, .shift, .command])
    let b = AccountShortcut(keyCode: 111, modifiers: [.control, .option, .shift, .command])
    try first.replace(a, for: "a")
    try second.replace(b, for: "b")
    #expect(throws: (any Error).self) { try first.replace(b, for: "a") }
    expectNoDifference(first.registeredIDs, ["a"])
    #expect(throws: (any Error).self) { try second.replace(a, for: "c") }
    first.removeAll()
    try second.replace(a, for: "c")
    expectNoDifference(second.registeredIDs, ["b", "c"])
    try second.replace(nil, for: "c")
    expectNoDifference(second.registeredIDs, ["b"])
  }
}
