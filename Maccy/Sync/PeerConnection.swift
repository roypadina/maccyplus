import CryptoKit
import Foundation
import Network

// Wraps a single NWConnection: runs the signed-ECDH handshake (client or server
// role), then reads/writes length-prefixed AEAD frames. Callbacks fire on the
// connection's private serial queue; the orchestrator hops to the main actor.
final class PeerConnection {
  enum Role { case server, client }

  struct Trust {
    /// Required peer identity (normal mode). Client always sets this (pinned
    /// Mac id). Server sets it when the phone is already paired.
    var expectedPeerIdPub: Data?
    /// Server-only: active one-time pairing token (pairing mode). nil otherwise.
    var pairingToken: String?
  }

  // Callbacks (invoked on `queue`).
  var onEstablished: (() -> Void)?
  var onControl: ((SyncMessage) -> Void)?
  var onContent: ((ContentChunk) -> Void)?
  var onClosed: ((Error?) -> Void)?
  /// Server pairing mode: a new client authenticated with a valid token.
  var onNewPairing: ((_ clientIdPub: Data) -> Void)?

  let role: Role
  private let connection: NWConnection
  private let identity: SyncIdentity
  private var trust: Trust
  private let queue = DispatchQueue(label: "maccy.sync.peer")

  private var ephPrivate: Curve25519.KeyAgreement.PrivateKey?
  private var clientEphPub = Data()
  private var serverEphPub = Data()
  private var cipher: SessionCipher?
  private var established = false
  private var closed = false

  init(role: Role, connection: NWConnection, identity: SyncIdentity, trust: Trust) {
    self.role = role
    self.connection = connection
    self.identity = identity
    self.trust = trust
  }

