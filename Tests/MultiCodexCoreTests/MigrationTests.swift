import Foundation
import Testing

@testable import MultiCodexCore

private struct MigrationFixture {
  let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
    .appendingPathComponent("Migration-\(UUID())")
  var source: Profile { profile("source") }
  var target: Profile { profile("target") }
  func profile(_ name: String) -> Profile {
    Profile(
      id: name, name: name, kind: .managed, codexHome: root.appendingPathComponent(name).path,
      userData: root.appendingPathComponent(name + "-user").path)
  }
  func write(_ profile: Profile, _ file: String, _ value: String) throws {
    let url = URL(fileURLWithPath: profile.codexHome).appendingPathComponent(file)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(value.utf8).write(to: url)
  }
  func read(_ profile: Profile, _ file: String) throws -> String {
    try String(contentsOfFile: profile.codexHome + "/" + file, encoding: .utf8)
  }
  func migrate(_ selection: MigrationSelection = .init()) throws -> MigrationResult {
    try ProfileMigration(
      source: source, target: target, backupRoot: root.appendingPathComponent("backups")
    ).run(selection: selection)
  }
  func clean() { try? FileManager.default.removeItem(at: root) }
  func state(_ profile: Profile) throws -> MigrationDatabase {
    try write(profile, "auth.json", "AUTH-\(profile.id)")
    let db = try MigrationDatabase(URL(fileURLWithPath: profile.codexHome + "/state_5.sqlite"))
    try db.execute(
      "CREATE TABLE _sqlx_migrations(version INTEGER PRIMARY KEY, checksum BLOB); INSERT INTO _sqlx_migrations VALUES(1, X'01'); CREATE TABLE projects(id TEXT PRIMARY KEY, name TEXT); CREATE TABLE project_roots(project_id TEXT REFERENCES projects(id), position INTEGER, path TEXT, PRIMARY KEY(project_id, position)); CREATE TABLE thread_sections(id TEXT PRIMARY KEY, name TEXT); CREATE TABLE threads(id TEXT PRIMARY KEY, rollout_path TEXT, project_id TEXT REFERENCES projects(id), thread_section_id TEXT REFERENCES thread_sections(id), creator_user_id TEXT, creator_account_id TEXT, title TEXT, history_mode TEXT); CREATE TABLE thread_attachments(id TEXT PRIMARY KEY, thread_id TEXT REFERENCES threads(id), payload TEXT)"
    )
    return db
  }
  func history(_ profile: Profile) throws -> MigrationDatabase {
    let db = try MigrationDatabase(
      URL(fileURLWithPath: profile.codexHome + "/thread_history_1.sqlite"))
    try db.execute(
      "CREATE TABLE _sqlx_migrations(version INTEGER PRIMARY KEY, checksum BLOB); INSERT INTO _sqlx_migrations VALUES(1,X'01'); CREATE TABLE thread_items(thread_id TEXT, item_id TEXT, item_json TEXT, PRIMARY KEY(thread_id,item_id))"
    )
    return db
  }
}

