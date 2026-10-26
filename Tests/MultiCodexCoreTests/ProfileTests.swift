import CustomDump
import Foundation
import Testing

@testable import MultiCodexCore

private struct Fixture {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "MultiCodexTests-\(UUID())")
  var original: Profile { Profile.original(home: root.appendingPathComponent("existing-user")) }
  var storeRoot: URL { root.appendingPathComponent("MultiCodex data with spaces") }
  func clean() { try? FileManager.default.removeItem(at: root) }
  func store() throws -> ProfileStore { try ProfileStore(root: storeRoot, original: original) }

  func savedLogin(_ profile: Profile, account: String, token: String = "test-refresh") throws {
    let directory = URL(fileURLWithPath: profile.codexHome)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: [
      "auth_mode": "chatgpt",
      "tokens": [
        "account_id": account, "access_token": "synthetic-test-access", "refresh_token": token,
        "id_token": "a.e30.z",
      ],
    ])
    try data.write(to: directory.appendingPathComponent("auth.json"))
  }

  @discardableResult
  func chat(_ profile: Profile, name: String) throws -> URL {
    let directory = URL(fileURLWithPath: profile.codexHome).appendingPathComponent(
      "sessions/2026/10/26")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent(name + ".jsonl")
    try Data("synthetic conversation".utf8).write(to: file)
    return file
  }
}

@Suite struct ProfileStoreTests {
  @Test func addingAndReloadingProfilesLeavesOriginalFilesUntouched() throws {
    let fixture = Fixture()
    defer { fixture.clean() }
    try fixture.savedLogin(fixture.original, account: "original")
    let chat = try fixture.chat(fixture.original, name: "original-chat")
    let chatBefore = try Data(contentsOf: chat)
    let auth = URL(fileURLWithPath: fixture.original.codexHome).appendingPathComponent("auth.json")
    let before = try Data(contentsOf: auth)
    let store = try fixture.store()
    let b = try store.add(name: "B · Work")
    let c = try store.add(name: "C · Personal")
    let reopened = try fixture.store()
    #expect(reopened.profiles.count == 3)
    #expect(b.codexHome != c.codexHome)
    #expect(b.userData != c.userData)
    #expect(b.sqliteHome != c.sqliteHome)
    #expect(try Data(contentsOf: auth) == before)
    #expect(try Data(contentsOf: chat) == chatBefore)
    #expect(!FileManager.default.fileExists(atPath: b.codexHome + "/auth.json"))
    let config = try String(contentsOfFile: b.codexHome + "/config.toml", encoding: .utf8)
    #expect(config.contains("cli_auth_credentials_store = \"file\""))
    let attributes = try FileManager.default.attributesOfItem(atPath: b.codexHome)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
  }

  @Test(arguments: [false, true])
  func renamingPersistsWithoutChangingAccountDataOrShortcuts(managed: Bool) throws {
    let fixture = Fixture()
    defer { fixture.clean() }
    let store = try fixture.store()
    let profile = managed ? try store.add(name: "Work") : fixture.original
    try fixture.savedLogin(profile, account: "account")
    let chatURL = try fixture.chat(profile, name: "existing-chat")
    let authURL = URL(fileURLWithPath: profile.codexHome).appendingPathComponent("auth.json")
    let authBefore = try Data(contentsOf: authURL)
    let chatBefore = try Data(contentsOf: chatURL)
    let shortcuts = try ShortcutStore(root: fixture.storeRoot)
    try shortcuts.synchronizeProfiles(store.profiles.map(\.id))
    let shortcutsURL = fixture.storeRoot.appendingPathComponent("shortcuts.json")
    let shortcutsBefore = try Data(contentsOf: shortcutsURL)

    try store.rename(id: profile.id, name: "  새 계정 제목  ")

    var expected = profile
    expected.name = "새 계정 제목"
    expectNoDifference(store.profiles.first { $0.id == profile.id }, expected)
    expectNoDifference(try fixture.store().profiles, store.profiles)
    #expect(try Data(contentsOf: authURL) == authBefore)
    #expect(try Data(contentsOf: chatURL) == chatBefore)
    #expect(try Data(contentsOf: shortcutsURL) == shortcutsBefore)
  }

