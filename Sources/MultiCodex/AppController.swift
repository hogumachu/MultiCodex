import AppKit
import MultiCodexCore
import Observation

@MainActor @Observable
final class AppController {
  let store: ProfileStore
  private(set) var profiles: [Profile] = []
  private(set) var runningIDs: Set<String> = []
  private(set) var loginLabels: [String: String] = [:]
  private(set) var busy = false
  private(set) var selectedID: String?
  private(set) var message = ""
  var onChange: (() -> Void)?
  private var activationObserver: NSObjectProtocol?
  private var appURL: URL?
  private var checkedAppVersion: String?

  init(root: URL) throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let instances = ProcessReader.instances(home: home)
    var original = Profile.original(home: home)
    // Adopt the existing default instance's actual location without moving or copying it.
    if let instance = instances.first(where: {
      $0.location?.userData == canonicalPath(original.userData)
    }),
      let location = instance.location
    {
      original.codexHome = location.codexHome
      original.userData = location.userData
      original.sqliteHome = location.sqliteHome
      appURL = instance.app.bundleURL
    }
    store = try ProfileStore(root: root, original: original)
    profiles = store.profiles
    refresh()
    if let frontmost = NSWorkspace.shared.frontmostApplication {
      selectedID = profileID(for: frontmost.processIdentifier)
    }
    activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] notification in
      guard
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication
      else { return }
      let pid = app.processIdentifier
      Task { @MainActor [weak self] in
        guard let self, let id = self.profileID(for: pid) else { return }
        self.selectedID = id
        self.refresh()
      }
    }
  }

  private func profileID(for pid: pid_t) -> String? {
    guard
      let instance = ProcessReader.instances().first(where: { $0.app.processIdentifier == pid }),
      let location = instance.location
    else { return nil }
    return store.profiles.first(where: { location.matches($0) })?.id
  }

  private func loginLabel(_ profile: Profile) -> String {
    let auth = AuthSummary.read(home: URL(fileURLWithPath: profile.codexHome))
    if let email = auth.email, auth.hasSavedLogin { return email }
    return auth.hasSavedLogin ? "로그인 정보 저장됨" : "최초 로그인 필요"
  }

  func addProfile(name: String) throws -> Profile {
    let profile = try store.add(name: name)
    message = "\(profile.name)을 만들었습니다. 열기를 누르고 최초 로그인을 완료해 주세요."
    refresh()
    return profile
  }

  func renameProfile(_ profile: Profile, name: String) throws {
    try store.rename(id: profile.id, name: name)
    message = "계정 이름을 변경했습니다."
    refresh()
  }

  func removeProfile(_ profile: Profile) throws {
    guard !busy else { throw MultiCodexError.accountOpening }
    try store.removeRegistration(id: profile.id)
    if selectedID == profile.id { selectedID = nil }
    message = "\(profile.name) 계정을 목록에서 삭제했습니다. 로그인과 대화 파일은 저장 폴더에 보관했습니다."
    refresh()
  }

  func openProfile(_ profile: Profile) async {
    guard !busy else { return }
    busy = true
    message = "\(profile.name) 여는 중…"
    refresh()
    defer {
      busy = false
      refresh()
    }
    do {
      try store.validate(profile)
      let instances = ProcessReader.instances()
      let matches = instances.filter { $0.location?.matches(profile) == true }
      guard matches.count <= 1 else { throw MultiCodexError.ambiguousInstance }
      let app: NSRunningApplication
      if let match = matches.first {
        app = match.app
      } else {
        guard !instances.contains(where: { $0.location == nil }) else {
          throw MultiCodexError.ambiguousInstance
        }
        let url = try findApp()
        try checkCompatibility(url)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        configuration.environment = profile.launchEnvironment
        configuration.arguments = profile.launchArguments
        app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        var matched = false
        for _ in 0..<50 {
          if app.isTerminated { break }
          if ProcessReader.location(
            pid: app.processIdentifier, home: FileManager.default.homeDirectoryForCurrentUser)?
            .matches(profile) == true
          {
            matched = true
            break
          }
          try await Task.sleep(for: .milliseconds(100))
        }
        guard matched else { throw MultiCodexError.launchMismatch }
      }
      _ = app.activate(options: [.activateAllWindows])
      var activated = false
      for _ in 0..<80 {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
          activated = true
          break
        }
        if app.isTerminated { break }
        try await Task.sleep(for: .milliseconds(100))
      }
      guard activated else { throw MultiCodexError.activationFailed }
      selectedID = profile.id
      message = "\(profile.name) 선택됨 · 다른 계정의 작업은 계속 실행됩니다."
    } catch { message = error.localizedDescription }
  }

  func migrate(from source: Profile, to target: Profile, selection: MigrationSelection) async throws
    -> MigrationResult
  {
    guard !busy else { throw MultiCodexError.accountOpening }
    try store.validate(source)
    try store.validate(target)
    let instances = ProcessReader.instances()
    guard
      !instances.contains(where: {
        $0.location == nil || $0.location?.matches(source) == true
          || $0.location?.matches(target) == true
      })
    else {
      throw MigrationError.invalid("원본과 대상 Codex 계정을 모두 종료한 뒤 다시 시도해 주세요. 창을 닫는 것만으로는 종료되지 않습니다.")
    }
    guard try !ProcessReader.hasDataWriter(for: [source, target]) else {
      throw MigrationError.invalid("원본 또는 대상 계정의 Codex CLI 작업이 실행 중입니다. 작업을 종료한 뒤 다시 시도해 주세요.")
    }
    busy = true
    message = "계정 데이터를 가져오는 중…"
    defer {
      busy = false
      refresh()
    }
    let backupRoot = store.root.appendingPathComponent("migration-backups")
    do {
      let result = try await Task.detached(priority: .userInitiated) {
        try ProfileMigration(source: source, target: target, backupRoot: backupRoot).run(
          selection: selection)
      }.value
      message =
        "\(target.name)에 대화 \(result.conversations)개를 가져오거나 복구했습니다. 원본 또는 이전 기록 없음으로 \(result.skippedConversations)개 제외."
      return result
    } catch {
      message = error.localizedDescription
      throw error
    }
  }

  func restoreMigration(for target: Profile, backup: URL) async throws {
    guard !busy else { throw MultiCodexError.accountOpening }
    try store.validate(target)
    guard
      !ProcessReader.instances().contains(where: {
        $0.location == nil || $0.location?.matches(target) == true
      }),
      try !ProcessReader.hasDataWriter(for: [target])
    else {
      throw MigrationError.invalid("복원할 Codex 계정과 CLI 작업을 종료해 주세요.")
    }
    busy = true
    defer {
      busy = false
      refresh()
    }
    let backupRoot = store.root.appendingPathComponent("migration-backups")
    try await Task.detached(priority: .userInitiated) {
      try ProfileMigration(source: target, target: target, backupRoot: backupRoot).restoreBackup(
        backup)
    }.value
    message = "\(target.name)의 데이터를 가져오기 전 상태로 복원했습니다."
  }

  func refresh() {
    profiles = store.profiles
    let instances = ProcessReader.instances()
    runningIDs = Set(
      profiles.filter { profile in instances.contains { $0.location?.matches(profile) == true } }
        .map(\.id))
    loginLabels = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, loginLabel($0)) })
    onChange?()
  }

  private func findApp() throws -> URL {
    let candidates = [
      appURL,
      ProcessReader.instances().first?.app.bundleURL,
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: ProcessReader.bundleID),
      URL(fileURLWithPath: "/Applications/ChatGPT.app"),
      URL(fileURLWithPath: "/Applications/Codex.app"),
    ].compactMap { $0 }
    guard
      let url = candidates.first(where: {
        Bundle(url: $0)?.bundleIdentifier == ProcessReader.bundleID
      })
    else {
      throw MultiCodexError.appNotFound
    }
    appURL = url
    return url
  }

  private func checkCompatibility(_ url: URL) throws {
    let version =
      (Bundle(url: url)?.infoDictionary?["CFBundleVersion"] as? String ?? "unknown") + url.path
    if checkedAppVersion == version { return }
    let archive = url.appendingPathComponent("Contents/Resources/app.asar")
    guard let data = try? Data(contentsOf: archive, options: .mappedIfSafe),
      data.range(of: Data("CODEX_ELECTRON_USER_DATA_PATH".utf8)) != nil,
      data.range(of: Data("requestSingleInstanceLock".utf8)) != nil
    else { throw MultiCodexError.unsupportedApp }
    checkedAppVersion = version
  }

}