@Suite struct MigrationTests {
  @Test func importsProjectsRolloutsAndPaginatedHistoryWithoutCredentials() throws {
    let f = MigrationFixture()
    defer { f.clean() }
    let source = try f.state(f.source)
    let target = try f.state(f.target)
    try f.write(f.source, "keybindings.json", #"[{"command":"newTask","key":"Cmd+K"}]"#)
    try f.write(f.target, "keybindings.json", "[]")
    try f.write(
      f.source, "sessions/a.jsonl", #"{"type":"session_meta","payload":{"id":"a"}}"# + "\n")
    try f.write(f.target, "sessions/b.jsonl", "target rollout")
    try source.execute(
      "INSERT INTO projects VALUES('p','Source'); INSERT INTO project_roots VALUES('p',0,'/tmp/project'); INSERT INTO threads VALUES('a','\(f.source.codexHome)/sessions/a.jsonl','p',NULL,'user-a','account-a','source title','paginated'); INSERT INTO thread_attachments VALUES('attachment','a','payload')"
    )
    try target.execute(
      "INSERT INTO threads VALUES('b','\(f.target.codexHome)/sessions/b.jsonl',NULL,NULL,'user-b','account-b','target title','paginated')"
    )
    source.close()
    target.close()
    let sh = try f.history(f.source)
    try sh.execute("INSERT INTO thread_items VALUES('a','item','source message')")
    sh.close()
    let th = try f.history(f.target)
    try th.execute("INSERT INTO thread_items VALUES('b','item','target message')")
    th.close()
    try f.write(
      f.source, ".codex-global-state.json",
      #"{"electron-saved-workspace-roots":["/tmp/project"],"environment-catalog-cache-v1":{"accountId":"A"}}"#
    )
    try f.write(
      f.target, ".codex-global-state.json",
      #"{"electron-saved-workspace-roots":["/tmp/target"],"environment-catalog-cache-v1":{"accountId":"B"}}"#
    )
    let result = try f.migrate()
    #expect(result.projects == 1 && result.conversations == 1)
    #expect(try f.read(f.target, "auth.json") == "AUTH-target")
    #expect(try f.read(f.source, "auth.json") == "AUTH-source")
    #expect(try f.read(f.target, "keybindings.json") == f.read(f.source, "keybindings.json"))
    #expect(try f.read(f.target, "sessions/a.jsonl") == f.read(f.source, "sessions/a.jsonl"))
    let db = try MigrationDatabase(URL(fileURLWithPath: f.target.codexHome + "/state_5.sqlite"))
    #expect(try db.rows("SELECT id FROM threads ORDER BY id") == [["a"], ["b"]])
    #expect(
      try db.rows("SELECT rollout_path,creator_account_id FROM threads WHERE id='a'") == [
        [f.target.codexHome + "/sessions/a.jsonl", nil]
      ])
    db.close()
    let h = try MigrationDatabase(
      URL(fileURLWithPath: f.target.codexHome + "/thread_history_1.sqlite"))
    #expect(
      try h.rows("SELECT item_json FROM thread_items ORDER BY thread_id") == [
        ["source message"], ["target message"],
      ])
    h.close()
    let global = try f.read(f.target, ".codex-global-state.json")
    #expect(global.contains("accountId\":\"B"))
    let again = try f.migrate()
    #expect(again.projects == 0 && again.conversations == 0)
  }

