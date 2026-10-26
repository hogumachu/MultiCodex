import Foundation

public struct AuthSummary: Equatable, Sendable {
  public var email: String?
  public var hasSavedLogin: Bool

  public static func read(home: URL) -> Self {
    let url = home.appendingPathComponent("auth.json")
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 128_000,
      let data = try? Data(contentsOf: url),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let tokens = json["tokens"] as? [String: Any],
      let accountID = tokens["account_id"] as? String, !accountID.isEmpty,
      let refresh = tokens["refresh_token"] as? String, !refresh.isEmpty,
      let access = tokens["access_token"] as? String, !access.isEmpty
    else {
      return Self(email: nil, hasSavedLogin: false)
    }
    var claims: [String: Any] = [:]
    if let token = tokens["id_token"] as? String {
      let parts = token.split(separator: ".")
      if parts.count == 3 {
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(
          of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        if let data = Data(base64Encoded: base64),
          let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
          claims = value
        }
      }
    }
    return Self(email: claims["email"] as? String, hasSavedLogin: true)
  }
}
