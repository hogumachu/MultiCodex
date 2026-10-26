import Foundation

public struct Profile: Codable, Identifiable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case original, managed }

  public var id: String
  public var name: String
  public var kind: Kind
  public var codexHome: String
  public var userData: String
  public var sqliteHome: String?

  public init(
    id: String, name: String, kind: Kind, codexHome: String, userData: String,
    sqliteHome: String? = nil
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.codexHome = codexHome
    self.userData = userData
    self.sqliteHome = sqliteHome
  }

  public static func original(home: URL) -> Self {
    Self(
      id: "original", name: "A · 기존 계정", kind: .original,
      codexHome: home.appendingPathComponent(".codex").path,
      userData: home.appendingPathComponent("Library/Application Support/Codex").path)
  }

  public var launchEnvironment: [String: String] {
    var values = ["CODEX_HOME": codexHome, "CODEX_ELECTRON_USER_DATA_PATH": userData]
    if let sqliteHome { values["CODEX_SQLITE_HOME"] = sqliteHome }
    return values
  }

  public var launchArguments: [String] { ["--user-data-dir=\(userData)"] }
}

public enum MultiCodexError: LocalizedError {
  case invalidName, duplicateName, invalidRegistry, profileMissing, originalProtected,
    accountOpening
  case unsafePath, appNotFound, unsupportedApp, ambiguousInstance, activationFailed, launchMismatch

  public var errorDescription: String? {
    switch self {
    case .invalidName: "계정 이름은 1~40자로 입력해 주세요."
    case .duplicateName: "같은 이름의 계정이 이미 있습니다."
    case .invalidRegistry: "프로필 목록을 읽을 수 없습니다. 기존 목록을 덮어쓰지 않았습니다."
    case .originalProtected: "기존 Codex 계정은 목록에서 삭제할 수 없습니다."
    case .accountOpening: "계정을 여는 중입니다. 잠시 후 다시 시도해 주세요."
    case .profileMissing: "프로필을 찾을 수 없습니다."
    case .unsafePath: "프로필 저장 경로가 예상 위치와 다릅니다. 실행을 중단했습니다."
    case .appNotFound: "설치된 Codex 또는 ChatGPT 앱을 찾을 수 없습니다."
    case .unsupportedApp: "이 앱 버전에서 프로필 분리 기능을 확인할 수 없습니다."
    case .ambiguousInstance: "실행 중인 Codex의 프로필을 확인할 수 없습니다. 중복 실행을 중단했습니다."
    case .activationFailed: "계정 창을 앞으로 가져오지 못했습니다. 앱이 준비된 뒤 다시 선택해 주세요."
    case .launchMismatch: "앱이 요청한 프로필로 실행되지 않았습니다. 기존 데이터는 변경하지 않았습니다."
    }
  }
}

public func canonicalPath(_ path: String) -> String {
  URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
}

public struct ProcessLocation: Equatable, Sendable {
  public var codexHome: String
  public var userData: String
  public var sqliteHome: String?

  public init(codexHome: String, userData: String, sqliteHome: String? = nil) {
    self.codexHome = canonicalPath(codexHome)
    self.userData = canonicalPath(userData)
    self.sqliteHome = sqliteHome.map(canonicalPath)
  }

  public func matches(_ profile: Profile) -> Bool {
    codexHome == canonicalPath(profile.codexHome)
      && userData == canonicalPath(profile.userData)
      && (profile.sqliteHome == nil || sqliteHome == profile.sqliteHome.map(canonicalPath))
  }
}
