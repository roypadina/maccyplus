import CryptoKit
import Foundation

// Crypto for the signed-ECDH (STS) handshake + AEAD framing. See docs/protocol/PROTOCOL.md.

enum SyncCryptoError: Error {
  case badKey
  case badSignature
  case openFailed
}

// MARK: - Long-lived Ed25519 identity (persisted in the Keychain)

final class SyncIdentity {
  let privateKey: Curve25519.Signing.PrivateKey

  var publicKeyRaw: Data { privateKey.publicKey.rawRepresentation }
  /// The device pin = base64 of the raw Ed25519 public key.
  var pin: String { publicKeyRaw.base64EncodedString() }

  init(privateKey: Curve25519.Signing.PrivateKey) {
    self.privateKey = privateKey
  }

  /// A fresh, non-persisted identity (tests / ephemeral use).
  static func generate() -> SyncIdentity {
    SyncIdentity(privateKey: Curve25519.Signing.PrivateKey())
  }

  func sign(_ message: Data) throws -> Data {
    try privateKey.signature(for: message)
  }

  static func verify(signature: Data, message: Data, publicKeyRaw: Data) -> Bool {
    guard let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyRaw) else {
      return false
    }
    return pub.isValidSignature(signature, for: message)
  }

  // Load the persisted identity, generating + storing one on first use.
  static func loadOrCreate() -> SyncIdentity {
    if let raw = Keychain.read(account: keychainAccount),
       let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
      return SyncIdentity(privateKey: key)
    }
    let key = Curve25519.Signing.PrivateKey()
    Keychain.write(key.rawRepresentation, account: keychainAccount)
    return SyncIdentity(privateKey: key)
  }

  private static let keychainAccount = "sync-identity-ed25519"
}

// MARK: - Handshake key agreement

enum Handshake {
  /// `clientEph || serverEph` — the bytes signed by both identities.
  static func transcript(clientEph: Data, serverEph: Data) -> Data {
    clientEph + serverEph
  }

  /// Derive the two directional keys from the ECDH shared secret.
  static func deriveKeys(
    sharedSecret: SharedSecret,
    clientEph: Data,
    serverEph: Data
  ) -> (c2s: SymmetricKey, s2c: SymmetricKey) {
    let salt = clientEph + serverEph
    let c2s = sharedSecret.hkdfDerivedSymmetricKey(
      using: SHA256.self, salt: salt,
      sharedInfo: Data("MaccySync-v1-c2s".utf8), outputByteCount: 32)
    let s2c = sharedSecret.hkdfDerivedSymmetricKey(
      using: SHA256.self, salt: salt,
      sharedInfo: Data("MaccySync-v1-s2c".utf8), outputByteCount: 32)
    return (c2s, s2c)
  }
}

// MARK: - Directional AEAD cipher (ChaCha20-Poly1305, implicit counter nonce)

final class SessionCipher {
  private let sendKey: SymmetricKey
  private let recvKey: SymmetricKey
  private var sendCounter: UInt64 = 0
  private var recvCounter: UInt64 = 0

  // `isServer` selects which derived key is send vs receive.
  init(c2s: SymmetricKey, s2c: SymmetricKey, isServer: Bool) {
    if isServer {
      sendKey = s2c
      recvKey = c2s
    } else {
      sendKey = c2s
      recvKey = s2c
    }
  }

  func seal(_ plaintext: Data) throws -> Data {
    let nonce = Self.nonce(sendCounter)
    sendCounter &+= 1
    let box = try ChaChaPoly.seal(plaintext, using: sendKey, nonce: nonce)
    return box.ciphertext + box.tag
  }

  func open(_ data: Data) throws -> Data {
    guard data.count >= 16 else { throw SyncCryptoError.openFailed }
    let nonce = Self.nonce(recvCounter)
    let ct = data.prefix(data.count - 16)
    let tag = data.suffix(16)
    let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
    let plain = try ChaChaPoly.open(box, using: recvKey)
    recvCounter &+= 1
    return plain
  }

  private static func nonce(_ counter: UInt64) -> ChaChaPoly.Nonce {
    var bytes = [UInt8](repeating: 0, count: 12)
    let be = counter.bigEndian
    withUnsafeBytes(of: be) { src in
      for index in 0..<8 { bytes[4 + index] = src[index] }
    }
    // 12-byte input is always a valid ChaChaPoly nonce.
    return try! ChaChaPoly.Nonce(data: Data(bytes)) // swiftlint:disable:this force_try
  }
}

// MARK: - Minimal Keychain wrapper (generic password)

enum Keychain {
  private static let service = (Bundle.main.bundleIdentifier ?? "com.royp.MaccyActions") + ".sync"

  static func read(account: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
    return result as? Data
  }

  @discardableResult
  static func write(_ data: Data, account: String) -> Bool {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    SecItemDelete(base as CFDictionary)
    var add = base
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
  }
}
