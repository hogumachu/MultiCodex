import Foundation
import SQLite3

public struct MigrationSelection: Sendable {
  public var shortcuts = true
  public var projects = true
  public var conversations = true
  public init() {}
  public var isEmpty: Bool { !shortcuts && !projects && !conversations }
}

public struct MigrationResult: Sendable {
  public let backup: URL
  public let projects: Int
  public let conversations: Int
  public let skippedConversations: Int
}

public enum MigrationError: LocalizedError {
  case invalid(String)
  public var errorDescription: String? {
    switch self {
    case .invalid(let message): message
    }
  }
}

/// Uses only explicit data allowlists; authentication, browser storage and config are never copied.
public final class ProfileMigration {
  private let fm = FileManager.default
  private let source: Profile
  private let target: Profile
  private let backupRoot: URL
  private var changes: [Change] = []
  private struct Change: Codable {
    let destination: String
    let original: String?
  }

  public init(source: Profile, target: Profile, backupRoot: URL) {
    self.source = source
    self.target = target
    self.backupRoot = backupRoot
  }

  public func run(selection: MigrationSelection) throws -> MigrationResult {
    guard source.id != target.id, !selection.isEmpty,
      canonicalPath(source.codexHome) != canonicalPath(target.codexHome)
    else { throw MigrationError.invalid("서로 다른 계정과 가져올 항목을 선택해 주세요.") }
    changes = []
    if fm.fileExists(atPath: backupRoot.path) {
      try safe(backupRoot)
      for folder in try fm.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil) {
        try safe(folder)
        let journal = folder.appendingPathComponent("undo.json")
        let owner = folder.appendingPathComponent("target-id")
        let status = folder.appendingPathComponent("status")
        if fm.fileExists(atPath: journal.path),
          (try? String(contentsOf: owner, encoding: .utf8)) == target.id,
          !fm.fileExists(atPath: status.path)
        {
          throw MigrationError.invalid(
            "중단된 가져오기가 있습니다. 먼저 ‘백업에서 복원’으로 다음 백업을 복원해 주세요: \(folder.path)")
        }
      }
    }
    let sourceHome = canonicalPath(source.codexHome) + "/"
    let targetHome = canonicalPath(target.codexHome) + "/"
    guard !sourceHome.hasPrefix(targetHome), !targetHome.hasPrefix(sourceHome) else {
      throw MigrationError.invalid("원본과 대상의 저장 폴더가 겹칩니다.")
    }
    let backup = backupRoot.appendingPathComponent(UUID().uuidString)
    try directory(backup)
    let stage = backup.appendingPathComponent("prepared")
    try directory(stage)
    try Data(target.id.utf8).write(to: backup.appendingPathComponent("target-id"))
    var prepared: [(URL, URL)] = []
    var projectCount = 0
    var threadCount = 0
    var skippedIDs = Set<String>()
    var requiresHistory = false
    do {
      if selection.shortcuts {
        let from = home(source, "keybindings.json")
        do {
          try safe(from)
          let data = fm.fileExists(atPath: from.path) ? try Data(contentsOf: from) : Data("[]".utf8)
          guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            rows.allSatisfy({
              $0["command"] is String && ($0["key"] is String || $0["key"] is NSNull)
            })
          else { throw MigrationError.invalid("Codex 단축키 파일 형식을 확인할 수 없습니다.") }
          let output = stage.appendingPathComponent("keybindings.json")
          try data.write(to: output)
          prepared.append((output, home(target, "keybindings.json")))
        }
      }
      var newThreadIDs = Set<String>()
      if selection.projects || selection.conversations {
        let sourceDB = try database(source, name: "state_5.sqlite")
        let targetDB = try database(target, name: "state_5.sqlite")
        if fm.fileExists(atPath: sourceDB.path) {
          let output = stage.appendingPathComponent("state_5.sqlite")
          let db = try prepareDatabase(source: sourceDB, target: targetDB, output: output)
          try db.execute("ATTACH DATABASE \(literal(sourceDB.path)) AS incoming")
          if selection.projects {
            projectCount = try db.merge("projects")
            _ = try db.merge(
              "project_roots", predicate: "project_id IN (SELECT id FROM imported_projects)")
          }
          if selection.conversations {
            try db.execute("CREATE TEMP TABLE eligible_threads (id TEXT PRIMARY KEY)")
            for row in try db.rows(
              "SELECT id, rollout_path FROM incoming.threads WHERE id NOT IN (SELECT id FROM main.threads)"
            ) {
              guard let id = row[0] else { continue }
              guard let path = row[1], !path.isEmpty else {
                skippedIDs.insert(id)
                continue
              }
              let file = URL(fileURLWithPath: path)
              try safe(file)
              guard fm.fileExists(atPath: file.path) else {
                skippedIDs.insert(id)
                continue
              }
              try db.execute("INSERT INTO eligible_threads VALUES (\(literal(id)))")
              newThreadIDs.insert(id)
            }
            if !selection.projects {
              // Project associations are optional when importing only conversations.
              threadCount = try db.merge(
                "threads", predicate: "id IN (SELECT id FROM eligible_threads)",
                replacements: [
                  "project_id": "NULL", "thread_section_id": "NULL", "creator_user_id": "NULL",
                  "creator_account_id": "NULL",
                ])
            } else {
              _ = try db.merge("thread_sections")
              threadCount = try db.merge(
                "threads", predicate: "id IN (SELECT id FROM eligible_threads)",
                replacements: ["creator_user_id": "NULL", "creator_account_id": "NULL"])
            }
            for table in ["thread_dynamic_tools", "thread_attachments", "thread_read_receipts"] {
              _ = try db.merge(table, predicate: "thread_id IN (SELECT id FROM imported_threads)")
            }
            _ = try db.merge(
              "thread_spawn_edges",
              predicate:
                "child_thread_id IN (SELECT id FROM imported_threads) AND parent_thread_id IN (SELECT id FROM main.threads)"
            )
            for row in try db.rows(
              "SELECT id, rollout_path FROM threads WHERE id IN (SELECT id FROM imported_threads)")
            {
              guard let id = row[0], let path = row[1] else { continue }
              let from = URL(fileURLWithPath: path)
              let relative = try rolloutRelative(from)
              let to = home(target, relative)
              try safe(from)
              guard fm.fileExists(atPath: from.path) else {
                throw MigrationError.invalid("일부 대화 원본 파일이 없습니다. 원본 계정에서 기록을 확인해 주세요.")
              }
              // Never replace a divergent rollout belonging to an existing target thread.
              if fm.fileExists(atPath: to.path) {
                guard fm.contentsEqual(atPath: from.path, andPath: to.path) else {
                  throw MigrationError.invalid("같은 경로에 다른 대화 파일이 있습니다. 가져오기를 중단했습니다.")
                }
              } else {
                prepared.append((from, to))
              }
              try db.execute(
                "UPDATE threads SET rollout_path = \(literal(to.path)) WHERE id = \(literal(id))")
            }
            let knownIDs = Set(try db.rows("SELECT id FROM threads").compactMap { $0[0] })
            let legacyIDs = try addUnindexedRollouts(
              prepared: &prepared, excluding: knownIDs.union(skippedIDs))
            newThreadIDs.formUnion(legacyIDs)
            threadCount += legacyIDs.count
            let columns = try db.rows("PRAGMA table_info(threads)").compactMap { $0[1] }
            if columns.contains("history_mode") {
              requiresHistory = try !db.rows(
                "SELECT id FROM threads WHERE id IN (SELECT id FROM imported_threads) AND history_mode = 'paginated'"
              ).isEmpty
            }
          }
          try db.check()
          db.close()
          prepared.append((output, targetDB))
        } else if selection.conversations {
          newThreadIDs = try addUnindexedRollouts(prepared: &prepared, excluding: [])
          threadCount = newThreadIDs.count
        }
        if selection.conversations {
          let from = try database(source, name: "thread_history_1.sqlite")
          if fm.fileExists(atPath: from.path) {
            let to = try database(target, name: "thread_history_1.sqlite")
            let output = stage.appendingPathComponent("thread_history_1.sqlite")
            let db = try prepareDatabase(source: from, target: to, output: output)
            try db.execute("ATTACH DATABASE \(literal(from.path)) AS incoming")
            try db.execute("CREATE TEMP TABLE imported_thread_ids (id TEXT PRIMARY KEY)")
            for id in newThreadIDs {
              try db.execute("INSERT INTO imported_thread_ids VALUES (\(literal(id)))")
            }
            for table in [
              "thread_turns", "thread_items", "thread_history_projection_state",
              "thread_realtime_items",
            ] {
              _ = try db.merge(
                table, predicate: "thread_id IN (SELECT id FROM imported_thread_ids)")
            }
            try db.check()
            db.close()
            prepared.append((output, to))
          } else if requiresHistory {
            throw MigrationError.invalid("페이지 방식 대화의 기록 DB가 없습니다. 원본 계정에서 대화 기록을 확인해 주세요.")
          }
        }
        try prepareGlobalState(
          selection: selection, importedIDs: newThreadIDs, stage: stage, prepared: &prepared)
      }
      // Persist the undo journal before each mutation, so interrupted imports can be recovered.
      for (from, to) in prepared {
        try safe(to)
        try directory(to.deletingLastPathComponent())
        let original: String?
        if fm.fileExists(atPath: to.path) {
          let saved = backup.appendingPathComponent("original-\(changes.count)")
          try fm.copyItem(at: to, to: saved)
          original = saved.lastPathComponent
        } else {
          original = nil
        }
        changes.append(Change(destination: to.path, original: original))
        try JSONEncoder().encode(changes).write(
          to: backup.appendingPathComponent("undo.json"), options: .atomic)
        // SQLite staging uses a complete snapshot. Stale WAL sidecars must not be replayed.
        if to.pathExtension == "sqlite" {
          for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: to.path + suffix)
            if fm.fileExists(atPath: sidecar.path) {
              try safe(sidecar)
              let saved = backup.appendingPathComponent("original-\(changes.count)")
              try fm.copyItem(at: sidecar, to: saved)
              changes.append(Change(destination: sidecar.path, original: saved.lastPathComponent))
              try JSONEncoder().encode(changes).write(
                to: backup.appendingPathComponent("undo.json"), options: .atomic)
              try fm.removeItem(at: sidecar)
            }
          }
        }
        let temporary = to.deletingLastPathComponent().appendingPathComponent(
          ".multicodex-\(UUID())")
        try fm.copyItem(at: from, to: temporary)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if rename(temporary.path, to.path) != 0 {
          try? fm.removeItem(at: temporary)
          throw MigrationError.invalid("가져온 파일을 저장하지 못했습니다.")
        }
      }
      try Data("complete".utf8).write(to: backup.appendingPathComponent("status"), options: .atomic)
      try fm.removeItem(at: stage)
      return MigrationResult(
        backup: backup, projects: projectCount, conversations: threadCount,
        skippedConversations: skippedIDs.count)
    } catch {
      do { try restore(backup: backup) } catch {
        throw MigrationError.invalid("가져오기 복구에 실패했습니다. 백업 폴더를 보관해 주세요: \(backup.path)")
      }
      throw error
    }
  }

  /// Restores only files explicitly owned by this migration, for the selected target profile.
  public func restoreBackup(_ backup: URL) throws {
    try safe(backup)
    guard canonicalPath(backup.deletingLastPathComponent().path) == canonicalPath(backupRoot.path),
      try String(contentsOf: backup.appendingPathComponent("target-id"), encoding: .utf8)
        == target.id
    else { throw MigrationError.invalid("이 계정에서 만든 마이그레이션 백업을 선택해 주세요.") }
    let journal = backup.appendingPathComponent("undo.json")
    try safe(journal)
    let entries = try JSONDecoder().decode([Change].self, from: Data(contentsOf: journal))
    let exact = Set([
      home(target, "keybindings.json").path, home(target, ".codex-global-state.json").path,
      try database(target, name: "state_5.sqlite").path,
      try database(target, name: "thread_history_1.sqlite").path,
    ])
    let sessionPrefixes = [
      home(target, "sessions").path + "/", home(target, "archived_sessions").path + "/",
    ]
    for entry in entries {
      let url = URL(fileURLWithPath: entry.destination)
      try safe(url)
      let base =
        entry.destination.hasSuffix("-wal") || entry.destination.hasSuffix("-shm")
        ? String(entry.destination.dropLast(4)) : entry.destination
      guard !url.pathComponents.contains(".."), !url.pathComponents.contains("."),
        exact.contains(base)
          || (url.pathExtension == "jsonl"
            && sessionPrefixes.contains(where: { entry.destination.hasPrefix($0) }))
      else { throw MigrationError.invalid("백업의 복원 경로가 올바르지 않습니다.") }
      if let original = entry.original {
        guard original.range(of: #"^original-[0-9]+$"#, options: .regularExpression) != nil else {
          throw MigrationError.invalid("백업 파일 이름이 올바르지 않습니다.")
        }
        let saved = backup.appendingPathComponent(original)
        try safe(saved)
        guard fm.fileExists(atPath: saved.path) else {
          throw MigrationError.invalid("백업 원본 파일이 없습니다.")
        }
      }
    }
    changes = entries
    try restore(backup: backup)
  }

  private func restore(backup: URL) throws {
    // A later Codex launch may have created sidecars absent from the original journal.
    for change in changes where change.destination.hasSuffix(".sqlite") {
      for suffix in ["-wal", "-shm"] {
        let sidecar = URL(fileURLWithPath: change.destination + suffix)
        try safe(sidecar)
        if fm.fileExists(atPath: sidecar.path) { try fm.removeItem(at: sidecar) }
      }
    }
    for change in changes.reversed() {
      let destination = URL(fileURLWithPath: change.destination)
      if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
      if let original = change.original {
        try fm.copyItem(at: backup.appendingPathComponent(original), to: destination)
      }
    }
    try Data("rolled-back".utf8).write(
      to: backup.appendingPathComponent("status"), options: .atomic)
  }

  private func prepareDatabase(source: URL, target: URL, output: URL) throws -> MigrationDatabase {
    try safe(source)
    try safe(target)
    guard canonicalPath(source.path) != canonicalPath(target.path) else {
      throw MigrationError.invalid("원본과 대상이 같은 데이터베이스를 사용하고 있습니다.")
    }
    let src = try MigrationDatabase(source, readOnly: true)
    defer { src.close() }
    let db: MigrationDatabase
    if fm.fileExists(atPath: target.path) {
      let existing = try MigrationDatabase(target, readOnly: true)
      defer { existing.close() }
      try existing.snapshot(to: output)
      db = try MigrationDatabase(output)
      // Never silently discard fields when Codex changes its private storage format.
      guard
        try src.rows("SELECT version, hex(checksum) FROM _sqlx_migrations ORDER BY version")
          == db.rows("SELECT version, hex(checksum) FROM _sqlx_migrations ORDER BY version")
      else {
        throw MigrationError.invalid(
          "두 계정의 Codex DB 버전이 다릅니다. 같은 Codex 버전으로 각 계정을 한 번 열고 종료한 뒤 다시 시도해 주세요.")
      }
    } else {
      db = try MigrationDatabase(output)
      for row in try src.rows(
        "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 ELSE 2 END"
      ) {
        if let sql = row[0] { try db.execute(sql) }
      }
      try db.execute("ATTACH DATABASE \(literal(source.path)) AS schema_source")
      try db.execute("INSERT INTO _sqlx_migrations SELECT * FROM schema_source._sqlx_migrations")
      try db.execute("DETACH DATABASE schema_source")
    }
    return db
  }

  private func database(_ profile: Profile, name: String) throws -> URL {
    if let sqliteHome = profile.sqliteHome {
      return URL(fileURLWithPath: sqliteHome).appendingPathComponent(name)
    }
    let config = home(profile, "config.toml")
    if fm.fileExists(atPath: config.path) {
      try safe(config)
      let text = try String(contentsOf: config, encoding: .utf8)
      // sqlite_home is a top-level TOML string. Never copy or change the config itself.
      for line in text.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") { break }
        guard trimmed.range(of: #"^sqlite_home\s*="#, options: .regularExpression) != nil else {
          continue
        }
        let pattern = #"^sqlite_home\s*=\s*("(?:\\.|[^"\\])*"|'[^']*')\s*(?:#.*)?$"#
        let regex = try NSRegularExpression(pattern: pattern)
        guard
          let match = regex.firstMatch(
            in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
          let range = Range(match.range(at: 1), in: trimmed)
        else {
          throw MigrationError.invalid("sqlite_home 설정의 문자열 형식을 확인할 수 없습니다.")
        }
        let raw = String(trimmed[range])
        let path: String
        if raw.hasPrefix("'") {
          path = String(raw.dropFirst().dropLast())
        } else {
          path = try JSONDecoder().decode(String.self, from: Data(raw.utf8))
        }
        guard path.hasPrefix("/"), !path.contains("\0") else {
          throw MigrationError.invalid("sqlite_home은 절대 경로여야 합니다.")
        }
        return URL(fileURLWithPath: path).appendingPathComponent(name)
      }
    }
    return home(profile, name)
  }

  private func addUnindexedRollouts(prepared: inout [(URL, URL)], excluding knownIDs: Set<String>)
    throws -> Set<String>
  {
    var imported = Set<String>()
    for folder in ["sessions", "archived_sessions"] {
      let root = home(source, folder)
      guard fm.fileExists(atPath: root.path) else { continue }
      try safe(root)
      var enumerationError: Error?
      guard
        let enumerator = fm.enumerator(
          at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [],
          errorHandler: { _, error in
            enumerationError = error
            return false
          })
      else { throw MigrationError.invalid("대화 폴더를 읽을 수 없습니다.") }
      for case let url as URL in enumerator {
        try safe(url)
        guard url.pathExtension == "jsonl",
          try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        else { continue }
        let file = try FileHandle(forReadingFrom: url)
        let firstChunk: Data
        do {
          firstChunk = try file.read(upToCount: 1_048_576) ?? Data()
          try file.close()
        } catch {
          try? file.close()
          throw error
        }
        guard let lineEnd = firstChunk.firstIndex(of: 10),
          let record = try JSONSerialization.jsonObject(with: firstChunk[..<lineEnd])
            as? [String: Any],
          record["type"] as? String == "session_meta",
          let payload = record["payload"] as? [String: Any], let id = payload["id"] as? String
        else {
          throw MigrationError.invalid("대화 파일의 첫 기록을 확인할 수 없습니다: \(url.lastPathComponent)")
        }
        guard !knownIDs.contains(id), !imported.contains(id) else { continue }
        let to = home(target, try rolloutRelative(url))
        if fm.fileExists(atPath: to.path) {
          try safe(to)
          guard fm.contentsEqual(atPath: url.path, andPath: to.path) else {
            throw MigrationError.invalid("같은 경로에 다른 대화 파일이 있습니다.")
          }
        } else {
          prepared.append((url, to))
          imported.insert(id)
        }
      }
      if let enumerationError { throw enumerationError }
    }
    return imported
  }

  private func rolloutRelative(_ url: URL) throws -> String {
    let prefix = URL(fileURLWithPath: source.codexHome).standardizedFileURL.path + "/"
    guard url.standardizedFileURL.path.hasPrefix(prefix) else {
      throw MigrationError.invalid("계정 폴더 밖에 대화 원본이 있어 자동으로 가져올 수 없습니다.")
    }
    let relative = String(url.standardizedFileURL.path.dropFirst(prefix.count))
    guard relative.hasPrefix("sessions/") || relative.hasPrefix("archived_sessions/") else {
      throw MigrationError.invalid("지원하지 않는 대화 저장 경로입니다.")
    }
    return relative
  }

  private func prepareGlobalState(
    selection: MigrationSelection, importedIDs: Set<String>, stage: URL,
    prepared: inout [(URL, URL)]
  ) throws {
    let sourceURL = home(source, ".codex-global-state.json")
    guard fm.fileExists(atPath: sourceURL.path) else { return }
    func read(_ url: URL) throws -> [String: Any] {
      guard fm.fileExists(atPath: url.path) else { return [:] }
      try safe(url)
      guard
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
      else {
        throw MigrationError.invalid("Codex 로컬 설정 파일 형식을 확인할 수 없습니다.")
      }
      return value
    }
    let incoming = try read(sourceURL)
    let targetURL = home(target, ".codex-global-state.json")
    var current = try read(targetURL)
    var keys: [String] = []
    if selection.projects {
      keys += [
        "electron-saved-workspace-roots", "local-projects", "project-order", "project-appearances",
        "pinned-project-ids",
      ]
    }
    if selection.conversations {
      keys += [
        "thread-titles", "thread-workspace-root-hints", "thread-projectless-output-directories",
        "projectless-thread-ids", "pinned-thread-ids",
      ]
      if selection.projects {
        keys += ["thread-project-assignments", "sidebar-project-thread-orders"]
      }
    }
    for key in keys {
      if var value = incoming[key] {
        if key == "local-projects", let projects = value as? [String: Any] {
          value = projects.filter { !$0.key.hasPrefix("g-p-") }
        } else if ["project-order", "pinned-project-ids"].contains(key),
          let ids = value as? [String]
        {
          value = ids.filter { !$0.hasPrefix("g-p-") }
        } else if key == "thread-titles", var titles = value as? [String: Any] {
          if let names = titles["titles"] as? [String: Any] {
            titles["titles"] = names.filter { importedIDs.contains($0.key) }
          }
          if let order = titles["order"] as? [String] {
            titles["order"] = order.filter { importedIDs.contains($0) }
          }
          value = titles
        } else if key == "sidebar-project-thread-orders", let orders = value as? [String: [String]]
        {
          value = orders.mapValues { $0.filter { importedIDs.contains($0) } }
        } else if key.hasPrefix("thread-"), let map = value as? [String: Any] {
          value = map.filter { importedIDs.contains($0.key) }
        } else if ["projectless-thread-ids", "pinned-thread-ids"].contains(key),
          let ids = value as? [String]
        {
          value = ids.filter { importedIDs.contains($0) }
        }
        current[key] = mergeJSON(existing: current[key], incoming: value)
      }
    }
    let output = stage.appendingPathComponent("global.json")
    try JSONSerialization.data(withJSONObject: current, options: [.sortedKeys]).write(to: output)
    prepared.append((output, targetURL))
  }

  private func mergeJSON(existing: Any?, incoming: Any) -> Any {
    if let left = existing as? [String: Any], let right = incoming as? [String: Any] {
      return left.merging(right) { mergeJSON(existing: $0, incoming: $1) }
    }
    if let left = existing as? [AnyHashable], let right = incoming as? [AnyHashable] {
      return left + right.filter { !left.contains($0) }
    }
    return existing ?? incoming
  }

  private func home(_ profile: Profile, _ path: String) -> URL {
    URL(fileURLWithPath: profile.codexHome).appendingPathComponent(path)
  }
  private func directory(_ url: URL) throws {
    try safe(url)
    try fm.createDirectory(
      at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  }
  private func safe(_ url: URL) throws {
    guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path
    else {
      throw MigrationError.invalid("심볼릭 링크가 포함된 경로는 가져오기를 지원하지 않습니다.")
    }
  }
}