  func start() {
    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        self.beginHandshake()
      case let .failed(error):
        self.fail(error)
      case .cancelled:
        if !self.closed { self.fail(nil) }
      default:
        break
      }
    }
    connection.start(queue: queue)
  }

  func cancel() {
    closed = true
    connection.cancel()
  }

  // MARK: - Sending (post-handshake)

  func send(_ message: SyncMessage) {
    guard let frame = try? FrameCodec.encode(message) else { return }
    sendEncrypted(frame)
  }

  func send(_ chunk: ContentChunk) {
    sendEncrypted(FrameCodec.encode(chunk))
  }

  private func sendEncrypted(_ frameBytes: Data) {
    queue.async { [weak self] in
      guard let self, let cipher = self.cipher else { return }
      guard let sealed = try? cipher.seal(frameBytes) else { return }
      self.sendRaw(sealed)
    }
  }

  private func sendHandshake(_ message: SyncMessage) {
    guard let frame = try? FrameCodec.encode(message) else { return }
    sendRaw(frame)
  }

  private func sendRaw(_ payload: Data) {
    var out = UInt32(payload.count).bigEndianData
    out.append(payload)
    connection.send(content: out, completion: .contentProcessed { [weak self] error in
      if let error { self?.fail(error) }
    })
  }

  // MARK: - Handshake

  private func beginHandshake() {
    let eph = Curve25519.KeyAgreement.PrivateKey()
    ephPrivate = eph
    switch role {
    case .client:
      clientEphPub = eph.publicKey.rawRepresentation
      sendHandshake(.hs1(eph: clientEphPub.base64EncodedString()))
      readHandshakeFrame { [weak self] msg in self?.clientHandleHS2(msg) }
    case .server:
      serverEphPub = eph.publicKey.rawRepresentation
      readHandshakeFrame { [weak self] msg in self?.serverHandleHS1(msg) }
    }
  }

  // --- Server role ---

  private func serverHandleHS1(_ msg: SyncMessage) {
    guard case let .hs1(ephB64) = msg, let clientEph = Data(base64Encoded: ephB64) else {
      return fail(SyncCryptoError.badKey)
    }
    clientEphPub = clientEph
    let transcript = Handshake.transcript(clientEph: clientEphPub, serverEph: serverEphPub)
    guard let sig = try? identity.sign(transcript) else { return fail(SyncCryptoError.badSignature) }
    sendHandshake(.hs2(eph: serverEphPub.base64EncodedString(),
                       id: identity.publicKeyRaw.base64EncodedString(),
                       sig: sig.base64EncodedString()))
    readHandshakeFrame { [weak self] msg in self?.serverHandleHS3(msg) }
  }

  private func serverHandleHS3(_ msg: SyncMessage) {
    guard case let .hs3(idB64, sigB64, receivedToken) = msg,
          let clientId = Data(base64Encoded: idB64),
          let sig = Data(base64Encoded: sigB64) else {
      return fail(SyncCryptoError.badKey)
    }
    let transcript = Handshake.transcript(clientEph: clientEphPub, serverEph: serverEphPub)
    guard SyncIdentity.verify(signature: sig, message: transcript, publicKeyRaw: clientId) else {
      return fail(SyncCryptoError.badSignature)
    }
    // Trust decision: pinned peer (normal) or valid one-time token (pairing).
    if let expected = trust.expectedPeerIdPub {
      guard clientId == expected else { return fail(SyncCryptoError.badSignature) }
    } else if let activeToken = trust.pairingToken, !activeToken.isEmpty {
      guard let receivedToken, receivedToken == activeToken else {
        return fail(SyncCryptoError.badSignature)
      }
      onNewPairing?(clientId)
    } else {
      return fail(SyncCryptoError.badSignature)
    }
    finishHandshake(peerEph: clientEphPub, isServer: true)
  }

  // --- Client role ---

  private func clientHandleHS2(_ msg: SyncMessage) {
    guard case let .hs2(ephB64, idB64, sigB64) = msg,
          let serverEph = Data(base64Encoded: ephB64),
          let serverId = Data(base64Encoded: idB64),
          let sig = Data(base64Encoded: sigB64) else {
      return fail(SyncCryptoError.badKey)
    }
    serverEphPub = serverEph
    guard let expected = trust.expectedPeerIdPub, serverId == expected else {
      return fail(SyncCryptoError.badSignature)
    }
    let transcript = Handshake.transcript(clientEph: clientEphPub, serverEph: serverEphPub)
    guard SyncIdentity.verify(signature: sig, message: transcript, publicKeyRaw: serverId) else {
      return fail(SyncCryptoError.badSignature)
    }
    guard let mySig = try? identity.sign(transcript) else { return fail(SyncCryptoError.badSignature) }
    sendHandshake(.hs3(id: identity.publicKeyRaw.base64EncodedString(),
                       sig: mySig.base64EncodedString(),
                       token: trust.pairingToken))
    finishHandshake(peerEph: serverEphPub, isServer: false)
  }

  // --- Common ---

  private func finishHandshake(peerEph: Data, isServer: Bool) {
    guard let eph = ephPrivate,
          let peerKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerEph),
          let shared = try? eph.sharedSecretFromKeyAgreement(with: peerKey) else {
      return fail(SyncCryptoError.badKey)
    }
    let keys = Handshake.deriveKeys(sharedSecret: shared, clientEph: clientEphPub, serverEph: serverEphPub)
    cipher = SessionCipher(c2s: keys.c2s, s2c: keys.s2c, isServer: isServer)
    established = true
    onEstablished?()
    readEncryptedLoop()
  }

  // MARK: - Reading

  private func readHandshakeFrame(_ handler: @escaping (SyncMessage) -> Void) {
    readFrame { [weak self] payload in
      guard let self else { return }
      guard case let .control(message) = (try? FrameCodec.decode(payload)) ?? .control(.ping) else {
        return self.fail(FrameError.malformed)
      }
      handler(message)
    }
  }

  private func readEncryptedLoop() {
    readFrame { [weak self] cipherText in
      guard let self, let cipher = self.cipher else { return }
      guard let plain = try? cipher.open(cipherText),
            let frame = try? FrameCodec.decode(plain) else {
        return self.fail(SyncCryptoError.openFailed)
      }
      switch frame {
      case let .control(message): self.onControl?(message)
      case let .content(chunk): self.onContent?(chunk)
      }
      if !self.closed { self.readEncryptedLoop() }
    }
  }

  private func readFrame(_ completion: @escaping (Data) -> Void) {
    readExactly(4) { [weak self] lenData in
      guard let self else { return }
      let len = Int(UInt32(bigEndianData: lenData))
      guard len > 0, len <= SyncProtocol.maxFrame else { return self.fail(FrameError.malformed) }
      self.readExactly(len) { payload in completion(payload) }
    }
  }

  private func readExactly(_ count: Int, _ completion: @escaping (Data) -> Void) {
    connection.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, isComplete, error in
      guard let self else { return }
      if let error { return self.fail(error) }
      if let data, data.count == count { return completion(data) }
      if isComplete { return self.fail(nil) }
      self.fail(FrameError.malformed)
    }
  }

  private func fail(_ error: Error?) {
    guard !closed else { return }
    closed = true
    connection.cancel()
    onClosed?(error)
  }
}
