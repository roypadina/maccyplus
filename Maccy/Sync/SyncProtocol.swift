import Foundation

// Wire protocol — see docs/protocol/PROTOCOL.md. Mirrored by the Android app.

enum SyncProtocol {
  static let version = 1
  static let bonjourType = "_maccysync._tcp"
  static let defaultPort: UInt16 = 53121
  static let inlineTextCap = 16_384          // bytes; text <= ships inline
  static let thumbCap = 65_536               // bytes; image thumbnail max
  static let chunkSize = 65_536              // bytes per content chunk
  static let maxFrame = 17_825_792           // 17 MiB
  static let maxContent = 16_777_216         // 16 MiB
  static let historySyncCount = 200
  static let pingInterval: TimeInterval = 20
  static let deadTimeout: TimeInterval = 60
}

// MARK: - Item metadata

struct ItemMeta: Codable, Identifiable, Hashable {
  enum Kind: String, Codable { case text, image, file }

  let id: String
  let kind: String
  let createdAt: Int64        // unix epoch millis
  let size: Int
  let mime: String?
  let preview: String
  let text: String?           // present iff text kind and size <= inlineTextCap
  let filename: String?
  let thumb: String?          // base64 PNG, image kind only

  var kindEnum: Kind { Kind(rawValue: kind) ?? .text }
}

// MARK: - Content chunk (binary frame payload)

struct ContentChunk {
  let id: UUID
  let seq: UInt32
  let last: Bool
  let bytes: Data
}

// MARK: - Control messages

enum SyncMessage {
  case hs1(eph: String)
  case hs2(eph: String, id: String, sig: String)
  case hs3(id: String, sig: String, token: String?)
  case hello(deviceId: String, name: String, platform: String, protocolVersion: Int)
  case historySync(items: [ItemMeta])
  case requestHistory
  case clipAdded(item: ItemMeta)
  case contentRequest(id: String)
  case contentBegin(id: String, kind: String, size: Int, mime: String?, filename: String?)
  case contentError(id: String, reason: String)
  case ping
  case pong

  var type: String {
    switch self {
    case .hs1: return "hs1"
    case .hs2: return "hs2"
    case .hs3: return "hs3"
    case .hello: return "hello"
    case .historySync: return "historySync"
    case .requestHistory: return "requestHistory"
    case .clipAdded: return "clipAdded"
    case .contentRequest: return "contentRequest"
    case .contentBegin: return "contentBegin"
    case .contentError: return "contentError"
    case .ping: return "ping"
    case .pong: return "pong"
    }
  }
}

