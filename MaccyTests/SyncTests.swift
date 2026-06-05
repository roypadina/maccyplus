import CryptoKit
import Network
import XCTest
@testable import Maccy

// Tests for the LAN clipboard-sync protocol, crypto, and handshake.
final class SyncTests: XCTestCase {

  // MARK: - Binary helpers

  func testUUIDDataRoundTrip() {
    let uuid = UUID()
    let data = uuid.dataRepresentation
    XCTAssertEqual(data.count, 16)
    XCTAssertEqual(UUID(dataRepresentation: data), uuid)
  }

  func testUInt32BigEndianRoundTrip() {
    for value: UInt32 in [0, 1, 255, 65_536, 4_294_967_295] {
      XCTAssertEqual(UInt32(bigEndianData: value.bigEndianData), value)
    }
  }

  // MARK: - Control message codec

  private func roundTrip(_ message: SyncMessage) throws -> SyncMessage {
    let frame = try FrameCodec.encode(message)
    guard case let .control(decoded) = try FrameCodec.decode(frame) else {
      throw XCTSkip("not a control frame")
    }
    return decoded
  }

  func testAllControlMessagesRoundTrip() throws {
    let meta = ItemMeta(id: UUID().uuidString, kind: "image", createdAt: 1_733_000_000_000,
                        size: 42, mime: "image/png", preview: "shot", text: nil,
                        filename: "image.png", thumb: "QUJD")
    let messages: [SyncMessage] = [
      .hs1(eph: "AAA"),
      .hs2(eph: "BBB", id: "CCC", sig: "DDD"),
      .hs3(id: "EEE", sig: "FFF", token: "GGG"),
      .hs3(id: "EEE", sig: "FFF", token: nil),
      .hello(deviceId: "dev", name: "Mac", platform: "macos", protocolVersion: 1),
      .historySync(items: [meta]),
      .clipAdded(item: meta),
      .contentRequest(id: "x"),
      .contentBegin(id: "x", kind: "file", size: 10, mime: "text/plain", filename: "a.txt"),
      .contentError(id: "x", reason: "too_large"),
      .ping, .pong
    ]
    for message in messages {
      let decoded = try roundTrip(message)
      XCTAssertEqual(decoded.type, message.type, "type mismatch for \(message.type)")
    }
  }

  func testItemMetaInlineTextPreserved() throws {
    let meta = ItemMeta(id: UUID().uuidString, kind: "text", createdAt: 1, size: 5,
                        mime: "text/plain", preview: "hello", text: "hello",
                        filename: nil, thumb: nil)
    guard case let .clipAdded(decoded) = try roundTrip(.clipAdded(item: meta)) else {
      return XCTFail("expected clipAdded")
    }
    XCTAssertEqual(decoded.text, "hello")
    XCTAssertEqual(decoded.kindEnum, .text)
  }

  // MARK: - Content chunk codec

  func testContentChunkRoundTrip() throws {
    let id = UUID()
    let bytes = Data((0..<300).map { UInt8($0 % 256) })
    let frame = FrameCodec.encode(ContentChunk(id: id, seq: 7, last: true, bytes: bytes))
    guard case let .content(chunk) = try FrameCodec.decode(frame) else {
      return XCTFail("expected content frame")
    }
    XCTAssertEqual(chunk.id, id)
    XCTAssertEqual(chunk.seq, 7)
    XCTAssertTrue(chunk.last)
    XCTAssertEqual(chunk.bytes, bytes)
  }

  func testEmptyFrameThrows() {
    XCTAssertThrowsError(try FrameCodec.decode(Data()))
  }

  // MARK: - Identity signatures

  func testSignVerify() throws {
    let identity = SyncIdentity.generate()
    let message = Data("transcript".utf8)
    let signature = try identity.sign(message)
    XCTAssertTrue(SyncIdentity.verify(signature: signature, message: message,
                                      publicKeyRaw: identity.publicKeyRaw))
    // Tampered message fails.
    XCTAssertFalse(SyncIdentity.verify(signature: signature, message: Data("other".utf8),
                                       publicKeyRaw: identity.publicKeyRaw))
    // Wrong key fails.
    XCTAssertFalse(SyncIdentity.verify(signature: signature, message: message,
                                       publicKeyRaw: SyncIdentity.generate().publicKeyRaw))
  }

  // MARK: - Key agreement + AEAD

  func testDerivedKeysMatchAndCipherInteroperates() throws {
    let clientEph = Curve25519.KeyAgreement.PrivateKey()
    let serverEph = Curve25519.KeyAgreement.PrivateKey()
    let clientPub = clientEph.publicKey.rawRepresentation
    let serverPub = serverEph.publicKey.rawRepresentation

    let clientShared = try clientEph.sharedSecretFromKeyAgreement(
      with: .init(rawRepresentation: serverPub))
    let serverShared = try serverEph.sharedSecretFromKeyAgreement(
      with: .init(rawRepresentation: clientPub))

    let clientKeys = Handshake.deriveKeys(sharedSecret: clientShared, clientEph: clientPub, serverEph: serverPub)
    let serverKeys = Handshake.deriveKeys(sharedSecret: serverShared, clientEph: clientPub, serverEph: serverPub)
    XCTAssertEqual(clientKeys.c2s, serverKeys.c2s)
    XCTAssertEqual(clientKeys.s2c, serverKeys.s2c)

    let clientCipher = SessionCipher(c2s: clientKeys.c2s, s2c: clientKeys.s2c, isServer: false)
    let serverCipher = SessionCipher(c2s: serverKeys.c2s, s2c: serverKeys.s2c, isServer: true)

    // Client -> server, multiple frames (counter must advance in lockstep).
    for index in 0..<5 {
      let plaintext = Data("msg-\(index)".utf8)
      let sealed = try clientCipher.seal(plaintext)
      XCTAssertEqual(try serverCipher.open(sealed), plaintext)
    }
    // Server -> client.
    let reply = Data("reply".utf8)
    XCTAssertEqual(try clientCipher.open(serverCipher.seal(reply)), reply)
  }

