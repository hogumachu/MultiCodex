import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  public static let control = Self(rawValue: 1)
  public static let option = Self(rawValue: 2)
  public static let shift = Self(rawValue: 4)
  public static let command = Self(rawValue: 8)
  public static let all: Self = [.control, .option, .shift, .command]
}

public struct AccountShortcut: Codable, Hashable, Sendable {
  public var keyCode: UInt32
  public var modifiers: ShortcutModifiers

  public init(keyCode: UInt32, modifiers: ShortcutModifiers) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  // Physical keys make the shortcut usable even while a Korean input source is active.
  public static let keys: [UInt32: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
    11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
    18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
    27: "−", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
    37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
    46: "M", 47: ".", 49: "Space", 50: "`", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
    100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2",
    122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
  ]

  public var display: String {
    (modifiers.contains(.control) ? "⌃" : "")
      + (modifiers.contains(.option) ? "⌥" : "")
      + (modifiers.contains(.shift) ? "⇧" : "")
      + (modifiers.contains(.command) ? "⌘" : "")
      + (Self.keys[keyCode] ?? "?")
  }

  public func validate() throws {
    guard Self.keys[keyCode] != nil,
      modifiers.subtracting(.all).isEmpty
    else {
      throw ShortcutError.unsupportedKey
    }
  }

  public static func defaultShortcut(at index: Int) -> Self? {
    let codes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    guard codes.indices.contains(index) else { return nil }
    return Self(keyCode: codes[index], modifiers: [.control, .option, .command])
  }
}

public enum ShortcutError: LocalizedError {
  case unsupportedKey, duplicate, invalidFile, unavailable
  case registration(Int32)
  public var errorDescription: String? {
    switch self {
    case .unsupportedKey: "지원하지 않는 키입니다. 다른 키를 선택해 주세요."
    case .duplicate: "다른 계정에 지정된 단축키입니다. 다른 조합을 입력해 주세요."
    case .invalidFile: "단축키 설정을 읽을 수 없어 단축키를 껐습니다. 설정 파일을 확인한 뒤 다시 실행해 주세요."
    case .unavailable: "단축키 서비스를 시작하지 못했습니다. 메뉴에서 계정을 열 수 있습니다."
    case .registration: "시스템이나 다른 앱이 사용 중인 단축키입니다. 다른 조합을 선택해 주세요."
    }
  }
}

public final class ShortcutStore {
  private struct Setting: Codable { var shortcut: AccountShortcut? }
  private struct File: Codable {
    var version = 1
    var profiles: [String: Setting] = [:]
  }
  private var file: File
  private let url: URL

  public init(root: URL) throws {
    url = root.appendingPathComponent("shortcuts.json")
    if FileManager.default.fileExists(atPath: url.path) {
      do {
        file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        guard file.version == 1 else { throw ShortcutError.invalidFile }
        let shortcuts = file.profiles.values.compactMap(\.shortcut)
        for shortcut in shortcuts { try shortcut.validate() }
        guard Set(shortcuts).count == shortcuts.count else { throw ShortcutError.invalidFile }
      } catch { throw ShortcutError.invalidFile }
    } else {
      file = File()
    }
  }

  public func shortcut(for id: String) -> AccountShortcut? { file.profiles[id]?.shortcut }

  public func addMissingProfiles(_ ids: [String]) throws {
    var next = file
    for (index, id) in ids.enumerated() where next.profiles[id] == nil {
      let candidate = AccountShortcut.defaultShortcut(at: index)
      let used = Set(next.profiles.values.compactMap(\.shortcut))
      next.profiles[id] = Setting(shortcut: candidate.flatMap { used.contains($0) ? nil : $0 })
    }
    if next.profiles.count != file.profiles.count { try persist(next) }
  }

  public func validate(_ shortcut: AccountShortcut?, for id: String) throws {
    guard let shortcut else { return }
    try shortcut.validate()
    guard !file.profiles.contains(where: { $0.key != id && $0.value.shortcut == shortcut }) else {
      throw ShortcutError.duplicate
    }
  }

  public func set(_ shortcut: AccountShortcut?, for id: String) throws {
    try validate(shortcut, for: id)
    var next = file
    next.profiles[id] = Setting(shortcut: shortcut)
    try persist(next)
  }

  private func persist(_ next: File) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(next).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    file = next
  }
}