  @Test func invalidRenameLeavesRegistryAndMemoryUnchanged() throws {
    let fixture = Fixture()
    defer { fixture.clean() }
    let store = try fixture.store()
    let profile = try store.add(name: "Work")
    let original = store.profiles
    let registry = fixture.storeRoot.appendingPathComponent("profiles.json")
    let before = try Data(contentsOf: registry)
    for name in ["", " \n ", "bad\nname", String(repeating: "가", count: 41), fixture.original.name]
    {
      #expect(throws: (any Error).self) { try store.rename(id: profile.id, name: name) }
      expectNoDifference(store.profiles, original)
      #expect(try Data(contentsOf: registry) == before)
    }
    #expect(throws: (any Error).self) { try store.rename(id: "missing", name: "New") }
    expectNoDifference(store.profiles, original)
    #expect(try Data(contentsOf: registry) == before)
  }

  @Test func renameAllowsOwnNameButRejectsAnotherAccountIgnoringCase() throws {
    let fixture = Fixture()
    defer { fixture.clean() }
    let store = try fixture.store()
    let first = try store.add(name: "Work")
    let second = try store.add(name: "Personal")
    try store.rename(id: first.id, name: " work ")
    #expect(store.profiles.first { $0.id == first.id }?.name == "work")
    #expect(throws: (any Error).self) { try store.rename(id: second.id, name: " WORK ") }
    #expect(try fixture.store().profiles.first { $0.id == second.id }?.name == "Personal")
  }

  @Test func removingRegistrationPersistsAndKeepsAccountFilesUntouched() throws {
    let fixture = Fixture()
    defer { fixture.clean() }
    let store = try fixture.store()
    let removed = try store.add(name: "Work")
    let retained = try store.add(name: "Personal")
    for profile in store.profiles { try fixture.savedLogin(profile, account: profile.id) }
    let chat = try fixture.chat(removed, name: "saved-chat")
    let preferences = URL(fileURLWithPath: removed.userData).appendingPathComponent(
      "preferences.json")
    let database = URL(fileURLWithPath: try #require(removed.sqliteHome)).appendingPathComponent(
      "state.sqlite")
    try Data("synthetic preferences".utf8).write(to: preferences)
    try Data("synthetic database bytes".utf8).write(to: database)
    let files =
      store.profiles.map { URL(fileURLWithPath: $0.codexHome).appendingPathComponent("auth.json") }
      + [
        chat, preferences, database,
        URL(fileURLWithPath: removed.codexHome).appendingPathComponent("config.toml"),
      ]
    let contents = try files.map { try Data(contentsOf: $0) }

    try store.removeRegistration(id: removed.id)

    expectNoDifference(store.profiles, [fixture.original, retained])
    expectNoDifference(try fixture.store().profiles, store.profiles)
    expectNoDifference(try files.map { try Data(contentsOf: $0) }, contents)
    let replacement = try store.add(name: "Work")
    #expect(replacement.id != removed.id)
    #expect(replacement.codexHome != removed.codexHome)
    #expect(throws: (any Error).self) {
      try store.add(name: "Reused", id: try #require(UUID(uuidString: removed.id)))
    }
  }

  @Test func originalAndUnknownProfilesCannotBeRemoved() throws {
    let fixture = Fixture()
    defer { fixture.clean() }
    let store = try fixture.store()
    _ = try store.add(name: "Work")
    let before = store.profiles
    let registry = fixture.storeRoot.appendingPathComponent("profiles.json")
    let data = try Data(contentsOf: registry)
    for id in [fixture.original.id, "missing"] {
      #expect(throws: (any Error).self) { try store.removeRegistration(id: id) }
      expectNoDifference(store.profiles, before)
      expectNoDifference(try Data(contentsOf: registry), data)
    }
  }