  func testTamperedCiphertextFails() throws {
    let key = SymmetricKey(size: .bits256)
    let cipher = SessionCipher(c2s: key, s2c: key, isServer: false)
    let peer = SessionCipher(c2s: key, s2c: key, isServer: true)
    var sealed = try cipher.seal(Data("secret".utf8))
    sealed[sealed.startIndex] ^= 0xFF
    XCTAssertThrowsError(try peer.open(sealed))
  }

  // MARK: - End-to-end handshake over loopback TCP

  func testHandshakeAndEncryptedClipOverLoopback() throws {
    let serverIdentity = SyncIdentity.generate()
    let clientIdentity = SyncIdentity.generate()
    let port = NWEndpoint.Port(rawValue: 53_987)!

    let listener = try NWListener(using: .tcp, on: port)
    let serverReady = expectation(description: "server established")
    let clientReady = expectation(description: "client established")
    let gotClip = expectation(description: "server received clip")
    var serverPeer: PeerConnection?

    listener.newConnectionHandler = { connection in
      let peer = PeerConnection(
        role: .server, connection: connection, identity: serverIdentity,
        trust: .init(expectedPeerIdPub: clientIdentity.publicKeyRaw, pairingToken: nil))
      serverPeer = peer
      peer.onEstablished = { serverReady.fulfill() }
      peer.onControl = { message in if case .clipAdded = message { gotClip.fulfill() } }
      peer.start()
    }
    listener.start(queue: .global())

    let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
    let client = PeerConnection(
      role: .client, connection: connection, identity: clientIdentity,
      trust: .init(expectedPeerIdPub: serverIdentity.publicKeyRaw, pairingToken: nil))
    client.onEstablished = {
      clientReady.fulfill()
      let meta = ItemMeta(id: UUID().uuidString, kind: "text", createdAt: 0, size: 3,
                          mime: "text/plain", preview: "foo", text: "foo", filename: nil, thumb: nil)
      client.send(.clipAdded(item: meta))
    }
    client.start()

    wait(for: [serverReady, clientReady, gotClip], timeout: 15)
    client.cancel()
    serverPeer?.cancel()
    listener.cancel()
  }

  func testHandshakeRejectsWrongServerIdentity() throws {
    let serverIdentity = SyncIdentity.generate()
    let clientIdentity = SyncIdentity.generate()
    let imposterPin = SyncIdentity.generate().publicKeyRaw  // client pins the wrong key
    let port = NWEndpoint.Port(rawValue: 53_988)!

    let listener = try NWListener(using: .tcp, on: port)
    let clientClosed = expectation(description: "client aborts on bad server pin")
    var serverPeer: PeerConnection?

    listener.newConnectionHandler = { connection in
      let peer = PeerConnection(
        role: .server, connection: connection, identity: serverIdentity,
        trust: .init(expectedPeerIdPub: clientIdentity.publicKeyRaw, pairingToken: nil))
      serverPeer = peer
      peer.start()
    }
    listener.start(queue: .global())

    let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
    let client = PeerConnection(
      role: .client, connection: connection, identity: clientIdentity,
      trust: .init(expectedPeerIdPub: imposterPin, pairingToken: nil))
    client.onEstablished = { XCTFail("must not establish with wrong server pin") }
    client.onClosed = { _ in clientClosed.fulfill() }
    client.start()

    wait(for: [clientClosed], timeout: 15)
    client.cancel()
    serverPeer?.cancel()
    listener.cancel()
  }

  // MARK: - Remote clip store

  @MainActor
  func testRemoteClipStoreDedupeAndOrder() {
    let store = RemoteClipStore()
    func meta(_ id: String, _ created: Int64) -> ItemMeta {
      ItemMeta(id: id, kind: "text", createdAt: created, size: 1, mime: "text/plain",
               preview: id, text: id, filename: nil, thumb: nil)
    }
    store.replaceAll([meta("a", 100), meta("b", 200), meta("a", 100)], peerName: "Phone")
    XCTAssertEqual(store.items.count, 2)              // deduped
    XCTAssertEqual(store.items.first?.id, "b")        // newest first
    store.add(meta("c", 300))
    XCTAssertEqual(store.items.first?.id, "c")
    store.add(meta("b", 400))                         // re-add moves to front
    XCTAssertEqual(store.items.first?.id, "b")
    XCTAssertEqual(store.items.count, 3)
    store.clear()
    XCTAssertTrue(store.items.isEmpty)
  }
}