extension SyncMessage: Codable {
  private enum CodingKeys: String, CodingKey {
    case t, eph, id, sig, token, deviceId, name, platform, protocolVersion
    case items, item, kind, size, mime, filename, reason
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let t = try c.decode(String.self, forKey: .t)
    switch t {
    case "hs1":
      self = .hs1(eph: try c.decode(String.self, forKey: .eph))
    case "hs2":
      self = .hs2(eph: try c.decode(String.self, forKey: .eph),
                  id: try c.decode(String.self, forKey: .id),
                  sig: try c.decode(String.self, forKey: .sig))
    case "hs3":
      self = .hs3(id: try c.decode(String.self, forKey: .id),
                  sig: try c.decode(String.self, forKey: .sig),
                  token: try c.decodeIfPresent(String.self, forKey: .token))
    case "hello":
      self = .hello(deviceId: try c.decode(String.self, forKey: .deviceId),
                    name: try c.decode(String.self, forKey: .name),
                    platform: try c.decode(String.self, forKey: .platform),
                    protocolVersion: try c.decode(Int.self, forKey: .protocolVersion))
    case "historySync":
      self = .historySync(items: try c.decode([ItemMeta].self, forKey: .items))
    case "requestHistory": self = .requestHistory
    case "clipAdded":
      self = .clipAdded(item: try c.decode(ItemMeta.self, forKey: .item))
    case "contentRequest":
      self = .contentRequest(id: try c.decode(String.self, forKey: .id))
    case "contentBegin":
      self = .contentBegin(id: try c.decode(String.self, forKey: .id),
                           kind: try c.decode(String.self, forKey: .kind),
                           size: try c.decode(Int.self, forKey: .size),
                           mime: try c.decodeIfPresent(String.self, forKey: .mime),
                           filename: try c.decodeIfPresent(String.self, forKey: .filename))
    case "contentError":
      self = .contentError(id: try c.decode(String.self, forKey: .id),
                           reason: try c.decode(String.self, forKey: .reason))
    case "ping": self = .ping
    case "pong": self = .pong
    default:
      throw DecodingError.dataCorruptedError(forKey: .t, in: c,
        debugDescription: "Unknown message type \(t)")
    }
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(type, forKey: .t)
    switch self {
    case let .hs1(eph):
      try c.encode(eph, forKey: .eph)
    case let .hs2(eph, id, sig):
      try c.encode(eph, forKey: .eph); try c.encode(id, forKey: .id); try c.encode(sig, forKey: .sig)
    case let .hs3(id, sig, token):
      try c.encode(id, forKey: .id); try c.encode(sig, forKey: .sig)
      try c.encodeIfPresent(token, forKey: .token)
    case let .hello(deviceId, name, platform, pv):
      try c.encode(deviceId, forKey: .deviceId); try c.encode(name, forKey: .name)
      try c.encode(platform, forKey: .platform); try c.encode(pv, forKey: .protocolVersion)
    case let .historySync(items):
      try c.encode(items, forKey: .items)
    case let .clipAdded(item):
      try c.encode(item, forKey: .item)
    case let .contentRequest(id):
      try c.encode(id, forKey: .id)
    case let .contentBegin(id, kind, size, mime, filename):
      try c.encode(id, forKey: .id); try c.encode(kind, forKey: .kind); try c.encode(size, forKey: .size)
      try c.encodeIfPresent(mime, forKey: .mime); try c.encodeIfPresent(filename, forKey: .filename)
    case let .contentError(id, reason):
      try c.encode(id, forKey: .id); try c.encode(reason, forKey: .reason)
    case .ping, .pong, .requestHistory:
      break
    }
  }
}

// MARK: - Frame codec (plaintext frame = [1-byte kind][payload])

enum Frame {
  case control(SyncMessage)
  case content(ContentChunk)
}

enum FrameError: Error { case empty, unknownKind(UInt8), malformed }

enum FrameCodec {
  static let jsonEncoder = JSONEncoder()
  static let jsonDecoder = JSONDecoder()

  static func encode(_ message: SyncMessage) throws -> Data {
    var out = Data([0x01])
    out.append(try jsonEncoder.encode(message))
    return out
  }

  static func encode(_ chunk: ContentChunk) -> Data {
    var out = Data([0x02])
    out.append(chunk.id.dataRepresentation)
    out.append(chunk.seq.bigEndianData)
    out.append(chunk.last ? 0x01 : 0x00)
    out.append(chunk.bytes)
    return out
  }

  static func decode(_ frame: Data) throws -> Frame {
    guard let kind = frame.first else { throw FrameError.empty }
    let payload = frame.dropFirst()
    switch kind {
    case 0x01:
      return .control(try jsonDecoder.decode(SyncMessage.self, from: Data(payload)))
    case 0x02:
      guard payload.count >= 21 else { throw FrameError.malformed }
      let p = Data(payload)
      let id = UUID(dataRepresentation: p.prefix(16))
      guard let id else { throw FrameError.malformed }
      let seq = UInt32(bigEndianData: p.subdata(in: 16..<20))
      let last = p[p.startIndex + 20] != 0
      let bytes = p.subdata(in: 21..<p.count)
      return .content(ContentChunk(id: id, seq: seq, last: last, bytes: bytes))
    default:
      throw FrameError.unknownKind(kind)
    }
  }
}

// MARK: - Binary helpers

extension UInt32 {
  var bigEndianData: Data { withUnsafeBytes(of: bigEndian) { Data($0) } }
  init(bigEndianData data: Data) {
    var value: UInt32 = 0
    let count = Swift.min(4, data.count)
    for byte in data.prefix(count) { value = (value << 8) | UInt32(byte) }
    self = value
  }
}

extension UUID {
  var dataRepresentation: Data {
    withUnsafeBytes(of: uuid) { Data($0) }
  }
  init?(dataRepresentation data: Data) {
    guard data.count >= 16 else { return nil }
    let bytes = Array(data.prefix(16))
    self = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                       bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
  }
}
