import AppKit
import Darwin
import MultiCodexCore

struct DesktopInstance {
  let app: NSRunningApplication
  let location: ProcessLocation?
}

enum ProcessReader {
  static let bundleID = "com.openai.codex"

  static func instances(home: URL = FileManager.default.homeDirectoryForCurrentUser)
    -> [DesktopInstance]
  {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
      .filter { !$0.isTerminated }
      .map { DesktopInstance(app: $0, location: location(pid: $0.processIdentifier, home: home)) }
  }

  static func location(pid: pid_t, home: URL) -> ProcessLocation? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4, size < 16_777_216 else { return nil }
    var data = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &data, &size, nil, 0) == 0 else { return nil }
    data = Array(data.prefix(size))
    let argc = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
    guard argc > 0, argc < 65_536 else { return nil }
    var cursor = 4
    func string() -> String? {
      guard cursor < data.count, let end = data[cursor...].firstIndex(of: 0) else { return nil }
      defer { cursor = end + 1 }
      return String(bytes: data[cursor..<end], encoding: .utf8)
    }
    guard string() != nil else { return nil }  // Executable path, followed by padding.
    while cursor < data.count && data[cursor] == 0 { cursor += 1 }
    var userDataArgument: String?
    var expectingUserData = false
    for _ in 0..<argc {
      guard let argument = string() else { return nil }
      if expectingUserData {
        userDataArgument = argument
        expectingUserData = false
      } else if argument == "--user-data-dir" {
        expectingUserData = true
      } else if argument.hasPrefix("--user-data-dir=") {
        userDataArgument = String(argument.dropFirst(16))
      }
    }
    // Keep only path selectors. Never expose process credentials or arbitrary environment values.
    let allowed = Set(["CODEX_HOME", "CODEX_ELECTRON_USER_DATA_PATH", "CODEX_SQLITE_HOME"])
    var paths: [String: String] = [:]
    while cursor < data.count {
      guard let variable = string(), !variable.isEmpty else { break }
      guard let separator = variable.firstIndex(of: "=") else { continue }
      let key = String(variable[..<separator])
      if allowed.contains(key) {
        paths[key] = String(variable[variable.index(after: separator)...])
      }
    }
    let codex = paths["CODEX_HOME"] ?? home.appendingPathComponent(".codex").path
    let userData =
      paths["CODEX_ELECTRON_USER_DATA_PATH"] ?? userDataArgument
      ?? home.appendingPathComponent("Library/Application Support/Codex").path
    guard codex.hasPrefix("/"), userData.hasPrefix("/") else { return nil }
    return ProcessLocation(
      codexHome: codex, userData: userData, sqliteHome: paths["CODEX_SQLITE_HOME"])
  }
}
