import CryptoKit
import Foundation
internal import libzstd

/// Codex keeps the DB path ending in .jsonl even after compressing that file to .jsonl.zst.
struct ConversationRollout {
  let file: URL
  let id: String
  let contentHash: Data

  static func read(path: String, expectedID: String? = nil) throws -> Self? {
    let logical = URL(
      fileURLWithPath: path.hasSuffix(".jsonl.zst") ? String(path.dropLast(4)) : path)
    guard logical.pathExtension == "jsonl" else {
      throw MigrationError.invalid("채팅 기록 경로를 확인할 수 없습니다: \(logical.lastPathComponent)")
    }
    let compressed = logical.appendingPathExtension("zst")
    try safe(logical)
    try safe(compressed)
    let fm = FileManager.default
    let file = fm.fileExists(atPath: logical.path) ? logical : compressed
    guard fm.fileExists(atPath: file.path) else { return nil }
    let (id, hash) = try inspect(file, expectedID: expectedID)
    return Self(file: file, id: id, contentHash: hash)
  }

  /// Hash the decoded bytes in bounded chunks; never retain every conversation in memory.
  private static func inspect(_ file: URL, expectedID: String?) throws -> (String, Data) {
    var hash = SHA256()
    var header = Data()
    var id: String?
    var lastByte: UInt8?
    try chunks(file) { bytes in
      guard !bytes.isEmpty else { return }
      hash.update(data: bytes)
      lastByte = bytes.last
      if id == nil {
        let end = bytes.firstIndex(of: 10)
        header.append(contentsOf: bytes.prefix(upTo: end ?? bytes.endIndex))
        guard header.count <= 4 * 1024 * 1024 else {
          throw MigrationError.invalid("채팅 기록의 첫 줄이 너무 큽니다: \(file.lastPathComponent)")
        }
        if end != nil {
          guard let record = try JSONSerialization.jsonObject(with: header) as? [String: Any],
            record["type"] as? String == "session_meta",
            let payload = record["payload"] as? [String: Any],
            let recordID = payload["id"] as? String, !recordID.isEmpty,
            expectedID == nil || recordID == expectedID
          else {
            throw MigrationError.invalid("채팅 기록의 ID가 다릅니다: \(file.lastPathComponent)")
          }
          id = recordID
          header = Data()
        }
      }
    }
    guard let id, lastByte == 10 else {
      throw MigrationError.invalid("채팅 기록이 완전히 저장되지 않았습니다: \(file.lastPathComponent)")
    }
    return (id, Data(hash.finalize()))
  }

  private static func chunks(_ file: URL, consume: (Data) throws -> Void) throws {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    let chunkSize = 128 * 1024
    guard file.pathExtension == "zst" else {
      while let data = try handle.read(upToCount: chunkSize), !data.isEmpty { try consume(data) }
      return
    }
    guard let decoder = ZSTD_createDStream() else {
      throw MigrationError.invalid("압축 채팅을 읽을 메모리가 부족합니다.")
    }
    defer { ZSTD_freeDStream(decoder) }
    func checked(_ code: Int) throws -> Int {
      guard ZSTD_isError(code) == 0 else {
        throw MigrationError.invalid(
          "압축 채팅을 읽지 못했습니다: \(file.lastPathComponent) (\(String(cString: ZSTD_getErrorName(code))))"
        )
      }
      return code
    }
    _ = try checked(ZSTD_initDStream(decoder))
    var remaining = 1
    var output = [UInt8](repeating: 0, count: chunkSize)
    while let data = try handle.read(upToCount: chunkSize), !data.isEmpty {
      try data.withUnsafeBytes { source in
        var input = ZSTD_inBuffer(src: source.baseAddress, size: source.count, pos: 0)
        var written: Int
        repeat {
          written = try output.withUnsafeMutableBytes { destination in
            var buffer = ZSTD_outBuffer(
              dst: destination.baseAddress, size: destination.count, pos: 0)
            remaining = try checked(ZSTD_decompressStream(decoder, &buffer, &input))
            try consume(Data(destination.prefix(buffer.pos)))
            return buffer.pos
          }
        } while input.pos < input.size || (written == chunkSize && remaining != 0)
      }
    }
    guard remaining == 0 else {
      throw MigrationError.invalid("압축 채팅 파일이 중간에 잘렸습니다: \(file.lastPathComponent)")
    }
  }

  private static func safe(_ url: URL) throws {
    guard url.standardizedFileURL.path == canonicalPath(url.path) else {
      throw MigrationError.invalid("심볼릭 링크 채팅 경로는 지원하지 않습니다.")
    }
  }
}