  @Test func schemaMismatchDoesNotPartiallyReplaceShortcuts() throws {
    let f = MigrationFixture()
    defer { f.clean() }
    let s = try f.state(f.source)
    s.close()
    let t = try f.state(f.target)
    try t.execute("UPDATE _sqlx_migrations SET checksum=X'02'")
    t.close()
    try f.write(f.source, "keybindings.json", #"[{"command":"newTask","key":null}]"#)
    try f.write(f.target, "keybindings.json", "[]")
    #expect(throws: MigrationError.self) { try f.migrate() }
    #expect(try f.read(f.target, "keybindings.json") == "[]")
  }

  @Test func rollsBackEarlierWritesOnLateSymlinkFailure() throws {
    let f = MigrationFixture()
    defer { f.clean() }
    try f.write(f.source, "keybindings.json", #"[{"command":"newTask","key":null}]"#)
    try f.write(f.target, "keybindings.json", "[]")
    try f.write(
      f.source, "sessions/a.jsonl", #"{"type":"session_meta","payload":{"id":"a"}}"# + "\n")
    let outside = f.root.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: f.target.codexHome + "/sessions", withDestinationPath: outside.path)
    #expect(throws: MigrationError.self) { try f.migrate() }
    #expect(try f.read(f.target, "keybindings.json") == "[]")
    #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("a.jsonl").path))
  }

  @Test func shortcutsOnlyDoesNotTouchProjectsOrAuth() throws {
    let f = MigrationFixture()
    defer { f.clean() }
    try f.write(f.source, "keybindings.json", #"[{"command":"newTask","key":null}]"#)
    try f.write(f.target, "auth.json", "keep")
    try f.write(f.target, ".codex-global-state.json", "existing state")
    var selection = MigrationSelection()
    selection.projects = false
    selection.conversations = false
    _ = try f.migrate(selection)
    #expect(try f.read(f.target, "auth.json") == "keep")
    #expect(try f.read(f.target, ".codex-global-state.json") == "existing state")
  }
}

@Suite struct InstalledCodexMigrationTests {
  @Test func installedSchemaImportsIntoFreshProfile() throws {
    let f = MigrationFixture()
    defer { f.clean() }
    try f.write(f.source, "auth.json", "source-secret")
    try f.write(f.target, "auth.json", "target-secret")
    for name in ["state_5", "thread_history_1"] {
      let schema = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/\(name).sql")
      let db = try MigrationDatabase(URL(fileURLWithPath: f.source.codexHome + "/\(name).sqlite"))
      try db.execute(String(contentsOf: schema, encoding: .utf8))
      if name == "state_5" {
        try db.execute("PRAGMA journal_mode=WAL")
        try db.execute(
          "INSERT INTO projects(id,name,position,created_at_ms,updated_at_ms) VALUES ('p','Project',0,1,1); INSERT INTO project_roots VALUES('p',0,'/tmp/project')"
        )
        try db.execute(
          "INSERT INTO threads(id,rollout_path,created_at,updated_at,source,model_provider,cwd,title,sandbox_policy,approval_mode,project_id,history_mode) VALUES ('a','\(f.source.codexHome)/archived_sessions/a.jsonl',1,1,'cli','openai','/tmp/project','Archived conversation','{}','on-request','p','paginated')"
        )
        try db.execute("UPDATE threads SET archived=1 WHERE id='a'")
      } else {
        try db.execute(
          "INSERT INTO thread_turns(thread_id,turn_id,rollout_ordinal,status) VALUES('a','turn',1,'completed'); INSERT INTO thread_items(thread_id,turn_id,item_id,rollout_ordinal,created_at_ms,item_json) VALUES('a','turn','item',1,1,'{\"type\":\"agentMessage\",\"text\":\"hello\"}')"
        )
      }
      db.close()
    }
    try f.write(
      f.source, "archived_sessions/a.jsonl", #"{"type":"session_meta","payload":{"id":"a"}}"# + "\n"
    )
    let result = try f.migrate()
    #expect(result.conversations == 1 && result.projects == 1)
    let db = try MigrationDatabase(URL(fileURLWithPath: f.target.codexHome + "/state_5.sqlite"))
    #expect(
      try db.rows("SELECT archived,project_id,rollout_path FROM threads") == [
        ["1", "p", f.target.codexHome + "/archived_sessions/a.jsonl"]
      ])
    #expect(try db.rows("SELECT count(*) FROM remote_control_enrollments") == [["0"]])
    try db.check()
    db.close()
    let history = try MigrationDatabase(
      URL(fileURLWithPath: f.target.codexHome + "/thread_history_1.sqlite"))
    #expect(try history.rows("SELECT count(*) FROM thread_items") == [["1"]])
    history.close()
    #expect(try f.read(f.target, "auth.json") == "target-secret")
    let repeatImport = try f.migrate()
    #expect(repeatImport.conversations == 0)
  }
}

@Suite struct MigrationRecoveryTests {
  @Test func restoreReturnsTargetToOriginalStateAndRemovesNewFiles() throws {
    let f = MigrationFixture()
    defer { f.clean() }
    try f.write(f.source, "keybindings.json", #"[{"command":"newTask","key":null}]"#)
    try f.write(f.target, "keybindings.json", "[]")
    try f.write(
      f.source, "sessions/new.jsonl", #"{"type":"session_meta","payload":{"id":"new"}}"# + "\n")
    try f.write(f.target, "auth.json", "keep")
    let result = try f.migrate()
    let migration = ProfileMigration(
      source: f.source, target: f.target, backupRoot: f.root.appendingPathComponent("backups"))
    try migration.restoreBackup(result.backup)
    #expect(try f.read(f.target, "keybindings.json") == "[]")
    #expect(try f.read(f.target, "auth.json") == "keep")
    #expect(!FileManager.default.fileExists(atPath: f.target.codexHome + "/sessions/new.jsonl"))
  }

  @Test func forgedRestorePathCannotOverwriteAuthentication() throws {
    let f = MigrationFixture()
    defer { f.clean() }
    try f.write(f.target, "auth.json", "keep")
    var selection = MigrationSelection()
    selection.projects = false
    selection.conversations = false
    let result = try f.migrate(selection)
    let data = try JSONSerialization.data(withJSONObject: [
      ["destination": f.target.codexHome + "/auth.json"]
    ])
    try data.write(to: result.backup.appendingPathComponent("undo.json"))
    let migration = ProfileMigration(
      source: f.source, target: f.target, backupRoot: f.root.appendingPathComponent("backups"))
    #expect(throws: MigrationError.self) { try migration.restoreBackup(result.backup) }
    #expect(try f.read(f.target, "auth.json") == "keep")
  }

  @Test func interruptedMigrationRequiresRecoveryBeforeAnotherImport() throws {
    let f = MigrationFixture()
    defer { f.clean() }
    try f.write(f.target, "auth.json", "keep")
    var selection = MigrationSelection()
    selection.projects = false
    selection.conversations = false
    let result = try f.migrate(selection)
    try FileManager.default.removeItem(at: result.backup.appendingPathComponent("status"))
    #expect(throws: MigrationError.self) { try f.migrate(selection) }
    try ProfileMigration(
      source: f.source, target: f.target, backupRoot: f.root.appendingPathComponent("backups")
    ).restoreBackup(result.backup)
    _ = try f.migrate(selection)
  }
}

@Suite struct MigrationIsolationTests {
  @Test func sameSQLiteHomeIsRejectedWithoutModifyingSource() throws {
    let f = MigrationFixture()
    defer { f.clean() }
    let db = try f.state(f.source)
    db.close()
    try f.write(f.target, "config.toml", "sqlite_home = '\(f.source.codexHome)' # shared path\n")
    let original = try Data(
      contentsOf: URL(fileURLWithPath: f.source.codexHome + "/state_5.sqlite"))
    #expect(throws: MigrationError.self) { try f.migrate() }
    #expect(
      try Data(contentsOf: URL(fileURLWithPath: f.source.codexHome + "/state_5.sqlite")) == original
    )
  }

  @Test func missingPaginatedHistoryFailsBeforeChangingTarget() throws {
    let f = MigrationFixture()
    defer { f.clean() }
    let db = try f.state(f.source)
    try db.execute(
      "INSERT INTO threads VALUES ('a','\(f.source.codexHome)/sessions/a.jsonl',NULL,NULL,NULL,NULL,'title','paginated')"
    )
    db.close()
    try f.write(
      f.source, "sessions/a.jsonl", #"{"type":"session_meta","payload":{"id":"a"}}"# + "\n")
    try f.write(f.target, "keybindings.json", "[]")
    #expect(throws: MigrationError.self) { try f.migrate() }
    #expect(!FileManager.default.fileExists(atPath: f.target.codexHome + "/sessions/a.jsonl"))
  }
}

@Suite struct MigrationPathAliasTests {
  @Test func restoresPrivateTmpAliasUsedByTheUI() throws {
    let root = URL(fileURLWithPath: "/private/tmp/MultiCodexAlias-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = Profile(
      id: "a", name: "A", kind: .original, codexHome: root.appendingPathComponent("a").path,
      userData: root.appendingPathComponent("a-user").path)
    let target = Profile(
      id: "b", name: "B", kind: .managed, codexHome: root.appendingPathComponent("b").path,
      userData: root.appendingPathComponent("b-user").path)
    let migration = ProfileMigration(
      source: source, target: target, backupRoot: root.appendingPathComponent("backups"))
    var selection = MigrationSelection()
    selection.projects = false
    selection.conversations = false
    let result = try migration.run(selection: selection)
    try migration.restoreBackup(result.backup)
    #expect(!FileManager.default.fileExists(atPath: target.codexHome + "/keybindings.json"))
  }
}

@Suite struct MissingRolloutMigrationTests {
  @Test(arguments: [false, true])
  func skipsMissingRolloutsAndTheirRelatedRecords(hasAvailableConversation: Bool) throws {
    let f = MigrationFixture()
    defer { f.clean() }
    let source = try f.state(f.source)
    let target = try f.state(f.target)
    try source.execute(
      "INSERT INTO projects VALUES('p','Source project'); INSERT INTO project_roots VALUES('p',0,'/tmp/project')"
    )
    try source.execute(
      "INSERT INTO threads VALUES('missing','\(f.source.codexHome)/sessions/missing.jsonl','p',NULL,NULL,NULL,'Missing','paginated'); INSERT INTO thread_attachments VALUES('missing-attachment','missing','payload')"
    )
    // A duplicate already in the destination must remain untouched and not count as skipped.
    try source.execute(
      "INSERT INTO threads VALUES('existing','\(f.source.codexHome)/sessions/existing.jsonl',NULL,NULL,NULL,NULL,'Source title','legacy')"
    )
    try target.execute(
      "INSERT INTO threads VALUES('existing','\(f.target.codexHome)/sessions/existing.jsonl',NULL,NULL,NULL,NULL,'Keep target title','legacy')"
    )
    if hasAvailableConversation {
      try f.write(
        f.source, "sessions/available.jsonl",
        #"{"type":"session_meta","payload":{"id":"available"}}"# + "\n")
      try source.execute(
        "INSERT INTO threads VALUES('available','\(f.source.codexHome)/sessions/available.jsonl','p',NULL,NULL,NULL,'Available','paginated'); INSERT INTO thread_attachments VALUES('available-attachment','available','payload')"
      )
    }
    source.close()
    target.close()
    let history = try f.history(f.source)
    try history.execute("INSERT INTO thread_items VALUES('missing','item','Missing message')")
    if hasAvailableConversation {
      try history.execute("INSERT INTO thread_items VALUES('available','item','Available message')")
    }
    history.close()
    try f.write(f.source, "keybindings.json", #"[{"command":"newTask","key":"Command+K"}]"#)
    try f.write(
      f.source, ".codex-global-state.json",
      #"{"thread-titles":{"titles":{"missing":"Missing","available":"Available"},"order":["missing","available"]},"thread-project-assignments":{"missing":"p","available":"p"},"sidebar-project-thread-orders":{"p":["missing","available"]}}"#
    )
    let result = try f.migrate()
    #expect(result.skippedConversations == 1)
    #expect(result.conversations == (hasAvailableConversation ? 1 : 0))
    #expect(result.projects == 1)
    #expect(try f.read(f.target, "keybindings.json") == f.read(f.source, "keybindings.json"))
    #expect(try f.read(f.target, "auth.json") == "AUTH-target")
    let db = try MigrationDatabase(URL(fileURLWithPath: f.target.codexHome + "/state_5.sqlite"))
    #expect(try db.rows("SELECT id FROM threads WHERE id='missing'").isEmpty)
    #expect(try db.rows("SELECT title FROM threads WHERE id='existing'") == [["Keep target title"]])
    #expect(
      try db.rows("SELECT thread_id FROM thread_attachments")
        == (hasAvailableConversation ? [["available"]] : []))
    try db.check()
    db.close()
    let importedHistory = try MigrationDatabase(
      URL(fileURLWithPath: f.target.codexHome + "/thread_history_1.sqlite"))
    #expect(
      try importedHistory.rows("SELECT thread_id FROM thread_items")
        == (hasAvailableConversation ? [["available"]] : []))
    importedHistory.close()
    #expect(try !f.read(f.target, ".codex-global-state.json").contains("missing"))
    let original = try MigrationDatabase(
      URL(fileURLWithPath: f.source.codexHome + "/state_5.sqlite"), readOnly: true)
    #expect(try original.rows("SELECT id FROM threads WHERE id='missing'") == [["missing"]])
    original.close()
  }
}
