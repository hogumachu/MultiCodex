import Foundation

public final class ProfileStore {
  public static func defaultRoot(home: URL) -> URL {
    home.appendingPathComponent("Library/Application Support/MultiCodex")
  }
  private struct Registry: Codable {
    var version = 1
    var profiles: [Profile]
  }

  public let root: URL
  public private(set) var profiles: [Profile]
  private let fileManager: FileManager
  private var registryURL: URL { root.appendingPathComponent("profiles.json") }

  public init(root: URL, original: Profile, fileManager: FileManager = .default) throws {
    self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    self.fileManager = fileManager
    profiles = []
    if fileManager.fileExists(atPath: registryURL.path) {
      do {
        let registry = try JSONDecoder().decode(Registry.self, from: Data(contentsOf: registryURL))
        guard registry.version == 1,
          registry.profiles.filter({ $0.kind == .original }).count == 1,
          Set(registry.profiles.map(\.id)).count == registry.profiles.count
        else {
          throw MultiCodexError.invalidRegistry
        }
        profiles = registry.profiles
        for profile in profiles { try validate(profile) }
      } catch { throw MultiCodexError.invalidRegistry }
    } else {
      try privateDirectory(self.root)
      profiles = [original]
      try persist(profiles)
    }
  }

  @discardableResult
  public func add(name: String, id: UUID = UUID()) throws -> Profile {
    let name = try validatedName(name)
    let identifier = id.uuidString.lowercased()
    let directory = root.appendingPathComponent("profiles/\(identifier)")
    // A reused ID must never adopt another profile's credentials or conversations.
    guard !fileManager.fileExists(atPath: directory.path),
      !profiles.contains(where: { $0.id == identifier })
    else {
      throw MultiCodexError.unsafePath
    }
    let codex = directory.appendingPathComponent("codex")
    let userData = directory.appendingPathComponent("user-data")
    let sqlite = codex.appendingPathComponent("sqlite")
    let profile = Profile(
      id: identifier, name: name, kind: .managed,
      codexHome: codex.path, userData: userData.path, sqliteHome: sqlite.path)
    try validate(profile)
    try privateDirectory(root.appendingPathComponent("profiles"))
    for path in [directory, codex, userData, sqlite] { try privateDirectory(path) }
    // Only new profiles get this config. Existing account files are never written.
    let sqlitePath = sqlite.path.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")
    let config = Data(
      "cli_auth_credentials_store = \"file\"\nsqlite_home = \"\(sqlitePath)\"\n".utf8)
    let configURL = codex.appendingPathComponent("config.toml")
    try config.write(to: configURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    let updated = profiles + [profile]
    try persist(updated)
    profiles = updated
    return profile
  }

  public func rename(id: String, name: String) throws {
    guard let index = profiles.firstIndex(where: { $0.id == id }) else {
      throw MultiCodexError.profileMissing
    }
    let name = try validatedName(name, excluding: id)
    var updated = profiles
    updated[index].name = name
    try persist(updated)
    profiles = updated
  }

  public func validate(_ profile: Profile) throws {
    guard !profile.name.isEmpty,
      profile.codexHome.hasPrefix("/"), profile.userData.hasPrefix("/"),
      canonicalPath(profile.codexHome) != canonicalPath(profile.userData)
    else {
      throw MultiCodexError.unsafePath
    }
    if profile.kind == .original {
      guard profile.id == "original" else { throw MultiCodexError.invalidRegistry }
      return
    }
    guard UUID(uuidString: profile.id) != nil else { throw MultiCodexError.unsafePath }
    let directory = root.appendingPathComponent("profiles/\(profile.id)")
    // Comparing resolved paths also rejects symlinked profile folders that escape this root.
    let expectedDirectory = root.path + "/profiles/" + profile.id
    guard canonicalPath(directory.path) == expectedDirectory,
      canonicalPath(profile.codexHome) == expectedDirectory + "/codex",
      canonicalPath(profile.userData) == expectedDirectory + "/user-data",
      profile.sqliteHome.map(canonicalPath) == expectedDirectory + "/codex/sqlite"
    else {
      throw MultiCodexError.unsafePath
    }
    if let original = profiles.first(where: { $0.kind == .original }) {
      guard canonicalPath(profile.codexHome) != canonicalPath(original.codexHome),
        canonicalPath(profile.userData) != canonicalPath(original.userData)
      else { throw MultiCodexError.unsafePath }
    }
  }

  private func validatedName(_ name: String, excluding id: String? = nil) throws -> String {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= 40,
      name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
    else {
      throw MultiCodexError.invalidName
    }
    guard
      !profiles.contains(where: {
        $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
      })
    else {
      throw MultiCodexError.duplicateName
    }
    return name
  }

  private func privateDirectory(_ url: URL) throws {
    try fileManager.createDirectory(
      at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
  }

  private func persist(_ profiles: [Profile]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(Registry(profiles: profiles)).write(to: registryURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registryURL.path)
  }
}
