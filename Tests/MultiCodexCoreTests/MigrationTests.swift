import CustomDump
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
  func compressed(_ profile: Profile, _ path: String) throws -> Data {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/compressed-rollout.jsonl.zst")
    let data = try Data(contentsOf: fixture)
    try write(profile, path, "")
    try data.write(to: URL(fileURLWithPath: profile.codexHome + "/" + path))
    return data
  }
  var decodedRollout: String {
    let header =
      #"{"timestamp":"2026-10-26T01:00:00Z","type":"session_meta","payload":{"id":"private-A","history_mode":"paginated"}}"#
    let event =
      #"{"type":"event_msg","payload":{"type":"user_message","message":"synthetic message"}}"#
    return header + "\n" + String(repeating: event + "\n", count: 5000)
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
  @Test(arguments: ["DELETE", "WAL"])
  func importsSameSourceIntoTwoAccountsInSequence(journalMode: String) throws {
    let f = MigrationFixture()
    defer { f.clean() }
    let targets = [f.target, f.profile("third")]
    for profile in [f.source] + targets {
      let db = try f.state(profile)
      try db.execute("PRAGMA journal_mode=\(journalMode)")
      let id = profile.id
      try f.write(
        profile, "sessions/\(id).jsonl",
        #"{"type":"session_meta","payload":{"id":"\#(id)"}}"# + "\n")
      try db.execute(
        "INSERT INTO projects VALUES('\(id)','\(id)'); INSERT INTO threads VALUES('\(id)','\(profile.codexHome)/sessions/\(id).jsonl','\(id)',NULL,NULL,NULL,'\(id)','paginated')"
      )
      db.close()
      let history = try f.history(profile)
      try history.execute("PRAGMA journal_mode=\(journalMode)")
      try history.execute("INSERT INTO thread_items VALUES('\(id)','item','message-\(id)')")
      history.close()
    }
    try f.write(f.source, "keybindings.json", #"[{"command":"newTask","key":"Cmd+K"}]"#)
    for target in targets {
      let result = try ProfileMigration(
        source: f.source, target: target, backupRoot: f.root.appendingPathComponent("backups")
      ).run(selection: .init())
      expectNoDifference(result.projects, 1)
      expectNoDifference(result.conversations, 1)
    }
    // Verify B again after importing C, including its own pre-existing conversation.
    for profile in [f.source] + targets {
      let db = try MigrationDatabase(URL(fileURLWithPath: profile.codexHome + "/state_5.sqlite"))
      defer { db.close() }
      let ids = profile.id == f.source.id ? [f.source.id] : [f.source.id, profile.id].sorted()
      expectNoDifference(try db.rows("SELECT id FROM threads ORDER BY id"), ids.map { [$0] })
      expectNoDifference(try db.rows("SELECT id FROM projects ORDER BY id"), ids.map { [$0] })
      expectNoDifference(
        try db.rows("SELECT rollout_path FROM threads WHERE id='source'"),
        [[profile.codexHome + "/sessions/source.jsonl"]])
      let history = try MigrationDatabase(
        URL(fileURLWithPath: profile.codexHome + "/thread_history_1.sqlite"))
      defer { history.close() }
      expectNoDifference(
        try history.rows("SELECT item_json FROM thread_items ORDER BY thread_id"),
        ids.map { ["message-" + $0] })
      expectNoDifference(try f.read(profile, "auth.json"), "AUTH-" + profile.id)
      expectNoDifference(
        try f.read(profile, "sessions/source.jsonl"), try f.read(f.source, "sessions/source.jsonl"))
      expectNoDifference(
        try f.read(profile, "keybindings.json"), try f.read(f.source, "keybindings.json"))
    }
  }

  @Test func importsWithSourceWALReaderWithoutChangingItsJournalMode() throws {
    let f = MigrationFixture()
    defer { f.clean() }
    let source = try f.state(f.source)
    defer { source.close() }
    try source.execute("PRAGMA journal_mode=WAL")
    try f.write(
      f.source, "sessions/a.jsonl", #"{"type":"session_meta","payload":{"id":"a"}}"# + "\n")
    try source.execute(
      "INSERT INTO threads VALUES('a','\(f.source.codexHome)/sessions/a.jsonl',NULL,NULL,NULL,NULL,'Chat','legacy')"
    )
    // A passive reader must not prevent imports or require changing the source's WAL mode.
    let reader = try MigrationDatabase(
      URL(fileURLWithPath: f.source.codexHome + "/state_5.sqlite"), readOnly: true)
    defer { reader.close() }
    try reader.execute("BEGIN")
    _ = try reader.rows("SELECT id FROM threads")
    for target in [f.target, f.profile("third")] {
      let result = try ProfileMigration(
        source: f.source, target: target, backupRoot: f.root.appendingPathComponent("backups")
      ).run(selection: .init())
      expectNoDifference(result.conversations, 1)
      expectNoDifference(try source.rows("PRAGMA journal_mode"), [["wal"]])
    }
    try reader.execute("ROLLBACK")
  }

  @Test func snapshotFailureReportsDatabaseAndSQLiteCode() throws {
    let f = MigrationFixture()
    defer { f.clean() }
    let locked = try f.state(f.target)
    defer { locked.close() }
    let reader = try MigrationDatabase(
      URL(fileURLWithPath: f.target.codexHome + "/state_5.sqlite"), readOnly: true)
    defer { reader.close() }
    try locked.execute("BEGIN EXCLUSIVE")
    defer { try? locked.execute("ROLLBACK") }
    do {
      try reader.snapshot(to: f.root.appendingPathComponent("state_5.sqlite"))
      Issue.record("An exclusive lock must prevent the snapshot")
    } catch {
      let message = error.localizedDescription
      #expect(message.contains("state_5.sqlite"))
      #expect(message.contains("SQLite 코드: 5"))
      #expect(message.contains("확장 코드:"))
      #expect(message.contains("백업 복사"))
    }
  }

  @Test func nonLockFailureDoesNotClaimDatabaseIsBusy() throws {
    let f = MigrationFixture()
    defer { f.clean() }
    let db = try f.state(f.source)
    defer { db.close() }
    do {
      try db.execute("SELECT * FROM missing_table")
      Issue.record("Missing table must fail")
    } catch {
      let message = error.localizedDescription
      #expect(message.contains("state_5.sqlite"))
      #expect(message.contains("SQLite 코드: 1"))
      #expect(!message.contains("작업을 종료"))
    }
  }

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

@Suite struct CompressedMigrationTests {
  @Test(arguments: ["sessions", "archived_sessions"], [false, true])
  func importsCompressedChatsIntoBandCAndRestores(folder: String, storedPathHasSuffix: Bool) throws
  {
    let f = MigrationFixture()
    defer { f.clean() }
    let relative = "\(folder)/a.jsonl"
    let bytes = try f.compressed(f.source, relative + ".zst")
    let db = try f.state(f.source)
    try db.execute(
      "INSERT INTO projects VALUES('p','Project'); INSERT INTO threads VALUES('private-A','\(f.source.codexHome)/\(relative)\(storedPathHasSuffix ? ".zst" : "")','p',NULL,'user-a','account-a','Compressed chat','paginated')"
    )
    db.close()
    // The rollout is authoritative even when this chat has no cached history rows.
    try f.history(f.source).close()
    for target in [f.target, f.profile("third")] {
      try f.write(target, "auth.json", "AUTH-" + target.id)
      let migration = ProfileMigration(
        source: f.source, target: target, backupRoot: f.root.appendingPathComponent("backups"))
      let result = try migration.run(selection: .init())
      expectNoDifference(result.conversations, 1)
      expectNoDifference(result.skippedConversations, 0)
      let to = URL(fileURLWithPath: target.codexHome + "/" + relative)
      expectNoDifference(try Data(contentsOf: to.appendingPathExtension("zst")), bytes)
      #expect(!FileManager.default.fileExists(atPath: to.path))
      let targetDB = try MigrationDatabase(
        URL(fileURLWithPath: target.codexHome + "/state_5.sqlite"))
      expectNoDifference(
        try targetDB.rows("SELECT rollout_path,project_id,creator_account_id FROM threads"),
        [[to.path, "p", nil]])
      targetDB.close()
      expectNoDifference(try migration.run(selection: .init()).conversations, 0)
      // Codex expands compressed rollouts when the imported chat is resumed.
      try Data(f.decodedRollout.utf8).write(to: to)
      try migration.restoreBackup(result.backup)
      #expect(!FileManager.default.fileExists(atPath: to.path))
      #expect(!FileManager.default.fileExists(atPath: to.appendingPathExtension("zst").path))
      expectNoDifference(try f.read(target, "auth.json"), "AUTH-" + target.id)
    }
    expectNoDifference(
      try Data(contentsOf: URL(fileURLWithPath: f.source.codexHome + "/" + relative + ".zst")),
      bytes)
  }

  @Test(arguments: [false, true])
  func importsUnindexedCompressedChatsAndPrefersResumedPlainFile(hasPlain: Bool) throws {
    let f = MigrationFixture()
    defer { f.clean() }
    let bytes = try f.compressed(f.source, "sessions/a.jsonl.zst")
    let resumed =
      f.decodedRollout
      + #"{"type":"event_msg","payload":{"type":"user_message","message":"continued"}}"# + "\n"
    if hasPlain { try f.write(f.source, "sessions/a.jsonl", resumed) }
    let result = try f.migrate()
    expectNoDifference(result.conversations, 1)
    expectNoDifference(result.skippedConversations, 0)
    if hasPlain {
      expectNoDifference(try f.read(f.target, "sessions/a.jsonl"), resumed)
      #expect(!FileManager.default.fileExists(atPath: f.target.codexHome + "/sessions/a.jsonl.zst"))
    } else {
      expectNoDifference(
        try Data(contentsOf: URL(fileURLWithPath: f.target.codexHome + "/sessions/a.jsonl.zst")),
        bytes)
    }
  }

  @Test(arguments: [false, true])
  func rejectsDamagedOrMismatchedCompressedRecordBeforeAnyWrites(wrongID: Bool) throws {
    let f = MigrationFixture()
    defer { f.clean() }
    let bytes = try f.compressed(f.source, "sessions/a.jsonl.zst")
    let db = try f.state(f.source)
    try db.execute(
      "INSERT INTO threads VALUES('\(wrongID ? "different" : "private-A")','\(f.source.codexHome)/sessions/a.jsonl',NULL,NULL,NULL,NULL,'Chat','legacy')"
    )
    db.close()
    if !wrongID {
      try bytes.dropLast(3).write(
        to: URL(fileURLWithPath: f.source.codexHome + "/sessions/a.jsonl.zst"))
    }
    try f.write(f.source, "keybindings.json", #"[{"command":"newTask","key":null}]"#)
    try f.write(f.target, "keybindings.json", "[]")
    #expect(throws: MigrationError.self) { try f.migrate() }
    expectNoDifference(try f.read(f.target, "keybindings.json"), "[]")
    #expect(!FileManager.default.fileExists(atPath: f.target.codexHome + "/state_5.sqlite"))
  }

  @Test(arguments: [false, true])
  func comparesDecodedContentBeforeReplacingExistingRollout(divergent: Bool) throws {
    let f = MigrationFixture()
    defer { f.clean() }
    _ = try f.compressed(f.source, "sessions/a.jsonl.zst")
    try f.write(f.target, "sessions/a.jsonl", f.decodedRollout + (divergent ? "{}\n" : ""))
    let sourceDB = try f.state(f.source)
    try sourceDB.execute(
      "INSERT INTO threads VALUES('private-A','\(f.source.codexHome)/sessions/a.jsonl',NULL,NULL,NULL,NULL,'Chat','legacy')"
    )
    sourceDB.close()
    if divergent {
      #expect(throws: MigrationError.self) { try f.migrate() }
      expectNoDifference(try f.read(f.target, "sessions/a.jsonl"), f.decodedRollout + "{}\n")
    } else {
      expectNoDifference(try f.migrate().conversations, 1)
      expectNoDifference(try f.read(f.target, "sessions/a.jsonl"), f.decodedRollout)
    }
    #expect(!FileManager.default.fileExists(atPath: f.target.codexHome + "/sessions/a.jsonl.zst"))
  }
}