private func literal(_ value: String) -> String {
  "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
}
private func identifier(_ value: String) -> String {
  "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

final class MigrationDatabase {
  private var handle: OpaquePointer?
  init(_ url: URL, readOnly: Bool = false) throws {
    let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
    guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
      sqlite3_close(handle)
      handle = nil
      throw MigrationError.invalid("Codex 데이터베이스를 열 수 없습니다.")
    }
    sqlite3_busy_timeout(handle, 2000)
  }
  deinit { close() }
  func close() {
    if let handle {
      sqlite3_close(handle)
      self.handle = nil
    }
  }
  func execute(_ sql: String) throws {
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
      throw MigrationError.invalid(
        "Codex 데이터베이스 형식을 확인할 수 없거나 사용 중입니다: \(String(cString: sqlite3_errmsg(handle)))")
    }
  }
  func rows(_ sql: String) throws -> [[String?]] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
      throw MigrationError.invalid("Codex 데이터베이스 형식이 지원되지 않습니다.")
    }
    defer { sqlite3_finalize(statement) }
    var result: [[String?]] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return result }
      guard status == SQLITE_ROW else { throw MigrationError.invalid("Codex 데이터베이스를 읽지 못했습니다.") }
      result.append(
        (0..<sqlite3_column_count(statement)).map { column in
          sqlite3_column_text(statement, column).map { String(cString: $0) }
        })
    }
  }
  func snapshot(to url: URL) throws {
    let destination = try MigrationDatabase(url)
    defer { destination.close() }
    guard let backup = sqlite3_backup_init(destination.handle, "main", handle, "main") else {
      throw MigrationError.invalid("데이터베이스 백업을 만들지 못했습니다.")
    }
    let status = sqlite3_backup_step(backup, -1)
    let finish = sqlite3_backup_finish(backup)
    guard status == SQLITE_DONE, finish == SQLITE_OK else {
      throw MigrationError.invalid("데이터베이스가 사용 중입니다. Codex 작업을 종료해 주세요.")
    }
  }
  @discardableResult
  func merge(_ table: String, predicate: String? = nil, replacements: [String: String] = [:]) throws
    -> Int
  {
    guard
      !(try rows(
        "SELECT name FROM incoming.sqlite_master WHERE type='table' AND name=\(literal(table))"))
        .isEmpty
    else { return 0 }
    let columns = try rows("PRAGMA incoming.table_info(\(identifier(table)))").compactMap { $0[1] }
    guard columns == (try rows("PRAGMA main.table_info(\(identifier(table)))").compactMap { $0[1] })
    else {
      throw MigrationError.invalid("두 계정의 데이터베이스 구조가 다릅니다.")
    }
    if table == "threads" || table == "projects" {
      try execute(
        "CREATE TEMP TABLE imported_\(table) AS SELECT id FROM incoming.\(identifier(table)) WHERE id NOT IN (SELECT id FROM main.\(identifier(table)))"
          + (predicate.map { " AND (" + $0 + ")" } ?? "")
      )
    }
    let values = columns.map { replacements[$0] ?? identifier($0) }.joined(separator: ",")
    try execute(
      "INSERT INTO main.\(identifier(table)) (\(columns.map(identifier).joined(separator: ","))) SELECT \(values) FROM incoming.\(identifier(table))"
        + (predicate.map { " WHERE " + $0 } ?? " WHERE true") + " ON CONFLICT DO NOTHING")
    return Int(sqlite3_changes(handle))
  }
  func check() throws {
    guard try rows("PRAGMA integrity_check") == [["ok"]],
      try rows("PRAGMA foreign_key_check").isEmpty
    else {
      throw MigrationError.invalid("가져올 데이터의 무결성 검사에 실패했습니다.")
    }
    try execute("PRAGMA journal_mode=DELETE")
  }
}