  @Test func failedRemovalWriteKeepsRegistrationInMemory() throws {
    let fixture = Fixture()
    defer { fixture.clean() }
    let store = try fixture.store()
    let profile = try store.add(name: "Work")
    let before = store.profiles
    let registry = fixture.storeRoot.appendingPathComponent("profiles.json")
    try FileManager.default.removeItem(at: registry)
    try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: false)
    #expect(throws: (any Error).self) { try store.removeRegistration(id: profile.id) }
    expectNoDifference(store.profiles, before)
    #expect(FileManager.default.fileExists(atPath: profile.codexHome))
  }

  @Test func corruptRegistryIsNeverReplaced() throws {
    let fixture = Fixture()
    defer { fixture.clean() }
    _ = try fixture.store()
    let url = fixture.storeRoot.appendingPathComponent("profiles.json")
    let corrupt = Data("not valid JSON".utf8)
    try corrupt.write(to: url)
    #expect(throws: (any Error).self) { try fixture.store() }
    #expect(try Data(contentsOf: url) == corrupt)
  }

  @Test func invalidNamesAndIDReuseCannotAdoptAnotherProfile() throws {
    let fixture = Fixture()
    defer { fixture.clean() }
    let store = try fixture.store()
    #expect(throws: (any Error).self) { try store.add(name: " \n ") }
    #expect(throws: (any Error).self) { try store.add(name: "bad\nname") }
    let id = UUID()
    _ = try store.add(name: "Work", id: id)
    #expect(throws: (any Error).self) { try store.add(name: " work ") }
    #expect(throws: (any Error).self) { try store.add(name: "Different", id: id) }
  }

  @Test func escapingAndSymlinkedPathsAreRejected() throws {
    let fixture = Fixture()
    defer { fixture.clean() }
    let store = try fixture.store()
    var b = try store.add(name: "B")
    let managedHome = b.codexHome
    b.codexHome = fixture.original.codexHome
    #expect(throws: (any Error).self) { try store.validate(b) }
    b.codexHome = managedHome
    try FileManager.default.removeItem(atPath: managedHome)
    try FileManager.default.createDirectory(
      atPath: fixture.original.codexHome, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: managedHome, withDestinationPath: fixture.original.codexHome)
    #expect(throws: (any Error).self) { try store.validate(b) }
  }

  @Test func identityRequiresBothStorageDirectoriesAndSQLiteIsolation() throws {
    let fixture = Fixture()
    defer { fixture.clean() }
    let store = try fixture.store()
    let b = try store.add(name: "B")
    let correct = ProcessLocation(
      codexHome: b.codexHome, userData: b.userData, sqliteHome: b.sqliteHome)
    #expect(correct.matches(b))
    #expect(
      !ProcessLocation(
        codexHome: b.codexHome, userData: fixture.original.userData, sqliteHome: b.sqliteHome
      ).matches(b))
    #expect(
      !ProcessLocation(
        codexHome: b.codexHome, userData: b.userData, sqliteHome: fixture.original.codexHome
      ).matches(b))
    #expect(b.launchArguments.count == 1)
    #expect(b.launchArguments[0].contains("MultiCodex data with spaces"))
    #expect(b.launchEnvironment["CODEX_SQLITE_HOME"] == b.sqliteHome)
    #expect(!b.launchEnvironment.keys.contains("OPENAI_API_KEY"))
  }
}

@Suite struct AuthSummaryTests {
  @Test func savedLoginReadsEmailAndSurvivesTokenRotation() throws {
    let fixture = Fixture()
    defer { fixture.clean() }
    let home = URL(fileURLWithPath: fixture.original.codexHome)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let claims = try JSONSerialization.data(withJSONObject: ["email": "person@example.com"])
      .base64EncodedString().replacingOccurrences(of: "=", with: "")
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    for refresh in ["first", "rotated"] {
      let data = try JSONSerialization.data(withJSONObject: [
        "tokens": [
          "account_id": "account", "access_token": "synthetic-access", "refresh_token": refresh,
          "id_token": "header.\(claims).signature",
        ]
      ])
      try data.write(to: home.appendingPathComponent("auth.json"))
      let summary = AuthSummary.read(home: home)
      #expect(summary.hasSavedLogin)
      #expect(summary.email == "person@example.com")
    }
  }

  @Test func missingOrMalformedCredentialsDoNotAppearSignedIn() throws {
    let fixture = Fixture()
    defer { fixture.clean() }
    let home = URL(fileURLWithPath: fixture.original.codexHome)
    #expect(!AuthSummary.read(home: home).hasSavedLogin)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    for content in [
      "not json", "{}", "{\"tokens\":{\"account_id\":\"account\"}}",
      String(repeating: "x", count: 128_000),
    ] {
      try Data(content.utf8).write(to: home.appendingPathComponent("auth.json"))
      let summary = AuthSummary.read(home: home)
      #expect(!summary.hasSavedLogin)
      #expect(summary.email == nil)
    }
  }

  @Test func savedCredentialsWithoutEmailRemainRecognized() throws {
    let fixture = Fixture()
    defer { fixture.clean() }
    try fixture.savedLogin(fixture.original, account: "account")
    let summary = AuthSummary.read(home: URL(fileURLWithPath: fixture.original.codexHome))
    #expect(summary.hasSavedLogin)
    #expect(summary.email == nil)
  }
}
